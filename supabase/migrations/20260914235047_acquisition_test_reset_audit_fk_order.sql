-- Conserva el historial append-only de audit_log y los command_log que este
-- referencia. El reset elimina solamente el estado transaccional mutable de
-- Adquisicion y reutiliza el plan autoritativo para los conteos antes/despues.

CREATE OR REPLACE FUNCTION public.reset_test_acquisition_environment(
    p_confirmation text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_plan jsonb := public.plan_test_acquisition_environment_reset(p_confirmation);
    v_environment_id uuid := (v_plan->>'environment_id')::uuid;
    v_now timestamptz := app.env_now(v_environment_id);
    v_profile_id uuid := app.auth_profile_id();
    v_storage_count bigint := COALESCE((v_plan->'counts'->>'storage_objects')::bigint, 0);
    v_before jsonb := v_plan->'counts';
    v_after jsonb;
BEGIN
    IF v_storage_count <> 0 THEN
        RAISE EXCEPTION 'test_environment_storage_not_empty'
            USING ERRCODE = '55000',
                  DETAIL = format('%s authorized TEST objects remain', v_storage_count),
                  HINT = 'Delete the planned objects through the Storage API before finalizing.';
    END IF;

    DELETE FROM public.acquisition_notifications WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_chat_read_receipts WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_chat_messages WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_chat_threads WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_orders WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_offers WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_requests WHERE environment_id = v_environment_id;

    -- audit_log es append-only por contrato y mantiene FK RESTRICT hacia
    -- command_log. Ambos se conservan como evidencia historica; no forman
    -- parte del estado operativo que reconstruyen los dashboards.

    v_after := (
        public.plan_test_acquisition_environment_reset(p_confirmation)->'counts'
    );

    INSERT INTO public.audit_log(
        environment_id, actor_profile_id, event_type, entity_type, metadata, recorded_at
    ) VALUES (
        v_environment_id,
        v_profile_id,
        'acquisition.test_environment.reset',
        'environment',
        jsonb_build_object('before', v_before, 'after', v_after),
        v_now
    );

    RETURN jsonb_build_object(
        'environment_id', v_environment_id,
        'before', v_before,
        'after', v_after
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.reset_test_acquisition_environment(text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_test_acquisition_environment(text)
TO authenticated, service_role;



