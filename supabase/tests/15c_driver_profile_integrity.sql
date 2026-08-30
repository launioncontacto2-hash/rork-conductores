BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

INSERT INTO public.stations (id, environment_id, region_id, code, name, status)
SELECT
    fixture.station_id,
    r.environment_id,
    r.id,
    fixture.code,
    fixture.name,
    'active'
FROM (
    SELECT *
    FROM public.regions
    ORDER BY created_at, id
    LIMIT 1
) r
CROSS JOIN (
    VALUES
        ('15c43000-0000-4000-8000-000000000001'::uuid, '15c-driver-station-1', '15C Driver Station 1'),
        ('15c43000-0000-4000-8000-000000000002'::uuid, '15c-driver-station-2', '15C Driver Station 2')
) AS fixture(station_id, code, name);

CREATE TEMP TABLE test_15c_driver_scope AS
SELECT environment_id
FROM public.stations
WHERE id = '15c43000-0000-4000-8000-000000000001'::uuid;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT
    fixture.profile_id,
    scope.environment_id,
    fixture.employee_number,
    fixture.display_name,
    'active'
FROM test_15c_driver_scope scope
CROSS JOIN (
    VALUES
        ('15c03000-0000-4000-8000-000000000001'::uuid, '15C-DP-DRIVER-1', '15C DP Driver 1'),
        ('15c03000-0000-4000-8000-000000000002'::uuid, '15C-DP-SUPERVISOR', '15C DP Supervisor'),
        ('15c03000-0000-4000-8000-000000000003'::uuid, '15C-DP-DRIVER-2', '15C DP Driver 2')
) AS fixture(profile_id, employee_number, display_name);

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role
)
SELECT
    fixture.membership_id,
    scope.environment_id,
    fixture.profile_id,
    '15c43000-0000-4000-8000-000000000001'::uuid,
    fixture.role
FROM test_15c_driver_scope scope
CROSS JOIN (
    VALUES
        ('15c13000-0000-4000-8000-000000000001'::uuid, '15c03000-0000-4000-8000-000000000001'::uuid, 'driver'),
        ('15c13000-0000-4000-8000-000000000002'::uuid, '15c03000-0000-4000-8000-000000000002'::uuid, 'supervisor'),
        ('15c13000-0000-4000-8000-000000000003'::uuid, '15c03000-0000-4000-8000-000000000003'::uuid, 'driver')
) AS fixture(membership_id, profile_id, role);

SELECT lives_ok(
    $sql$
        INSERT INTO public.driver_profiles (
            id, environment_id, station_id, profile_id, membership_id,
            employee_number, status
        )
        SELECT
            '15c23000-0000-4000-8000-000000000001'::uuid,
            environment_id,
            '15c43000-0000-4000-8000-000000000001'::uuid,
            '15c03000-0000-4000-8000-000000000001'::uuid,
            '15c13000-0000-4000-8000-000000000001'::uuid,
            '15C-DP-DRIVER-1',
            'active'
        FROM test_15c_driver_scope
    $sql$,
    'acepta una membresia driver coincidente'
);

SELECT throws_ok(
    $sql$
        INSERT INTO public.driver_profiles (
            id, environment_id, station_id, profile_id, membership_id,
            employee_number, status
        )
        SELECT
            '15c23000-0000-4000-8000-000000000002'::uuid,
            environment_id,
            '15c43000-0000-4000-8000-000000000001'::uuid,
            '15c03000-0000-4000-8000-000000000002'::uuid,
            '15c13000-0000-4000-8000-000000000002'::uuid,
            '15C-DP-SUPERVISOR',
            'active'
        FROM test_15c_driver_scope
    $sql$,
    '23514'
);

SELECT throws_ok(
    $sql$
        INSERT INTO public.driver_profiles (
            id, environment_id, station_id, profile_id, membership_id,
            employee_number, status
        )
        SELECT
            '15c23000-0000-4000-8000-000000000003'::uuid,
            environment_id,
            '15c43000-0000-4000-8000-000000000001'::uuid,
            '15c03000-0000-4000-8000-000000000003'::uuid,
            '15c13000-0000-4000-8000-000000000001'::uuid,
            '15C-DP-MISMATCH-1',
            'active'
        FROM test_15c_driver_scope
    $sql$,
    '23514'
);

SELECT throws_ok(
    $sql$
        INSERT INTO public.driver_profiles (
            id, environment_id, station_id, profile_id, membership_id,
            employee_number, status
        )
        SELECT
            '15c23000-0000-4000-8000-000000000004'::uuid,
            environment_id,
            '15c43000-0000-4000-8000-000000000002'::uuid,
            '15c03000-0000-4000-8000-000000000003'::uuid,
            '15c13000-0000-4000-8000-000000000003'::uuid,
            '15C-DP-MISMATCH-2',
            'active'
        FROM test_15c_driver_scope
    $sql$,
    '23514'
);

SELECT * FROM finish();
ROLLBACK;
