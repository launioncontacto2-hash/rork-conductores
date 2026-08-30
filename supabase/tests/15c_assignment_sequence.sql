BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(6);

INSERT INTO public.stations (id, environment_id, region_id, code, name, status)
SELECT
    '15c41000-0000-4000-8000-000000000001'::uuid,
    r.environment_id,
    r.id,
    '15c-sequence-station',
    '15C Sequence Station',
    'active'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE test_15c_sequence_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = '15c41000-0000-4000-8000-000000000001'::uuid;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT
    '15c01000-0000-4000-8000-000000000001'::uuid,
    environment_id,
    '15C-SEQUENCE-DRIVER',
    '15C Sequence Driver',
    'active'
FROM test_15c_sequence_scope;

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role
)
SELECT
    '15c11000-0000-4000-8000-000000000001'::uuid,
    environment_id,
    '15c01000-0000-4000-8000-000000000001'::uuid,
    station_id,
    'driver'
FROM test_15c_sequence_scope;

INSERT INTO public.driver_profiles (
    id, environment_id, station_id, profile_id, membership_id,
    employee_number, status
)
SELECT
    '15c21000-0000-4000-8000-000000000001'::uuid,
    environment_id,
    station_id,
    '15c01000-0000-4000-8000-000000000001'::uuid,
    '15c11000-0000-4000-8000-000000000001'::uuid,
    '15C-SEQUENCE-DRIVER',
    'active'
FROM test_15c_sequence_scope;

INSERT INTO public.vehicles (
    id, environment_id, station_id, internal_number, qr_code, model, status
)
SELECT
    fixture.vehicle_id,
    scope.environment_id,
    scope.station_id,
    fixture.internal_number,
    fixture.qr_code,
    '15C Sequence Vehicle',
    'available'
FROM test_15c_sequence_scope scope
CROSS JOIN (
    VALUES
        ('15c31000-0000-4000-8000-000000000001'::uuid, '15C-SEQUENCE-V1', '15C-SEQUENCE-QR1'),
        ('15c31000-0000-4000-8000-000000000002'::uuid, '15C-SEQUENCE-V2', '15C-SEQUENCE-QR2')
) AS fixture(vehicle_id, internal_number, qr_code);

SELECT lives_ok(
    $sql$
        INSERT INTO public.assignments (
            environment_id, station_id, driver_profile_id, vehicle_id,
            kind, assigned_by
        )
        SELECT environment_id, station_id,
            '15c21000-0000-4000-8000-000000000001'::uuid,
            '15c31000-0000-4000-8000-000000000001'::uuid,
            'titular',
            '15c01000-0000-4000-8000-000000000001'::uuid
        FROM test_15c_sequence_scope
    $sql$,
    'crea la asignacion titular inicial'
);

UPDATE public.assignments
SET ended_at = assigned_at
WHERE driver_profile_id = '15c21000-0000-4000-8000-000000000001'::uuid
  AND ended_at IS NULL;

SELECT lives_ok(
    $sql$
        INSERT INTO public.assignments (
            environment_id, station_id, driver_profile_id, vehicle_id,
            kind, titular_vehicle_id, assigned_by
        )
        SELECT environment_id, station_id,
            '15c21000-0000-4000-8000-000000000001'::uuid,
            '15c31000-0000-4000-8000-000000000002'::uuid,
            'substitute',
            '15c31000-0000-4000-8000-000000000001'::uuid,
            '15c01000-0000-4000-8000-000000000001'::uuid
        FROM test_15c_sequence_scope
    $sql$,
    'cambia de titular a unidad sustituta'
);

UPDATE public.assignments
SET ended_at = assigned_at
WHERE driver_profile_id = '15c21000-0000-4000-8000-000000000001'::uuid
  AND ended_at IS NULL;

SELECT lives_ok(
    $sql$
        INSERT INTO public.assignments (
            environment_id, station_id, driver_profile_id, vehicle_id,
            kind, assigned_by
        )
        SELECT environment_id, station_id,
            '15c21000-0000-4000-8000-000000000001'::uuid,
            '15c31000-0000-4000-8000-000000000001'::uuid,
            'titular',
            '15c01000-0000-4000-8000-000000000001'::uuid
        FROM test_15c_sequence_scope
    $sql$,
    'regresa de sustituta a titular'
);

UPDATE public.assignments
SET ended_at = assigned_at
WHERE driver_profile_id = '15c21000-0000-4000-8000-000000000001'::uuid
  AND ended_at IS NULL;

SELECT throws_ok(
    $sql$
        INSERT INTO public.assignments (
            environment_id, station_id, driver_profile_id, vehicle_id,
            kind, assigned_by
        )
        SELECT environment_id, station_id,
            '15c21000-0000-4000-8000-000000000001'::uuid,
            '15c31000-0000-4000-8000-000000000002'::uuid,
            'substitute',
            '15c01000-0000-4000-8000-000000000001'::uuid
        FROM test_15c_sequence_scope
    $sql$,
    '23514'
);

SELECT throws_ok(
    $sql$
        INSERT INTO public.assignments (
            environment_id, station_id, driver_profile_id, vehicle_id,
            kind, titular_vehicle_id, assigned_by
        )
        SELECT environment_id, station_id,
            '15c21000-0000-4000-8000-000000000001'::uuid,
            '15c31000-0000-4000-8000-000000000002'::uuid,
            'substitute',
            '15c31000-0000-4000-8000-000000000002'::uuid,
            '15c01000-0000-4000-8000-000000000001'::uuid
        FROM test_15c_sequence_scope
    $sql$,
    '23514'
);

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.assignments
        WHERE driver_profile_id = '15c21000-0000-4000-8000-000000000001'::uuid
    ),
    3::bigint,
    'conserva las tres etapas del historial'
);

SELECT * FROM finish();
ROLLBACK;
