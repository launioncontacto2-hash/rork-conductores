-- DORI Adquisicion: limpieza reproducible y segura del entorno TEST.
--
-- Los objetos se eliminan mediante la API de Storage. Esta migracion expone
-- una lista cerrada de rutas, habilita DELETE solo al administrador DORI de
-- TEST y finaliza la limpieza transaccional unicamente cuando Storage ya esta
-- vacio para el environment actual.

DROP POLICY IF EXISTS acquisition_test_evidence_objects_delete
ON storage.objects;

CREATE POLICY acquisition_test_evidence_objects_delete
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id IN ('acquisition-evidence', 'acquisition-chat-attachments')
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND app.auth_is_acquisition_admin()
    AND EXISTS (
        SELECT 1
        FROM public.environments environment
        WHERE environment.id = app.current_environment_id()
          AND environment.code = 'test'
    )
);

CREATE OR REPLACE FUNCTION public.plan_test_acquisition_environment_reset(
    p_confirmation text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_environment_code text;
    v_objects jsonb;
    v_counts jsonb;
BEGIN
    IF NOT app.auth_is_acquisition_admin() OR p_confirmation <> 'LIMPIAR TEST' THEN
        RAISE EXCEPTION 'test_environment_reset_denied' USING ERRCODE = '42501';
    END IF;

    SELECT code INTO v_environment_code
    FROM public.environments
    WHERE id = v_environment_id;

    IF v_environment_code IS DISTINCT FROM 'test' THEN
        RAISE EXCEPTION 'test_environment_required' USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object('bucket', object.bucket_id, 'path', object.name)
            ORDER BY object.bucket_id, object.name
        ),
        '[]'::jsonb
    )
    INTO v_objects
    FROM storage.objects object
    WHERE object.bucket_id IN ('acquisition-evidence', 'acquisition-chat-attachments')
      AND (storage.foldername(object.name))[1] = v_environment_id::text;

    SELECT jsonb_build_object(
        'requests', (SELECT count(*) FROM public.acquisition_requests WHERE environment_id = v_environment_id),
        'request_rules', (SELECT count(*) FROM public.acquisition_request_rules WHERE environment_id = v_environment_id),
        'request_requirements', (SELECT count(*) FROM public.acquisition_request_requirements WHERE environment_id = v_environment_id),
        'offers', (SELECT count(*) FROM public.acquisition_offers WHERE environment_id = v_environment_id),
        'evidence', (SELECT count(*) FROM public.acquisition_evidence WHERE environment_id = v_environment_id),
        'assessments', (SELECT count(*) FROM public.acquisition_offer_assessments WHERE environment_id = v_environment_id),
        'negotiations', (SELECT count(*) FROM public.acquisition_negotiations WHERE environment_id = v_environment_id),
        'orders', (SELECT count(*) FROM public.acquisition_orders WHERE environment_id = v_environment_id),
        'deliveries', (SELECT count(*) FROM public.acquisition_deliveries WHERE environment_id = v_environment_id),
        'receptions', (SELECT count(*) FROM public.acquisition_receptions WHERE environment_id = v_environment_id),
        'holds', (SELECT count(*) FROM public.acquisition_holds WHERE environment_id = v_environment_id),
        'delivery_commitments', (SELECT count(*) FROM public.acquisition_delivery_commitment_history WHERE environment_id = v_environment_id),
        'threads', (SELECT count(*) FROM public.acquisition_chat_threads WHERE environment_id = v_environment_id),
        'messages', (SELECT count(*) FROM public.acquisition_chat_messages WHERE environment_id = v_environment_id),
        'read_receipts', (SELECT count(*) FROM public.acquisition_chat_read_receipts WHERE environment_id = v_environment_id),
        'notifications', (SELECT count(*) FROM public.acquisition_notifications WHERE environment_id = v_environment_id),
        'storage_objects', jsonb_array_length(v_objects)
    ) INTO v_counts;

    RETURN jsonb_build_object(
        'environment_id', v_environment_id,
        'counts', v_counts,
        'storage_objects', v_objects
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.plan_test_acquisition_environment_reset(text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.plan_test_acquisition_environment_reset(text)
TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reset_test_acquisition_environment(
    p_confirmation text
)
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
    v_storage_count bigint;
    v_before jsonb;
    v_after jsonb;
BEGIN
    IF NOT app.auth_is_acquisition_admin() OR p_confirmation <> 'LIMPIAR TEST' THEN
        RAISE EXCEPTION 'test_environment_reset_denied' USING ERRCODE = '42501';
    END IF;

    SELECT code INTO v_environment_code
    FROM public.environments
    WHERE id = v_environment_id;

    IF v_environment_code IS DISTINCT FROM 'test' THEN
        RAISE EXCEPTION 'test_environment_required' USING ERRCODE = '42501';
    END IF;

    SELECT count(*) INTO v_storage_count
    FROM storage.objects object
    WHERE object.bucket_id IN ('acquisition-evidence', 'acquisition-chat-attachments')
      AND (storage.foldername(object.name))[1] = v_environment_id::text;

    IF v_storage_count <> 0 THEN
        RAISE EXCEPTION 'test_environment_storage_not_empty'
            USING ERRCODE = '55000',
                  DETAIL = format('%s authorized TEST objects remain', v_storage_count),
                  HINT = 'Delete the planned objects through the Storage API before finalizing.';
    END IF;

    SELECT jsonb_build_object(
        'requests', (SELECT count(*) FROM public.acquisition_requests WHERE environment_id = v_environment_id),
        'request_rules', (SELECT count(*) FROM public.acquisition_request_rules WHERE environment_id = v_environment_id),
        'request_requirements', (SELECT count(*) FROM public.acquisition_request_requirements WHERE environment_id = v_environment_id),
        'offers', (SELECT count(*) FROM public.acquisition_offers WHERE environment_id = v_environment_id),
        'evidence', (SELECT count(*) FROM public.acquisition_evidence WHERE environment_id = v_environment_id),
        'assessments', (SELECT count(*) FROM public.acquisition_offer_assessments WHERE environment_id = v_environment_id),
        'negotiations', (SELECT count(*) FROM public.acquisition_negotiations WHERE environment_id = v_environment_id),
        'orders', (SELECT count(*) FROM public.acquisition_orders WHERE environment_id = v_environment_id),
        'deliveries', (SELECT count(*) FROM public.acquisition_deliveries WHERE environment_id = v_environment_id),
        'receptions', (SELECT count(*) FROM public.acquisition_receptions WHERE environment_id = v_environment_id),
        'holds', (SELECT count(*) FROM public.acquisition_holds WHERE environment_id = v_environment_id),
        'delivery_commitments', (SELECT count(*) FROM public.acquisition_delivery_commitment_history WHERE environment_id = v_environment_id),
        'threads', (SELECT count(*) FROM public.acquisition_chat_threads WHERE environment_id = v_environment_id),
        'messages', (SELECT count(*) FROM public.acquisition_chat_messages WHERE environment_id = v_environment_id),
        'read_receipts', (SELECT count(*) FROM public.acquisition_chat_read_receipts WHERE environment_id = v_environment_id),
        'notifications', (SELECT count(*) FROM public.acquisition_notifications WHERE environment_id = v_environment_id)
    ) INTO v_before;

    -- Allowlist explicita y ordenada por dependencias. Los hijos directos de
    -- solicitud/oferta se eliminan por sus FK ON DELETE CASCADE.
    DELETE FROM public.acquisition_notifications WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_chat_read_receipts WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_chat_messages WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_chat_threads WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_orders WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_offers WHERE environment_id = v_environment_id;
    DELETE FROM public.acquisition_requests WHERE environment_id = v_environment_id;
    DELETE FROM public.command_log
    WHERE environment_id = v_environment_id AND command_name LIKE '%acquisition%';
    DELETE FROM public.audit_log
    WHERE environment_id = v_environment_id AND event_type LIKE 'acquisition.%';

    SELECT jsonb_build_object(
        'requests', (SELECT count(*) FROM public.acquisition_requests WHERE environment_id = v_environment_id),
        'request_rules', (SELECT count(*) FROM public.acquisition_request_rules WHERE environment_id = v_environment_id),
        'request_requirements', (SELECT count(*) FROM public.acquisition_request_requirements WHERE environment_id = v_environment_id),
        'offers', (SELECT count(*) FROM public.acquisition_offers WHERE environment_id = v_environment_id),
        'evidence', (SELECT count(*) FROM public.acquisition_evidence WHERE environment_id = v_environment_id),
        'assessments', (SELECT count(*) FROM public.acquisition_offer_assessments WHERE environment_id = v_environment_id),
        'negotiations', (SELECT count(*) FROM public.acquisition_negotiations WHERE environment_id = v_environment_id),
        'orders', (SELECT count(*) FROM public.acquisition_orders WHERE environment_id = v_environment_id),
        'deliveries', (SELECT count(*) FROM public.acquisition_deliveries WHERE environment_id = v_environment_id),
        'receptions', (SELECT count(*) FROM public.acquisition_receptions WHERE environment_id = v_environment_id),
        'holds', (SELECT count(*) FROM public.acquisition_holds WHERE environment_id = v_environment_id),
        'delivery_commitments', (SELECT count(*) FROM public.acquisition_delivery_commitment_history WHERE environment_id = v_environment_id),
        'threads', (SELECT count(*) FROM public.acquisition_chat_threads WHERE environment_id = v_environment_id),
        'messages', (SELECT count(*) FROM public.acquisition_chat_messages WHERE environment_id = v_environment_id),
        'read_receipts', (SELECT count(*) FROM public.acquisition_chat_read_receipts WHERE environment_id = v_environment_id),
        'notifications', (SELECT count(*) FROM public.acquisition_notifications WHERE environment_id = v_environment_id),
        'storage_objects', 0
    ) INTO v_after;

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
