BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(15);

SELECT has_table(
    'app', 'driver_device_sessions',
    'existe el arrendamiento interno de sesion del conductor'
);
SELECT has_function(
    'public', 'claim_driver_device', ARRAY['text', 'text'],
    'existe claim_driver_device'
);
SELECT has_function(
    'public', 'heartbeat_driver_device', ARRAY['text'],
    'existe heartbeat_driver_device'
);
SELECT is(
    has_function_privilege(
        'authenticated',
        'public.start_shift(uuid,bigint,integer,text)', 'EXECUTE'
    ),
    false,
    'el cliente no puede saltarse el control usando start_shift legado'
);
SELECT is(
    has_function_privilege(
        'authenticated',
        'public.start_shift_v2(uuid,bigint,integer,text,text)', 'EXECUTE'
    ),
    true,
    'authenticated puede ejecutar start_shift_v2'
);

INSERT INTO public.stations (
    id, environment_id, region_id, code, name, status, timezone
)
SELECT
    '16a40000-0000-4000-8000-000000000001'::uuid,
    r.environment_id,
    r.id,
    '16a-device-station',
    '16A Device Station',
    'active',
    'America/Mexico_City'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE test_16a_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = '16a40000-0000-4000-8000-000000000001'::uuid;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT fixture.profile_id, scope.environment_id,
       fixture.employee_number, fixture.display_name, 'active'
FROM test_16a_scope scope
CROSS JOIN (
    VALUES
        (
            '16a00000-0000-4000-8000-000000000001'::uuid,
            '16A-DRIVER', '16A Driver'
        ),
        (
            '16a00000-0000-4000-8000-000000000002'::uuid,
            '16A-SUPERVISOR', '16A Supervisor'
        )
) AS fixture(profile_id, employee_number, display_name);

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role,
    starts_at, shift_group, shift_slot
)
SELECT fixture.membership_id, scope.environment_id,
       fixture.profile_id, scope.station_id, fixture.role,
       '2000-01-01 00:00:00+00'::timestamptz,
       fixture.shift_group, fixture.shift_slot
FROM test_16a_scope scope
CROSS JOIN (
    VALUES
        (
            '16a10000-0000-4000-8000-000000000001'::uuid,
            '16a00000-0000-4000-8000-000000000001'::uuid,
            'driver', 'weekday', 'morning'
        ),
        (
            '16a10000-0000-4000-8000-000000000002'::uuid,
            '16a00000-0000-4000-8000-000000000002'::uuid,
            'supervisor', NULL::text, NULL::text
        )
) AS fixture(
    membership_id, profile_id, role, shift_group, shift_slot
);

-- El resolvedor transaccional permite probar identidades sin crear auth.users.
CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, app, auth, pg_temp
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

SELECT set_config(
    'request.jwt.claim.sub',
    '16a00000-0000-4000-8000-000000000001', true
);
SELECT set_config(
    'request.jwt.claims',
    '{"session_id":"16a60000-0000-4000-8000-000000000001"}', true
);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
    $sql$ SELECT public.claim_driver_device('16a-iphone-1', 'pgtap') $sql$,
    'el primer iPhone toma el control'
);
SELECT lives_ok(
    $sql$ SELECT public.heartbeat_driver_device('16a-iphone-1') $sql$,
    'el primer iPhone conserva el control'
);

RESET ROLE;
SELECT set_config(
    'request.jwt.claims',
    '{"session_id":"16a60000-0000-4000-8000-000000000002"}', true
);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
    $sql$ SELECT public.claim_driver_device('16a-iphone-2', 'pgtap') $sql$,
    'el segundo inicio de sesion toma el control'
);
SELECT lives_ok(
    $sql$ SELECT public.heartbeat_driver_device('16a-iphone-2') $sql$,
    'el segundo iPhone queda activo'
);

RESET ROLE;
SELECT set_config(
    'request.jwt.claims',
    '{"session_id":"16a60000-0000-4000-8000-000000000001"}', true
);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
    $sql$ SELECT public.heartbeat_driver_device('16a-iphone-1') $sql$,
    '42501', 'driver_session_replaced',
    'la sesion anterior deja de ser operativa'
);

RESET ROLE;
SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.devices d
        WHERE d.profile_id = '16a00000-0000-4000-8000-000000000001'::uuid
          AND d.deleted_at IS NULL
    ),
    1::bigint,
    'solo queda un dispositivo activo para el conductor'
);
SELECT results_eq(
    $sql$
        SELECT d.install_id
        FROM public.devices d
        WHERE d.profile_id = '16a00000-0000-4000-8000-000000000001'::uuid
          AND d.deleted_at IS NULL
    $sql$,
    $sql$ VALUES ('16a-iphone-2'::text) $sql$,
    'el dispositivo activo es el ultimo que inicio sesion'
);

SELECT set_config(
    'request.jwt.claim.sub',
    '16a00000-0000-4000-8000-000000000002', true
);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
    $sql$
        SELECT public.touch_device(
            '16a-supervisor-iphone',
            '16a10000-0000-4000-8000-000000000002'::uuid,
            'ios', 'pgtap'
        )
    $sql$,
    'el supervisor registra su iPhone'
);
SELECT lives_ok(
    $sql$
        SELECT public.touch_device(
            '16a-supervisor-web',
            '16a10000-0000-4000-8000-000000000002'::uuid,
            'web', 'pgtap'
        )
    $sql$,
    'el supervisor registra tambien la consola'
);

RESET ROLE;
SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.devices d
        WHERE d.profile_id = '16a00000-0000-4000-8000-000000000002'::uuid
          AND d.deleted_at IS NULL
    ),
    2::bigint,
    'el supervisor conserva dos dispositivos simultaneos'
);

SELECT * FROM finish();
ROLLBACK;
