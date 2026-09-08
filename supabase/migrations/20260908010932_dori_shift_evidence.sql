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

-- Una carga puede terminar antes que la transaccion del turno (red interrumpida,
-- lectura invalida o conflicto de revision). El conductor puede limpiar solamente
-- objetos propios que aun no sean evidencia formal. Una vez enlazados, esta politica
-- deja de verlos para DELETE y la app no puede alterar el expediente del turno.
CREATE POLICY shift_evidence_objects_delete_unreferenced
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id = 'shift-evidence'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) >= 4
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND (storage.foldername(name))[3] = app.auth_profile_id()::text
    AND NOT EXISTS (
        SELECT 1
        FROM public.shift_evidence evidence
        WHERE evidence.object_path = name
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

    IF NOT EXISTS (
        SELECT 1
        FROM public.shift_evidence evidence
        WHERE evidence.shift_id = v_shift.id
          AND evidence.kind = 'start_odometer'
          AND evidence.object_path = btrim(p_odometer_path)
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.shift_evidence evidence
        WHERE evidence.shift_id = v_shift.id
          AND evidence.kind = 'start_battery'
          AND evidence.object_path = btrim(p_battery_path)
    ) THEN
        RAISE EXCEPTION 'shift_evidence_idempotency_conflict'
            USING ERRCODE = '23505';
    END IF;

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

    IF NOT EXISTS (
        SELECT 1
        FROM public.shift_evidence evidence
        WHERE evidence.shift_id = v_shift.id
          AND evidence.kind = 'finish_odometer'
          AND evidence.object_path = btrim(p_odometer_path)
    ) THEN
        RAISE EXCEPTION 'shift_evidence_idempotency_conflict'
            USING ERRCODE = '23505';
    END IF;

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

CREATE OR REPLACE FUNCTION public.console_audit_history(p_limit integer DEFAULT 100)
RETURNS TABLE (
    id uuid,
    station_id uuid,
    actor_profile_id uuid,
    actor_name text,
    actor_employee_number text,
    event_type text,
    entity_type text,
    entity_id uuid,
    metadata jsonb,
    occurred_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_environment_id uuid;
    v_actor_profile_id uuid;
    v_limit integer;
BEGIN
    v_actor_profile_id := app.auth_profile_id();
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;

    v_environment_id := app.current_environment_id();
    v_limit := least(greatest(coalesce(p_limit, 100), 1), 200);

    IF NOT EXISTS (
        SELECT 1
        FROM public.staff_memberships membership
        WHERE membership.profile_id = v_actor_profile_id
          AND membership.environment_id = v_environment_id
          AND membership.role = 'supervisor'
          AND membership.starts_at <= app.env_now(v_environment_id)
          AND (
              membership.ends_at IS NULL
              OR membership.ends_at > app.env_now(v_environment_id)
          )
    ) THEN
        RAISE EXCEPTION 'supervisor_role_required' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        event.id,
        event.station_id,
        event.actor_profile_id,
        coalesce(actor.display_name, 'Sistema') AS actor_name,
        coalesce(actor.employee_number, '—') AS actor_employee_number,
        event.event_type,
        event.entity_type,
        event.entity_id,
        event.metadata,
        event.occurred_at
    FROM public.audit_log event
    LEFT JOIN public.profiles actor ON actor.id = event.actor_profile_id
    WHERE event.environment_id = v_environment_id
      AND event.station_id IS NOT NULL
      AND app.auth_has_role('supervisor', event.station_id)
    ORDER BY event.occurred_at DESC, event.id DESC
    LIMIT v_limit;
END;
$function$;

REVOKE ALL ON FUNCTION public.console_audit_history(integer)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.console_audit_history(integer)
TO authenticated, service_role;

CREATE OR REPLACE FUNCTION app.enforce_sensitive_command_reason()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
BEGIN
    IF NEW.command_name IN (
        'assign_vehicle', 'update_incident', 'approve_guard', 'resolve_absence',
        'revoke_driver_device'
    ) AND char_length(btrim(coalesce(NEW.request_payload ->> 'note', ''))) < 5 THEN
        RAISE EXCEPTION 'sensitive_command_reason_required'
            USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS command_log_sensitive_reason_guard ON public.command_log;
CREATE TRIGGER command_log_sensitive_reason_guard
BEFORE INSERT ON public.command_log
FOR EACH ROW EXECUTE FUNCTION app.enforce_sensitive_command_reason();

REVOKE ALL ON FUNCTION app.enforce_sensitive_command_reason()
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.enforce_sensitive_command_reason()
TO postgres, service_role;

CREATE OR REPLACE FUNCTION app.assert_driver_device_session(p_install_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_profile_id uuid;
    v_environment_id uuid;
    v_session_id uuid;
    v_now timestamptz;
BEGIN
    v_profile_id := app.auth_profile_id();
    v_session_id := app.auth_session_id();
    IF v_profile_id IS NULL OR v_session_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_install_id IS NULL OR btrim(p_install_id) = '' THEN
        RAISE EXCEPTION 'install_id_required' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);

    IF NOT EXISTS (
        SELECT 1
        FROM app.driver_device_sessions lease
        JOIN public.devices device ON device.id = lease.device_id
        JOIN public.staff_memberships membership
          ON membership.id = device.active_membership_id
         AND membership.profile_id = device.profile_id
         AND membership.environment_id = device.environment_id
        WHERE lease.profile_id = v_profile_id
          AND lease.environment_id = v_environment_id
          AND lease.auth_session_id = v_session_id
          AND device.profile_id = v_profile_id
          AND device.environment_id = v_environment_id
          AND device.install_id = btrim(p_install_id)
          AND device.deleted_at IS NULL
          AND membership.role = 'driver'
          AND membership.starts_at <= v_now
          AND (membership.ends_at IS NULL OR membership.ends_at > v_now)
    ) THEN
        RAISE EXCEPTION 'driver_session_replaced' USING ERRCODE = '42501';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION app.assert_driver_device_session(text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.assert_driver_device_session(text)
TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.revoke_driver_device(
    p_device_id uuid,
    p_note text,
    p_idempotency_key text
)
RETURNS public.devices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_station_id uuid;
    v_now timestamptz;
    v_request jsonb;
    v_device public.devices%ROWTYPE;
    v_command public.command_log%ROWTYPE;
BEGIN
    v_actor_profile_id := app.auth_profile_id();
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_device_id IS NULL THEN
        RAISE EXCEPTION 'device_id_required' USING ERRCODE = '22023';
    END IF;
    IF p_note IS NULL OR char_length(btrim(p_note)) NOT BETWEEN 5 AND 1000 THEN
        RAISE EXCEPTION 'device_revocation_reason_required' USING ERRCODE = '22023';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_request := jsonb_build_object(
        'device_id', p_device_id,
        'note', btrim(p_note)
    );

    SELECT command.*
    INTO v_command
    FROM public.command_log command
    WHERE command.environment_id = v_environment_id
      AND command.idempotency_key = btrim(p_idempotency_key);

    IF FOUND THEN
        IF v_command.command_name <> 'revoke_driver_device'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed' THEN
            RAISE EXCEPTION 'idempotency_key_reused' USING ERRCODE = '23505';
        END IF;
        SELECT device, membership.station_id
        INTO STRICT v_device, v_station_id
        FROM public.devices device
        JOIN public.staff_memberships membership
          ON membership.id = device.active_membership_id
         AND membership.profile_id = device.profile_id
         AND membership.environment_id = device.environment_id
        WHERE device.id = p_device_id
          AND device.environment_id = v_environment_id
          AND membership.role = 'driver';
        IF NOT app.auth_has_role('supervisor', v_station_id) THEN
            RAISE EXCEPTION 'supervisor_station_role_required' USING ERRCODE = '42501';
        END IF;
        RETURN v_device;
    END IF;

    SELECT device, membership.station_id
    INTO v_device, v_station_id
    FROM public.devices device
    JOIN public.staff_memberships membership
      ON membership.id = device.active_membership_id
     AND membership.profile_id = device.profile_id
     AND membership.environment_id = device.environment_id
    WHERE device.id = p_device_id
      AND device.environment_id = v_environment_id
      AND device.deleted_at IS NULL
      AND membership.role = 'driver'
    FOR UPDATE OF device;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_driver_device_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT app.auth_has_role('supervisor', v_station_id) THEN
        RAISE EXCEPTION 'supervisor_station_role_required' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'revoke_driver_device',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    DELETE FROM app.driver_device_sessions
    WHERE device_id = v_device.id;

    UPDATE public.devices
    SET deleted_at = v_now
    WHERE id = v_device.id
      AND deleted_at IS NULL
    RETURNING * INTO STRICT v_device;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'device_id', v_device.id,
            'profile_id', v_device.profile_id,
            'revoked_at', v_device.deleted_at
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_station_id, v_command.id,
        'device.revoked', 'device', v_device.id,
        jsonb_build_object(
            'profile_id', v_device.profile_id,
            'platform', v_device.platform,
            'note', btrim(p_note)
        ),
        v_now
    );

    RETURN v_device;
END;
$function$;

REVOKE ALL ON FUNCTION public.revoke_driver_device(uuid, text, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_driver_device(uuid, text, text)
TO authenticated, service_role;

COMMENT ON TABLE public.shift_evidence IS
    'Evidencia fotografica privada e inmutable del inicio y cierre de cada turno DORI.';
COMMENT ON FUNCTION public.start_shift_v3(uuid, bigint, integer, text, text, text, text) IS
    'Abre un turno y registra sus dos fotografias propias en la misma transaccion.';
COMMENT ON FUNCTION public.finish_shift_v3(uuid, bigint, bigint, integer, text, text, text) IS
    'Cierra un turno y registra la fotografia final propia en la misma transaccion.';
COMMENT ON FUNCTION public.console_audit_history(integer) IS
    'Devuelve a supervision el historial append-only de sus estaciones vigentes sin exponer command_log.';
COMMENT ON FUNCTION app.enforce_sensitive_command_reason() IS
    'Impide que un comando sensible se registre sin un motivo operativo suficiente.';
COMMENT ON FUNCTION app.assert_driver_device_session(text) IS
    'Exige que la sesion exclusiva del conductor, su dispositivo y su membresia sigan vigentes.';
COMMENT ON FUNCTION public.revoke_driver_device(uuid, text, text) IS
    'Permite a supervision retirar con motivo auditado el acceso operativo de un dispositivo conductor de su estacion.';
