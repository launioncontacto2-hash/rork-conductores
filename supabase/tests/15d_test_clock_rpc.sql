BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(12);

SELECT has_function(
    'public',
    'update_test_clock',
    ARRAY[
        'uuid', 'timestamp with time zone', 'timestamp with time zone',
        'double precision', 'boolean', 'bigint'
    ],
    'existe update_test_clock con el contrato de iOS'
);

SELECT is(
    has_function_privilege(
        'anon',
        'public.update_test_clock(uuid,timestamptz,timestamptz,double precision,boolean,bigint)',
        'EXECUTE'
    ),
    false,
    'anon no puede mover el reloj TEST'
);

SELECT is(
    has_function_privilege(
        'authenticated',
        'public.update_test_clock(uuid,timestamptz,timestamptz,double precision,boolean,bigint)',
        'EXECUTE'
    ),
    true,
    'authenticated puede invocar el RPC sujeto a autorizacion interna'
);

SELECT is(
    (
        SELECT p.prosecdef
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'update_test_clock'
          AND pg_catalog.pg_get_function_identity_arguments(p.oid) =
              'p_environment_id uuid, p_anchor_simulated_at timestamp with time zone, p_anchor_real_at timestamp with time zone, p_speed double precision, p_is_paused boolean, p_expected_revision bigint'
    ),
    false,
    'el RPC expuesto es SECURITY INVOKER'
);

INSERT INTO public.stations (
    id, environment_id, region_id, code, name, status, timezone
)
SELECT
    '15d41000-0000-4000-8000-000000000001'::uuid,
    r.environment_id,
    r.id,
    '15d-clock-station',
    '15D Clock Station',
    'active',
    'America/Mexico_City'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE test_15d_clock_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = '15d41000-0000-4000-8000-000000000001'::uuid;

-- Las llamadas se ejecutan tras SET LOCAL ROLE authenticated. La tabla
-- temporal conserva como propietario a postgres, por lo que el rol de la
-- sesion necesita lectura explicita para resolver el environment_id.
GRANT SELECT ON test_15d_clock_scope TO authenticated;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT fixture.profile_id, scope.environment_id,
       fixture.employee_number, fixture.display_name, 'active'
FROM test_15d_clock_scope scope
CROSS JOIN (
    VALUES
        (
            '15d01000-0000-4000-8000-000000000001'::uuid,
            '15D-CLOCK-SUPERVISOR', '15D Clock Supervisor'
        ),
        (
            '15d01000-0000-4000-8000-000000000002'::uuid,
            '15D-CLOCK-DRIVER', '15D Clock Driver'
        )
) AS fixture(profile_id, employee_number, display_name);

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role, starts_at,
    shift_group, shift_slot
)
SELECT fixture.membership_id, scope.environment_id,
       fixture.profile_id, scope.station_id, fixture.role,
       '2026-01-01 00:00:00+00'::timestamptz,
       fixture.shift_group, fixture.shift_slot
FROM test_15d_clock_scope scope
CROSS JOIN (
    VALUES
        (
            '15d11000-0000-4000-8000-000000000001'::uuid,
            '15d01000-0000-4000-8000-000000000001'::uuid,
            'supervisor', NULL::text, NULL::text
        ),
        (
            '15d11000-0000-4000-8000-000000000002'::uuid,
            '15d01000-0000-4000-8000-000000000002'::uuid,
            'driver', 'weekday', 'morning'
        )
) AS fixture(
    membership_id, profile_id, role, shift_group, shift_slot
);

-- Sustitucion transaccional del resolvedor. ROLLBACK restaura la funcion real.
CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

SELECT set_config(
    'request.jwt.claim.sub',
    '15d01000-0000-4000-8000-000000000002',
    true
);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
    $sql$
        SELECT public.update_test_clock(
            (SELECT environment_id FROM test_15d_clock_scope),
            '2026-08-31 10:55:00+00'::timestamptz,
            '2026-09-01 04:00:00+00'::timestamptz,
            1, true, NULL
        )
    $sql$,
    '42501',
    'supervisor_role_required_for_test_clock',
    'un conductor autenticado no puede mover el reloj'
);

RESET ROLE;
SELECT set_config(
    'request.jwt.claim.sub',
    '15d01000-0000-4000-8000-000000000001',
    true
);

CREATE TEMP TABLE test_15d_clock_before AS
SELECT revision
FROM public.test_clock
WHERE environment_id = (SELECT environment_id FROM test_15d_clock_scope);

-- Permite que el payload y el mensaje esperado de revision se calculen con
-- el mismo valor capturado antes del cambio de rol.
GRANT SELECT ON test_15d_clock_before TO authenticated;

SET LOCAL ROLE authenticated;

SELECT lives_ok(
    $sql$
        SELECT public.update_test_clock(
            (SELECT environment_id FROM test_15d_clock_scope),
            '2026-08-31 10:55:00+00'::timestamptz,
            '2026-09-01 04:00:00+00'::timestamptz,
            1, true,
            (SELECT revision FROM test_15d_clock_before)
        )
    $sql$,
    'el supervisor mueve el reloj TEST'
);

RESET ROLE;

SELECT results_eq(
    $sql$
        SELECT anchor_simulated_at, anchor_real_at, speed, is_paused
        FROM public.test_clock
        WHERE environment_id =
            (SELECT environment_id FROM test_15d_clock_scope)
    $sql$,
    $sql$
        VALUES (
            '2026-08-31 10:55:00+00'::timestamptz,
            '2026-09-01 04:00:00+00'::timestamptz,
            1::double precision,
            true
        )
    $sql$,
    'el RPC persiste anclas, velocidad y pausa'
);

SELECT is(
    (
        SELECT revision
        FROM public.test_clock
        WHERE environment_id =
            (SELECT environment_id FROM test_15d_clock_scope)
    ),
    (SELECT revision + 1 FROM test_15d_clock_before),
    'la revision avanza exactamente una vez'
);

SET LOCAL ROLE authenticated;

SELECT throws_ok(
    $sql$
        SELECT public.update_test_clock(
            (SELECT environment_id FROM test_15d_clock_scope),
            '2026-08-31 11:00:00+00'::timestamptz,
            '2026-09-01 04:01:00+00'::timestamptz,
            1, true,
            (SELECT revision FROM test_15d_clock_before)
        )
    $sql$,
    '40001',
    'revision_conflict expected=' ||
        (SELECT revision::text FROM test_15d_clock_before) ||
        ' current=' ||
        (SELECT (revision + 1)::text FROM test_15d_clock_before),
    'una revision obsoleta no pisa el cambio vigente'
);

SELECT throws_ok(
    $sql$
        SELECT public.update_test_clock(
            '00000000-0000-4000-8000-000000000099'::uuid,
            '2026-08-31 11:00:00+00'::timestamptz,
            '2026-09-01 04:01:00+00'::timestamptz,
            1, true, NULL
        )
    $sql$,
    '42501',
    'clock_environment_outside_session',
    'el supervisor no puede mover otro entorno'
);

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
    $sql$
        SELECT public.update_test_clock(
            (SELECT environment_id FROM test_15d_clock_scope),
            '2026-08-31 11:00:00+00'::timestamptz,
            '2026-09-01 04:01:00+00'::timestamptz,
            1, true, NULL
        )
    $sql$,
    '42501',
    'authentication_required',
    'sin identidad autenticada el RPC se rechaza'
);

RESET ROLE;

SELECT is(
    (
        SELECT anchor_simulated_at
        FROM public.test_clock
        WHERE environment_id =
            (SELECT environment_id FROM test_15d_clock_scope)
    ),
    '2026-08-31 10:55:00+00'::timestamptz,
    'los intentos rechazados no alteran el reloj'
);

SELECT * FROM finish();
ROLLBACK;
