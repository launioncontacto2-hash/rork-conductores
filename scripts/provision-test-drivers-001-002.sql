-- Transicion idempotente a las identidades Conductor TEST 001 y 002.
--
-- Requisito previo: crear en Supabase Auth, desde el Dashboard de TEST, los usuarios
-- test.001@joramza.test y test.002@joramza.test con contrasenas que nunca se copien
-- a Git ni a este SQL. El perfil operativo 001 conserva su UUID, asignacion e
-- historial; solo cambia su identidad Auth. La cuenta test.driver@joramza.test queda
-- sin perfil enlazado y por tanto sin acceso operativo.

BEGIN;

DO $block$
DECLARE
    v_auth_user_001_id uuid;
    v_auth_user_002_id uuid;
    v_environment_id uuid;
    v_station_id uuid;
    v_profile_001_id uuid;
    v_profile_002_id constant uuid := '16000000-0000-4000-8000-000000000002';
    v_membership_002_id constant uuid := '16100000-0000-4000-8000-000000000002';
    v_driver_profile_002_id constant uuid := '16200000-0000-4000-8000-000000000002';
BEGIN
    SELECT u.id
    INTO v_auth_user_001_id
    FROM auth.users u
    WHERE lower(u.email) = 'test.001@joramza.test';

    IF v_auth_user_001_id IS NULL THEN
        RAISE EXCEPTION 'auth_user_test_001_required'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT u.id
    INTO v_auth_user_002_id
    FROM auth.users u
    WHERE lower(u.email) = 'test.002@joramza.test';

    IF v_auth_user_002_id IS NULL THEN
        RAISE EXCEPTION 'auth_user_test_002_required'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT e.id
    INTO STRICT v_environment_id
    FROM public.environments e
    WHERE e.code = 'test';

    SELECT s.id
    INTO STRICT v_station_id
    FROM public.stations s
    WHERE s.environment_id = v_environment_id
      AND s.code = 'PUE-TEST-01'
      AND s.status = 'active';

    -- Conserva intacto el dominio del conductor 001. Cambiar auth_user_id
    -- invalida operativamente la identidad heredada sin borrar su Auth user.
    SELECT p.id
    INTO STRICT v_profile_001_id
    FROM public.profiles p
    WHERE p.environment_id = v_environment_id
      AND p.employee_number = 'DRV-TEST-001';

    IF EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.auth_user_id = v_auth_user_001_id
          AND p.id <> v_profile_001_id
    ) THEN
        RAISE EXCEPTION 'auth_user_test_001_profile_conflict'
            USING ERRCODE = '23505';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.auth_user_id = v_auth_user_002_id
          AND p.id <> v_profile_002_id
    ) THEN
        RAISE EXCEPTION 'auth_user_test_002_profile_conflict'
            USING ERRCODE = '23505';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.employee_number = 'DRV-TEST-002'
          AND p.id <> v_profile_002_id
    ) THEN
        RAISE EXCEPTION 'driver_test_002_employee_number_conflict'
            USING ERRCODE = '23505';
    END IF;

    UPDATE public.profiles
    SET auth_user_id = v_auth_user_001_id,
        display_name = 'Conductor TEST 001',
        status = 'active'
    WHERE id = v_profile_001_id
      AND environment_id = v_environment_id;

    INSERT INTO public.profiles (
        id, environment_id, auth_user_id, employee_number,
        display_name, status
    ) VALUES (
        v_profile_002_id, v_environment_id, v_auth_user_002_id, 'DRV-TEST-002',
        'Conductor TEST 002', 'active'
    )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        auth_user_id = EXCLUDED.auth_user_id,
        employee_number = EXCLUDED.employee_number,
        display_name = EXCLUDED.display_name,
        status = 'active';

    INSERT INTO public.staff_memberships (
        id, environment_id, profile_id, station_id, role,
        starts_at, shift_group, shift_slot
    ) VALUES (
        v_membership_002_id, v_environment_id, v_profile_002_id, v_station_id,
        'driver', '2000-01-01 00:00:00+00', 'weekday', 'morning'
    )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        profile_id = EXCLUDED.profile_id,
        station_id = EXCLUDED.station_id,
        role = 'driver',
        starts_at = EXCLUDED.starts_at,
        ends_at = NULL,
        shift_group = 'weekday',
        shift_slot = 'morning';

    INSERT INTO public.driver_profiles (
        id, environment_id, station_id, profile_id, membership_id,
        employee_number, status
    ) VALUES (
        v_driver_profile_002_id, v_environment_id, v_station_id,
        v_profile_002_id, v_membership_002_id, 'DRV-TEST-002', 'active'
    )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        station_id = EXCLUDED.station_id,
        profile_id = EXCLUDED.profile_id,
        membership_id = EXCLUDED.membership_id,
        employee_number = EXCLUDED.employee_number,
        status = 'active';

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = v_profile_001_id
          AND p.environment_id = v_environment_id
          AND p.auth_user_id = v_auth_user_001_id
          AND p.employee_number = 'DRV-TEST-001'
          AND p.status = 'active'
    ) THEN
        RAISE EXCEPTION 'driver_test_001_mapping_failed'
            USING ERRCODE = '23514';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles p
        JOIN public.staff_memberships m
          ON m.profile_id = p.id
         AND m.environment_id = p.environment_id
        JOIN public.driver_profiles d
          ON d.profile_id = p.id
         AND d.membership_id = m.id
         AND d.environment_id = p.environment_id
        WHERE p.id = v_profile_002_id
          AND p.environment_id = v_environment_id
          AND p.auth_user_id = v_auth_user_002_id
          AND p.employee_number = 'DRV-TEST-002'
          AND p.status = 'active'
          AND m.id = v_membership_002_id
          AND m.station_id = v_station_id
          AND m.role = 'driver'
          AND m.ends_at IS NULL
          AND d.id = v_driver_profile_002_id
          AND d.station_id = v_station_id
          AND d.employee_number = 'DRV-TEST-002'
          AND d.status = 'active'
    ) THEN
        RAISE EXCEPTION 'driver_test_002_mapping_failed'
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.profiles p
        JOIN auth.users u ON u.id = p.auth_user_id
        WHERE p.environment_id = v_environment_id
          AND lower(u.email) = 'test.driver@joramza.test'
    ) THEN
        RAISE EXCEPTION 'legacy_test_driver_still_linked'
            USING ERRCODE = '23514';
    END IF;
END
$block$;

COMMIT;

-- Evidencia legible para la ejecucion manual en el SQL Editor de TEST.
SELECT
    p.employee_number,
    lower(u.email) AS auth_email,
    p.display_name,
    m.role,
    s.code AS station_code,
    p.status
FROM public.profiles p
JOIN auth.users u
  ON u.id = p.auth_user_id
JOIN public.staff_memberships m
  ON m.profile_id = p.id
 AND m.environment_id = p.environment_id
JOIN public.stations s
  ON s.id = m.station_id
 AND s.environment_id = m.environment_id
JOIN public.environments e
  ON e.id = p.environment_id
WHERE e.code = 'test'
  AND p.employee_number IN ('DRV-TEST-001', 'DRV-TEST-002')
  AND m.role = 'driver'
  AND m.ends_at IS NULL
ORDER BY p.employee_number;
