-- DORI TEST vehicle identification.
--
-- `vehicles.id` remains the immutable business key and `internal_number` remains
-- the technical TEST reference used by existing shifts, assignments and QR flows.
-- The additional nullable attributes provide the stable operational identity
-- shown to people without rewriting historical references.

ALTER TABLE public.vehicles
    ADD COLUMN manufacturer text,
    ADD COLUMN model_display text,
    ADD COLUMN unit_number integer,
    ADD COLUMN operational_code text,
    ADD COLUMN color text;

ALTER TABLE public.vehicles
    ADD CONSTRAINT vehicles_manufacturer_not_blank
        CHECK (manufacturer IS NULL OR btrim(manufacturer) <> ''),
    ADD CONSTRAINT vehicles_model_display_not_blank
        CHECK (model_display IS NULL OR btrim(model_display) <> ''),
    ADD CONSTRAINT vehicles_unit_number_positive
        CHECK (unit_number IS NULL OR unit_number > 0),
    ADD CONSTRAINT vehicles_operational_code_not_blank
        CHECK (operational_code IS NULL OR btrim(operational_code) <> ''),
    ADD CONSTRAINT vehicles_color_not_blank
        CHECK (color IS NULL OR btrim(color) <> '');

CREATE UNIQUE INDEX vehicles_environment_unit_number_unique
ON public.vehicles(environment_id, unit_number)
WHERE unit_number IS NOT NULL;

CREATE UNIQUE INDEX vehicles_environment_operational_code_unique
ON public.vehicles(environment_id, operational_code)
WHERE operational_code IS NOT NULL;

-- Only TEST data is mapped. Production rows, if this migration is later promoted,
-- are deliberately left untouched. Keeping the exact mapping in one private helper
-- also lets pgTAP prove the behavior without relying on remote seed data.
CREATE OR REPLACE FUNCTION app.apply_dori_test_vehicle_identity()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public, app
AS $function$
    UPDATE public.vehicles AS vehicle
    SET manufacturer = 'BYD',
        model = 'Dolphin Mini Plus',
        model_display = 'Dolphin Mini P.',
        unit_number = 1,
        operational_code = 'DMP-001'
    FROM public.environments AS environment
    WHERE environment.id = vehicle.environment_id
      AND environment.code = 'test'
      AND vehicle.internal_number = 'LAB-15C-001';
$function$;

REVOKE ALL ON FUNCTION app.apply_dori_test_vehicle_identity() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.apply_dori_test_vehicle_identity() TO postgres, service_role;
SELECT app.apply_dori_test_vehicle_identity();

CREATE OR REPLACE FUNCTION app.station_profile_display_name(
    p_profile_id uuid,
    p_station_id uuid
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, app
AS $function$
DECLARE
    v_name text;
BEGIN
    IF NOT app.auth_has_role('supervisor', p_station_id) THEN
        RAISE EXCEPTION 'station access denied' USING ERRCODE = '42501';
    END IF;

    SELECT profile.display_name
    INTO STRICT v_name
    FROM public.profiles AS profile
    JOIN public.staff_memberships AS membership
      ON membership.profile_id = profile.id
     AND membership.environment_id = profile.environment_id
     AND membership.station_id = p_station_id
    WHERE profile.id = p_profile_id
      AND membership.role = 'driver'
      AND membership.starts_at <= app.auth_env_now(membership.environment_id)
      AND (membership.ends_at IS NULL OR membership.ends_at > app.auth_env_now(membership.environment_id));

    RETURN v_name;
END;
$function$;

REVOKE ALL ON FUNCTION app.station_profile_display_name(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION app.station_profile_display_name(uuid, uuid) TO authenticated, postgres, service_role;

-- The console read model exposes only the human name already stored in profiles.
-- Its scope remains limited to an authenticated supervisor's active station.
CREATE OR REPLACE VIEW public.console_drivers
WITH (security_invoker = true, security_barrier = true)
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
    m.ends_at,
    app.station_profile_display_name(dp.profile_id, dp.station_id) AS display_name
FROM public.driver_profiles AS dp
JOIN public.staff_memberships AS m
  ON m.id = dp.membership_id
 AND m.environment_id = dp.environment_id
 AND m.station_id = dp.station_id
WHERE m.role = 'driver'
  AND m.starts_at <= app.auth_env_now(m.environment_id)
  AND (m.ends_at IS NULL OR m.ends_at > app.auth_env_now(m.environment_id));

REVOKE ALL ON TABLE public.console_drivers FROM anon, authenticated;
GRANT SELECT ON TABLE public.console_drivers TO authenticated;
GRANT ALL ON TABLE public.console_drivers TO postgres, service_role;

COMMENT ON COLUMN public.vehicles.model IS
'Master catalogue model name; model_display is the short interface label.';
COMMENT ON COLUMN public.vehicles.internal_number IS
'Technical/legacy unit reference retained for compatibility; not the primary operational label.';
COMMENT ON COLUMN public.vehicles.color IS
'Optional visible vehicle color; never part of the permanent operational code.';
