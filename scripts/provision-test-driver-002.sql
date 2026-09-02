-- Provisionamiento idempotente de Conductor TEST 002.
--
-- Requisito previo: crear en Supabase Auth, desde el Dashboard de TEST, el usuario
-- test.driver.002@joramza.test con una contrasena que nunca se copie a Git ni a este SQL.
-- Este archivo solo enlaza esa identidad Auth con el dominio operativo existente.

BEGIN;

DO $block$
DECLARE
    v_auth_user_id uuid;
    v_environment_id uuid;
    v_station_id uuid;
    v_profile_id constant uuid := '16000000-0000-4000-8000-000000000002';
    v_membership_id constant uuid := '16100000-0000-4000-8000-000000000002';
    v_driver_profile_id constant uuid := '16200000-0000-4000-8000-000000000002';
BEGIN
    SELECT u.id
    INTO v_auth_user_id
    FROM auth.users u
    WHERE lower(u.email) = 'test.driver.002@joramza.test';

    IF v_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'auth_user_test_driver_002_required'
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

    INSERT INTO public.profiles (
        id, environment_id, auth_user_id, employee_number,
        display_name, status
    ) VALUES (
        v_profile_id, v_environment_id, v_auth_user_id, 'DRV-TEST-002',
        'Conductor TEST 002', 'active'
    )
    ON CONFLICT (id) DO UPDATE
    SET auth_user_id = EXCLUDED.auth_user_id,
        display_name = EXCLUDED.display_name,
        status = 'active';

    IF EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.employee_number = 'DRV-TEST-002'
          AND p.id <> v_profile_id
    ) THEN
        RAISE EXCEPTION 'driver_test_002_employee_number_conflict'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.staff_memberships (
        id, environment_id, profile_id, station_id, role,
        starts_at, shift_group, shift_slot
    ) VALUES (
        v_membership_id, v_environment_id, v_profile_id, v_station_id,
        'driver', '2000-01-01 00:00:00+00', 'weekday', 'morning'
    )
    ON CONFLICT (id) DO UPDATE
    SET station_id = EXCLUDED.station_id,
        role = 'driver',
        ends_at = NULL,
        shift_group = 'weekday',
        shift_slot = 'morning';

    INSERT INTO public.driver_profiles (
        id, environment_id, station_id, profile_id, membership_id,
        employee_number, status
    ) VALUES (
        v_driver_profile_id, v_environment_id, v_station_id,
        v_profile_id, v_membership_id, 'DRV-TEST-002', 'active'
    )
    ON CONFLICT (id) DO UPDATE
    SET station_id = EXCLUDED.station_id,
        membership_id = EXCLUDED.membership_id,
        status = 'active';
END
$block$;

COMMIT;
