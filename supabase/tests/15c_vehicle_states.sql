BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(7);

INSERT INTO public.stations (id, environment_id, region_id, code, name, status)
SELECT
    '15c42000-0000-4000-8000-000000000001'::uuid,
    r.environment_id,
    r.id,
    '15c-state-station',
    '15C State Station',
    'active'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE test_15c_state_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = '15c42000-0000-4000-8000-000000000001'::uuid;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT
    '15c02000-0000-4000-8000-000000000001'::uuid,
    environment_id,
    '15C-STATE-ACTOR',
    '15C State Actor',
    'active'
FROM test_15c_state_scope;

INSERT INTO public.vehicles (
    id, environment_id, station_id, internal_number, qr_code, model
)
SELECT
    '15c32000-0000-4000-8000-000000000001'::uuid,
    environment_id,
    station_id,
    '15C-STATE-V1',
    '15C-STATE-QR1',
    '15C State Vehicle'
FROM test_15c_state_scope;

SELECT is(
    (
        SELECT status
        FROM public.vehicles
        WHERE id = '15c32000-0000-4000-8000-000000000001'::uuid
    ),
    'available',
    'el estado inicial del vehiculo es available'
);

UPDATE public.vehicles
SET status = 'maintenance'
WHERE id = '15c32000-0000-4000-8000-000000000001'::uuid;

SELECT lives_ok(
    $sql$
        INSERT INTO public.vehicle_state_transitions (
            environment_id, station_id, vehicle_id, actor_profile_id,
            from_status, to_status, reason
        )
        SELECT environment_id, station_id,
            '15c32000-0000-4000-8000-000000000001'::uuid,
            '15c02000-0000-4000-8000-000000000001'::uuid,
            'available', 'maintenance', 'scheduled test maintenance'
        FROM test_15c_state_scope
    $sql$,
    'registra un cambio de estado valido'
);

SELECT throws_ok(
    $sql$
        INSERT INTO public.vehicle_state_transitions (
            environment_id, station_id, vehicle_id,
            from_status, to_status
        )
        SELECT environment_id, station_id,
            '15c32000-0000-4000-8000-000000000001'::uuid,
            'maintenance', 'maintenance'
        FROM test_15c_state_scope
    $sql$,
    '23514'
);

SELECT throws_ok(
    $sql$
        UPDATE public.vehicle_state_transitions
        SET reason = 'changed'
        WHERE vehicle_id = '15c32000-0000-4000-8000-000000000001'::uuid
    $sql$,
    '42501'
);

SELECT throws_ok(
    $sql$
        DELETE FROM public.vehicle_state_transitions
        WHERE vehicle_id = '15c32000-0000-4000-8000-000000000001'::uuid
    $sql$,
    '42501'
);

SELECT throws_ok(
    $sql$
        UPDATE public.vehicles
        SET status = 'retired'
        WHERE id = '15c32000-0000-4000-8000-000000000001'::uuid
    $sql$,
    '23514'
);

SELECT throws_ok(
    $sql$
        UPDATE public.vehicles
        SET battery_pct = 101
        WHERE id = '15c32000-0000-4000-8000-000000000001'::uuid
    $sql$,
    '23514'
);

SELECT * FROM finish();
ROLLBACK;
