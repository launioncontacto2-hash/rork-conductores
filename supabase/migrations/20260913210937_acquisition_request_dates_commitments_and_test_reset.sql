-- Incremental request timing, flexible requirement responses and provider
-- delivery commitments. Existing authentication, memberships and RLS remain
-- authoritative.
ALTER TABLE public.acquisition_requests
    ADD COLUMN target_delivery_date date;

ALTER TABLE public.acquisition_request_requirements
    ADD COLUMN response_type text NOT NULL DEFAULT 'confirmation',
    ADD COLUMN requires_dori_verification boolean NOT NULL DEFAULT false,
    ADD CONSTRAINT acquisition_requirement_response_type_check CHECK (
        response_type IN ('confirmation', 'text', 'number', 'date', 'document', 'photo')
    );

ALTER TABLE public.acquisition_offers
    ADD COLUMN committed_delivery_date date;

CREATE TABLE public.acquisition_delivery_commitment_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    offer_id uuid NOT NULL,
    previous_date date,
    committed_date date NOT NULL,
    reason text NOT NULL,
    changed_by uuid NOT NULL,
    created_at timestamptz NOT NULL,
    CONSTRAINT acquisition_commitment_offer_fkey FOREIGN KEY (offer_id, environment_id)
        REFERENCES public.acquisition_offers(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_commitment_profile_fkey FOREIGN KEY (changed_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_commitment_reason_not_blank CHECK (btrim(reason) <> '')
);

ALTER TABLE public.acquisition_delivery_commitment_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.acquisition_delivery_commitment_history FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.acquisition_delivery_commitment_history TO authenticated;
GRANT ALL ON public.acquisition_delivery_commitment_history TO postgres, service_role;

CREATE POLICY acquisition_delivery_commitment_history_read
ON public.acquisition_delivery_commitment_history FOR SELECT TO authenticated
USING (
    environment_id = app.current_environment_id()
    AND EXISTS (
        SELECT 1 FROM public.acquisition_offers offer
        WHERE offer.id = acquisition_delivery_commitment_history.offer_id
          AND offer.environment_id = acquisition_delivery_commitment_history.environment_id
          AND (
              app.auth_is_acquisition_admin()
              OR offer.supplier_id = app.auth_acquisition_supplier_id()
          )
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
    p_target_delivery_date timestamptz,
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
    v_now timestamptz := app.env_now(v_environment_id);
    v_result public.acquisition_requests%ROWTYPE;
BEGIN
    IF p_deadline_at IS NULL OR p_deadline_at <= v_now THEN
        RAISE EXCEPTION 'acquisition_request_deadline_must_be_future' USING ERRCODE = '22023';
    END IF;
    IF p_target_delivery_date IS NULL OR p_target_delivery_date::date < p_deadline_at::date THEN
        RAISE EXCEPTION 'acquisition_target_delivery_date_invalid' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_result FROM public.publish_acquisition_request(
        p_model, p_versions, p_target_quantity, p_minimum_year, p_maximum_year,
        p_maximum_mileage, p_delivery_city, p_deadline_at, p_requirements,
        p_idempotency_key
    );

    UPDATE public.acquisition_requests
    SET target_delivery_date = p_target_delivery_date::date
    WHERE id = v_result.id
    RETURNING * INTO v_result;

    UPDATE public.acquisition_request_requirements requirement
    SET response_type = COALESCE(item.value->>'response_type', 'confirmation'),
        requires_dori_verification = COALESCE((item.value->>'requires_dori_verification')::boolean, false),
        metadata = requirement.metadata || jsonb_build_object(
            'response_type', COALESCE(item.value->>'response_type', 'confirmation'),
            'requires_dori_verification', COALESCE((item.value->>'requires_dori_verification')::boolean, false)
        )
    FROM jsonb_array_elements(p_requirements) item
    WHERE requirement.request_id = v_result.id
      AND requirement.code = item.value->>'code';

    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.publish_acquisition_request(
    text, text[], integer, integer, integer, integer, text, timestamptz,
    timestamptz, jsonb, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.publish_acquisition_request(
    text, text[], integer, integer, integer, integer, text, timestamptz,
    timestamptz, jsonb, text
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.submit_acquisition_offer(
    p_offer_id uuid, p_request_id uuid, p_vin text, p_model text,
    p_version text, p_year integer, p_mileage integer,
    p_declared_soh numeric, p_color text, p_price_mxn numeric,
    p_transfer_included boolean, p_committed_delivery_date timestamptz,
    p_evidence jsonb, p_idempotency_key text
)
RETURNS public.acquisition_offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_now timestamptz := app.env_now(v_environment_id);
    v_request public.acquisition_requests%ROWTYPE;
    v_result public.acquisition_offers%ROWTYPE;
BEGIN
    SELECT * INTO v_request FROM public.acquisition_requests request
    WHERE request.id = p_request_id AND request.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_acquisition_request_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_request.deadline_at IS NOT NULL AND v_now > v_request.deadline_at THEN
        RAISE EXCEPTION 'acquisition_request_offer_deadline_passed' USING ERRCODE = '55000';
    END IF;
    IF p_committed_delivery_date IS NULL THEN
        RAISE EXCEPTION 'supplier_delivery_commitment_required' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_result FROM public.submit_acquisition_offer(
        p_offer_id, p_request_id, p_vin, p_model, p_version, p_year,
        p_mileage, p_declared_soh, p_color, p_price_mxn,
        p_transfer_included, p_evidence, p_idempotency_key
    );

    UPDATE public.acquisition_offers
    SET committed_delivery_date = p_committed_delivery_date::date
    WHERE id = v_result.id
    RETURNING * INTO v_result;
    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_acquisition_offer(
    uuid, uuid, text, text, text, integer, integer, numeric, text, numeric,
    boolean, timestamptz, jsonb, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_acquisition_offer(
    uuid, uuid, text, text, text, integer, integer, numeric, text, numeric,
    boolean, timestamptz, jsonb, text
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.change_acquisition_delivery_commitment(
    p_offer_id uuid, p_committed_date date, p_reason text, p_idempotency_key text
)
RETURNS public.acquisition_offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_profile_id uuid := app.auth_profile_id();
    v_supplier_id uuid := app.auth_acquisition_supplier_id();
    v_now timestamptz := app.env_now(v_environment_id);
    v_offer public.acquisition_offers%ROWTYPE;
    v_command public.command_log%ROWTYPE;
BEGIN
    IF v_supplier_id IS NULL OR p_committed_date IS NULL OR btrim(COALESCE(p_reason, '')) = '' THEN
        RAISE EXCEPTION 'invalid_delivery_commitment_change' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_offer FROM public.acquisition_offers offer
    WHERE offer.id = p_offer_id AND offer.environment_id = v_environment_id
      AND offer.supplier_id = v_supplier_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'acquisition_offer_access_denied' USING ERRCODE = '42501';
    END IF;
    v_command := app.begin_acquisition_command(
        'change_acquisition_delivery_commitment', p_idempotency_key,
        jsonb_build_object('offer_id', p_offer_id, 'committed_date', p_committed_date, 'reason', btrim(p_reason))
    );
    IF v_command.result_payload IS NOT NULL THEN RETURN v_offer; END IF;
    INSERT INTO public.acquisition_delivery_commitment_history(
        environment_id, offer_id, previous_date, committed_date, reason, changed_by, created_at
    ) VALUES (
        v_environment_id, p_offer_id, v_offer.committed_delivery_date,
        p_committed_date, btrim(p_reason), v_profile_id, v_now
    );
    UPDATE public.acquisition_offers SET committed_delivery_date = p_committed_date,
        revision = revision + 1, updated_at = v_now WHERE id = p_offer_id RETURNING * INTO v_offer;
    PERFORM app.finish_acquisition_command(
        v_command.id, jsonb_build_object('offer_id', p_offer_id, 'committed_date', p_committed_date),
        'acquisition.offer.delivery_commitment_changed', 'acquisition_offer', p_offer_id,
        jsonb_build_object('previous_date', v_offer.committed_delivery_date, 'reason', btrim(p_reason))
    );
    RETURN v_offer;
END;
$function$;

REVOKE ALL ON FUNCTION public.change_acquisition_delivery_commitment(uuid, date, text, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_acquisition_delivery_commitment(uuid, date, text, text)
TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reset_test_acquisition_environment(p_confirmation text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_environment_code text;
    v_now timestamptz := app.env_now(v_environment_id);
    v_profile_id uuid := app.auth_profile_id();
    v_deleted_requests bigint;
BEGIN
    IF NOT app.auth_is_acquisition_admin() OR p_confirmation <> 'LIMPIAR TEST' THEN
        RAISE EXCEPTION 'test_environment_reset_denied' USING ERRCODE = '42501';
    END IF;
    SELECT code INTO v_environment_code FROM public.environments WHERE id = v_environment_id;
    IF v_environment_code IS DISTINCT FROM 'test' THEN
        RAISE EXCEPTION 'test_environment_required' USING ERRCODE = '42501';
    END IF;

    DELETE FROM storage.objects
    WHERE bucket_id IN ('acquisition-evidence', 'acquisition-chat-attachments')
      AND (storage.foldername(name))[1] = v_environment_id::text;
    DELETE FROM public.acquisition_notifications WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_chat_read_receipts WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_chat_messages WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_chat_threads WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_orders WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_offers WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_requests WHERE environment_id = v_environment_id;
    GET DIAGNOSTICS v_deleted_requests = ROW_COUNT;
    DELETE FROM public.command_log
    WHERE environment_id = v_environment_id AND command_name LIKE '%acquisition%';
    DELETE FROM public.audit_log
    WHERE environment_id = v_environment_id AND event_type LIKE 'acquisition.%';

    INSERT INTO public.audit_log(environment_id, actor_profile_id, event_type, entity_type, metadata, recorded_at)
    VALUES (
        v_environment_id, v_profile_id, 'acquisition.test_environment.reset',
        'environment', jsonb_build_object('deleted_requests', v_deleted_requests), v_now
    );
    RETURN jsonb_build_object('environment_id', v_environment_id, 'deleted_requests', v_deleted_requests);
END;
$function$;

REVOKE ALL ON FUNCTION public.reset_test_acquisition_environment(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_test_acquisition_environment(text) TO authenticated, service_role;
