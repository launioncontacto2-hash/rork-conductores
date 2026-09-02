-- Vincula la credencial Auth TEST del taller con su identidad operativa.
--
-- Requisito previo: crear test.maintenance@joramza.test en Supabase Auth del proyecto
-- TEST. La contrasena nunca debe copiarse a este archivo ni al repositorio.

BEGIN;

DO $block$
DECLARE
    v_auth_user_id uuid;
    v_environment_id uuid;
    v_station_id uuid;
    v_profile_id constant uuid := '16000000-0000-4000-8000-0000000000a1';
    v_membership_id constant uuid := '16100000-0000-4000-8000-0000000000a1';
BEGIN
    SELECT u.id
    INTO v_auth_user_id
    FROM auth.users u
    WHERE lower(u.email) = 'test.maintenance@joramza.test';

    IF v_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'auth_user_test_maintenance_required'
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

    IF EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.auth_user_id = v_auth_user_id
          AND p.id <> v_profile_id
    ) THEN
        RAISE EXCEPTION 'auth_user_test_maintenance_profile_conflict'
            USING ERRCODE = '23505';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.environment_id = v_environment_id
          AND p.employee_number = 'MNT-TEST-001'
          AND p.id <> v_profile_id
    ) THEN
        RAISE EXCEPTION 'maintenance_test_employee_number_conflict'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.profiles (
        id, environment_id, auth_user_id, employee_number,
        display_name, status
    ) VALUES (
        v_profile_id, v_environment_id, v_auth_user_id, 'MNT-TEST-001',
        'Taller TEST 001', 'active'
    )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        auth_user_id = EXCLUDED.auth_user_id,
        employee_number = EXCLUDED.employee_number,
        display_name = EXCLUDED.display_name,
        status = 'active';

    INSERT INTO public.staff_memberships (
        id, environment_id, profile_id, station_id, role,
        starts_at, ends_at, shift_group, shift_slot
    ) VALUES (
        v_membership_id, v_environment_id, v_profile_id, v_station_id,
        'maintenance', '2000-01-01 00:00:00+00', NULL, NULL, NULL
    )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        profile_id = EXCLUDED.profile_id,
        station_id = EXCLUDED.station_id,
        role = 'maintenance',
        starts_at = EXCLUDED.starts_at,
        ends_at = NULL,
        shift_group = NULL,
        shift_slot = NULL;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles p
        JOIN public.staff_memberships sm ON sm.profile_id = p.id
        WHERE p.id = v_profile_id
          AND p.auth_user_id = v_auth_user_id
          AND p.status = 'active'
          AND sm.id = v_membership_id
          AND sm.station_id = v_station_id
          AND sm.role = 'maintenance'
          AND sm.ends_at IS NULL
    ) THEN
        RAISE EXCEPTION 'maintenance_test_provision_verification_failed'
            USING ERRCODE = 'P0001';
    END IF;
END;
$block$;

COMMIT;

SELECT
    p.employee_number,
    lower(u.email) AS auth_email,
    p.display_name,
    sm.role,
    s.code AS station_code,
    p.status
FROM public.profiles p
JOIN auth.users u ON u.id = p.auth_user_id
JOIN public.staff_memberships sm
  ON sm.profile_id = p.id
 AND sm.ends_at IS NULL
JOIN public.stations s ON s.id = sm.station_id
WHERE p.employee_number = 'MNT-TEST-001';
