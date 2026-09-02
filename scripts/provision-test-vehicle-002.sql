-- Segunda unidad persistente para las pruebas fisicas con dos conductores.
-- Se ejecuta exclusivamente contra el proyecto TEST turno-ev-laboratorio.
-- El codigo QR visible y escaneable es: LAB-16B-VEHICLE-002

BEGIN;

DO $block$
DECLARE
    v_environment_id uuid;
    v_station_id uuid;
    v_vehicle_id constant uuid := '16b40000-0000-4000-8000-000000000002';
BEGIN
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
        FROM public.vehicles v
        WHERE v.environment_id = v_environment_id
          AND v.id <> v_vehicle_id
          AND (
              v.internal_number = 'LAB-16B-002'
              OR v.qr_code = 'LAB-16B-VEHICLE-002'
          )
    ) THEN
        RAISE EXCEPTION 'test_vehicle_002_identity_conflict'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.vehicles (
        id,
        environment_id,
        station_id,
        internal_number,
        qr_code,
        model,
        odometer_km,
        battery_pct,
        status
    ) VALUES (
        v_vehicle_id,
        v_environment_id,
        v_station_id,
        'LAB-16B-002',
        'LAB-16B-VEHICLE-002',
        'TurnoEV Laboratorio 002',
        0,
        100,
        'available'
    )
    ON CONFLICT (id) DO NOTHING;

    IF NOT EXISTS (
        SELECT 1
        FROM public.vehicles v
        WHERE v.id = v_vehicle_id
          AND v.environment_id = v_environment_id
          AND v.station_id = v_station_id
          AND v.internal_number = 'LAB-16B-002'
          AND v.qr_code = 'LAB-16B-VEHICLE-002'
          AND v.status IN ('available', 'occupied')
    ) THEN
        RAISE EXCEPTION 'test_vehicle_002_provisioning_failed'
            USING ERRCODE = '23514';
    END IF;
END
$block$;

SELECT
    v.id,
    v.internal_number,
    v.qr_code,
    v.model,
    v.status,
    s.code AS station_code,
    e.code AS environment_code
FROM public.vehicles v
JOIN public.stations s ON s.id = v.station_id
JOIN public.environments e ON e.id = v.environment_id
WHERE v.id = '16b40000-0000-4000-8000-000000000002'::uuid;

COMMIT;
