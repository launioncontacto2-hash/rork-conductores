-- Fixture exclusivo para Supabase local. Requiere usuarios Auth locales:
-- Usuarios Auth locales requeridos: copilot.console@local.test,
-- copilot.driver.a@local.test, copilot.driver.b@local.test,
-- copilot.supervisor@local.test.
BEGIN;
DO $block$
DECLARE
  v_env uuid;
  v_station uuid := '17000000-0000-4000-8000-000000000001';
  v_region uuid := '17300000-0000-4000-8000-000000000001';
  v_console_profile uuid := '17100000-0000-4000-8000-000000000001';
  v_driver_profile uuid := '17400000-0000-4000-8000-000000000002';
  v_driver_identity uuid := '17100000-0000-4000-8000-000000000002';
  v_driver_b_profile uuid := '17400000-0000-4000-8000-000000000003';
  v_driver_b_identity uuid := '17100000-0000-4000-8000-000000000003';
  v_supervisor_profile uuid := '17100000-0000-4000-8000-000000000004';
  v_console_membership uuid := '17200000-0000-4000-8000-000000000001';
  v_driver_membership uuid := '17200000-0000-4000-8000-000000000002';
  v_driver_b_membership uuid := '17200000-0000-4000-8000-000000000003';
  v_supervisor_membership uuid := '17200000-0000-4000-8000-000000000004';
  v_console_auth uuid;
  v_driver_auth uuid;
  v_driver_b_auth uuid;
  v_supervisor_auth uuid;
BEGIN
  SELECT id INTO STRICT v_env FROM public.environments WHERE code='test';
  SELECT id INTO STRICT v_console_auth FROM auth.users WHERE email='copilot.console@local.test';
  SELECT id INTO STRICT v_driver_auth FROM auth.users WHERE email='copilot.driver.a@local.test';
  SELECT id INTO STRICT v_driver_b_auth FROM auth.users WHERE email='copilot.driver.b@local.test';
  SELECT id INTO STRICT v_supervisor_auth FROM auth.users WHERE email='copilot.supervisor@local.test';
  INSERT INTO public.regions(id, environment_id, code, name, status)
    VALUES (v_region, v_env, 'REG-COPILOT', 'Región Laboratorio Copiloto', 'active')
    ON CONFLICT (id) DO UPDATE SET environment_id=EXCLUDED.environment_id, code=EXCLUDED.code, name=EXCLUDED.name, status='active';
  INSERT INTO public.stations(id, environment_id, region_id, code, name, status)
    VALUES (v_station, v_env, v_region, 'PUE-COPILOT-01', 'Laboratorio DORI Copiloto', 'active')
    ON CONFLICT (id) DO UPDATE SET environment_id=EXCLUDED.environment_id, region_id=EXCLUDED.region_id, code=EXCLUDED.code, name=EXCLUDED.name, status='active';
  INSERT INTO public.profiles(id, environment_id, auth_user_id, employee_number, display_name, status)
    VALUES (v_console_profile, v_env, v_console_auth, 'LAB-CONSOLE-001', 'Consola Copiloto', 'active'),
           (v_driver_identity, v_env, v_driver_auth, 'LAB-DRIVER-001', 'Conductor Copiloto A', 'active'),
           (v_driver_b_identity, v_env, v_driver_b_auth, 'LAB-DRIVER-002', 'Conductor Copiloto B', 'active'),
           (v_supervisor_profile, v_env, v_supervisor_auth, 'LAB-SUPERVISOR-001', 'Supervisor Copiloto', 'active')
    ON CONFLICT (id) DO UPDATE SET environment_id=EXCLUDED.environment_id, auth_user_id=EXCLUDED.auth_user_id, employee_number=EXCLUDED.employee_number, display_name=EXCLUDED.display_name, status='active';
  INSERT INTO public.staff_memberships(id, environment_id, profile_id, station_id, role, starts_at, shift_group, shift_slot)
    VALUES (v_console_membership, v_env, v_console_profile, v_station, 'console', '2000-01-01 00:00:00+00', 'weekday', 'morning'),
           (v_driver_membership, v_env, v_driver_identity, v_station, 'driver', '2000-01-01 00:00:00+00', 'weekday', 'morning'),
           (v_driver_b_membership, v_env, v_driver_b_identity, v_station, 'driver', '2000-01-01 00:00:00+00', 'weekday', 'morning'),
           (v_supervisor_membership, v_env, v_supervisor_profile, v_station, 'supervisor', '2000-01-01 00:00:00+00', 'weekday', 'morning')
    ON CONFLICT (id) DO UPDATE SET environment_id=EXCLUDED.environment_id, profile_id=EXCLUDED.profile_id, station_id=EXCLUDED.station_id, role=EXCLUDED.role, ends_at=NULL, starts_at=EXCLUDED.starts_at, shift_group=EXCLUDED.shift_group, shift_slot=EXCLUDED.shift_slot;
  INSERT INTO public.driver_profiles(id, environment_id, station_id, profile_id, membership_id, employee_number, status)
    VALUES (v_driver_profile, v_env, v_station, v_driver_identity, v_driver_membership, 'LAB-DRIVER-001', 'active')
          ,(v_driver_b_profile, v_env, v_station, v_driver_b_identity, v_driver_b_membership, 'LAB-DRIVER-002', 'active')
    ON CONFLICT (id) DO UPDATE SET environment_id=EXCLUDED.environment_id, station_id=EXCLUDED.station_id, profile_id=EXCLUDED.profile_id, membership_id=EXCLUDED.membership_id, employee_number=EXCLUDED.employee_number, status='active';
END
$block$;
COMMIT;

SELECT u.email, p.id AS profile_id, m.id AS membership_id, m.role,
       d.id AS driver_profile_id, s.code AS station, e.code AS environment, p.status
FROM auth.users u JOIN public.profiles p ON p.auth_user_id=u.id
JOIN public.staff_memberships m ON m.profile_id=p.id
JOIN public.stations s ON s.id=m.station_id JOIN public.environments e ON e.id=p.environment_id
LEFT JOIN public.driver_profiles d ON d.profile_id=p.id
WHERE u.email LIKE 'copilot.%@local.test' ORDER BY u.email;
