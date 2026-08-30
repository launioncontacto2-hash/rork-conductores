BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(4);

DO $fixture$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.regions) THEN
        RAISE EXCEPTION '15c_test_requires_bootstrap_region';
    END IF;
END;
$fixture$;

INSERT INTO public.stations (
    id,
    environment_id,
    region_id,
    code,
    name,
    status
)
SELECT
    '15c40000-0000-4000-8000-000000000001'::uuid,
    r.environment_id,
    r.id,
    '15c-test-station',
    '15C Test Station',
    'active'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE test_15c_scope AS
SELECT
    s.environment_id,
    s.id AS station_id
FROM public.stations s
WHERE s.id = '15c40000-0000-4000-8000-000000000001'::uuid;

INSERT INTO public.profiles (
    id,
    environment_id,
    employee_number,
    display_name,
    status
)
SELECT
    fixture.profile_id,
    scope.environment_id,
    fixture.employee_number,
    fixture.display_name,
    'active'
FROM test_15c_scope scope
CROSS JOIN (
    VALUES
        ('15c00000-0000-4000-8000-000000000001'::uuid, '15C-TEST-DRIVER-1', '15C Test Driver 1'),
        ('15c00000-0000-4000-8000-000000000002'::uuid, '15C-TEST-DRIVER-2', '15C Test Driver 2')
) AS fixture(profile_id, employee_number, display_name);

INSERT INTO public.staff_memberships (
    id,
    environment_id,
    profile_id,
    station_id,
    role
)
SELECT
    fixture.membership_id,
    scope.environment_id,
    fixture.profile_id,
    scope.station_id,
    'driver'
FROM test_15c_scope scope
CROSS JOIN (
    VALUES
        ('15c10000-0000-4000-8000-000000000001'::uuid, '15c00000-0000-4000-8000-000000000001'::uuid),
        ('15c10000-0000-4000-8000-000000000002'::uuid, '15c00000-0000-4000-8000-000000000002'::uuid)
) AS fixture(membership_id, profile_id);

INSERT INTO public.driver_profiles (
    id,
    environment_id,
    station_id,
    profile_id,
    membership_id,
    employee_number,
    status
)
SELECT
    fixture.driver_profile_id,
    scope.environment_id,
    scope.station_id,
    fixture.profile_id,
    fixture.membership_id,
    fixture.employee_number,
    'active'
FROM test_15c_scope scope
CROSS JOIN (
    VALUES
        ('15c20000-0000-4000-8000-000000000001'::uuid, '15c00000-0000-4000-8000-000000000001'::uuid, '15c10000-0000-4000-8000-000000000001'::uuid, '15C-TEST-DRIVER-1'),
        ('15c20000-0000-4000-8000-000000000002'::uuid, '15c00000-0000-4000-8000-000000000002'::uuid, '15c10000-0000-4000-8000-000000000002'::uuid, '15C-TEST-DRIVER-2')
) AS fixture(driver_profile_id, profile_id, membership_id, employee_number);

INSERT INTO public.vehicles (
    id,
    environment_id,
    station_id,
    internal_number,
    qr_code,
    model,
    status
)
SELECT
    fixture.vehicle_id,
    scope.environment_id,
    scope.station_id,
    fixture.internal_number,
    fixture.qr_code,
    '15C Test Vehicle',
    'available'
FROM test_15c_scope scope
CROSS JOIN (
    VALUES
        ('15c30000-0000-4000-8000-000000000001'::uuid, '15C-TEST-VEHICLE-1', '15C-TEST-QR-1'),
        ('15c30000-0000-4000-8000-000000000002'::uuid, '15C-TEST-VEHICLE-2', '15C-TEST-QR-2')
) AS fixture(vehicle_id, internal_number, qr_code);

SELECT lives_ok(
    $sql$
        INSERT INTO public.assignments (
            environment_id,
            station_id,
            driver_profile_id,
            vehicle_id,
            kind,
            assigned_by
        )
        SELECT
            scope.environment_id,
            scope.station_id,
            '15c20000-0000-4000-8000-000000000001'::uuid,
            '15c30000-0000-4000-8000-000000000001'::uuid,
            'titular',
            '15c00000-0000-4000-8000-000000000001'::uuid
        FROM test_15c_scope scope
    $sql$,
    'permite la primera asignacion activa'
);

SELECT throws_ok(
    $sql$
        INSERT INTO public.assignments (
            environment_id,
            station_id,
            driver_profile_id,
            vehicle_id,
            kind,
            assigned_by
        )
        SELECT
            scope.environment_id,
            scope.station_id,
            '15c20000-0000-4000-8000-000000000001'::uuid,
            '15c30000-0000-4000-8000-000000000002'::uuid,
            'titular',
            '15c00000-0000-4000-8000-000000000001'::uuid
        FROM test_15c_scope scope
    $sql$,
    '23505'
);

SELECT throws_ok(
    $sql$
        INSERT INTO public.assignments (
            environment_id,
            station_id,
            driver_profile_id,
            vehicle_id,
            kind,
            assigned_by
        )
        SELECT
            scope.environment_id,
            scope.station_id,
            '15c20000-0000-4000-8000-000000000002'::uuid,
            '15c30000-0000-4000-8000-000000000001'::uuid,
            'titular',
            '15c00000-0000-4000-8000-000000000001'::uuid
        FROM test_15c_scope scope
    $sql$,
    '23505'
);

UPDATE public.assignments
SET ended_at = assigned_at
WHERE driver_profile_id = '15c20000-0000-4000-8000-000000000001'::uuid
  AND ended_at IS NULL;

SELECT lives_ok(
    $sql$
        INSERT INTO public.assignments (
            environment_id,
            station_id,
            driver_profile_id,
            vehicle_id,
            kind,
            assigned_by
        )
        SELECT
            scope.environment_id,
            scope.station_id,
            '15c20000-0000-4000-8000-000000000001'::uuid,
            '15c30000-0000-4000-8000-000000000002'::uuid,
            'titular',
            '15c00000-0000-4000-8000-000000000001'::uuid
        FROM test_15c_scope scope
    $sql$,
    'permite una nueva asignacion despues de cerrar la anterior'
);

SELECT * FROM finish();

ROLLBACK;
