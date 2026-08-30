-- =====================================================================
-- TurnoEV · 15C
-- Vehiculos, historial de estado y asignaciones.
--
-- Autoridad:
--   - vehicles conserva el estado operativo actual
--   - vehicle_state_transitions conserva la historia append-only
--   - assignments conserva la relacion conductor <-> unidad
--   - la exclusividad activa se garantiza en PostgreSQL
--
-- Estados alineados con los clientes actuales:
--   available | occupied | maintenance
--
-- Tipos de asignacion alineados con iOS:
--   titular | substitute
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Vehiculos
-- ---------------------------------------------------------------------

CREATE TABLE public.vehicles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,

    internal_number text NOT NULL,
    plate text,
    vin text,
    qr_code text NOT NULL,
    legacy_code text,

    model text NOT NULL,

    odometer_km bigint NOT NULL DEFAULT 0,
    battery_pct integer,

    status text NOT NULL DEFAULT 'available',

    revision bigint NOT NULL DEFAULT 1,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT vehicles_environment_id_fkey
        FOREIGN KEY (environment_id)
        REFERENCES public.environments(id)
        ON DELETE RESTRICT,

    CONSTRAINT vehicles_station_environment_fkey
        FOREIGN KEY (station_id, environment_id)
        REFERENCES public.stations(id, environment_id)
        ON DELETE RESTRICT,

    CONSTRAINT vehicles_internal_number_not_blank
        CHECK (btrim(internal_number) <> ''),

    CONSTRAINT vehicles_qr_code_not_blank
        CHECK (btrim(qr_code) <> ''),

    CONSTRAINT vehicles_model_not_blank
        CHECK (btrim(model) <> ''),

    CONSTRAINT vehicles_plate_not_blank
        CHECK (plate IS NULL OR btrim(plate) <> ''),

    CONSTRAINT vehicles_vin_not_blank
        CHECK (vin IS NULL OR btrim(vin) <> ''),

    CONSTRAINT vehicles_legacy_code_not_blank
        CHECK (legacy_code IS NULL OR btrim(legacy_code) <> ''),

    CONSTRAINT vehicles_status_check
        CHECK (status IN ('available', 'occupied', 'maintenance')),

    CONSTRAINT vehicles_odometer_nonnegative
        CHECK (odometer_km >= 0),

    CONSTRAINT vehicles_battery_pct_range
        CHECK (
            battery_pct IS NULL
            OR battery_pct BETWEEN 0 AND 100
        ),

    CONSTRAINT vehicles_revision_positive
        CHECK (revision > 0),

    CONSTRAINT vehicles_environment_internal_number_unique
        UNIQUE (environment_id, internal_number),

    CONSTRAINT vehicles_environment_qr_code_unique
        UNIQUE (environment_id, qr_code),

    CONSTRAINT vehicles_environment_legacy_code_unique
        UNIQUE (environment_id, legacy_code),

    CONSTRAINT vehicles_id_environment_unique
        UNIQUE (id, environment_id),

    CONSTRAINT vehicles_id_station_environment_unique
        UNIQUE (id, station_id, environment_id)
);

CREATE UNIQUE INDEX vehicles_environment_plate_unique
    ON public.vehicles(environment_id, plate)
    WHERE plate IS NOT NULL;

CREATE UNIQUE INDEX vehicles_environment_vin_unique
    ON public.vehicles(environment_id, vin)
    WHERE vin IS NOT NULL;

CREATE INDEX vehicles_station_status_idx
    ON public.vehicles(station_id, status);

CREATE INDEX vehicles_environment_station_idx
    ON public.vehicles(environment_id, station_id);

ALTER TABLE public.vehicles
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.vehicles FROM anon, authenticated;
GRANT ALL ON TABLE public.vehicles TO postgres, service_role;


-- ---------------------------------------------------------------------
-- 2. Historial append-only de estados
-- ---------------------------------------------------------------------

CREATE TABLE public.vehicle_state_transitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,

    actor_profile_id uuid,

    from_status text,
    to_status text NOT NULL,

    reason text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_at timestamptz NOT NULL DEFAULT app.env_now(),

    CONSTRAINT vehicle_state_transitions_vehicle_environment_fkey
        FOREIGN KEY (vehicle_id, station_id, environment_id)
        REFERENCES public.vehicles(id, station_id, environment_id)
        ON DELETE RESTRICT,

    CONSTRAINT vehicle_state_transitions_actor_environment_fkey
        FOREIGN KEY (actor_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,

    CONSTRAINT vehicle_state_transitions_from_status_check
        CHECK (
            from_status IS NULL
            OR from_status IN ('available', 'occupied', 'maintenance')
        ),

    CONSTRAINT vehicle_state_transitions_to_status_check
        CHECK (
            to_status IN ('available', 'occupied', 'maintenance')
        ),

    CONSTRAINT vehicle_state_transitions_actual_change
        CHECK (
            from_status IS NULL
            OR from_status <> to_status
        ),

    CONSTRAINT vehicle_state_transitions_reason_not_blank
        CHECK (reason IS NULL OR btrim(reason) <> ''),

    CONSTRAINT vehicle_state_transitions_metadata_object
        CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX vehicle_state_transitions_vehicle_created_idx
    ON public.vehicle_state_transitions(vehicle_id, created_at DESC, id);

CREATE INDEX vehicle_state_transitions_station_created_idx
    ON public.vehicle_state_transitions(station_id, created_at DESC, id);

ALTER TABLE public.vehicle_state_transitions
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.vehicle_state_transitions
    FROM anon, authenticated;

GRANT ALL ON TABLE public.vehicle_state_transitions
    TO postgres, service_role;

-- ---------------------------------------------------------------------
-- 2.1 Candidate key de memberships para referencias con environment_id
-- ---------------------------------------------------------------------

ALTER TABLE public.staff_memberships
    ADD CONSTRAINT staff_memberships_id_environment_unique
        UNIQUE (id, environment_id);

-- ---------------------------------------------------------------------
-- 3. Driver profiles
--
-- 15A separa identidad (profiles) de datos laborales del conductor.
-- Cada driver_profile pertenece a una membresia role='driver'.
-- ---------------------------------------------------------------------

CREATE TABLE public.driver_profiles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    profile_id uuid NOT NULL,
    membership_id uuid NOT NULL,

    employee_number text NOT NULL,
    legacy_code text,

    revision bigint NOT NULL DEFAULT 1,

    status text NOT NULL DEFAULT 'active',

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT driver_profiles_profile_environment_fkey
        FOREIGN KEY (profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,

    CONSTRAINT driver_profiles_station_environment_fkey
        FOREIGN KEY (station_id, environment_id)
        REFERENCES public.stations(id, environment_id)
        ON DELETE RESTRICT,

    CONSTRAINT driver_profiles_membership_environment_fkey
        FOREIGN KEY (membership_id, environment_id)
        REFERENCES public.staff_memberships(id, environment_id)
        ON DELETE RESTRICT,

    CONSTRAINT driver_profiles_employee_number_not_blank
        CHECK (btrim(employee_number) <> ''),

    CONSTRAINT driver_profiles_legacy_code_not_blank
        CHECK (legacy_code IS NULL OR btrim(legacy_code) <> ''),

    CONSTRAINT driver_profiles_revision_positive
        CHECK (revision > 0),

    CONSTRAINT driver_profiles_status_check
        CHECK (status IN ('active', 'inactive')),

    CONSTRAINT driver_profiles_profile_unique
        UNIQUE (profile_id),

    CONSTRAINT driver_profiles_membership_unique
        UNIQUE (membership_id),

    CONSTRAINT driver_profiles_environment_employee_unique
        UNIQUE (environment_id, employee_number),

    CONSTRAINT driver_profiles_environment_legacy_code_unique
        UNIQUE (environment_id, legacy_code),

    CONSTRAINT driver_profiles_id_environment_unique
        UNIQUE (id, environment_id),

    CONSTRAINT driver_profiles_id_station_environment_unique
        UNIQUE (id, station_id, environment_id)
);

CREATE INDEX driver_profiles_station_status_idx
    ON public.driver_profiles(station_id, status);

ALTER TABLE public.driver_profiles
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.driver_profiles FROM anon, authenticated;
GRANT ALL ON TABLE public.driver_profiles TO postgres, service_role;

-- ---------------------------------------------------------------------
-- 3.1 Backfill de conductores existentes
-- ---------------------------------------------------------------------

INSERT INTO public.driver_profiles (
    environment_id,
    station_id,
    profile_id,
    membership_id,
    employee_number,
    legacy_code,
    status
)
SELECT
    m.environment_id,
    m.station_id,
    p.id,
    m.id,
    p.employee_number,
    p.legacy_code,
    CASE
        WHEN p.status = 'active' THEN 'active'
        ELSE 'inactive'
    END
FROM public.staff_memberships m
JOIN public.profiles p
  ON p.id = m.profile_id
 AND p.environment_id = m.environment_id
WHERE m.role = 'driver'
  AND m.ends_at IS NULL
ON CONFLICT (profile_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. Asignaciones
-- ---------------------------------------------------------------------

CREATE TABLE public.assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,

    driver_profile_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,

    kind text NOT NULL,

    titular_vehicle_id uuid,

    note text,

    assigned_by uuid NOT NULL,

    assigned_at timestamptz NOT NULL DEFAULT app.env_now(),
    ended_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT assignments_driver_station_environment_fkey
        FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id)
        ON DELETE RESTRICT,

    CONSTRAINT assignments_vehicle_station_environment_fkey
        FOREIGN KEY (vehicle_id, station_id, environment_id)
        REFERENCES public.vehicles(id, station_id, environment_id)
        ON DELETE RESTRICT,

    CONSTRAINT assignments_titular_vehicle_station_environment_fkey
        FOREIGN KEY (titular_vehicle_id, station_id, environment_id)
        REFERENCES public.vehicles(id, station_id, environment_id)
        ON DELETE RESTRICT,

    CONSTRAINT assignments_assigned_by_environment_fkey
        FOREIGN KEY (assigned_by, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,

    CONSTRAINT assignments_kind_check
        CHECK (kind IN ('titular', 'substitute')),

    CONSTRAINT assignments_note_not_blank
        CHECK (note IS NULL OR btrim(note) <> ''),

    CONSTRAINT assignments_valid_interval
    CHECK (ended_at IS NULL OR ended_at >= assigned_at),

    CONSTRAINT assignments_substitute_requires_titular
        CHECK (
            (kind = 'titular' AND titular_vehicle_id IS NULL)
            OR
            (
                kind = 'substitute'
                AND titular_vehicle_id IS NOT NULL
                AND titular_vehicle_id <> vehicle_id
            )
        )
);

-- Una sola unidad activa por conductor.
CREATE UNIQUE INDEX assignments_active_driver_unique
    ON public.assignments(driver_profile_id)
    WHERE ended_at IS NULL;

-- Un solo conductor activo por unidad.
CREATE UNIQUE INDEX assignments_active_vehicle_unique
    ON public.assignments(vehicle_id)
    WHERE ended_at IS NULL;

CREATE INDEX assignments_station_active_idx
    ON public.assignments(station_id, assigned_at DESC)
    WHERE ended_at IS NULL;

CREATE INDEX assignments_driver_history_idx
    ON public.assignments(driver_profile_id, assigned_at DESC, id);

CREATE INDEX assignments_vehicle_history_idx
    ON public.assignments(vehicle_id, assigned_at DESC, id);

ALTER TABLE public.assignments
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.assignments FROM anon, authenticated;
GRANT ALL ON TABLE public.assignments TO postgres, service_role;


-- ---------------------------------------------------------------------
-- 5. Integridad adicional de driver_profiles
--
-- Una FK no puede expresar que membership.role = 'driver'.
-- El trigger lo verifica autoritativamente.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.guard_driver_profile()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
DECLARE
    v_profile_id uuid;
    v_station_id uuid;
    v_environment_id uuid;
    v_role text;
BEGIN
    SELECT
        m.profile_id,
        m.station_id,
        m.environment_id,
        m.role
    INTO
        v_profile_id,
        v_station_id,
        v_environment_id,
        v_role
    FROM public.staff_memberships m
    WHERE m.id = NEW.membership_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'driver_membership_missing'
            USING ERRCODE = '23503';
    END IF;

    IF v_role <> 'driver' THEN
        RAISE EXCEPTION 'driver_membership_role_invalid'
            USING ERRCODE = '23514';
    END IF;

    IF v_profile_id <> NEW.profile_id
       OR v_station_id <> NEW.station_id
       OR v_environment_id <> NEW.environment_id THEN
        RAISE EXCEPTION 'driver_membership_identity_mismatch'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION app.guard_driver_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.guard_driver_profile() TO postgres;

CREATE TRIGGER driver_profiles_guard
BEFORE INSERT OR UPDATE
ON public.driver_profiles
FOR EACH ROW
EXECUTE FUNCTION app.guard_driver_profile();


-- ---------------------------------------------------------------------
-- 6. Append-only del historial de estado
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.guard_vehicle_state_transition_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
BEGIN
    RAISE EXCEPTION 'vehicle_state_transitions_append_only'
        USING ERRCODE = '42501';
END;
$function$;

REVOKE ALL ON FUNCTION app.guard_vehicle_state_transition_append_only()
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION app.guard_vehicle_state_transition_append_only()
TO postgres;

CREATE TRIGGER vehicle_state_transitions_block_update
BEFORE UPDATE
ON public.vehicle_state_transitions
FOR EACH ROW
EXECUTE FUNCTION app.guard_vehicle_state_transition_append_only();

CREATE TRIGGER vehicle_state_transitions_block_delete
BEFORE DELETE
ON public.vehicle_state_transitions
FOR EACH ROW
EXECUTE FUNCTION app.guard_vehicle_state_transition_append_only();


-- ---------------------------------------------------------------------
-- 7. updated_at
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION app.touch_updated_at() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.touch_updated_at() TO postgres;

CREATE TRIGGER vehicles_touch
BEFORE UPDATE ON public.vehicles
FOR EACH ROW
EXECUTE FUNCTION app.touch_updated_at();

CREATE TRIGGER driver_profiles_touch
BEFORE UPDATE ON public.driver_profiles
FOR EACH ROW
EXECUTE FUNCTION app.touch_updated_at();

CREATE TRIGGER assignments_touch
BEFORE UPDATE ON public.assignments
FOR EACH ROW
EXECUTE FUNCTION app.touch_updated_at();


-- ---------------------------------------------------------------------
-- 8. RLS de lectura inicial
--
-- La escritura productiva de 15C se hará mediante RPC.
-- No se concede INSERT/UPDATE directo a authenticated.
-- ---------------------------------------------------------------------

CREATE POLICY vehicles_station_staff_read
ON public.vehicles
FOR SELECT
TO authenticated
USING (
    station_id IN (
        SELECT station_id
        FROM app.auth_station_ids()
    )
);

CREATE POLICY driver_profiles_self_read
ON public.driver_profiles
FOR SELECT
TO authenticated
USING (
    profile_id = app.auth_profile_id()
);

CREATE POLICY driver_profiles_station_staff_read
ON public.driver_profiles
FOR SELECT
TO authenticated
USING (
    station_id IN (
        SELECT station_id
        FROM app.auth_station_ids()
    )
);

CREATE POLICY assignments_driver_read
ON public.assignments
FOR SELECT
TO authenticated
USING (
    driver_profile_id IN (
        SELECT dp.id
        FROM public.driver_profiles dp
        WHERE dp.profile_id = app.auth_profile_id()
    )
);

CREATE POLICY assignments_station_staff_read
ON public.assignments
FOR SELECT
TO authenticated
USING (
    station_id IN (
        SELECT station_id
        FROM app.auth_station_ids()
    )
);

CREATE POLICY vehicle_state_transitions_station_staff_read
ON public.vehicle_state_transitions
FOR SELECT
TO authenticated
USING (
    station_id IN (
        SELECT station_id
        FROM app.auth_station_ids()
    )
);

GRANT SELECT ON TABLE public.vehicles TO authenticated;
GRANT SELECT ON TABLE public.driver_profiles TO authenticated;
GRANT SELECT ON TABLE public.assignments TO authenticated;
GRANT SELECT ON TABLE public.vehicle_state_transitions TO authenticated;


-- ---------------------------------------------------------------------
-- 9. Comprobaciones finales
-- ---------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.driver_profiles dp
        JOIN public.staff_memberships m
          ON m.id = dp.membership_id
        WHERE m.role <> 'driver'
           OR m.profile_id <> dp.profile_id
           OR m.station_id <> dp.station_id
           OR m.environment_id <> dp.environment_id
    ) THEN
        RAISE EXCEPTION 'driver_profiles_integrity_failure'
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.assignments a
        JOIN public.driver_profiles dp
          ON dp.id = a.driver_profile_id
        JOIN public.vehicles v
          ON v.id = a.vehicle_id
        WHERE dp.station_id <> a.station_id
           OR v.station_id <> a.station_id
           OR dp.environment_id <> a.environment_id
           OR v.environment_id <> a.environment_id
    ) THEN
        RAISE EXCEPTION 'assignments_scope_failure'
            USING ERRCODE = '23514';
    END IF;
END;
$$;