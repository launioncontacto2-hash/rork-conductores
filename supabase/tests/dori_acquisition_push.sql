BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(21);

SELECT has_table('public', 'acquisition_push_devices', 'existe registro privado de dispositivos');
SELECT has_table('public', 'acquisition_notifications', 'existe outbox autoritativo de notificaciones');
SELECT has_function('public', 'register_acquisition_push_device', ARRAY['text','text','text','text'], 'existe RPC de registro');
SELECT has_function('public', 'revoke_acquisition_push_device', ARRAY['text'], 'existe RPC de revocacion');
SELECT has_function('public', 'acquisition_notification_badge_count', ARRAY[]::text[], 'existe RPC de badge');
SELECT has_function('public', 'acquisition_unread_offer_ids', ARRAY[]::text[], 'existe RPC de actividad no leida');
SELECT has_function('public', 'mark_acquisition_notification_context_read', ARRAY['text','uuid'], 'existe RPC de lectura por contexto');
SELECT has_column('public', 'acquisition_push_devices', 'app_environment', 'token separa TEST y produccion');
SELECT has_column('public', 'acquisition_push_devices', 'revoked_at', 'token conserva revocacion');
SELECT ok(NOT has_table_privilege('authenticated', 'public.acquisition_push_devices', 'SELECT'), 'cliente no enumera tokens');
SELECT ok(NOT has_table_privilege('authenticated', 'public.acquisition_push_devices', 'INSERT'), 'cliente no inserta tokens directamente');

CREATE TEMP TABLE test_push_scope AS
SELECT id AS environment_id FROM public.environments WHERE code = 'test' LIMIT 1;

INSERT INTO public.profiles(id, environment_id, employee_number, display_name, status)
SELECT fixture.id, scope.environment_id, fixture.employee_number, fixture.display_name, 'active'
FROM test_push_scope scope
CROSS JOIN (VALUES
    ('ad910000-0000-4000-8000-000000000001'::uuid, 'PUSH-ADMIN', 'Administrador Push'),
    ('ad910000-0000-4000-8000-000000000002'::uuid, 'PUSH-PROV', 'Proveedor Push')
) fixture(id, employee_number, display_name);

INSERT INTO public.acquisition_suppliers(id, environment_id, code, name, city)
SELECT 'ad920000-0000-4000-8000-000000000001', environment_id,
       'PUSH-SUP', 'BYD Push', 'Puebla' FROM test_push_scope;

INSERT INTO public.acquisition_memberships(id, environment_id, profile_id, supplier_id, role, status, starts_at)
SELECT fixture.id, scope.environment_id, fixture.profile_id, fixture.supplier_id,
       fixture.role, 'active', app.env_now(scope.environment_id) - interval '1 day'
FROM test_push_scope scope
CROSS JOIN (VALUES
    ('ad930000-0000-4000-8000-000000000001'::uuid, 'ad910000-0000-4000-8000-000000000001'::uuid, NULL::uuid, 'dori_admin'),
    ('ad930000-0000-4000-8000-000000000002'::uuid, 'ad910000-0000-4000-8000-000000000002'::uuid, 'ad920000-0000-4000-8000-000000000001'::uuid, 'provider')
) fixture(id, profile_id, supplier_id, role);

INSERT INTO public.acquisition_requests(
    id, environment_id, code, title, target_quantity, model, versions,
    minimum_year, maximum_year, maximum_mileage, delivery_city,
    status, created_by, created_at, updated_at
)
SELECT 'ad940000-0000-4000-8000-000000000001', environment_id,
       'PUSH-REQ', 'Dolphin Mini para Puebla', 1, 'Dolphin Mini', ARRAY['Plus'],
       2025, 2026, 20000, 'Puebla', 'evaluating',
       'ad910000-0000-4000-8000-000000000001', app.env_now(environment_id), app.env_now(environment_id)
FROM test_push_scope;

INSERT INTO public.acquisition_offers(
    id, environment_id, request_id, supplier_id, created_by, vin, model,
    version, year, mileage, color, price_mxn, transfer_included,
    status, submitted_at, updated_at
)
SELECT 'ad950000-0000-4000-8000-000000000001', environment_id,
       'ad940000-0000-4000-8000-000000000001', 'ad920000-0000-4000-8000-000000000001',
       'ad910000-0000-4000-8000-000000000002', 'LGXCE6CB1S0095011', 'Dolphin Mini',
       'Plus', 2025, 8400, 'Blanco', 295000, true, 'negotiating',
       app.env_now(environment_id), app.env_now(environment_id)
FROM test_push_scope;

CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $function$;

SELECT set_config('request.jwt.claim.sub', 'ad910000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.register_acquisition_push_device(
      repeat('a', 64), 'ios', 'test', 'com.turnoev.mobility') $sql$,
    'proveedor registra token APNs TEST por RPC'
);
SELECT throws_ok(
    $sql$ SELECT public.register_acquisition_push_device(
      repeat('b', 64), 'ios', 'prod', 'com.turnoev.mobility') $sql$,
    '22023', 'invalid_acquisition_push_device',
    'token de produccion no entra al entorno TEST'
);
RESET ROLE;

SELECT is(
    (SELECT profile_id FROM public.acquisition_push_devices WHERE device_token = repeat('a', 64)),
    'ad910000-0000-4000-8000-000000000002'::uuid,
    'token queda ligado al perfil autenticado sin exponerlo'
);

INSERT INTO public.audit_log(
    environment_id, actor_profile_id, event_type, entity_type,
    entity_id, metadata, occurred_at
)
SELECT environment_id, 'ad910000-0000-4000-8000-000000000002',
       'acquisition.offer.counteroffer', 'acquisition_offer',
       'ad950000-0000-4000-8000-000000000001',
       jsonb_build_object('actor_role', 'provider', 'amount_mxn', 293000),
       app.env_now(environment_id)
FROM test_push_scope;

SELECT is(
    (SELECT count(*)::bigint FROM public.acquisition_notifications
     WHERE recipient_profile_id = 'ad910000-0000-4000-8000-000000000001'),
    1::bigint,
    'evento del proveedor crea una notificacion para DORI'
);
SELECT is(
    (SELECT body FROM public.acquisition_notifications
     WHERE recipient_profile_id = 'ad910000-0000-4000-8000-000000000001'),
    'Nuevo precio: $293,000',
    'push contiene monto comercial comprensible'
);
SELECT ok(
    (SELECT deep_link->>'offer_id' FROM public.acquisition_notifications LIMIT 1)
      = 'ad950000-0000-4000-8000-000000000001',
    'push conserva deep link a la unidad'
);

SELECT set_config('request.jwt.claim.sub', 'ad910000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*)::bigint FROM public.acquisition_notifications), 0::bigint, 'proveedor no lee notificacion privada de DORI');
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad910000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT is(public.acquisition_notification_badge_count(), 1::bigint, 'badge autoritativo cuenta pendientes');
SELECT is(
    public.mark_acquisition_notification_context_read('offer', 'ad950000-0000-4000-8000-000000000001'),
    1::bigint,
    'abrir la unidad marca su contexto como leido'
);
SELECT is(public.acquisition_notification_badge_count(), 0::bigint, 'badge queda sincronizado despues de leer');
RESET ROLE;

SELECT finish();
ROLLBACK;
