-- =====================================================================
-- TurnoEV · 15D · Turnos y lecturas operativas
--
-- Autoridad:
--   - shifts conserva el ciclo de vida y su revision optimista
--   - shift_readings conserva evidencia numerica append-only
--   - start_shift / finish_shift son las unicas vias de escritura cliente
--   - todas las horas operativas provienen de app.env_now(environment_id)
-- =====================================================================

-- La ventana se calcula siempre en la zona de la estacion, nunca en la
-- configuracion del telefono. El valor por defecto cubre la operacion actual.
ALTER TABLE public.stations
    ADD COLUMN timezone text NOT NULL DEFAULT 'America/Mexico_City';

ALTER TABLE public.stations
    ADD CONSTRAINT stations_timezone_not_blank
        CHECK (btrim(timezone) <> '');

CREATE OR REPLACE FUNCTION app.guard_station_timezone()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names()
        WHERE name = NEW.timezone
    ) THEN
        RAISE EXCEPTION 'invalid_station_timezone'
            USING ERRCODE = '22023';
    END IF;

    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION app.guard_station_timezone() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.guard_station_timezone() TO postgres;

CREATE TRIGGER stations_timezone_guard
BEFORE INSERT OR UPDATE OF timezone
ON public.stations
FOR EACH ROW
EXECUTE FUNCTION app.guard_station_timezone();

ALTER TABLE public.assignments
    ADD CONSTRAINT assignments_id_station_environment_unique
        UNIQUE (id, station_id, environment_id);

CREATE TABLE public.shifts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    assignment_id uuid NOT NULL,

    folio text NOT NULL DEFAULT (
        'SH-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
    ),
    status text NOT NULL DEFAULT 'open',
    shift_group text NOT NULL,
    shift_slot text NOT NULL,
    operating_date date NOT NULL,
    scheduled_start_at timestamptz NOT NULL,
    scheduled_end_at timestamptz NOT NULL,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    late_minutes integer NOT NULL DEFAULT 0,

    start_odometer_km bigint NOT NULL,
    start_battery_pct integer NOT NULL,
    end_odometer_km bigint,
    end_battery_pct integer,

    revision bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT shifts_assignment_scope_fkey
        FOREIGN KEY (assignment_id, station_id, environment_id)
        REFERENCES public.assignments(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT shifts_driver_scope_fkey
        FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT shifts_vehicle_scope_fkey
        FOREIGN KEY (vehicle_id, station_id, environment_id)
        REFERENCES public.vehicles(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT shifts_environment_folio_unique
        UNIQUE (environment_id, folio),
    CONSTRAINT shifts_id_station_environment_unique
        UNIQUE (id, station_id, environment_id),
    CONSTRAINT shifts_folio_not_blank
        CHECK (btrim(folio) <> ''),
    CONSTRAINT shifts_status_check
        CHECK (status IN ('open', 'closed')),
    CONSTRAINT shifts_group_check
        CHECK (shift_group IN ('weekday', 'weekend')),
    CONSTRAINT shifts_slot_check
        CHECK (shift_slot IN ('morning', 'evening')),
    CONSTRAINT shifts_schedule_valid
        CHECK (scheduled_end_at > scheduled_start_at),
    CONSTRAINT shifts_started_after_window_open
        CHECK (started_at <= scheduled_end_at + interval '1 hour'),
    CONSTRAINT shifts_late_minutes_nonnegative
        CHECK (late_minutes >= 0),
    CONSTRAINT shifts_start_odometer_nonnegative
        CHECK (start_odometer_km >= 0),
    CONSTRAINT shifts_start_battery_range
        CHECK (start_battery_pct BETWEEN 0 AND 100),
    CONSTRAINT shifts_revision_positive
        CHECK (revision > 0),
    CONSTRAINT shifts_closed_fields_consistent
        CHECK (
            (
                status = 'open'
                AND finished_at IS NULL
                AND end_odometer_km IS NULL
                AND end_battery_pct IS NULL
            )
            OR
            (
                status = 'closed'
                AND finished_at IS NOT NULL
                AND finished_at >= started_at
                AND end_odometer_km IS NOT NULL
                AND end_odometer_km >= start_odometer_km
                AND end_battery_pct BETWEEN 0 AND 100
            )
        )
);

CREATE UNIQUE INDEX shifts_open_driver_unique
    ON public.shifts(driver_profile_id)
    WHERE status = 'open';

CREATE UNIQUE INDEX shifts_open_vehicle_unique
    ON public.shifts(vehicle_id)
    WHERE status = 'open';

CREATE UNIQUE INDEX shifts_open_assignment_unique
    ON public.shifts(assignment_id)
    WHERE status = 'open';

CREATE INDEX shifts_station_started_idx
    ON public.shifts(station_id, started_at DESC, id);

CREATE INDEX shifts_driver_started_idx
    ON public.shifts(driver_profile_id, started_at DESC, id);

ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.shifts FROM anon, authenticated;
GRANT ALL ON TABLE public.shifts TO postgres, service_role;

CREATE TABLE public.shift_readings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    shift_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    actor_profile_id uuid NOT NULL,
    kind text NOT NULL,
    odometer_km bigint NOT NULL,
    battery_pct integer NOT NULL,
    captured_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT shift_readings_shift_scope_fkey
        FOREIGN KEY (shift_id, station_id, environment_id)
        REFERENCES public.shifts(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT shift_readings_vehicle_scope_fkey
        FOREIGN KEY (vehicle_id, station_id, environment_id)
        REFERENCES public.vehicles(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT shift_readings_actor_environment_fkey
        FOREIGN KEY (actor_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT shift_readings_kind_check
        CHECK (kind IN ('start', 'finish')),
    CONSTRAINT shift_readings_odometer_nonnegative
        CHECK (odometer_km >= 0),
    CONSTRAINT shift_readings_battery_range
        CHECK (battery_pct BETWEEN 0 AND 100),
    CONSTRAINT shift_readings_shift_kind_unique
        UNIQUE (shift_id, kind)
);

CREATE INDEX shift_readings_vehicle_captured_idx
    ON public.shift_readings(vehicle_id, captured_at DESC, id);

ALTER TABLE public.shift_readings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.shift_readings FROM anon, authenticated;
GRANT ALL ON TABLE public.shift_readings TO postgres, service_role;

CREATE OR REPLACE FUNCTION app.guard_shift_reading_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
BEGIN
    RAISE EXCEPTION 'shift_readings_append_only'
        USING ERRCODE = '42501';
END;
$function$;

REVOKE ALL ON FUNCTION app.guard_shift_reading_append_only() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.guard_shift_reading_append_only() TO postgres;

CREATE TRIGGER shift_readings_block_update
BEFORE UPDATE ON public.shift_readings
FOR EACH ROW EXECUTE FUNCTION app.guard_shift_reading_append_only();

CREATE TRIGGER shift_readings_block_delete
BEFORE DELETE ON public.shift_readings
FOR EACH ROW EXECUTE FUNCTION app.guard_shift_reading_append_only();

CREATE TRIGGER shifts_touch
BEFORE UPDATE ON public.shifts
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE POLICY shifts_authorized_read
ON public.shifts
FOR SELECT TO authenticated
USING (
    driver_profile_id IN (
        SELECT dp.id
        FROM public.driver_profiles dp
        WHERE dp.profile_id = app.auth_profile_id()
    )
    OR station_id IN (SELECT station_id FROM app.auth_station_ids())
);

CREATE POLICY shift_readings_authorized_read
ON public.shift_readings
FOR SELECT TO authenticated
USING (
    shift_id IN (
        SELECT s.id
        FROM public.shifts s
        JOIN public.driver_profiles dp ON dp.id = s.driver_profile_id
        WHERE dp.profile_id = app.auth_profile_id()
    )
    OR station_id IN (SELECT station_id FROM app.auth_station_ids())
);

GRANT SELECT ON TABLE public.shifts TO authenticated;
GRANT SELECT ON TABLE public.shift_readings TO authenticated;

-- Devuelve la ventana absoluta del bloque en la zona de la estacion.
CREATE OR REPLACE FUNCTION app.shift_window(
    p_shift_slot text,
    p_now timestamptz,
    p_timezone text
)
RETURNS TABLE (
    operating_date date,
    scheduled_start_at timestamptz,
    scheduled_end_at timestamptz,
    opens_at timestamptz,
    closes_at timestamptz
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
DECLARE
    v_local_now timestamp;
    v_date date;
BEGIN
    IF p_shift_slot NOT IN ('morning', 'evening') THEN
        RAISE EXCEPTION 'invalid_shift_slot' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_timezone_names() WHERE name = p_timezone
    ) THEN
        RAISE EXCEPTION 'invalid_station_timezone' USING ERRCODE = '22023';
    END IF;

    v_local_now := p_now AT TIME ZONE p_timezone;
    v_date := v_local_now::date;

    IF p_shift_slot = 'evening' AND v_local_now::time < time '00:30' THEN
        v_date := v_date - 1;
    END IF;

    operating_date := v_date;

    IF p_shift_slot = 'morning' THEN
        scheduled_start_at := (v_date + time '05:00') AT TIME ZONE p_timezone;
        scheduled_end_at := (v_date + time '14:00') AT TIME ZONE p_timezone;
        opens_at := (v_date + time '04:00') AT TIME ZONE p_timezone;
        closes_at := scheduled_end_at;
    ELSE
        scheduled_start_at := (v_date + time '14:30') AT TIME ZONE p_timezone;
        scheduled_end_at := (v_date + time '23:30') AT TIME ZONE p_timezone;
        opens_at := (v_date + time '14:00') AT TIME ZONE p_timezone;
        closes_at := ((v_date + 1) + time '00:30') AT TIME ZONE p_timezone;
    END IF;

    RETURN NEXT;
END;
$function$;

REVOKE ALL ON FUNCTION app.shift_window(text, timestamptz, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.shift_window(text, timestamptz, text) TO postgres;

CREATE OR REPLACE FUNCTION public.start_shift(
    p_assignment_id uuid,
    p_odometer_km bigint,
    p_battery_pct integer,
    p_idempotency_key text
)
RETURNS public.shifts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_now timestamptz;
    v_request jsonb;
    v_assignment public.assignments%ROWTYPE;
    v_driver public.driver_profiles%ROWTYPE;
    v_membership public.staff_memberships%ROWTYPE;
    v_vehicle public.vehicles%ROWTYPE;
    v_station public.stations%ROWTYPE;
    v_command public.command_log%ROWTYPE;
    v_result public.shifts%ROWTYPE;
    v_window record;
    v_expected_group text;
    v_latest_odometer bigint;
BEGIN
    v_actor_profile_id := app.auth_profile_id();
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;

    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;
    IF p_odometer_km IS NULL OR p_odometer_km < 0 THEN
        RAISE EXCEPTION 'invalid_odometer' USING ERRCODE = '22023';
    END IF;
    IF p_battery_pct IS NULL OR p_battery_pct NOT BETWEEN 0 AND 100 THEN
        RAISE EXCEPTION 'invalid_battery_pct' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_request := jsonb_build_object(
        'assignment_id', p_assignment_id,
        'odometer_km', p_odometer_km,
        'battery_pct', p_battery_pct
    );

    SELECT cl.* INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;

    IF FOUND THEN
        IF v_command.command_name <> 'start_shift'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'shift_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT s.* INTO STRICT v_result
        FROM public.shifts s
        WHERE s.id = (v_command.result_payload->>'shift_id')::uuid;
        RETURN v_result;
    END IF;

    SELECT a.* INTO v_assignment
    FROM public.assignments a
    WHERE a.id = p_assignment_id
      AND a.environment_id = v_environment_id
      AND a.ended_at IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_assignment_not_found' USING ERRCODE = 'P0002';
    END IF;

    SELECT dp.* INTO STRICT v_driver
    FROM public.driver_profiles dp
    WHERE dp.id = v_assignment.driver_profile_id
      AND dp.status = 'active';

    IF v_driver.profile_id <> v_actor_profile_id THEN
        RAISE EXCEPTION 'assignment_not_owned_by_authenticated_driver'
            USING ERRCODE = '42501';
    END IF;

    SELECT m.* INTO v_membership
    FROM public.staff_memberships m
    WHERE m.id = v_driver.membership_id
      AND m.profile_id = v_actor_profile_id
      AND m.station_id = v_assignment.station_id
      AND m.environment_id = v_environment_id
      AND m.role = 'driver'
      AND m.starts_at <= v_now
      AND (m.ends_at IS NULL OR m.ends_at > v_now)
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_driver_membership_required' USING ERRCODE = '42501';
    END IF;
    IF v_membership.shift_group IS NULL OR v_membership.shift_slot IS NULL THEN
        RAISE EXCEPTION 'driver_shift_membership_incomplete' USING ERRCODE = '23514';
    END IF;

    SELECT s.* INTO STRICT v_station
    FROM public.stations s
    WHERE s.id = v_assignment.station_id
      AND s.environment_id = v_environment_id
      AND s.status = 'active';

    SELECT v.* INTO v_vehicle
    FROM public.vehicles v
    WHERE v.id = v_assignment.vehicle_id
      AND v.station_id = v_assignment.station_id
      AND v.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'assigned_vehicle_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_vehicle.status <> 'occupied' THEN
        RAISE EXCEPTION 'assigned_vehicle_not_occupied' USING ERRCODE = '55000';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(v_assignment.station_id::text, 15)
    );

    SELECT * INTO STRICT v_window
    FROM app.shift_window(v_membership.shift_slot, v_now, v_station.timezone);

    v_expected_group := CASE
        WHEN extract(isodow FROM v_window.operating_date) IN (6, 7)
            THEN 'weekend'
        ELSE 'weekday'
    END;

    IF v_membership.shift_group <> v_expected_group THEN
        RAISE EXCEPTION 'shift_group_not_scheduled_today' USING ERRCODE = '55000';
    END IF;
    IF v_now < v_window.opens_at THEN
        RAISE EXCEPTION 'shift_window_not_open' USING ERRCODE = '55000';
    END IF;
    IF v_now > v_window.closes_at THEN
        RAISE EXCEPTION 'shift_window_closed' USING ERRCODE = '55000';
    END IF;

    SELECT COALESCE(
        (
            SELECT sr.odometer_km
            FROM public.shift_readings sr
            WHERE sr.vehicle_id = v_vehicle.id
            ORDER BY sr.captured_at DESC, sr.id DESC
            LIMIT 1
        ),
        v_vehicle.odometer_km
    ) INTO v_latest_odometer;

    IF p_odometer_km < v_latest_odometer THEN
        RAISE EXCEPTION 'odometer_cannot_decrease' USING ERRCODE = '23514';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'start_shift',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    INSERT INTO public.shifts (
        environment_id, station_id, driver_profile_id, vehicle_id,
        assignment_id, status, shift_group, shift_slot, operating_date,
        scheduled_start_at, scheduled_end_at, started_at, late_minutes,
        start_odometer_km, start_battery_pct
    ) VALUES (
        v_environment_id, v_assignment.station_id, v_driver.id,
        v_vehicle.id, v_assignment.id, 'open', v_membership.shift_group,
        v_membership.shift_slot, v_window.operating_date,
        v_window.scheduled_start_at, v_window.scheduled_end_at, v_now,
        greatest(0, floor(extract(epoch FROM (v_now - v_window.scheduled_start_at)) / 60)::integer),
        p_odometer_km, p_battery_pct
    ) RETURNING * INTO v_result;

    INSERT INTO public.shift_readings (
        environment_id, station_id, shift_id, vehicle_id,
        actor_profile_id, kind, odometer_km, battery_pct, captured_at
    ) VALUES (
        v_environment_id, v_assignment.station_id, v_result.id, v_vehicle.id,
        v_actor_profile_id, 'start', p_odometer_km, p_battery_pct, v_now
    );

    UPDATE public.vehicles
    SET odometer_km = p_odometer_km,
        battery_pct = p_battery_pct,
        revision = revision + 1
    WHERE id = v_vehicle.id;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'shift_id', v_result.id,
            'started_at', v_result.started_at,
            'revision', v_result.revision
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_assignment.station_id,
        v_command.id, 'shift.started', 'shift', v_result.id,
        jsonb_build_object(
            'assignment_id', v_assignment.id,
            'vehicle_id', v_vehicle.id,
            'driver_profile_id', v_driver.id
        ), v_now
    );

    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.finish_shift(
    p_shift_id uuid,
    p_expected_revision bigint,
    p_odometer_km bigint,
    p_battery_pct integer,
    p_idempotency_key text
)
RETURNS public.shifts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_now timestamptz;
    v_request jsonb;
    v_shift public.shifts%ROWTYPE;
    v_driver public.driver_profiles%ROWTYPE;
    v_command public.command_log%ROWTYPE;
BEGIN
    v_actor_profile_id := app.auth_profile_id();
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;
    IF p_expected_revision IS NULL OR p_expected_revision < 1 THEN
        RAISE EXCEPTION 'invalid_expected_revision' USING ERRCODE = '22023';
    END IF;
    IF p_odometer_km IS NULL OR p_odometer_km < 0 THEN
        RAISE EXCEPTION 'invalid_odometer' USING ERRCODE = '22023';
    END IF;
    IF p_battery_pct IS NULL OR p_battery_pct NOT BETWEEN 0 AND 100 THEN
        RAISE EXCEPTION 'invalid_battery_pct' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_request := jsonb_build_object(
        'shift_id', p_shift_id,
        'expected_revision', p_expected_revision,
        'odometer_km', p_odometer_km,
        'battery_pct', p_battery_pct
    );

    SELECT cl.* INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;

    IF FOUND THEN
        IF v_command.command_name <> 'finish_shift'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'shift_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT s.* INTO STRICT v_shift
        FROM public.shifts s
        WHERE s.id = (v_command.result_payload->>'shift_id')::uuid;
        RETURN v_shift;
    END IF;

    SELECT s.* INTO v_shift
    FROM public.shifts s
    WHERE s.id = p_shift_id
      AND s.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'shift_not_found' USING ERRCODE = 'P0002';
    END IF;

    SELECT dp.* INTO STRICT v_driver
    FROM public.driver_profiles dp
    WHERE dp.id = v_shift.driver_profile_id;

    IF v_driver.profile_id <> v_actor_profile_id THEN
        RAISE EXCEPTION 'shift_not_owned_by_authenticated_driver'
            USING ERRCODE = '42501';
    END IF;
    IF v_shift.status <> 'open' THEN
        RAISE EXCEPTION 'shift_not_open' USING ERRCODE = '55000';
    END IF;
    IF v_shift.revision <> p_expected_revision THEN
        RAISE EXCEPTION 'shift_revision_conflict' USING ERRCODE = '40001';
    END IF;
    IF p_odometer_km < v_shift.start_odometer_km THEN
        RAISE EXCEPTION 'odometer_cannot_decrease' USING ERRCODE = '23514';
    END IF;
    IF v_now < v_shift.started_at THEN
        RAISE EXCEPTION 'environment_clock_precedes_shift_start'
            USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'finish_shift',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    UPDATE public.shifts
    SET status = 'closed',
        finished_at = v_now,
        end_odometer_km = p_odometer_km,
        end_battery_pct = p_battery_pct,
        revision = revision + 1
    WHERE id = v_shift.id
      AND revision = p_expected_revision
    RETURNING * INTO STRICT v_shift;

    INSERT INTO public.shift_readings (
        environment_id, station_id, shift_id, vehicle_id,
        actor_profile_id, kind, odometer_km, battery_pct, captured_at
    ) VALUES (
        v_environment_id, v_shift.station_id, v_shift.id, v_shift.vehicle_id,
        v_actor_profile_id, 'finish', p_odometer_km, p_battery_pct, v_now
    );

    UPDATE public.vehicles
    SET odometer_km = p_odometer_km,
        battery_pct = p_battery_pct,
        revision = revision + 1
    WHERE id = v_shift.vehicle_id;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'shift_id', v_shift.id,
            'finished_at', v_shift.finished_at,
            'revision', v_shift.revision
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_shift.station_id,
        v_command.id, 'shift.finished', 'shift', v_shift.id,
        jsonb_build_object(
            'vehicle_id', v_shift.vehicle_id,
            'driver_profile_id', v_shift.driver_profile_id,
            'revision', v_shift.revision
        ), v_now
    );

    RETURN v_shift;
END;
$function$;

COMMENT ON FUNCTION public.start_shift(uuid, bigint, integer, text) IS
    'Abre de forma idempotente el turno del conductor autenticado usando su asignacion activa y el reloj autoritativo del entorno.';

COMMENT ON FUNCTION public.finish_shift(uuid, bigint, bigint, integer, text) IS
    'Cierra de forma idempotente un turno propio abierto, exige revision vigente y registra la lectura final en la misma transaccion.';

REVOKE ALL ON FUNCTION public.start_shift(uuid, bigint, integer, text)
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finish_shift(uuid, bigint, bigint, integer, text)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.start_shift(uuid, bigint, integer, text)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finish_shift(uuid, bigint, bigint, integer, text)
TO authenticated, service_role;
