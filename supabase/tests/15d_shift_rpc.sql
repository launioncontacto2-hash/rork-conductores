BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(24);

SELECT has_table('public', 'shifts', 'existe la tabla shifts');
SELECT has_table('public', 'shift_readings', 'existe la tabla shift_readings');
SELECT has_function(
    'public', 'start_shift', ARRAY['uuid', 'bigint', 'integer', 'text'],
    'existe start_shift con el contrato 15D'
);
SELECT has_function(
    'public', 'finish_shift',
    ARRAY['uuid', 'bigint', 'bigint', 'integer', 'text'],
    'existe finish_shift con revision optimista'
);

INSERT INTO public.stations (
    id, environment_id, region_id, code, name, status, timezone
)
SELECT
    '15d40000-0000-4000-8000-000000000001'::uuid,
    r.environment_id,
    r.id,
    '15d-rpc-station',
    '15D RPC Station',
    'active',
    'America/Mexico_City'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE test_15d_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = '15d40000-0000-4000-8000-000000000001'::uuid;

-- Lunes 31 de agosto de 2026, 05:10 en Ciudad de Mexico.
UPDATE app.env_clock c
SET is_simulated = true,
    anchor_logical_at = '2026-08-31 11:10:00+00'::timestamptz,
    anchor_real_at = now(),
    speed = 1,
    is_paused = true
FROM test_15d_scope scope
WHERE c.environment_id = scope.environment_id;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT fixture.profile_id, scope.environment_id,
       fixture.employee_number, fixture.display_name, 'active'
FROM test_15d_scope scope
CROSS JOIN (
    VALUES
        (
            '15d00000-0000-4000-8000-000000000001'::uuid,
            '15D-RPC-SUPERVISOR', '15D RPC Supervisor'
        ),
        (
            '15d00000-0000-4000-8000-000000000002'::uuid,
            '15D-RPC-DRIVER', '15D RPC Driver'
        ),
        (
            '15d00000-0000-4000-8000-000000000003'::uuid,
            '15D-RPC-OTHER', '15D RPC Other Driver'
        )
) AS fixture(profile_id, employee_number, display_name);

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role,
    starts_at, shift_group, shift_slot
)
SELECT fixture.membership_id, scope.environment_id,
       fixture.profile_id, scope.station_id, fixture.role,
       '2026-01-01 00:00:00+00'::timestamptz,
       fixture.shift_group, fixture.shift_slot
FROM test_15d_scope scope
CROSS JOIN (
    VALUES
        (
            '15d10000-0000-4000-8000-000000000001'::uuid,
            '15d00000-0000-4000-8000-000000000001'::uuid,
            'supervisor', NULL::text, NULL::text
        ),
        (
            '15d10000-0000-4000-8000-000000000002'::uuid,
            '15d00000-0000-4000-8000-000000000002'::uuid,
            'driver', 'weekday', 'morning'
        ),
        (
            '15d10000-0000-4000-8000-000000000003'::uuid,
            '15d00000-0000-4000-8000-000000000003'::uuid,
            'driver', 'weekday', 'morning'
        )
) AS fixture(
    membership_id, profile_id, role, shift_group, shift_slot
);

INSERT INTO public.driver_profiles (
    id, environment_id, station_id, profile_id, membership_id,
    employee_number, status
)
SELECT fixture.driver_profile_id, scope.environment_id, scope.station_id,
       fixture.profile_id, fixture.membership_id,
       fixture.employee_number, 'active'
FROM test_15d_scope scope
CROSS JOIN (
    VALUES
        (
            '15d20000-0000-4000-8000-000000000001'::uuid,
            '15d00000-0000-4000-8000-000000000002'::uuid,
            '15d10000-0000-4000-8000-000000000002'::uuid,
            '15D-RPC-DRIVER'
        ),
        (
            '15d20000-0000-4000-8000-000000000002'::uuid,
            '15d00000-0000-4000-8000-000000000003'::uuid,
            '15d10000-0000-4000-8000-000000000003'::uuid,
            '15D-RPC-OTHER'
        )
) AS fixture(
    driver_profile_id, profile_id, membership_id, employee_number
);

INSERT INTO public.vehicles (
    id, environment_id, station_id, internal_number, qr_code,
    model, odometer_km, battery_pct, status
)
SELECT fixture.vehicle_id, scope.environment_id, scope.station_id,
       fixture.internal_number, fixture.qr_code,
       '15D RPC Vehicle', 1000, 80, 'occupied'
FROM test_15d_scope scope
CROSS JOIN (
    VALUES
        (
            '15d30000-0000-4000-8000-000000000001'::uuid,
            '15D-RPC-V1', '15D-RPC-QR1'
        ),
        (
            '15d30000-0000-4000-8000-000000000002'::uuid,
            '15D-RPC-V2', '15D-RPC-QR2'
        )
) AS fixture(vehicle_id, internal_number, qr_code);

INSERT INTO public.assignments (
    id, environment_id, station_id, driver_profile_id, vehicle_id,
    kind, assigned_by, assigned_at
)
SELECT fixture.assignment_id, scope.environment_id, scope.station_id,
       fixture.driver_profile_id, fixture.vehicle_id, 'titular',
       '15d00000-0000-4000-8000-000000000001'::uuid,
       '2026-08-30 12:00:00+00'::timestamptz
FROM test_15d_scope scope
CROSS JOIN (
    VALUES
        (
            '15d50000-0000-4000-8000-000000000001'::uuid,
            '15d20000-0000-4000-8000-000000000001'::uuid,
            '15d30000-0000-4000-8000-000000000001'::uuid
        ),
        (
            '15d50000-0000-4000-8000-000000000002'::uuid,
            '15d20000-0000-4000-8000-000000000002'::uuid,
            '15d30000-0000-4000-8000-000000000002'::uuid
        )
) AS fixture(assignment_id, driver_profile_id, vehicle_id);

-- Sustitucion transaccional del resolvedor; ROLLBACK restaura el real.
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
    '15d00000-0000-4000-8000-000000000003', true
);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
    $sql$
        SELECT public.start_shift(
            '15d50000-0000-4000-8000-000000000001'::uuid,
            1001, 79, '15d-start-denied'
        )
    $sql$,
    '42501',
    'assignment_not_owned_by_authenticated_driver',
    'otro conductor no puede abrir la asignacion'
);

RESET ROLE;
SELECT set_config(
    'request.jwt.claim.sub',
    '15d00000-0000-4000-8000-000000000002', true
);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
    $sql$
        SELECT public.start_shift(
            '15d50000-0000-4000-8000-000000000001'::uuid,
            1001, 79, '15d-start-1'
        )
    $sql$,
    'el conductor abre su turno dentro de la ventana'
);

RESET ROLE;

SELECT is(
    (SELECT count(*)::bigint FROM public.shifts WHERE status = 'open'),
    1::bigint,
    'queda exactamente un turno abierto'
);

SELECT results_eq(
    $sql$
        SELECT shift_group, shift_slot, operating_date, late_minutes
        FROM public.shifts
        WHERE driver_profile_id =
            '15d20000-0000-4000-8000-000000000001'::uuid
    $sql$,
    $sql$
        VALUES ('weekday'::text, 'morning'::text, '2026-08-31'::date, 10)
    $sql$,
    'el servidor deriva bloque, fecha operativa y retraso'
);

SELECT is(
    (SELECT count(*)::bigint FROM public.shift_readings WHERE kind = 'start'),
    1::bigint,
    'la apertura registra una lectura inicial'
);

SELECT results_eq(
    $sql$
        SELECT odometer_km, battery_pct, status
        FROM public.vehicles
        WHERE id = '15d30000-0000-4000-8000-000000000001'::uuid
    $sql$,
    $sql$ VALUES (1001::bigint, 79::integer, 'occupied'::text) $sql$,
    'actualiza lecturas sin liberar la unidad asignada'
);

SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$
        SELECT public.start_shift(
            '15d50000-0000-4000-8000-000000000001'::uuid,
            1001, 79, '15d-start-1'
        )
    $sql$,
    'repetir la clave de apertura devuelve el mismo turno'
);
RESET ROLE;

SELECT is(
    (SELECT count(*)::bigint FROM public.shifts),
    1::bigint,
    'la apertura idempotente no duplica turnos'
);

SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$
        SELECT public.start_shift(
            '15d50000-0000-4000-8000-000000000001'::uuid,
            1002, 79, '15d-start-1'
        )
    $sql$,
    '23505', 'idempotency_key_conflict',
    'una clave no puede reutilizarse con otro payload'
);

SELECT throws_ok(
    $sql$
        SELECT public.finish_shift(
            (SELECT id FROM public.shifts LIMIT 1),
            9, 1010, 60, '15d-finish-wrong-revision'
        )
    $sql$,
    '40001', 'shift_revision_conflict',
    'el cierre rechaza una revision obsoleta'
);

SELECT lives_ok(
    $sql$
        SELECT public.finish_shift(
            (SELECT id FROM public.shifts LIMIT 1),
            1, 1010, 60, '15d-finish-1'
        )
    $sql$,
    'el conductor cierra su turno con la revision vigente'
);
RESET ROLE;

SELECT results_eq(
    $sql$
        SELECT status, revision, end_odometer_km, end_battery_pct
        FROM public.shifts
    $sql$,
    $sql$ VALUES ('closed'::text, 2::bigint, 1010::bigint, 60::integer) $sql$,
    'el turno queda cerrado y avanza su revision'
);

SELECT is(
    (SELECT count(*)::bigint FROM public.shift_readings),
    2::bigint,
    'inicio y cierre quedan como dos lecturas append-only'
);

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.audit_log
        WHERE event_type IN ('shift.started', 'shift.finished')
          AND actor_profile_id =
            '15d00000-0000-4000-8000-000000000002'::uuid
    ),
    2::bigint,
    'inicio y cierre quedan auditados'
);

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.command_log
        WHERE command_name IN ('start_shift', 'finish_shift')
          AND status = 'completed'
    ),
    2::bigint,
    'los dos comandos quedan completados'
);

SELECT throws_ok(
    $sql$
        UPDATE public.shift_readings
        SET battery_pct = 61
        WHERE shift_id = (SELECT id FROM public.shifts LIMIT 1)
    $sql$,
    '42501', 'shift_readings_append_only',
    'una lectura registrada no se puede editar'
);

SELECT is(
    has_table_privilege('authenticated', 'public.shifts', 'SELECT'),
    true,
    'authenticated puede leer shifts sujeto a RLS'
);

SELECT is(
    has_table_privilege('authenticated', 'public.shifts', 'INSERT, UPDATE, DELETE'),
    false,
    'authenticated no puede escribir shifts directamente'
);

SELECT is(
    has_function_privilege(
        'anon', 'public.start_shift(uuid,bigint,integer,text)', 'EXECUTE'
    ),
    false,
    'anon no puede ejecutar start_shift'
);

SELECT is(
    has_function_privilege(
        'authenticated', 'public.start_shift(uuid,bigint,integer,text)', 'EXECUTE'
    ),
    true,
    'authenticated puede ejecutar start_shift'
);

SELECT * FROM finish();
ROLLBACK;
