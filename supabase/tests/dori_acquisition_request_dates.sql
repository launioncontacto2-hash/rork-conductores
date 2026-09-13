BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(13);

SELECT has_column('public', 'acquisition_requests', 'target_delivery_date', 'la solicitud conserva fecha objetivo');
SELECT has_column('public', 'acquisition_offers', 'committed_delivery_date', 'la oferta conserva compromiso del proveedor');
SELECT has_column('public', 'acquisition_request_requirements', 'response_type', 'el requisito define tipo de respuesta');
SELECT has_column('public', 'acquisition_request_requirements', 'requires_dori_verification', 'el requisito define verificación DORI');
SELECT has_table('public', 'acquisition_delivery_commitment_history', 'existe historial inmutable de compromisos');
SELECT has_function(
    'public', 'publish_acquisition_request',
    ARRAY['text','text[]','integer','integer','integer','integer','text','timestamp with time zone','timestamp with time zone','jsonb','text'],
    'publicación recibe vigencia y fecha objetivo'
);
SELECT has_function(
    'public', 'submit_acquisition_offer',
    ARRAY['uuid','uuid','text','text','text','integer','integer','numeric','text','numeric','boolean','timestamp with time zone','jsonb','text'],
    'oferta recibe compromiso formal'
);
SELECT has_function('public', 'change_acquisition_delivery_commitment', ARRAY['uuid','date','text','text'], 'cambio de compromiso exige motivo');
SELECT has_function('public', 'reset_test_acquisition_environment', ARRAY['text'], 'limpieza TEST usa RPC autorizado');
SELECT table_privs_are(
    'public', 'acquisition_delivery_commitment_history', 'authenticated', ARRAY['SELECT'],
    'el cliente no altera directamente el historial'
);

CREATE TEMP TABLE test_dates_scope AS
SELECT id AS environment_id FROM public.environments ORDER BY created_at, id LIMIT 1;

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
        app.env_now(app.current_environment_id()) + interval '30 days',
        '[{"code":"vin","category":"evidence","title":"VIN","value":"Legible"}]'::jsonb,
        'dates-null-deadline'
    ) $sql$,
    '22023', 'acquisition_request_deadline_must_be_future',
    'backend rechaza publicación sin vigencia'
);
SELECT lives_ok(
    $sql$ SELECT public.publish_acquisition_request(
        'Dolphin Mini', ARRAY['Plus'], 1, 2025, 2026, 20000, 'Puebla',
        app.env_now(app.current_environment_id()) + interval '14 days',
        app.env_now(app.current_environment_id()) + interval '30 days',
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
