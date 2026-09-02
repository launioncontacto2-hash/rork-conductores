-- =====================================================================
-- TurnoEV · Consola 0.1 · modelo de lectura y pulso operativo
--
-- La consola es deliberadamente de solo lectura. Sus unicas escrituras son
-- el heartbeat del dispositivo autenticado mediante touch_device().
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Capacidad versionada y vistas vigentes
-- ---------------------------------------------------------------------

-- Las migraciones 15C/15D usaban `SELECT station_id FROM
-- app.auth_station_ids()` sin nombrar la columna devuelta por la funcion.
-- Dentro de una policy, PostgreSQL podia resolver ese nombre contra la fila
-- exterior y convertir el filtro en una tautologia. Se recrean aqui con un
-- alias de columna explicito antes de exponer la consola multiestacion.
DROP POLICY IF EXISTS vehicles_station_staff_read ON public.vehicles;
CREATE POLICY vehicles_station_staff_read
ON public.vehicles FOR SELECT TO authenticated
USING (
    station_id IN (
        SELECT scope.station_id
        FROM app.auth_station_ids() AS scope(station_id)
    )
);

DROP POLICY IF EXISTS driver_profiles_station_staff_read
ON public.driver_profiles;
CREATE POLICY driver_profiles_station_staff_read
ON public.driver_profiles FOR SELECT TO authenticated
USING (
    station_id IN (
        SELECT scope.station_id
        FROM app.auth_station_ids() AS scope(station_id)
    )
);

DROP POLICY IF EXISTS staff_memberships_supervisor_driver_read
ON public.staff_memberships;
CREATE POLICY staff_memberships_supervisor_driver_read
ON public.staff_memberships FOR SELECT TO authenticated
USING (
    role = 'driver'
    AND app.auth_has_role('supervisor', station_id)
);

DROP POLICY IF EXISTS assignments_station_staff_read ON public.assignments;
CREATE POLICY assignments_station_staff_read
ON public.assignments FOR SELECT TO authenticated
USING (
    station_id IN (
        SELECT scope.station_id
        FROM app.auth_station_ids() AS scope(station_id)
    )
);

DROP POLICY IF EXISTS vehicle_state_transitions_station_staff_read
ON public.vehicle_state_transitions;
CREATE POLICY vehicle_state_transitions_station_staff_read
ON public.vehicle_state_transitions FOR SELECT TO authenticated
USING (
    station_id IN (
        SELECT scope.station_id
        FROM app.auth_station_ids() AS scope(station_id)
    )
);

DROP POLICY IF EXISTS shifts_authorized_read ON public.shifts;
CREATE POLICY shifts_authorized_read
ON public.shifts FOR SELECT TO authenticated
USING (
    driver_profile_id IN (
        SELECT dp.id
        FROM public.driver_profiles dp
        WHERE dp.profile_id = app.auth_profile_id()
    )
    OR station_id IN (
        SELECT scope.station_id
        FROM app.auth_station_ids() AS scope(station_id)
    )
);

DROP POLICY IF EXISTS shift_readings_authorized_read
ON public.shift_readings;
CREATE POLICY shift_readings_authorized_read
ON public.shift_readings FOR SELECT TO authenticated
USING (
    shift_id IN (
        SELECT s.id
        FROM public.shifts s
        JOIN public.driver_profiles dp ON dp.id = s.driver_profile_id
        WHERE dp.profile_id = app.auth_profile_id()
    )
    OR station_id IN (
        SELECT scope.station_id
        FROM app.auth_station_ids() AS scope(station_id)
    )
);

CREATE TABLE public.station_capacity_grants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    capacity integer NOT NULL,
    granted_by uuid,
    effective_from timestamptz NOT NULL DEFAULT app.env_now(),
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT station_capacity_grants_capacity_check
        CHECK (capacity BETWEEN 1 AND 100),
    CONSTRAINT station_capacity_grants_station_environment_fkey
        FOREIGN KEY (station_id, environment_id)
        REFERENCES public.stations(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT station_capacity_grants_granter_environment_fkey
        FOREIGN KEY (granted_by, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT
);

CREATE INDEX station_capacity_grants_station_effective_idx
    ON public.station_capacity_grants(
        station_id,
        effective_from DESC,
        created_at DESC,
        id DESC
    );

CREATE INDEX station_capacity_grants_granter_environment_idx
    ON public.station_capacity_grants(granted_by, environment_id)
    WHERE granted_by IS NOT NULL;

ALTER TABLE public.station_capacity_grants ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION app.auth_env_now(p_environment_id uuid)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, app, auth, pg_temp
AS $function$
BEGIN
    IF auth.uid() IS NULL OR app.auth_profile_id() IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_environment_id <> app.current_environment_id() THEN
        RAISE EXCEPTION 'environment_mismatch' USING ERRCODE = '42501';
    END IF;
    RETURN app.env_now(p_environment_id);
END;
$function$;

REVOKE ALL ON FUNCTION app.auth_env_now(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION app.auth_env_now(uuid) TO authenticated, postgres;

CREATE OR REPLACE FUNCTION app.guard_station_capacity_grant_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, app, pg_temp
AS $function$
BEGIN
    RAISE EXCEPTION 'station_capacity_grants_append_only'
        USING ERRCODE = '55000';
END;
$function$;

REVOKE ALL ON FUNCTION app.guard_station_capacity_grant_append_only()
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.guard_station_capacity_grant_append_only()
TO postgres;

CREATE TRIGGER station_capacity_grants_block_update
BEFORE UPDATE ON public.station_capacity_grants
FOR EACH ROW
EXECUTE FUNCTION app.guard_station_capacity_grant_append_only();

CREATE TRIGGER station_capacity_grants_block_delete
BEFORE DELETE ON public.station_capacity_grants
FOR EACH ROW
EXECUTE FUNCTION app.guard_station_capacity_grant_append_only();

CREATE POLICY station_capacity_grants_station_staff_read
ON public.station_capacity_grants
FOR SELECT
TO authenticated
USING (
    station_id IN (
        SELECT scope.station_id
        FROM app.auth_station_ids() AS scope(station_id)
    )
);

REVOKE ALL ON TABLE public.station_capacity_grants FROM anon, authenticated;
GRANT SELECT ON TABLE public.station_capacity_grants TO authenticated;
GRANT ALL ON TABLE public.station_capacity_grants TO postgres, service_role;

CREATE VIEW public.station_capacity_current
WITH (security_invoker = true)
AS
SELECT DISTINCT ON (g.station_id)
    g.id,
    g.environment_id,
    g.station_id,
    g.capacity,
    g.granted_by,
    g.effective_from,
    g.created_at
FROM public.station_capacity_grants g
WHERE g.effective_from <= app.auth_env_now(g.environment_id)
ORDER BY
    g.station_id,
    g.effective_from DESC,
    g.created_at DESC,
    g.id DESC;

CREATE VIEW public.assignment_current
WITH (security_invoker = true)
AS
SELECT
    a.id,
    a.environment_id,
    a.station_id,
    a.driver_profile_id,
    a.vehicle_id,
    a.kind,
    a.titular_vehicle_id,
    a.note,
    a.assigned_by,
    a.assigned_at,
    a.created_at,
    a.updated_at
FROM public.assignments a
WHERE a.ended_at IS NULL;

-- Una sola fuente para resolver la identidad de la consola. La vigencia se
-- evalua con el reloj del entorno (incluido TEST), no con el reloj del PC.
CREATE VIEW public.console_identity
WITH (security_invoker = true)
AS
SELECT
    p.id AS profile_id,
    p.environment_id,
    p.display_name,
    p.employee_number,
    m.id AS membership_id,
    m.station_id,
    m.role,
    m.starts_at,
    m.ends_at,
    s.code AS station_code,
    s.name AS station_name,
    s.timezone AS station_timezone
FROM public.profiles p
JOIN public.staff_memberships m
  ON m.profile_id = p.id
 AND m.environment_id = p.environment_id
JOIN public.stations s
  ON s.id = m.station_id
 AND s.environment_id = m.environment_id
WHERE p.id = app.auth_profile_id()
  AND p.status = 'active'
  AND m.role = 'supervisor'
  AND m.starts_at <= app.auth_env_now(m.environment_id)
  AND (m.ends_at IS NULL OR m.ends_at > app.auth_env_now(m.environment_id))
  AND s.status = 'active';

CREATE VIEW public.console_drivers
WITH (security_invoker = true)
AS
SELECT
    dp.id,
    dp.environment_id,
    dp.station_id,
    dp.profile_id,
    dp.employee_number,
    dp.status,
    dp.revision,
    m.id AS membership_id,
    m.shift_group,
    m.shift_slot,
    m.starts_at,
    m.ends_at
FROM public.driver_profiles dp
JOIN public.staff_memberships m
  ON m.id = dp.membership_id
 AND m.environment_id = dp.environment_id
 AND m.station_id = dp.station_id
WHERE m.role = 'driver'
  AND m.starts_at <= app.auth_env_now(m.environment_id)
  AND (m.ends_at IS NULL OR m.ends_at > app.auth_env_now(m.environment_id));

REVOKE ALL ON TABLE public.station_capacity_current FROM anon, authenticated;
REVOKE ALL ON TABLE public.assignment_current FROM anon, authenticated;
REVOKE ALL ON TABLE public.console_identity FROM anon, authenticated;
REVOKE ALL ON TABLE public.console_drivers FROM anon, authenticated;
GRANT SELECT ON TABLE public.station_capacity_current TO authenticated;
GRANT SELECT ON TABLE public.assignment_current TO authenticated;
GRANT SELECT ON TABLE public.console_identity TO authenticated;
GRANT SELECT ON TABLE public.console_drivers TO authenticated;
GRANT ALL ON TABLE public.station_capacity_current TO postgres, service_role;
GRANT ALL ON TABLE public.assignment_current TO postgres, service_role;
GRANT ALL ON TABLE public.console_identity TO postgres, service_role;
GRANT ALL ON TABLE public.console_drivers TO postgres, service_role;

-- ---------------------------------------------------------------------
-- 2. Dispositivos y heartbeat autenticado
-- ---------------------------------------------------------------------

CREATE TABLE public.devices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    install_id text NOT NULL,
    profile_id uuid NOT NULL,
    active_membership_id uuid NOT NULL,
    platform text NOT NULL,
    app_version text,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,

    CONSTRAINT devices_install_id_not_blank CHECK (btrim(install_id) <> ''),
    CONSTRAINT devices_platform_check CHECK (platform IN ('ios', 'web', 'android')),
    CONSTRAINT devices_app_version_not_blank
        CHECK (app_version IS NULL OR btrim(app_version) <> ''),
    CONSTRAINT devices_profile_environment_fkey
        FOREIGN KEY (profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT devices_active_membership_fkey
        FOREIGN KEY (active_membership_id)
        REFERENCES public.staff_memberships(id)
        ON DELETE RESTRICT
);

CREATE UNIQUE INDEX devices_active_install_unique
    ON public.devices(environment_id, install_id)
    WHERE deleted_at IS NULL;

CREATE INDEX devices_profile_seen_idx
    ON public.devices(profile_id, last_seen_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX devices_membership_seen_idx
    ON public.devices(active_membership_id, last_seen_at DESC)
    WHERE deleted_at IS NULL;

-- Los indices parciales anteriores sirven a las lecturas activas; estos dos
-- cubren tambien filas retiradas cuando PostgreSQL valida las llaves foraneas.
CREATE INDEX devices_profile_environment_idx
    ON public.devices(profile_id, environment_id);

CREATE INDEX devices_active_membership_idx
    ON public.devices(active_membership_id);

ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER devices_touch
BEFORE UPDATE ON public.devices
FOR EACH ROW
EXECUTE FUNCTION app.touch_updated_at();

CREATE POLICY devices_self_read
ON public.devices
FOR SELECT
TO authenticated
USING (profile_id = app.auth_profile_id() AND deleted_at IS NULL);

CREATE POLICY devices_station_staff_read
ON public.devices
FOR SELECT
TO authenticated
USING (
    deleted_at IS NULL
    AND EXISTS (
        SELECT 1
        FROM public.staff_memberships m
        WHERE m.id = devices.active_membership_id
          AND m.station_id IN (
              SELECT scope.station_id
              FROM app.auth_station_ids() AS scope(station_id)
          )
    )
);

REVOKE ALL ON TABLE public.devices FROM anon, authenticated;
GRANT SELECT ON TABLE public.devices TO authenticated;
GRANT ALL ON TABLE public.devices TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.touch_device(
    p_install_id text,
    p_active_membership_id uuid,
    p_platform text,
    p_app_version text DEFAULT NULL
)
RETURNS public.devices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, app, auth, pg_temp
AS $function$
DECLARE
    v_profile_id uuid;
    v_environment_id uuid;
    v_membership public.staff_memberships%ROWTYPE;
    v_existing public.devices%ROWTYPE;
    v_device public.devices%ROWTYPE;
    v_now timestamptz;
BEGIN
    v_profile_id := app.auth_profile_id();
    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;

    IF p_install_id IS NULL OR btrim(p_install_id) = '' THEN
        RAISE EXCEPTION 'install_id_required' USING ERRCODE = '22023';
    END IF;

    IF p_platform NOT IN ('ios', 'web', 'android') THEN
        RAISE EXCEPTION 'invalid_platform' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);

    -- Dos tareas de arranque del mismo cliente no pueden crear dos filas ni
    -- convertir una colision del indice en un error visible para el usuario.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(v_environment_id::text || ':' || btrim(p_install_id), 0)
    );

    SELECT m.*
    INTO v_membership
    FROM public.staff_memberships m
    WHERE m.id = p_active_membership_id
      AND m.profile_id = v_profile_id
      AND m.environment_id = v_environment_id
      AND m.starts_at <= v_now
      AND (m.ends_at IS NULL OR m.ends_at > v_now);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'membership_revoked' USING ERRCODE = '42501';
    END IF;

    SELECT d.*
    INTO v_existing
    FROM public.devices d
    WHERE d.environment_id = v_environment_id
      AND d.install_id = btrim(p_install_id)
      AND d.deleted_at IS NULL
    FOR UPDATE;

    IF FOUND AND v_existing.profile_id <> v_profile_id THEN
        RAISE EXCEPTION 'device_owned_by_another_profile' USING ERRCODE = '42501';
    END IF;

    IF FOUND THEN
        IF v_existing.active_membership_id = v_membership.id
           AND v_existing.platform = p_platform
           AND v_existing.app_version IS NOT DISTINCT FROM NULLIF(btrim(p_app_version), '')
           AND v_existing.last_seen_at > now() - interval '1 minute' THEN
            RETURN v_existing;
        END IF;

        UPDATE public.devices
        SET active_membership_id = v_membership.id,
            platform = p_platform,
            app_version = NULLIF(btrim(p_app_version), ''),
            last_seen_at = now()
        WHERE id = v_existing.id
        RETURNING * INTO v_device;
    ELSE
        INSERT INTO public.devices (
            environment_id,
            install_id,
            profile_id,
            active_membership_id,
            platform,
            app_version,
            last_seen_at
        ) VALUES (
            v_environment_id,
            btrim(p_install_id),
            v_profile_id,
            v_membership.id,
            p_platform,
            NULLIF(btrim(p_app_version), ''),
            now()
        )
        RETURNING * INTO v_device;
    END IF;

    PERFORM app.refresh_station_live(v_membership.station_id);

    RETURN v_device;
END;
$function$;

REVOKE ALL ON FUNCTION public.touch_device(text, uuid, text, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.touch_device(text, uuid, text, text)
TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- 3. Proyeccion compacta por estacion
-- ---------------------------------------------------------------------

CREATE TABLE public.station_live (
    station_id uuid PRIMARY KEY,
    environment_id uuid NOT NULL,
    active_shifts integer NOT NULL DEFAULT 0,
    present_drivers integer NOT NULL DEFAULT 0,
    available_units integer NOT NULL DEFAULT 0,
    units_in_shop integer NOT NULL DEFAULT 0,
    open_incidents integer NOT NULL DEFAULT 0,
    critical_alerts integer NOT NULL DEFAULT 0,
    open_vacancies integer NOT NULL DEFAULT 0,
    billed_today_mxn integer NOT NULL DEFAULT 0,
    last_event_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT station_live_station_environment_fkey
        FOREIGN KEY (station_id, environment_id)
        REFERENCES public.stations(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT station_live_counts_nonnegative CHECK (
        active_shifts >= 0
        AND present_drivers >= 0
        AND available_units >= 0
        AND units_in_shop >= 0
        AND open_incidents >= 0
        AND critical_alerts >= 0
        AND open_vacancies >= 0
        AND billed_today_mxn >= 0
    )
);

CREATE INDEX station_live_environment_updated_idx
    ON public.station_live(environment_id, updated_at DESC);

ALTER TABLE public.station_live ENABLE ROW LEVEL SECURITY;

CREATE POLICY station_live_station_staff_read
ON public.station_live
FOR SELECT
TO authenticated
USING (
    station_id IN (
        SELECT scope.station_id
        FROM app.auth_station_ids() AS scope(station_id)
    )
);

REVOKE ALL ON TABLE public.station_live FROM anon, authenticated;
GRANT SELECT ON TABLE public.station_live TO authenticated;
GRANT ALL ON TABLE public.station_live TO postgres, service_role;

CREATE OR REPLACE FUNCTION app.refresh_station_live(p_station_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, app, pg_temp
AS $function$
DECLARE
    v_environment_id uuid;
BEGIN
    SELECT s.environment_id
    INTO v_environment_id
    FROM public.stations s
    WHERE s.id = p_station_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    INSERT INTO public.station_live (
        station_id,
        environment_id,
        active_shifts,
        present_drivers,
        available_units,
        units_in_shop,
        last_event_at,
        updated_at
    )
    SELECT
        p_station_id,
        v_environment_id,
        (SELECT count(*)::integer FROM public.shifts sh
         WHERE sh.station_id = p_station_id AND sh.status = 'open'),
        (SELECT count(DISTINCT sh.driver_profile_id)::integer FROM public.shifts sh
         WHERE sh.station_id = p_station_id AND sh.status = 'open'),
        (SELECT count(*)::integer FROM public.vehicles v
         WHERE v.station_id = p_station_id AND v.status = 'available'),
        (SELECT count(*)::integer FROM public.vehicles v
         WHERE v.station_id = p_station_id AND v.status = 'maintenance'),
        app.env_now(v_environment_id),
        now()
    ON CONFLICT (station_id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        active_shifts = EXCLUDED.active_shifts,
        present_drivers = EXCLUDED.present_drivers,
        available_units = EXCLUDED.available_units,
        units_in_shop = EXCLUDED.units_in_shop,
        last_event_at = EXCLUDED.last_event_at,
        updated_at = EXCLUDED.updated_at;
END;
$function$;

CREATE OR REPLACE FUNCTION app.refresh_station_live_from_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, app, pg_temp
AS $function$
DECLARE
    v_old_station_id uuid;
    v_new_station_id uuid;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        v_old_station_id := OLD.station_id;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        v_new_station_id := NEW.station_id;
    END IF;

    IF v_old_station_id IS NOT NULL THEN
        PERFORM app.refresh_station_live(v_old_station_id);
    END IF;
    IF v_new_station_id IS NOT NULL
       AND v_new_station_id IS DISTINCT FROM v_old_station_id THEN
        PERFORM app.refresh_station_live(v_new_station_id);
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION app.refresh_station_live_from_station()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, app, pg_temp
AS $function$
BEGIN
    PERFORM app.refresh_station_live(NEW.id);
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION app.refresh_station_live(uuid)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.refresh_station_live_from_row()
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.refresh_station_live_from_station()
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.refresh_station_live(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION app.refresh_station_live_from_row() TO postgres;
GRANT EXECUTE ON FUNCTION app.refresh_station_live_from_station() TO postgres;

CREATE TRIGGER station_live_from_stations
AFTER INSERT ON public.stations
FOR EACH ROW EXECUTE FUNCTION app.refresh_station_live_from_station();

CREATE TRIGGER station_live_from_vehicles
AFTER INSERT OR UPDATE OR DELETE ON public.vehicles
FOR EACH ROW EXECUTE FUNCTION app.refresh_station_live_from_row();

CREATE TRIGGER station_live_from_assignments
AFTER INSERT OR UPDATE OR DELETE ON public.assignments
FOR EACH ROW EXECUTE FUNCTION app.refresh_station_live_from_row();

CREATE TRIGGER station_live_from_shifts
AFTER INSERT OR UPDATE OR DELETE ON public.shifts
FOR EACH ROW EXECUTE FUNCTION app.refresh_station_live_from_row();

INSERT INTO public.station_live (station_id, environment_id)
SELECT s.id, s.environment_id
FROM public.stations s
ON CONFLICT (station_id) DO NOTHING;

DO $block$
DECLARE
    v_station_id uuid;
BEGIN
    FOR v_station_id IN SELECT id FROM public.stations LOOP
        PERFORM app.refresh_station_live(v_station_id);
    END LOOP;
END;
$block$;

-- La consola abre exactamente dos canales: pulso de estacion y membresia propia.
DO $block$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename = 'station_live'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.station_live;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename = 'staff_memberships'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.staff_memberships;
        END IF;
    END IF;
END;
$block$;

COMMENT ON TABLE public.station_live IS
    'Proyeccion reconstruible de una fila por estacion para la Consola 0.1 y Realtime.';
COMMENT ON FUNCTION public.touch_device(text, uuid, text, text) IS
    'Registra como maximo un heartbeat por minuto desde clientes; siempre deriva identidad y entorno de la sesion.';

;
