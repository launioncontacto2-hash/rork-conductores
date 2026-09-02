-- =====================================================================
-- TurnoEV · 15E · Incidencias y ordenes de trabajo
--
-- Autoridad:
--   - incidents conserva el reporte que la estacion realmente recibio
--   - work_orders conserva el ciclo de reparacion y su revision optimista
--   - work_order_updates conserva el historial append-only
--   - toda escritura cliente cruza una RPC autenticada e idempotente
-- =====================================================================

CREATE TABLE public.incidents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    shift_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    reported_by uuid NOT NULL,
    folio text NOT NULL DEFAULT (
        'INC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
    ),
    kind text NOT NULL,
    severity text NOT NULL,
    description text NOT NULL,
    status text NOT NULL DEFAULT 'open',
    resolution_note text,
    revision bigint NOT NULL DEFAULT 1,
    reported_at timestamptz NOT NULL,
    closed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT incidents_shift_scope_fkey
        FOREIGN KEY (shift_id, station_id, environment_id)
        REFERENCES public.shifts(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT incidents_vehicle_scope_fkey
        FOREIGN KEY (vehicle_id, station_id, environment_id)
        REFERENCES public.vehicles(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT incidents_reporter_environment_fkey
        FOREIGN KEY (reported_by, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT incidents_id_station_environment_unique
        UNIQUE (id, station_id, environment_id),
    CONSTRAINT incidents_environment_folio_unique
        UNIQUE (environment_id, folio),
    CONSTRAINT incidents_folio_not_blank CHECK (btrim(folio) <> ''),
    CONSTRAINT incidents_kind_check
        CHECK (kind IN ('accident', 'damage', 'mechanical')),
    CONSTRAINT incidents_severity_check
        CHECK (severity IN ('medium', 'high', 'critical')),
    CONSTRAINT incidents_description_length
        CHECK (char_length(btrim(description)) BETWEEN 10 AND 2000),
    CONSTRAINT incidents_status_check
        CHECK (status IN ('open', 'review', 'closed')),
    CONSTRAINT incidents_revision_positive CHECK (revision > 0),
    CONSTRAINT incidents_closed_fields_consistent CHECK (
        (status = 'closed' AND closed_at IS NOT NULL)
        OR (status <> 'closed' AND closed_at IS NULL)
    )
);

CREATE INDEX incidents_station_reported_idx
    ON public.incidents(station_id, reported_at DESC, id);
CREATE INDEX incidents_reporter_reported_idx
    ON public.incidents(reported_by, reported_at DESC, id);
CREATE INDEX incidents_vehicle_reported_idx
    ON public.incidents(vehicle_id, reported_at DESC, id);

CREATE TABLE public.work_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    incident_id uuid NOT NULL,
    opened_by uuid NOT NULL,
    technician_profile_id uuid,
    folio text NOT NULL DEFAULT (
        'OT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
    ),
    problem text NOT NULL,
    priority text NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    estimated_minutes integer NOT NULL,
    work_done text NOT NULL DEFAULT '',
    pending_work text NOT NULL DEFAULT '',
    observations text NOT NULL DEFAULT '',
    revision bigint NOT NULL DEFAULT 1,
    opened_at timestamptz NOT NULL,
    accepted_at timestamptz,
    finished_at timestamptz,
    closed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT work_orders_incident_scope_fkey
        FOREIGN KEY (incident_id, station_id, environment_id)
        REFERENCES public.incidents(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT work_orders_vehicle_scope_fkey
        FOREIGN KEY (vehicle_id, station_id, environment_id)
        REFERENCES public.vehicles(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT work_orders_opener_environment_fkey
        FOREIGN KEY (opened_by, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT work_orders_technician_environment_fkey
        FOREIGN KEY (technician_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT work_orders_id_station_environment_unique
        UNIQUE (id, station_id, environment_id),
    CONSTRAINT work_orders_incident_unique UNIQUE (incident_id),
    CONSTRAINT work_orders_environment_folio_unique
        UNIQUE (environment_id, folio),
    CONSTRAINT work_orders_folio_not_blank CHECK (btrim(folio) <> ''),
    CONSTRAINT work_orders_problem_length
        CHECK (char_length(btrim(problem)) BETWEEN 10 AND 2000),
    CONSTRAINT work_orders_priority_check
        CHECK (priority IN ('low', 'medium', 'high', 'critical')),
    CONSTRAINT work_orders_status_check CHECK (
        status IN (
            'pending', 'in_progress', 'waiting', 'finished',
            'returned', 'closed', 'cancelled'
        )
    ),
    CONSTRAINT work_orders_estimated_minutes_positive
        CHECK (estimated_minutes BETWEEN 1 AND 10080),
    CONSTRAINT work_orders_revision_positive CHECK (revision > 0),
    CONSTRAINT work_orders_closed_fields_consistent CHECK (
        (status = 'closed' AND finished_at IS NOT NULL AND closed_at IS NOT NULL)
        OR (status <> 'closed' AND closed_at IS NULL)
    )
);

CREATE UNIQUE INDEX work_orders_open_vehicle_unique
    ON public.work_orders(vehicle_id)
    WHERE status IN ('pending', 'in_progress', 'waiting', 'finished', 'returned');
CREATE INDEX work_orders_station_opened_idx
    ON public.work_orders(station_id, opened_at DESC, id);

CREATE TABLE public.work_order_updates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    work_order_id uuid NOT NULL,
    actor_profile_id uuid NOT NULL,
    kind text NOT NULL,
    from_status text,
    to_status text NOT NULL,
    note text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL,

    CONSTRAINT work_order_updates_order_scope_fkey
        FOREIGN KEY (work_order_id, station_id, environment_id)
        REFERENCES public.work_orders(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT work_order_updates_actor_environment_fkey
        FOREIGN KEY (actor_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT work_order_updates_kind_check
        CHECK (kind IN ('opened', 'status_changed', 'closed')),
    CONSTRAINT work_order_updates_from_status_check CHECK (
        from_status IS NULL OR from_status IN (
            'pending', 'in_progress', 'waiting', 'finished',
            'returned', 'closed', 'cancelled'
        )
    ),
    CONSTRAINT work_order_updates_to_status_check CHECK (
        to_status IN (
            'pending', 'in_progress', 'waiting', 'finished',
            'returned', 'closed', 'cancelled'
        )
    ),
    CONSTRAINT work_order_updates_note_not_blank
        CHECK (note IS NULL OR btrim(note) <> ''),
    CONSTRAINT work_order_updates_metadata_object
        CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX work_order_updates_order_created_idx
    ON public.work_order_updates(work_order_id, created_at DESC, id);

ALTER TABLE public.incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_order_updates ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.incidents, public.work_orders,
    public.work_order_updates FROM anon, authenticated;
GRANT ALL ON TABLE public.incidents, public.work_orders,
    public.work_order_updates TO postgres, service_role;

CREATE TRIGGER incidents_touch
BEFORE UPDATE ON public.incidents
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TRIGGER work_orders_touch
BEFORE UPDATE ON public.work_orders
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE OR REPLACE FUNCTION app.guard_work_order_update_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
BEGIN
    RAISE EXCEPTION 'work_order_updates_append_only'
        USING ERRCODE = '42501';
END;
$function$;

REVOKE ALL ON FUNCTION app.guard_work_order_update_append_only() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.guard_work_order_update_append_only() TO postgres;

CREATE TRIGGER work_order_updates_block_update
BEFORE UPDATE ON public.work_order_updates
FOR EACH ROW EXECUTE FUNCTION app.guard_work_order_update_append_only();

CREATE TRIGGER work_order_updates_block_delete
BEFORE DELETE ON public.work_order_updates
FOR EACH ROW EXECUTE FUNCTION app.guard_work_order_update_append_only();

CREATE POLICY incidents_authorized_read
ON public.incidents FOR SELECT TO authenticated
USING (
    reported_by = app.auth_profile_id()
    OR app.auth_has_role('supervisor', station_id)
    OR app.auth_has_role('maintenance', station_id)
    OR app.auth_has_role('management', station_id)
);

CREATE POLICY work_orders_authorized_read
ON public.work_orders FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.incidents i
        WHERE i.id = incident_id
          AND i.reported_by = app.auth_profile_id()
    )
    OR app.auth_has_role('supervisor', station_id)
    OR app.auth_has_role('maintenance', station_id)
    OR app.auth_has_role('management', station_id)
);

CREATE POLICY work_order_updates_station_staff_read
ON public.work_order_updates FOR SELECT TO authenticated
USING (
    app.auth_has_role('supervisor', station_id)
    OR app.auth_has_role('maintenance', station_id)
    OR app.auth_has_role('management', station_id)
);

GRANT SELECT ON TABLE public.incidents, public.work_orders,
    public.work_order_updates TO authenticated;

-- El conductor solo puede reportar sobre su propio turno abierto y desde el
-- dispositivo que conserva el arrendamiento operativo de 16A.
CREATE OR REPLACE FUNCTION public.report_incident(
    p_shift_id uuid,
    p_kind text,
    p_description text,
    p_idempotency_key text,
    p_install_id text
)
RETURNS public.incidents
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
    v_result public.incidents%ROWTYPE;
    v_severity text;
BEGIN
    PERFORM app.assert_driver_device_session(p_install_id);
    v_actor_profile_id := app.auth_profile_id();
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;
    IF p_kind NOT IN ('accident', 'damage', 'mechanical') THEN
        RAISE EXCEPTION 'invalid_incident_kind' USING ERRCODE = '22023';
    END IF;
    IF p_description IS NULL
       OR char_length(btrim(p_description)) NOT BETWEEN 10 AND 2000 THEN
        RAISE EXCEPTION 'invalid_incident_description' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_severity := CASE p_kind
        WHEN 'accident' THEN 'critical'
        WHEN 'mechanical' THEN 'high'
        ELSE 'medium'
    END;
    v_request := jsonb_build_object(
        'shift_id', p_shift_id,
        'kind', p_kind,
        'description', btrim(p_description)
    );

    SELECT cl.* INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;

    IF FOUND THEN
        IF v_command.command_name <> 'report_incident'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'incident_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT i.* INTO STRICT v_result
        FROM public.incidents i
        WHERE i.id = (v_command.result_payload->>'incident_id')::uuid;
        RETURN v_result;
    END IF;

    SELECT s.* INTO v_shift
    FROM public.shifts s
    WHERE s.id = p_shift_id
      AND s.environment_id = v_environment_id
      AND s.status = 'open'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'open_shift_not_found' USING ERRCODE = 'P0002';
    END IF;

    SELECT dp.* INTO STRICT v_driver
    FROM public.driver_profiles dp
    WHERE dp.id = v_shift.driver_profile_id;

    IF v_driver.profile_id <> v_actor_profile_id THEN
        RAISE EXCEPTION 'shift_not_owned_by_authenticated_driver'
            USING ERRCODE = '42501';
    END IF;
    IF NOT app.auth_has_role('driver', v_shift.station_id) THEN
        RAISE EXCEPTION 'active_driver_membership_required'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'report_incident',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    INSERT INTO public.incidents (
        environment_id, station_id, shift_id, vehicle_id, reported_by,
        kind, severity, description, status, reported_at
    ) VALUES (
        v_environment_id, v_shift.station_id, v_shift.id, v_shift.vehicle_id,
        v_actor_profile_id, p_kind, v_severity, btrim(p_description),
        'open', v_now
    ) RETURNING * INTO v_result;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'incident_id', v_result.id,
            'folio', v_result.folio,
            'revision', v_result.revision
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_shift.station_id,
        v_command.id, 'incident.reported', 'incident', v_result.id,
        jsonb_build_object(
            'shift_id', v_shift.id,
            'vehicle_id', v_shift.vehicle_id,
            'kind', p_kind,
            'severity', v_severity
        ), v_now
    );

    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_incident(
    p_incident_id uuid,
    p_expected_revision bigint,
    p_status text,
    p_note text,
    p_idempotency_key text
)
RETURNS public.incidents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_now timestamptz;
    v_request jsonb;
    v_command public.command_log%ROWTYPE;
    v_incident public.incidents%ROWTYPE;
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
    IF p_status NOT IN ('review', 'closed') THEN
        RAISE EXCEPTION 'invalid_incident_status' USING ERRCODE = '22023';
    END IF;
    IF p_note IS NOT NULL AND btrim(p_note) = '' THEN
        RAISE EXCEPTION 'invalid_incident_note' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_request := jsonb_build_object(
        'incident_id', p_incident_id,
        'expected_revision', p_expected_revision,
        'status', p_status,
        'note', nullif(btrim(p_note), '')
    );

    SELECT cl.* INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'update_incident'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'incident_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT i.* INTO STRICT v_incident
        FROM public.incidents i
        WHERE i.id = (v_command.result_payload->>'incident_id')::uuid;
        RETURN v_incident;
    END IF;

    SELECT i.* INTO v_incident
    FROM public.incidents i
    WHERE i.id = p_incident_id
      AND i.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'incident_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT app.auth_has_role('supervisor', v_incident.station_id) THEN
        RAISE EXCEPTION 'supervisor_role_required_for_station'
            USING ERRCODE = '42501';
    END IF;
    IF v_incident.status = 'closed' THEN
        RAISE EXCEPTION 'incident_already_closed' USING ERRCODE = '55000';
    END IF;
    IF v_incident.revision <> p_expected_revision THEN
        RAISE EXCEPTION 'incident_revision_conflict' USING ERRCODE = '40001';
    END IF;
    IF p_status = 'closed' AND EXISTS (
        SELECT 1 FROM public.work_orders wo
        WHERE wo.incident_id = v_incident.id
          AND wo.status <> 'closed'
    ) THEN
        RAISE EXCEPTION 'incident_has_open_work_order' USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'update_incident',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    UPDATE public.incidents
    SET status = p_status,
        resolution_note = CASE
            WHEN p_note IS NULL THEN resolution_note ELSE btrim(p_note)
        END,
        closed_at = CASE WHEN p_status = 'closed' THEN v_now ELSE NULL END,
        revision = revision + 1
    WHERE id = v_incident.id
      AND revision = p_expected_revision
    RETURNING * INTO STRICT v_incident;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'incident_id', v_incident.id,
            'status', v_incident.status,
            'revision', v_incident.revision
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_incident.station_id,
        v_command.id, 'incident.updated', 'incident', v_incident.id,
        jsonb_build_object('status', v_incident.status, 'revision', v_incident.revision),
        v_now
    );

    RETURN v_incident;
END;
$function$;

CREATE OR REPLACE FUNCTION public.open_work_order(
    p_incident_id uuid,
    p_priority text,
    p_estimated_minutes integer,
    p_idempotency_key text
)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_now timestamptz;
    v_request jsonb;
    v_command public.command_log%ROWTYPE;
    v_incident public.incidents%ROWTYPE;
    v_vehicle public.vehicles%ROWTYPE;
    v_result public.work_orders%ROWTYPE;
BEGIN
    v_actor_profile_id := app.auth_profile_id();
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;
    IF p_priority NOT IN ('low', 'medium', 'high', 'critical') THEN
        RAISE EXCEPTION 'invalid_work_order_priority' USING ERRCODE = '22023';
    END IF;
    IF p_estimated_minutes IS NULL OR p_estimated_minutes NOT BETWEEN 1 AND 10080 THEN
        RAISE EXCEPTION 'invalid_estimated_minutes' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_request := jsonb_build_object(
        'incident_id', p_incident_id,
        'priority', p_priority,
        'estimated_minutes', p_estimated_minutes
    );

    SELECT cl.* INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'open_work_order'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'work_order_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT wo.* INTO STRICT v_result
        FROM public.work_orders wo
        WHERE wo.id = (v_command.result_payload->>'work_order_id')::uuid;
        RETURN v_result;
    END IF;

    SELECT i.* INTO v_incident
    FROM public.incidents i
    WHERE i.id = p_incident_id
      AND i.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'incident_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT app.auth_has_role('maintenance', v_incident.station_id) THEN
        RAISE EXCEPTION 'maintenance_role_required_for_station'
            USING ERRCODE = '42501';
    END IF;
    IF v_incident.status = 'closed' THEN
        RAISE EXCEPTION 'incident_already_closed' USING ERRCODE = '55000';
    END IF;

    SELECT v.* INTO STRICT v_vehicle
    FROM public.vehicles v
    WHERE v.id = v_incident.vehicle_id
      AND v.station_id = v_incident.station_id
      AND v.environment_id = v_environment_id
    FOR UPDATE;

    IF EXISTS (
        SELECT 1 FROM public.work_orders wo
        WHERE wo.incident_id = v_incident.id
    ) THEN
        RAISE EXCEPTION 'incident_work_order_already_exists'
            USING ERRCODE = '23505';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.work_orders wo
        WHERE wo.vehicle_id = v_vehicle.id
          AND wo.status IN ('pending', 'in_progress', 'waiting', 'finished', 'returned')
    ) THEN
        RAISE EXCEPTION 'vehicle_has_open_work_order' USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'open_work_order',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    INSERT INTO public.work_orders (
        environment_id, station_id, vehicle_id, incident_id, opened_by,
        technician_profile_id, problem, priority, status,
        estimated_minutes, opened_at
    ) VALUES (
        v_environment_id, v_incident.station_id, v_vehicle.id, v_incident.id,
        v_actor_profile_id, v_actor_profile_id, v_incident.description,
        p_priority, 'pending', p_estimated_minutes, v_now
    ) RETURNING * INTO v_result;

    INSERT INTO public.work_order_updates (
        environment_id, station_id, work_order_id, actor_profile_id,
        kind, from_status, to_status, note, created_at
    ) VALUES (
        v_environment_id, v_result.station_id, v_result.id, v_actor_profile_id,
        'opened', NULL, 'pending', 'Orden abierta desde incidencia', v_now
    );

    UPDATE public.incidents
    SET status = 'review', revision = revision + 1
    WHERE id = v_incident.id;

    IF v_vehicle.status <> 'maintenance' THEN
        INSERT INTO public.vehicle_state_transitions (
            environment_id, station_id, vehicle_id, actor_profile_id,
            from_status, to_status, reason, metadata, created_at
        ) VALUES (
            v_environment_id, v_incident.station_id, v_vehicle.id,
            v_actor_profile_id, v_vehicle.status, 'maintenance',
            'work_order_opened',
            jsonb_build_object('work_order_id', v_result.id, 'incident_id', v_incident.id),
            v_now
        );

        UPDATE public.vehicles
        SET status = 'maintenance', revision = revision + 1
        WHERE id = v_vehicle.id;
    END IF;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'work_order_id', v_result.id,
            'folio', v_result.folio,
            'revision', v_result.revision
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_result.station_id,
        v_command.id, 'work_order.opened', 'work_order', v_result.id,
        jsonb_build_object('incident_id', v_incident.id, 'vehicle_id', v_vehicle.id),
        v_now
    );

    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.close_work_order(
    p_work_order_id uuid,
    p_expected_revision bigint,
    p_work_done text,
    p_idempotency_key text
)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_now timestamptz;
    v_request jsonb;
    v_command public.command_log%ROWTYPE;
    v_order public.work_orders%ROWTYPE;
    v_vehicle public.vehicles%ROWTYPE;
    v_restore_status text;
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
    IF p_work_done IS NULL
       OR char_length(btrim(p_work_done)) NOT BETWEEN 10 AND 4000 THEN
        RAISE EXCEPTION 'invalid_work_done' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_request := jsonb_build_object(
        'work_order_id', p_work_order_id,
        'expected_revision', p_expected_revision,
        'work_done', btrim(p_work_done)
    );

    SELECT cl.* INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'close_work_order'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'work_order_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT wo.* INTO STRICT v_order
        FROM public.work_orders wo
        WHERE wo.id = (v_command.result_payload->>'work_order_id')::uuid;
        RETURN v_order;
    END IF;

    SELECT wo.* INTO v_order
    FROM public.work_orders wo
    WHERE wo.id = p_work_order_id
      AND wo.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'work_order_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT app.auth_has_role('maintenance', v_order.station_id) THEN
        RAISE EXCEPTION 'maintenance_role_required_for_station'
            USING ERRCODE = '42501';
    END IF;
    IF v_order.status IN ('closed', 'cancelled') THEN
        RAISE EXCEPTION 'work_order_not_open' USING ERRCODE = '55000';
    END IF;
    IF v_order.revision <> p_expected_revision THEN
        RAISE EXCEPTION 'work_order_revision_conflict' USING ERRCODE = '40001';
    END IF;

    SELECT v.* INTO STRICT v_vehicle
    FROM public.vehicles v
    WHERE v.id = v_order.vehicle_id
      AND v.station_id = v_order.station_id
      AND v.environment_id = v_environment_id
    FOR UPDATE;
    IF v_vehicle.status <> 'maintenance' THEN
        RAISE EXCEPTION 'work_order_vehicle_not_in_maintenance'
            USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'close_work_order',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    UPDATE public.work_orders
    SET status = 'closed',
        work_done = btrim(p_work_done),
        finished_at = v_now,
        closed_at = v_now,
        revision = revision + 1
    WHERE id = v_order.id
      AND revision = p_expected_revision
    RETURNING * INTO STRICT v_order;

    UPDATE public.incidents
    SET status = 'closed',
        resolution_note = 'Cerrada por ' || v_order.folio,
        closed_at = v_now,
        revision = revision + 1
    WHERE id = v_order.incident_id
      AND status <> 'closed';

    v_restore_status := CASE WHEN EXISTS (
        SELECT 1 FROM public.assignments a
        WHERE a.vehicle_id = v_vehicle.id AND a.ended_at IS NULL
    ) THEN 'occupied' ELSE 'available' END;

    INSERT INTO public.vehicle_state_transitions (
        environment_id, station_id, vehicle_id, actor_profile_id,
        from_status, to_status, reason, metadata, created_at
    ) VALUES (
        v_environment_id, v_order.station_id, v_vehicle.id,
        v_actor_profile_id, 'maintenance', v_restore_status,
        'work_order_closed', jsonb_build_object('work_order_id', v_order.id),
        v_now
    );

    UPDATE public.vehicles
    SET status = v_restore_status, revision = revision + 1
    WHERE id = v_vehicle.id;

    INSERT INTO public.work_order_updates (
        environment_id, station_id, work_order_id, actor_profile_id,
        kind, from_status, to_status, note, created_at
    ) VALUES (
        v_environment_id, v_order.station_id, v_order.id, v_actor_profile_id,
        'closed', 'pending', 'closed', btrim(p_work_done), v_now
    );

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'work_order_id', v_order.id,
            'status', v_order.status,
            'revision', v_order.revision
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_order.station_id,
        v_command.id, 'work_order.closed', 'work_order', v_order.id,
        jsonb_build_object(
            'incident_id', v_order.incident_id,
            'vehicle_id', v_vehicle.id,
            'vehicle_status', v_restore_status
        ), v_now
    );

    RETURN v_order;
END;
$function$;

COMMENT ON FUNCTION public.report_incident(uuid, text, text, text, text) IS
    'Registra de forma idempotente una incidencia del turno abierto propio y exige el dispositivo conductor vigente.';
COMMENT ON FUNCTION public.update_incident(uuid, bigint, text, text, text) IS
    'Permite a supervision avanzar o cerrar una incidencia con revision optimista.';
COMMENT ON FUNCTION public.open_work_order(uuid, text, integer, text) IS
    'Abre una unica orden para la incidencia, exige taller de la estacion y mueve la unidad a mantenimiento.';
COMMENT ON FUNCTION public.close_work_order(uuid, bigint, text, text) IS
    'Cierra la orden y la incidencia en una transaccion y restaura el estado coherente de la unidad.';

REVOKE ALL ON FUNCTION public.report_incident(uuid, text, text, text, text)
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_incident(uuid, bigint, text, text, text)
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.open_work_order(uuid, text, integer, text)
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.close_work_order(uuid, bigint, text, text)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.report_incident(uuid, text, text, text, text)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_incident(uuid, bigint, text, text, text)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.open_work_order(uuid, text, integer, text)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.close_work_order(uuid, bigint, text, text)
TO authenticated, service_role;

DO $block$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.incidents;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.work_orders;
    END IF;
END;
$block$;
