-- DORI identity contract: explicit administration and console roles.
-- This migration is intentionally not applied in TEST by this checkpoint.

ALTER TABLE public.staff_memberships
    DROP CONSTRAINT staff_memberships_role_check;

ALTER TABLE public.staff_memberships
    ADD CONSTRAINT staff_memberships_role_check CHECK (
        role = ANY (ARRAY[
            'driver', 'supervisor', 'maintenance', 'management', 'direction',
            'recruitment', 'hr', 'lab', 'administration', 'console'
        ])
    );

CREATE OR REPLACE VIEW public.console_identity
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
  AND m.role IN ('supervisor', 'console')
  AND m.starts_at <= app.auth_env_now(m.environment_id)
  AND (m.ends_at IS NULL OR m.ends_at > app.auth_env_now(m.environment_id))
  AND s.status = 'active';

REVOKE ALL ON TABLE public.console_identity FROM anon, authenticated;
GRANT SELECT ON TABLE public.console_identity TO authenticated;
GRANT ALL ON TABLE public.console_identity TO postgres, service_role;

-- Preserve the existing TEST vehicle RPC contract while allowing the explicit
-- station-scoped console role. No direct table write is introduced.
CREATE OR REPLACE FUNCTION public.console_create_test_vehicle(
    p_color text DEFAULT NULL,
    p_note text DEFAULT NULL,
    p_idempotency_key text DEFAULT NULL
)
RETURNS public.vehicles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor uuid := app.auth_profile_id();
    v_environment uuid := app.current_environment_id();
    v_station uuid;
    v_next integer;
    v_vehicle public.vehicles%ROWTYPE;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
    IF v_environment IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.environments WHERE id = v_environment AND code = 'test'
    ) THEN RAISE EXCEPTION 'test_environment_required' USING ERRCODE = '42501'; END IF;

    SELECT m.station_id INTO STRICT v_station
    FROM public.staff_memberships m
    WHERE m.profile_id = v_actor
      AND m.environment_id = v_environment
      AND m.role IN ('supervisor', 'console')
      AND m.starts_at <= app.auth_env_now(v_environment)
      AND (m.ends_at IS NULL OR m.ends_at > app.auth_env_now(v_environment));
    IF NOT app.auth_has_role('supervisor', v_station)
       AND NOT app.auth_has_role('console', v_station) THEN
        RAISE EXCEPTION 'console_station_role_required' USING ERRCODE = '42501';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;

    SELECT coalesce(max(unit_number), 0) + 1 INTO v_next
    FROM public.vehicles WHERE environment_id = v_environment;
    INSERT INTO public.vehicles (
        environment_id, station_id, internal_number, qr_code, legacy_code, model,
        manufacturer, model_display, unit_number, operational_code, color, status
    ) VALUES (
        v_environment, v_station, 'DMP-' || lpad(v_next::text, 3, '0'),
        'DMP-' || lpad(v_next::text, 3, '0'), 'DMP-' || lpad(v_next::text, 3, '0'),
        'Dolphin Mini Plus', 'BYD', 'Dolphin Mini P.', v_next,
        'DMP-' || lpad(v_next::text, 3, '0'), NULLIF(btrim(p_color), ''), 'available'
    ) RETURNING * INTO v_vehicle;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, event_type, entity_type,
        entity_id, metadata, occurred_at
    ) VALUES (
        v_environment, v_actor, v_station, 'vehicle.created', 'vehicle', v_vehicle.id,
        jsonb_build_object('unit_number', v_next, 'operational_code', v_vehicle.operational_code,
                           'note', NULLIF(btrim(coalesce(p_note, '')), '')), now()
    );
    RETURN v_vehicle;
END;
$function$;

REVOKE ALL ON FUNCTION public.console_create_test_vehicle(text, text, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.console_create_test_vehicle(text, text, text)
TO authenticated, service_role;
