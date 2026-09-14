BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(18);

SELECT has_column('public', 'acquisition_requests', 'target_delivery_date', 'la solicitud conserva fecha objetivo');
SELECT has_column('public', 'acquisition_offers', 'committed_delivery_date', 'la oferta conserva compromiso del proveedor');
SELECT has_column('public', 'acquisition_request_requirements', 'response_type', 'el requisito define tipo de respuesta');
SELECT has_column('public', 'acquisition_request_requirements', 'requires_dori_verification', 'el requisito define verificación DORI');
SELECT has_table('public', 'acquisition_delivery_commitment_history', 'existe historial inmutable de compromisos');
SELECT has_function(
    'public', 'publish_acquisition_request',
    ARRAY['text','text[]','integer','integer','integer','integer','text','timestamp with time zone','date','jsonb','text'],
    'publicación recibe vigencia y fecha objetivo'
);
SELECT hasnt_function(
    'public', 'publish_acquisition_request',
    ARRAY['text','text[]','integer','integer','integer','integer','text','timestamp with time zone','jsonb','text'],
    'no queda la firma pública anterior sin fecha objetivo'
);
SELECT hasnt_function(
    'public', 'publish_acquisition_request',
    ARRAY['text','text[]','integer','integer','integer','integer','text','timestamp with time zone','timestamp with time zone','jsonb','text'],
    'no queda una sobrecarga pública con fecha objetivo como timestamp'
);
SELECT hasnt_function(
    'public', 'publish_acquisition_request',
    ARRAY['text','text','integer','text','text[]','integer','integer','integer','text','timestamp with time zone','numeric','numeric','numeric','text'],
    'no queda la firma pública legada con reglas internas'
);
SELECT has_function(
    'public', 'submit_acquisition_offer',
    ARRAY['uuid','uuid','text','text','text','integer','integer','numeric','text','numeric','boolean','timestamp with time zone','jsonb','text'],
    'oferta recibe compromiso formal'
);
SELECT has_function('public', 'change_acquisition_delivery_commitment', ARRAY['uuid','date','text','text'], 'cambio de compromiso exige motivo');
SELECT has_function('public', 'reset_test_acquisition_environment', ARRAY['text'], 'limpieza TEST usa RPC autorizado');
SELECT has_function('public', 'plan_test_acquisition_environment_reset', ARRAY['text'], 'limpieza TEST obtiene una allowlist cerrada de Storage');
SELECT is(
    (
        SELECT count(*)::bigint
        FROM pg_catalog.pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'acquisition_test_evidence_objects_delete'
          AND cmd = 'DELETE'
    ),
    1::bigint,
    'Storage incluye DELETE limitado al administrador DORI de TEST'
);
SELECT table_privs_are(
    'public', 'acquisition_delivery_commitment_history', 'authenticated', ARRAY['SELECT'],
    'el cliente no altera directamente el historial'
);

CREATE TEMP TABLE test_dates_scope AS
SELECT id AS environment_id, app.env_now(id) AS now_at
FROM public.environments ORDER BY created_at, id LIMIT 1;
GRANT SELECT ON test_dates_scope TO authenticated;

INSERT INTO public.profiles(id, environment_id, employee_number, display_name, status)
SELECT 'ad900000-0000-4000-8000-000000000001', environment_id,
       'ADQ-DATE-ADMIN', 'Administrador fechas', 'active'
FROM test_dates_scope;

INSERT INTO public.acquisition_memberships(id, environment_id, profile_id, supplier_id, role, status, starts_at)
SELECT 'ad910000-0000-4000-8000-000000000001', environment_id,
       'ad900000-0000-4000-8000-000000000001', NULL, 'dori_admin', 'active',
       app.env_now(environment_id) - interval '1 day'
FROM test_dates_scope;

CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $function$;

SELECT set_config('request.jwt.claim.sub', 'ad900000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$ SELECT public.publish_acquisition_request(
        'Dolphin Mini', ARRAY['Plus'], 1, 2025, 2026, 20000, 'Puebla', NULL,
        ((SELECT now_at FROM test_dates_scope) + interval '30 days')::date,
        '[{"code":"vin","category":"evidence","title":"VIN","value":"Legible"}]'::jsonb,
        'dates-null-deadline'
    ) $sql$,
    '22023', 'acquisition_request_deadline_must_be_future',
    'backend rechaza publicación sin vigencia'
);
SELECT lives_ok(
    $sql$ SELECT public.publish_acquisition_request(
        'Dolphin Mini', ARRAY['Plus'], 1, 2025, 2026, 20000, 'Puebla',
        (SELECT now_at FROM test_dates_scope) + interval '14 days',
        ((SELECT now_at FROM test_dates_scope) + interval '30 days')::date,
        '[{"code":"vin","category":"evidence","title":"VIN","value":"Legible","response_type":"photo","requires_dori_verification":true}]'::jsonb,
        'dates-valid'
    ) $sql$,
    'DORI publica con fechas autoritativas'
);
RESET ROLE;

SELECT is(
    (SELECT requirement.response_type
     FROM public.acquisition_request_requirements requirement
     JOIN public.acquisition_requests request ON request.id = requirement.request_id
     WHERE requirement.code = 'vin' AND request.model = 'Dolphin Mini'
     ORDER BY requirement.created_at DESC LIMIT 1),
    'photo', 'se persiste el tipo de respuesta dinámico'
);

SELECT * FROM finish();
ROLLBACK;
