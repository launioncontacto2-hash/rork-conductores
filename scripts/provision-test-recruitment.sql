-- Vincula la credencial Auth TEST de reclutamiento y crea un expediente de prueba.
--
-- Requisito previo: crear test.recruitment@joramza.test en Supabase Auth del proyecto
-- TEST. La contrasena nunca debe copiarse a este archivo ni al repositorio.

BEGIN;

DO $block$
DECLARE
    v_auth_user_id uuid;
    v_environment_id uuid;
    v_station_id uuid;
    v_profile_id constant uuid := '16200000-0000-4000-8000-0000000000a1';
    v_membership_id constant uuid := '16300000-0000-4000-8000-0000000000a1';
    v_candidate_id constant uuid := '16400000-0000-4000-8000-0000000000a1';
BEGIN
    SELECT u.id
    INTO v_auth_user_id
    FROM auth.users u
    WHERE lower(u.email) = 'test.recruitment@joramza.test';

    IF v_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'auth_user_test_recruitment_required'
            USING ERRCODE = 'P0002';
    END IF;
    IF EXISTS (
        SELECT 1 FROM auth.users u
        WHERE u.id = v_auth_user_id
          AND u.email_confirmed_at IS NULL
    ) THEN
        RAISE EXCEPTION 'auth_user_test_recruitment_must_be_confirmed'
            USING ERRCODE = '22023';
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

    -- Fixed fixture identifiers must never take ownership of rows from another
    -- environment. Stop loudly instead of moving or rewriting such a row.
    IF EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = v_profile_id
          AND profile.environment_id <> v_environment_id
    ) OR EXISTS (
        SELECT 1 FROM public.staff_memberships membership
        WHERE membership.id = v_membership_id
          AND membership.environment_id <> v_environment_id
    ) OR EXISTS (
        SELECT 1 FROM public.candidates candidate
        WHERE candidate.id = v_candidate_id
          AND candidate.environment_id <> v_environment_id
    ) THEN
        RAISE EXCEPTION 'recruitment_test_fixture_id_cross_environment_conflict'
            USING ERRCODE = '23505';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.auth_user_id = v_auth_user_id
          AND profile.id <> v_profile_id
    ) THEN
        RAISE EXCEPTION 'auth_user_test_recruitment_profile_conflict'
            USING ERRCODE = '23505';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.employee_number = 'REC-TEST-001'
          AND profile.id <> v_profile_id
    ) THEN
        RAISE EXCEPTION 'recruitment_test_employee_number_conflict'
            USING ERRCODE = '23505';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.staff_memberships membership
        WHERE membership.profile_id = v_profile_id
          AND membership.ends_at IS NULL
          AND membership.id <> v_membership_id
    ) THEN
        RAISE EXCEPTION 'recruitment_test_active_membership_conflict'
            USING ERRCODE = '23505';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.candidates candidate
        WHERE candidate.environment_id = v_environment_id
          AND candidate.id <> v_candidate_id
          AND (
              lower(btrim(candidate.email)) = 'test.hire.001@joramza.test'
              OR btrim(candidate.curp) = 'TEST900101HPLABC01'
          )
    ) THEN
        RAISE EXCEPTION 'recruitment_test_candidate_identity_conflict'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.profiles(
        id, environment_id, auth_user_id, employee_number, display_name, status
    ) VALUES (
        v_profile_id, v_environment_id, v_auth_user_id,
        'REC-TEST-001', 'Reclutamiento TEST 001', 'active'
    )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        auth_user_id = EXCLUDED.auth_user_id,
        employee_number = EXCLUDED.employee_number,
        display_name = EXCLUDED.display_name,
        status = 'active';

    INSERT INTO public.staff_memberships(
        id, environment_id, profile_id, station_id, role,
        starts_at, ends_at, shift_group, shift_slot
    ) VALUES (
        v_membership_id, v_environment_id, v_profile_id, v_station_id,
        'recruitment', '2000-01-01 00:00:00+00', NULL, NULL, NULL
    )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        profile_id = EXCLUDED.profile_id,
        station_id = EXCLUDED.station_id,
        role = 'recruitment',
        starts_at = EXCLUDED.starts_at,
        ends_at = NULL,
        shift_group = NULL,
        shift_slot = NULL;

    INSERT INTO public.candidates(
        id, environment_id, station_id, created_by,
        full_name, phone, email, city, age, curp,
        requested_shift_group, requested_shift_slot, stage,
        screening_status, interview_score, interview_decision, notes
    ) VALUES (
        v_candidate_id, v_environment_id, v_station_id, v_profile_id,
        'Candidato TEST 15H', '2220001500', 'test.hire.001@joramza.test',
        'Puebla', 30, 'TEST900101HPLABC01',
        'weekday', 'morning', 'documents',
        'fit', 95, 'recommended', 'Expediente ficticio para prueba fisica 15H.'
    )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        station_id = EXCLUDED.station_id,
        created_by = EXCLUDED.created_by,
        full_name = EXCLUDED.full_name,
        phone = EXCLUDED.phone,
        email = EXCLUDED.email,
        city = EXCLUDED.city,
        age = EXCLUDED.age,
        curp = EXCLUDED.curp,
        requested_shift_group = EXCLUDED.requested_shift_group,
        requested_shift_slot = EXCLUDED.requested_shift_slot,
        screening_status = EXCLUDED.screening_status,
        interview_score = EXCLUDED.interview_score,
        interview_decision = EXCLUDED.interview_decision,
        notes = EXCLUDED.notes,
        stage = CASE
            WHEN public.candidates.stage IN ('approved', 'hired')
            THEN public.candidates.stage
            ELSE 'documents'
        END,
        revision = public.candidates.revision + 1,
        updated_at = now();

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles profile
        JOIN public.staff_memberships membership ON membership.profile_id = profile.id
        JOIN public.candidates candidate ON candidate.created_by = profile.id
        WHERE profile.id = v_profile_id
          AND profile.auth_user_id = v_auth_user_id
          AND profile.status = 'active'
          AND membership.id = v_membership_id
          AND membership.station_id = v_station_id
          AND membership.role = 'recruitment'
          AND membership.ends_at IS NULL
          AND candidate.id = v_candidate_id
          AND candidate.station_id = v_station_id
    ) THEN
        RAISE EXCEPTION 'recruitment_test_provision_verification_failed'
            USING ERRCODE = 'P0001';
    END IF;
END;
$block$;

COMMIT;

SELECT
    profile.employee_number,
    lower(auth_user.email) AS auth_email,
    profile.display_name,
    membership.role,
    station.code AS station_code,
    candidate.full_name AS candidate_name,
    candidate.stage AS candidate_stage
FROM public.profiles profile
JOIN auth.users auth_user ON auth_user.id = profile.auth_user_id
JOIN public.staff_memberships membership
  ON membership.profile_id = profile.id
 AND membership.ends_at IS NULL
JOIN public.stations station ON station.id = membership.station_id
JOIN public.candidates candidate ON candidate.created_by = profile.id
WHERE profile.employee_number = 'REC-TEST-001'
  AND candidate.id = '16400000-0000-4000-8000-0000000000a1';
