-- Flexible, request-owned public requirements. Internal valuation rules remain
-- in acquisition_request_rules and are never projected to providers.

CREATE TABLE public.acquisition_request_requirements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    request_id uuid NOT NULL,
    code text NOT NULL,
    category text NOT NULL,
    title text NOT NULL,
    value text NOT NULL,
    required boolean NOT NULL DEFAULT true,
    display_order integer NOT NULL DEFAULT 0,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL,
    CONSTRAINT acquisition_request_requirements_request_fkey
        FOREIGN KEY (request_id, environment_id)
        REFERENCES public.acquisition_requests(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_request_requirements_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT acquisition_request_requirements_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT acquisition_request_requirements_value_not_blank CHECK (btrim(value) <> ''),
    CONSTRAINT acquisition_request_requirements_category_check CHECK (
        category IN ('specification', 'documentation', 'condition', 'evidence')
    ),
    CONSTRAINT acquisition_request_requirements_metadata_object CHECK (
        jsonb_typeof(metadata) = 'object'
    ),
    CONSTRAINT acquisition_request_requirements_request_code_unique UNIQUE (request_id, code)
);

CREATE INDEX acquisition_request_requirements_request_idx
    ON public.acquisition_request_requirements(environment_id, request_id, display_order);

ALTER TABLE public.acquisition_request_requirements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.acquisition_request_requirements FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.acquisition_request_requirements TO authenticated;
GRANT ALL ON TABLE public.acquisition_request_requirements TO postgres, service_role;

CREATE POLICY acquisition_request_requirements_read
ON public.acquisition_request_requirements
FOR SELECT TO authenticated
USING (
    environment_id = app.current_environment_id()
    AND EXISTS (
        SELECT 1
        FROM public.acquisition_requests request
        WHERE request.id = acquisition_request_requirements.request_id
          AND request.environment_id = acquisition_request_requirements.environment_id
          AND (
              app.auth_is_acquisition_admin()
              OR (
                  app.auth_acquisition_supplier_id() IS NOT NULL
                  AND request.status IN ('published', 'evaluating', 'partially_awarded', 'awarded')
              )
          )
    )
);

-- New requests may be published before DORI defines private valuation rules.
-- Missing rules produce a neutral manual-review recommendation, never a client
-- hard-coded purchase decision.
ALTER TABLE public.acquisition_request_rules
    ALTER COLUMN internal_price_limit_mxn DROP NOT NULL;
ALTER TABLE public.acquisition_request_rules
    DROP CONSTRAINT acquisition_request_rules_price_positive;
ALTER TABLE public.acquisition_request_rules
    ADD CONSTRAINT acquisition_request_rules_price_positive CHECK (
        internal_price_limit_mxn IS NULL OR internal_price_limit_mxn > 0
    );

ALTER TABLE public.acquisition_evidence
    DROP CONSTRAINT acquisition_evidence_kind_check;
ALTER TABLE public.acquisition_evidence
    ADD CONSTRAINT acquisition_evidence_kind_check CHECK (
        kind IN (
            -- v0.1 legacy evidence identifiers remain valid.
            'vin', 'dashboard', 'front', 'rear', 'left_side', 'right_side',
            'interior', 'charger', 'battery', 'document',
            -- Approved detailed evidence identifiers.
            'exterior_front', 'exterior_driver_side', 'exterior_passenger_side',
            'exterior_rear', 'interior_dashboard', 'steering_wheel', 'odometer',
            'driver_seat', 'passenger_seat', 'rear_seats', 'keys',
            'charger_110v', 'charger_220v', 'origin_invoice'
        )
    );

CREATE OR REPLACE FUNCTION public.publish_acquisition_request(
    p_model text,
    p_versions text[],
    p_target_quantity integer,
    p_minimum_year integer,
    p_maximum_year integer,
    p_maximum_mileage integer,
    p_delivery_city text,
    p_deadline_at timestamptz,
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
        deadline_at, status, created_by, created_at, updated_at
    ) VALUES (
        v_environment_id, v_code,
        p_target_quantity::text || ' vehículos requeridos',
        p_target_quantity, btrim(p_model), COALESCE(p_versions, '{}'),
        p_minimum_year, p_maximum_year, p_maximum_mileage,
        btrim(p_delivery_city), p_deadline_at, 'published',
        v_actor_profile_id, v_now, v_now
    ) RETURNING * INTO v_result;

    INSERT INTO public.acquisition_request_rules(
        request_id, environment_id, target_soh, minimum_soh,
        internal_price_limit_mxn, created_at
    ) VALUES (v_result.id, v_environment_id, NULL, NULL, NULL, v_now);

    INSERT INTO public.acquisition_request_requirements(
        environment_id, request_id, code, category, title, value,
        required, display_order, metadata, created_at
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
        COALESCE(item->'metadata', '{}'::jsonb),
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
            'requirements_count', jsonb_array_length(p_requirements)
        )
    );
    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.publish_acquisition_request(
    text, text[], integer, integer, integer, integer,
    text, timestamptz, jsonb, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.publish_acquisition_request(
    text, text[], integer, integer, integer, integer,
    text, timestamptz, jsonb, text
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.submit_acquisition_offer(
    p_offer_id uuid, p_request_id uuid, p_vin text, p_model text,
    p_version text, p_year integer, p_mileage integer,
    p_declared_soh numeric, p_color text, p_price_mxn numeric,
    p_transfer_included boolean, p_evidence jsonb, p_idempotency_key text
)
RETURNS public.acquisition_offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_actor_profile_id uuid := app.auth_profile_id();
    v_supplier_id uuid := app.auth_acquisition_supplier_id();
    v_now timestamptz := app.env_now(v_environment_id);
    v_request_row public.acquisition_requests%ROWTYPE;
    v_rules public.acquisition_request_rules%ROWTYPE;
    v_request jsonb;
    v_command public.command_log%ROWTYPE;
    v_result public.acquisition_offers%ROWTYPE;
    v_item jsonb;
    v_kind text;
    v_path text;
    v_recommendation text;
    v_risk text;
    v_summary text;
BEGIN
    IF v_supplier_id IS NULL THEN
        RAISE EXCEPTION 'active_acquisition_provider_required' USING ERRCODE = '42501';
    END IF;
    IF p_offer_id IS NULL THEN
        RAISE EXCEPTION 'offer_id_required' USING ERRCODE = '22023';
    END IF;
    IF jsonb_typeof(p_evidence) <> 'array' OR jsonb_array_length(p_evidence) < 3 THEN
        RAISE EXCEPTION 'at_least_three_evidence_items_required' USING ERRCODE = '22023';
    END IF;

    SELECT request.* INTO v_request_row
    FROM public.acquisition_requests request
    WHERE request.id = p_request_id
      AND request.environment_id = v_environment_id
      AND request.status IN ('published', 'evaluating', 'partially_awarded')
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_acquisition_request_not_found' USING ERRCODE = 'P0002';
    END IF;

    SELECT * INTO STRICT v_rules
    FROM public.acquisition_request_rules
    WHERE request_id = p_request_id AND environment_id = v_environment_id;

    v_request := jsonb_build_object(
        'offer_id', p_offer_id, 'request_id', p_request_id,
        'vin', upper(btrim(p_vin)), 'model', btrim(p_model),
        'version', NULLIF(btrim(p_version), ''), 'year', p_year,
        'mileage', p_mileage, 'declared_soh', p_declared_soh,
        'color', NULLIF(btrim(p_color), ''), 'price_mxn', p_price_mxn,
        'transfer_included', p_transfer_included, 'evidence', p_evidence
    );
    v_command := app.begin_acquisition_command('submit_acquisition_offer', p_idempotency_key, v_request);
    IF v_command.result_payload IS NOT NULL THEN
        SELECT * INTO STRICT v_result FROM public.acquisition_offers
        WHERE id = (v_command.result_payload->>'offer_id')::uuid;
        RETURN v_result;
    END IF;

    FOR v_item IN SELECT value FROM jsonb_array_elements(p_evidence)
    LOOP
        v_kind := v_item->>'kind';
        v_path := v_item->>'path';
        IF v_kind NOT IN (
            'vin', 'dashboard', 'front', 'rear', 'left_side', 'right_side',
            'interior', 'charger', 'battery', 'document',
            'exterior_front', 'exterior_driver_side', 'exterior_passenger_side',
            'exterior_rear', 'interior_dashboard', 'steering_wheel', 'odometer',
            'driver_seat', 'passenger_seat', 'rear_seats', 'keys',
            'charger_110v', 'charger_220v', 'origin_invoice'
        )
           OR v_path IS NULL
           OR v_path NOT LIKE v_environment_id::text || '/' || v_supplier_id::text || '/' || p_offer_id::text || '/%'
           OR NOT EXISTS (
                SELECT 1 FROM storage.objects object
                WHERE object.bucket_id = 'acquisition-evidence'
                  AND object.name = v_path
                  AND object.owner_id = auth.uid()::text
           ) THEN
            RAISE EXCEPTION 'invalid_or_unowned_acquisition_evidence' USING ERRCODE = '42501';
        END IF;
    END LOOP;

    INSERT INTO public.acquisition_offers(
        id, environment_id, request_id, supplier_id, created_by, vin,
        model, version, year, mileage, declared_soh, color, price_mxn,
        transfer_included, status, submitted_at, updated_at
    ) VALUES (
        p_offer_id, v_environment_id, p_request_id, v_supplier_id,
        v_actor_profile_id, upper(btrim(p_vin)), btrim(p_model),
        NULLIF(btrim(p_version), ''), p_year, p_mileage, p_declared_soh,
        NULLIF(btrim(p_color), ''), p_price_mxn, p_transfer_included,
        'submitted', v_now, v_now
    ) RETURNING * INTO v_result;

    INSERT INTO public.acquisition_evidence(
        environment_id, offer_id, kind, object_path, uploaded_by, created_at
    )
    SELECT v_environment_id, p_offer_id, item->>'kind', item->>'path', v_actor_profile_id, v_now
    FROM jsonb_array_elements(p_evidence) item;

    IF p_declared_soh IS NULL THEN
        v_recommendation := 'wait_for_information'; v_risk := 'medium';
        v_summary := 'Falta confirmar el estado de salud de la bateria.';
    ELSIF v_rules.minimum_soh IS NOT NULL AND p_declared_soh < v_rules.minimum_soh THEN
        v_recommendation := 'do_not_buy'; v_risk := 'high';
        v_summary := 'El estado de salud declarado esta por debajo del minimo.';
    ELSIF p_year < v_request_row.minimum_year OR p_year > v_request_row.maximum_year
          OR p_mileage > v_request_row.maximum_mileage THEN
        v_recommendation := 'do_not_buy'; v_risk := 'high';
        v_summary := 'La unidad no cumple ano o kilometraje de la solicitud.';
    ELSIF v_rules.internal_price_limit_mxn IS NULL THEN
        v_recommendation := 'wait_for_information'; v_risk := 'medium';
        v_summary := 'DORI debe completar la valuacion interna antes de decidir.';
    ELSIF p_price_mxn <= v_rules.internal_price_limit_mxn THEN
        v_recommendation := 'buy'; v_risk := 'low';
        v_summary := 'La unidad cumple los parametros principales de la solicitud.';
    ELSIF p_price_mxn <= v_rules.internal_price_limit_mxn * 1.05 THEN
        v_recommendation := 'negotiate'; v_risk := 'medium';
        v_summary := 'La unidad es viable si se ajusta el precio.';
    ELSIF p_price_mxn <= v_rules.internal_price_limit_mxn * 1.15 THEN
        v_recommendation := 'review'; v_risk := 'medium';
        v_summary := 'El precio requiere una revision adicional.';
    ELSE
        v_recommendation := 'do_not_buy'; v_risk := 'high';
        v_summary := 'El precio supera ampliamente el limite interno.';
    END IF;

    INSERT INTO public.acquisition_offer_assessments(
        offer_id, environment_id, estimated_value_mxn, maximum_recommended_mxn,
        risk, recommendation, evidence_status, summary, calculated_at
    ) VALUES (
        p_offer_id, v_environment_id, v_rules.internal_price_limit_mxn,
        v_rules.internal_price_limit_mxn, v_risk, v_recommendation,
        'complete', v_summary, v_now
    );

    UPDATE public.acquisition_requests
    SET status = 'evaluating', revision = revision + 1, updated_at = v_now
    WHERE id = p_request_id AND status = 'published';

    PERFORM app.finish_acquisition_command(
        v_command.id, jsonb_build_object('offer_id', v_result.id),
        'acquisition.offer.submitted', 'acquisition_offer', v_result.id,
        jsonb_build_object('request_id', p_request_id, 'supplier_id', v_supplier_id)
    );
    RETURN v_result;
END;
$function$;

-- Enforce request-owned evidence requirements at transaction commit, after the
-- offer RPC has inserted all evidence rows. Legacy requests keep their existing
-- minimum-three contract.
CREATE OR REPLACE FUNCTION app.enforce_acquisition_offer_required_evidence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(requirement.code, ',' ORDER BY requirement.display_order, requirement.code)
    INTO v_missing
    FROM public.acquisition_request_requirements requirement
    WHERE requirement.request_id = NEW.request_id
      AND requirement.environment_id = NEW.environment_id
      AND requirement.category = 'evidence'
      AND requirement.required
      AND NOT EXISTS (
          SELECT 1
          FROM public.acquisition_evidence evidence
          WHERE evidence.offer_id = NEW.id
            AND evidence.environment_id = NEW.environment_id
            AND evidence.kind = requirement.code
      );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'required_acquisition_evidence_missing:%', v_missing
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION app.enforce_acquisition_offer_required_evidence()
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.enforce_acquisition_offer_required_evidence()
TO postgres, service_role;

CREATE CONSTRAINT TRIGGER acquisition_offer_required_evidence
AFTER INSERT ON public.acquisition_offers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION app.enforce_acquisition_offer_required_evidence();

-- Missing private valuation data must degrade to manual review. This trigger
-- corrects the assessment created by the established offer RPC atomically.
CREATE OR REPLACE FUNCTION app.normalize_acquisition_assessment_without_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NEW.maximum_recommended_mxn IS NULL THEN
        NEW.risk := 'medium';
        NEW.recommendation := 'wait_for_information';
        NEW.summary := 'DORI debe completar la valuación interna antes de decidir.';
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION app.normalize_acquisition_assessment_without_rules()
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.normalize_acquisition_assessment_without_rules()
TO postgres, service_role;

CREATE TRIGGER acquisition_assessment_without_rules
BEFORE INSERT OR UPDATE ON public.acquisition_offer_assessments
FOR EACH ROW EXECUTE FUNCTION app.normalize_acquisition_assessment_without_rules();

-- Expose the server-side activity timestamp used for authoritative ordering.
DROP FUNCTION IF EXISTS public.list_acquisition_chat_threads();
CREATE FUNCTION public.list_acquisition_chat_threads()
RETURNS TABLE (
    thread_id uuid,
    supplier_id uuid,
    offer_id uuid,
    scope text,
    title text,
    supplier_name text,
    last_message text,
    last_message_kind text,
    last_message_at timestamptz,
    updated_at timestamptz,
    unread_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT thread.id,
           thread.supplier_id,
           thread.offer_id,
           thread.scope,
           thread.title,
           supplier.name,
           latest.body,
           latest.message_kind,
           latest.created_at,
           thread.updated_at,
           (
               SELECT count(*)
               FROM public.acquisition_chat_messages unread
               WHERE unread.thread_id = thread.id
                 AND unread.environment_id = thread.environment_id
                 AND unread.event_sequence > COALESCE(receipt.last_read_sequence, 0)
                 AND unread.sender_profile_id IS DISTINCT FROM app.auth_profile_id()
           )
    FROM public.acquisition_chat_threads thread
    JOIN public.acquisition_suppliers supplier
      ON supplier.id = thread.supplier_id
     AND supplier.environment_id = thread.environment_id
    LEFT JOIN public.acquisition_chat_read_receipts receipt
      ON receipt.thread_id = thread.id
     AND receipt.profile_id = app.auth_profile_id()
    LEFT JOIN LATERAL (
        SELECT message.body, message.message_kind, message.created_at
        FROM public.acquisition_chat_messages message
        WHERE message.thread_id = thread.id
          AND message.environment_id = thread.environment_id
        ORDER BY message.event_sequence DESC
        LIMIT 1
    ) latest ON true
    WHERE thread.environment_id = app.current_environment_id()
      AND (
          app.auth_is_acquisition_admin()
          OR thread.supplier_id = app.auth_acquisition_supplier_id()
      )
    ORDER BY COALESCE(latest.created_at, thread.updated_at) DESC, thread.id;
$function$;

REVOKE ALL ON FUNCTION public.list_acquisition_chat_threads() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_acquisition_chat_threads()
TO authenticated, service_role;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'acquisition_request_requirements'
    ) THEN
        ALTER PUBLICATION supabase_realtime
            ADD TABLE public.acquisition_request_requirements;
    END IF;
END
$block$;

COMMENT ON TABLE public.acquisition_request_requirements IS
    'Requisitos públicos y flexibles que pertenecen a una solicitud de adquisición.';



