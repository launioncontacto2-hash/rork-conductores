-- Prepara una sola vacante extraordinaria para la prueba fisica 15F.
-- Requiere que la migracion 15F ya este desplegada exclusivamente en TEST.
-- No crea credenciales, no contiene secretos y no modifica Produccion.

DO $block$
DECLARE
    v_environment_id uuid;
    v_station_id uuid;
    v_supervisor_profile_id uuid;
    v_now timestamptz;
    v_operating_date date;
    v_candidate_count integer;
BEGIN
    SELECT e.id INTO STRICT v_environment_id
    FROM public.environments e
    WHERE e.code = 'test';

    SELECT s.id INTO STRICT v_station_id
    FROM public.stations s
    WHERE s.environment_id = v_environment_id
      AND s.code = 'PUE-TEST-01'
      AND s.status = 'active';

    SELECT sm.profile_id INTO STRICT v_supervisor_profile_id
    FROM public.staff_memberships sm
    JOIN public.profiles p ON p.id = sm.profile_id
    WHERE sm.environment_id = v_environment_id
      AND sm.station_id = v_station_id
      AND sm.role = 'supervisor'
      AND sm.ends_at IS NULL
      AND p.employee_number = 'SUP-TEST-15C';

    SELECT count(*)::integer INTO v_candidate_count
    FROM public.driver_profiles dp
    WHERE dp.environment_id = v_environment_id
      AND dp.station_id = v_station_id
      AND dp.employee_number IN ('DRV-TEST-001', 'DRV-TEST-002')
      AND dp.status = 'active';
    IF v_candidate_count <> 2 THEN
        RAISE EXCEPTION 'two_test_drivers_required_for_15f_race'
            USING ERRCODE = 'P0002';
    END IF;

    v_now := app.env_now(v_environment_id);
    v_operating_date := (v_now AT TIME ZONE 'America/Mexico_City')::date + 1;
    WHILE extract(isodow FROM v_operating_date) NOT BETWEEN 1 AND 5 LOOP
        v_operating_date := v_operating_date + 1;
    END LOOP;

    IF EXISTS (
        SELECT 1 FROM public.coverage_vacancies cv
        WHERE cv.environment_id = v_environment_id
          AND cv.folio = 'VAC-TEST-RACE-15F'
    ) THEN
        RAISE EXCEPTION 'test_coverage_race_already_exists'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.coverage_vacancies (
        id, environment_id, station_id, opened_by, folio,
        operating_date, shift_group, shift_slot, origin,
        bonus_mode, bonus_mxn, reason, status, is_critical, opened_at
    ) VALUES (
        '15f90000-0000-4000-8000-000000000001'::uuid,
        v_environment_id, v_station_id, v_supervisor_profile_id,
        'VAC-TEST-RACE-15F', v_operating_date, 'weekday', 'evening',
        'extraordinary', 'fixed', 300,
        'Prueba de competencia 15F', 'searching', false, v_now
    );
END;
$block$;

SELECT
    cv.folio,
    cv.operating_date,
    cv.shift_group,
    cv.shift_slot,
    cv.status,
    cv.bonus_mxn,
    s.code AS station_code
FROM public.coverage_vacancies cv
JOIN public.stations s ON s.id = cv.station_id
WHERE cv.folio = 'VAC-TEST-RACE-15F';
