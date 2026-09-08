-- DORI · evidencia privada y transaccional del turno.

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'shift-evidence', 'shift-evidence', false, 5242880,
    ARRAY['image/jpeg']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE TABLE public.shift_evidence (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    shift_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    kind text NOT NULL,
    object_path text NOT NULL,
    captured_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT shift_evidence_shift_scope_fkey
        FOREIGN KEY (shift_id, station_id, environment_id)
        REFERENCES public.shifts(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT shift_evidence_driver_scope_fkey
        FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT shift_evidence_kind_check
        CHECK (kind IN ('start_odometer', 'start_battery', 'finish_odometer')),
    CONSTRAINT shift_evidence_shift_kind_unique UNIQUE (shift_id, kind),
    CONSTRAINT shift_evidence_object_path_unique UNIQUE (object_path),
    CONSTRAINT shift_evidence_object_path_not_blank CHECK (btrim(object_path) <> '')
);

CREATE INDEX shift_evidence_driver_created_idx
ON public.shift_evidence(driver_profile_id, created_at DESC);

ALTER TABLE public.shift_evidence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.shift_evidence FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.shift_evidence TO authenticated, service_role;
GRANT ALL ON TABLE public.shift_evidence TO postgres;

CREATE POLICY shift_evidence_authorized_read
ON public.shift_evidence FOR SELECT TO authenticated
USING (
    environment_id = app.current_environment_id()
    AND (
        driver_profile_id IN (
            SELECT driver.id
            FROM public.driver_profiles driver
            WHERE driver.profile_id = app.auth_profile_id()
        )
        OR app.auth_has_role('supervisor', station_id)
    )
);

-- La politica 15D permitia leer por pertenecer a la estacion. Eso incluia a
-- conductores y exponia turnos ajenos. DORI separa propiedad y supervision.
DROP POLICY IF EXISTS shifts_authorized_read ON public.shifts;
CREATE POLICY shifts_authorized_read
ON public.shifts FOR SELECT TO authenticated
USING (
    environment_id = app.current_environment_id()
    AND (
        driver_profile_id IN (
            SELECT driver.id
            FROM public.driver_profiles driver
            WHERE driver.profile_id = app.auth_profile_id()
        )
        OR app.auth_has_role('supervisor', station_id)
    )
);

DROP POLICY IF EXISTS shift_readings_authorized_read ON public.shift_readings;
CREATE POLICY shift_readings_authorized_read
ON public.shift_readings FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.shifts shift_row
        WHERE shift_row.id = shift_readings.shift_id
          AND shift_row.environment_id = app.current_environment_id()
          AND (
              shift_row.driver_profile_id IN (
                  SELECT driver.id
                  FROM public.driver_profiles driver
                  WHERE driver.profile_id = app.auth_profile_id()
              )
              OR app.auth_has_role('supervisor', shift_row.station_id)
          )
    )
);

CREATE POLICY shift_evidence_objects_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'shift-evidence'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) >= 4
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND (storage.foldername(name))[3] = app.auth_profile_id()::text
    AND EXISTS (
        SELECT 1
        FROM public.driver_profiles driver
        WHERE driver.environment_id = app.current_environment_id()
          AND driver.station_id::text = (storage.foldername(name))[2]
          AND driver.profile_id = app.auth_profile_id()
          AND driver.status = 'active'
          AND app.auth_has_role('driver', driver.station_id)
    )
);

CREATE POLICY shift_evidence_objects_select
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'shift-evidence'
    AND array_length(storage.foldername(name), 1) >= 4
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND (
        (storage.foldername(name))[3] = app.auth_profile_id()::text
        OR app.auth_has_role('supervisor', (storage.foldername(name))[2]::uuid)
    )
);

CREATE OR REPLACE FUNCTION app.assert_owned_shift_evidence(
    p_object_path text,
    p_environment_id uuid,
    p_station_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'storage', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_object storage.objects%ROWTYPE;
    v_prefix text;
    v_content_type text;
    v_byte_size bigint;
BEGIN
    IF coalesce(btrim(p_object_path), '') = '' THEN
        RAISE EXCEPTION 'shift_evidence_required' USING ERRCODE = '22023';
    END IF;

    v_prefix := p_environment_id::text || '/' || p_station_id::text || '/' ||
        app.auth_profile_id()::text || '/';
    IF left(btrim(p_object_path), char_length(v_prefix)) <> v_prefix
       OR position('/../' IN ('/' || btrim(p_object_path) || '/')) > 0
    THEN
        RAISE EXCEPTION 'shift_evidence_path_out_of_scope' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_object
    FROM storage.objects
    WHERE bucket_id = 'shift-evidence'
      AND name = btrim(p_object_path);
    IF NOT FOUND OR v_object.owner_id IS DISTINCT FROM auth.uid()::text THEN
        RAISE EXCEPTION 'owned_shift_evidence_required' USING ERRCODE = '22023';
    END IF;

    v_content_type := lower(coalesce(v_object.metadata ->> 'mimetype', ''));
    v_byte_size := coalesce(nullif(v_object.metadata ->> 'size', '')::bigint, 0);
    IF v_content_type <> 'image/jpeg' OR v_byte_size NOT BETWEEN 1 AND 5242880 THEN
        RAISE EXCEPTION 'unsupported_shift_evidence' USING ERRCODE = '22023';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION app.assert_owned_shift_evidence(text, uuid, uuid)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.assert_owned_shift_evidence(text, uuid, uuid)
TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.start_shift_v3(
    p_assignment_id uuid,
    p_odometer_km bigint,
    p_battery_pct integer,
    p_odometer_path text,
    p_battery_path text,
    p_idempotency_key text,
    p_install_id text
)
RETURNS public.shifts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'storage', 'pg_temp'
AS $function$
DECLARE
    v_assignment public.assignments%ROWTYPE;
    v_shift public.shifts%ROWTYPE;
BEGIN
    PERFORM app.assert_driver_device_session(p_install_id);

    SELECT * INTO STRICT v_assignment
    FROM public.assignments assignment
    WHERE assignment.id = p_assignment_id
      AND assignment.environment_id = app.current_environment_id();

    PERFORM app.assert_owned_shift_evidence(
        p_odometer_path, v_assignment.environment_id, v_assignment.station_id
    );
    PERFORM app.assert_owned_shift_evidence(
        p_battery_path, v_assignment.environment_id, v_assignment.station_id
    );

    v_shift := public.start_shift(
        p_assignment_id, p_odometer_km, p_battery_pct, p_idempotency_key
    );

    INSERT INTO public.shift_evidence (
        environment_id, station_id, shift_id, driver_profile_id,
        kind, object_path, captured_at
    ) VALUES
        (
            v_shift.environment_id, v_shift.station_id, v_shift.id,
            v_shift.driver_profile_id, 'start_odometer', btrim(p_odometer_path),
            v_shift.started_at
        ),
        (
            v_shift.environment_id, v_shift.station_id, v_shift.id,
            v_shift.driver_profile_id, 'start_battery', btrim(p_battery_path),
            v_shift.started_at
        )
    ON CONFLICT (shift_id, kind) DO NOTHING;

    RETURN v_shift;
EXCEPTION
    WHEN no_data_found THEN
        RAISE EXCEPTION 'active_assignment_required' USING ERRCODE = '42501';
    WHEN too_many_rows THEN
        RAISE EXCEPTION 'assignment_not_unique' USING ERRCODE = '23514';
END;
$function$;

CREATE OR REPLACE FUNCTION public.finish_shift_v3(
    p_shift_id uuid,
    p_expected_revision bigint,
    p_odometer_km bigint,
    p_battery_pct integer,
    p_odometer_path text,
    p_idempotency_key text,
    p_install_id text
)
RETURNS public.shifts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'storage', 'pg_temp'
AS $function$
DECLARE
    v_existing public.shifts%ROWTYPE;
    v_shift public.shifts%ROWTYPE;
BEGIN
    PERFORM app.assert_driver_device_session(p_install_id);

    SELECT * INTO STRICT v_existing
    FROM public.shifts shift_row
    WHERE shift_row.id = p_shift_id
      AND shift_row.environment_id = app.current_environment_id();

    PERFORM app.assert_owned_shift_evidence(
        p_odometer_path, v_existing.environment_id, v_existing.station_id
    );

    v_shift := public.finish_shift(
        p_shift_id, p_expected_revision, p_odometer_km,
        p_battery_pct, p_idempotency_key
    );

    INSERT INTO public.shift_evidence (
        environment_id, station_id, shift_id, driver_profile_id,
        kind, object_path, captured_at
    ) VALUES (
        v_shift.environment_id, v_shift.station_id, v_shift.id,
        v_shift.driver_profile_id, 'finish_odometer', btrim(p_odometer_path),
        v_shift.finished_at
    )
    ON CONFLICT (shift_id, kind) DO NOTHING;

    RETURN v_shift;
EXCEPTION
    WHEN no_data_found THEN
        RAISE EXCEPTION 'open_shift_required' USING ERRCODE = '42501';
    WHEN too_many_rows THEN
        RAISE EXCEPTION 'shift_not_unique' USING ERRCODE = '23514';
END;
$function$;

REVOKE ALL ON FUNCTION public.start_shift_v3(
    uuid, bigint, integer, text, text, text, text
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finish_shift_v3(
    uuid, bigint, bigint, integer, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_shift_v3(
    uuid, bigint, integer, text, text, text, text
) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finish_shift_v3(
    uuid, bigint, bigint, integer, text, text, text
) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.start_shift_v2(uuid, bigint, integer, text, text)
FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.finish_shift_v2(uuid, bigint, bigint, integer, text, text)
FROM authenticated;

COMMENT ON TABLE public.shift_evidence IS
    'Evidencia fotografica privada e inmutable del inicio y cierre de cada turno DORI.';
COMMENT ON FUNCTION public.start_shift_v3(uuid, bigint, integer, text, text, text, text) IS
    'Abre un turno y registra sus dos fotografias propias en la misma transaccion.';
COMMENT ON FUNCTION public.finish_shift_v3(uuid, bigint, bigint, integer, text, text, text) IS
    'Cierra un turno y registra la fotografia final propia en la misma transaccion.';
