BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

INSERT INTO public.stations (id, environment_id, region_id, code, name, status)
SELECT
    '15c44000-0000-4000-8000-000000000001'::uuid,
    r.environment_id,
    r.id,
    '15c-backfill-station',
    '15C Backfill Station',
    'active'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE test_15c_backfill_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = '15c44000-0000-4000-8000-000000000001'::uuid;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT
    fixture.profile_id,
    scope.environment_id,
    fixture.employee_number,
    fixture.display_name,
    fixture.status
FROM test_15c_backfill_scope scope
CROSS JOIN (
    VALUES
        ('15c04000-0000-4000-8000-000000000001'::uuid, '15C-BACKFILL-ACTIVE', '15C Backfill Active', 'active'),
        ('15c04000-0000-4000-8000-000000000002'::uuid, '15C-BACKFILL-SUSPENDED', '15C Backfill Suspended', 'suspended'),
        ('15c04000-0000-4000-8000-000000000003'::uuid, '15C-BACKFILL-SUPERVISOR', '15C Backfill Supervisor', 'active'),
        ('15c04000-0000-4000-8000-000000000004'::uuid, '15C-BACKFILL-ENDED', '15C Backfill Ended', 'active')
) AS fixture(profile_id, employee_number, display_name, status);

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role, starts_at, ends_at
)
SELECT
    fixture.membership_id,
    scope.environment_id,
    fixture.profile_id,
    scope.station_id,
    fixture.role,
    fixture.starts_at,
    fixture.ends_at
FROM test_15c_backfill_scope scope
CROSS JOIN (
    VALUES
        (
            '15c14000-0000-4000-8000-000000000001'::uuid,
            '15c04000-0000-4000-8000-000000000001'::uuid,
            'driver',
            app.env_now() - interval '1 day',
            NULL::timestamptz
        ),
        (
            '15c14000-0000-4000-8000-000000000002'::uuid,
            '15c04000-0000-4000-8000-000000000002'::uuid,
            'driver',
            app.env_now() - interval '1 day',
            NULL::timestamptz
        ),
        (
            '15c14000-0000-4000-8000-000000000003'::uuid,
            '15c04000-0000-4000-8000-000000000003'::uuid,
            'supervisor',
            app.env_now() - interval '1 day',
            NULL::timestamptz
        ),
        (
            '15c14000-0000-4000-8000-000000000004'::uuid,
            '15c04000-0000-4000-8000-000000000004'::uuid,
            'driver',
            app.env_now() - interval '2 days',
            app.env_now() - interval '1 day'
        )
) AS fixture(membership_id, profile_id, role, starts_at, ends_at);

-- Misma operacion de backfill definida por la migracion 15C.
INSERT INTO public.driver_profiles (
    environment_id,
    station_id,
    profile_id,
    membership_id,
    employee_number,
    legacy_code,
    status
)
SELECT
    m.environment_id,
    m.station_id,
    p.id,
    m.id,
    p.employee_number,
    p.legacy_code,
    CASE
        WHEN p.status = 'active' THEN 'active'
        ELSE 'inactive'
    END
FROM public.staff_memberships m
JOIN public.profiles p
  ON p.id = m.profile_id
 AND p.environment_id = m.environment_id
WHERE m.role = 'driver'
  AND m.ends_at IS NULL
ON CONFLICT (profile_id) DO NOTHING;

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.driver_profiles
        WHERE profile_id IN (
            '15c04000-0000-4000-8000-000000000001'::uuid,
            '15c04000-0000-4000-8000-000000000002'::uuid,
            '15c04000-0000-4000-8000-000000000003'::uuid,
            '15c04000-0000-4000-8000-000000000004'::uuid
        )
    ),
    2::bigint,
    'crea driver_profiles solo para membresias driver activas'
);

SELECT is(
    (
        SELECT status
        FROM public.driver_profiles
        WHERE profile_id = '15c04000-0000-4000-8000-000000000001'::uuid
    ),
    'active',
    'conserva active para el perfil activo'
);

SELECT is(
    (
        SELECT status
        FROM public.driver_profiles
        WHERE profile_id = '15c04000-0000-4000-8000-000000000002'::uuid
    ),
    'inactive',
    'convierte suspended en driver_profile inactive'
);

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.driver_profiles
        WHERE profile_id IN (
            '15c04000-0000-4000-8000-000000000003'::uuid,
            '15c04000-0000-4000-8000-000000000004'::uuid
        )
    ),
    0::bigint,
    'excluye supervisor y membresia driver terminada'
);

SELECT * FROM finish();
ROLLBACK;
