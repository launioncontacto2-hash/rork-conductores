-- PostgREST resolves an RPC by its public name and argument names. DORI had
-- accumulated three public overloads of publish_acquisition_request; Supabase
-- explicitly recommends unique function names because overloaded RPCs are not
-- supported reliably by the Data API. Keep one canonical, client-facing
-- transaction with the complete v0.1 request contract.
DROP FUNCTION IF EXISTS public.publish_acquisition_request(
    text, text, integer, text, text[], integer, integer, integer, text,
    timestamptz, numeric, numeric, numeric, text
);
DROP FUNCTION IF EXISTS public.publish_acquisition_request(
    text, text[], integer, integer, integer, integer, text,
    timestamptz, jsonb, text
);
DROP FUNCTION IF EXISTS public.publish_acquisition_request(
    text, text[], integer, integer, integer, integer, text,
    timestamptz, timestamptz, jsonb, text
);

CREATE FUNCTION public.publish_acquisition_request(
    p_model text,
    p_versions text[],
    p_target_quantity integer,
    p_minimum_year integer,
    p_maximum_year integer,
    p_maximum_mileage integer,
    p_delivery_city text,
    p_deadline_at timestamptz,
    p_target_delivery_date date,
    p_requirements jsonb,
    p_idempotency_key text
)
RETURNS public.acquisition_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_actor_profile_id uuid := app.auth_profile_id();
    v_now timestamptz := app.env_now(v_environment_id);
    v_payload jsonb;
    v_command public.command_log%ROWTYPE;
    v_result public.acquisition_requests%ROWTYPE;
    v_code text;
    v_item jsonb;
BEGIN
    IF NOT app.auth_is_acquisition_admin() THEN
        RAISE EXCEPTION 'dori_acquisition_admin_required' USING ERRCODE = '42501';
    END IF;
    IF btrim(COALESCE(p_model, '')) = ''
       OR p_target_quantity <= 0
       OR p_minimum_year NOT BETWEEN 2000 AND 2100
       OR p_maximum_year < p_minimum_year
       OR p_maximum_mileage < 0
       OR btrim(COALESCE(p_delivery_city, '')) = '' THEN
        RAISE EXCEPTION 'invalid_acquisition_request_fields' USING ERRCODE = '22023';
    END IF;
    IF p_deadline_at IS NULL OR p_deadline_at <= v_now THEN
        RAISE EXCEPTION 'acquisition_request_deadline_must_be_future' USING ERRCODE = '22023';
    END IF;
    IF p_target_delivery_date IS NULL OR p_target_delivery_date < p_deadline_at::date THEN
        RAISE EXCEPTION 'acquisition_target_delivery_date_invalid' USING ERRCODE = '22023';
    END IF;
    IF jsonb_typeof(p_requirements) <> 'array' OR jsonb_array_length(p_requirements) = 0 THEN
        RAISE EXCEPTION 'acquisition_request_requirements_required' USING ERRCODE = '22023';
    END IF;

    FOR v_item IN SELECT value FROM jsonb_array_elements(p_requirements)
    LOOP
        IF btrim(COALESCE(v_item->>'code', '')) = ''
           OR btrim(COALESCE(v_item->>'title', '')) = ''
           OR btrim(COALESCE(v_item->>'value', '')) = ''
           OR COALESCE(v_item->>'category', '') NOT IN (
               'specification', 'documentation', 'condition', 'evidence'
           )
           OR COALESCE(v_item->>'response_type', 'confirmation') NOT IN (
               'confirmation', 'text', 'number', 'date', 'document', 'photo'
           ) THEN
            RAISE EXCEPTION 'invalid_acquisition_request_requirement' USING ERRCODE = '22023';
        END IF;
    END LOOP;

    v_payload := jsonb_build_object(
        'model', btrim(p_model),
        'versions', COALESCE(to_jsonb(p_versions), '[]'::jsonb),
        'target_quantity', p_target_quantity,
        'minimum_year', p_minimum_year,
        'maximum_year', p_maximum_year,
        'maximum_mileage', p_maximum_mileage,
        'delivery_city', btrim(p_delivery_city),
        'deadline_at', p_deadline_at,
        'target_delivery_date', p_target_delivery_date,
        'requirements', p_requirements
    );
    v_command := app.begin_acquisition_command(
        'publish_acquisition_request', p_idempotency_key, v_payload
    );

    IF v_command.result_payload IS NOT NULL THEN
        SELECT * INTO STRICT v_result
        FROM public.acquisition_requests
        WHERE id = (v_command.result_payload->>'request_id')::uuid;
        RETURN v_result;
    END IF;

    v_code := 'ADQ-' || to_char(v_now, 'YYYYMMDD') || '-'
        || upper(substr(replace(extensions.gen_random_uuid()::text, '-', ''), 1, 6));

    INSERT INTO public.acquisition_requests(
        environment_id, code, title, target_quantity, model, versions,
        minimum_year, maximum_year, maximum_mileage, delivery_city,
        deadline_at, target_delivery_date, status, created_by, created_at, updated_at
    ) VALUES (
        v_environment_id, v_code,
        p_target_quantity::text || ' vehículos requeridos',
        p_target_quantity, btrim(p_model), COALESCE(p_versions, '{}'),
        p_minimum_year, p_maximum_year, p_maximum_mileage,
        btrim(p_delivery_city), p_deadline_at, p_target_delivery_date,
        'published', v_actor_profile_id, v_now, v_now
    ) RETURNING * INTO v_result;

    INSERT INTO public.acquisition_request_rules(
        request_id, environment_id, target_soh, minimum_soh,
        internal_price_limit_mxn, created_at
    ) VALUES (v_result.id, v_environment_id, NULL, NULL, NULL, v_now);

    INSERT INTO public.acquisition_request_requirements(
        environment_id, request_id, code, category, title, value,
        required, display_order, response_type, requires_dori_verification,
        metadata, created_at
    )
    SELECT
        v_environment_id,
        v_result.id,
        btrim(item->>'code'),
        item->>'category',
        btrim(item->>'title'),
        btrim(item->>'value'),
        COALESCE((item->>'required')::boolean, true),
        COALESCE((item->>'display_order')::integer, ordinal::integer),
        COALESCE(item->>'response_type', 'confirmation'),
        COALESCE((item->>'requires_dori_verification')::boolean, false),
        COALESCE(item->'metadata', '{}'::jsonb) || jsonb_build_object(
            'response_type', COALESCE(item->>'response_type', 'confirmation'),
            'requires_dori_verification',
                COALESCE((item->>'requires_dori_verification')::boolean, false)
        ),
        v_now
    FROM jsonb_array_elements(p_requirements) WITH ORDINALITY AS requirement(item, ordinal);

    PERFORM app.finish_acquisition_command(
        v_command.id,
        jsonb_build_object('request_id', v_result.id),
        'acquisition.request.published',
        'acquisition_request',
        v_result.id,
        jsonb_build_object(
            'code', v_result.code,
            'target_quantity', v_result.target_quantity,
            'requirements_count', jsonb_array_length(p_requirements),
            'deadline_at', v_result.deadline_at,
            'target_delivery_date', v_result.target_delivery_date
        )
    );
    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.publish_acquisition_request(
    text, text[], integer, integer, integer, integer, text,
    timestamptz, date, jsonb, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.publish_acquisition_request(
    text, text[], integer, integer, integer, integer, text,
    timestamptz, date, jsonb, text
) TO authenticated, service_role;

COMMENT ON FUNCTION public.publish_acquisition_request(
    text, text[], integer, integer, integer, integer, text,
    timestamptz, date, jsonb, text
) IS 'Publicación transaccional canónica de solicitudes de DORI Adquisición.';
