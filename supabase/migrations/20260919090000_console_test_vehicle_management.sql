-- DORI TEST: creación controlada de unidades desde la Consola.
-- No concede escritura directa sobre public.vehicles; toda mutación pasa por RPC.

CREATE OR REPLACE FUNCTION public.console_create_test_vehicle(
    p_color text DEFAULT NULL,
    p_note text DEFAULT NULL,
    p_idempotency_key text DEFAULT NULL
)
RETURNS public.vehicles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor uuid := app.auth_profile_id();
    v_environment uuid := app.current_environment_id();
    v_station uuid;
    v_next integer;
    v_vehicle public.vehicles%ROWTYPE;
    v_command uuid;
    v_note text := NULLIF(btrim(coalesce(p_note, '')), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
    IF v_environment IS NULL OR NOT EXISTS (SELECT 1 FROM public.environments WHERE id = v_environment AND code = 'test') THEN
        RAISE EXCEPTION 'test_environment_required' USING ERRCODE = '42501';
    END IF;
    SELECT m.station_id INTO STRICT v_station
    FROM public.staff_memberships m
    WHERE m.profile_id = v_actor AND m.environment_id = v_environment
      AND m.role = 'supervisor'
      AND m.starts_at <= app.auth_env_now(v_environment)
      AND (m.ends_at IS NULL OR m.ends_at > app.auth_env_now(v_environment));
    IF NOT app.auth_has_role('supervisor', v_station) THEN RAISE EXCEPTION 'supervisor_role_required' USING ERRCODE = '42501'; END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023'; END IF;

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

    INSERT INTO public.audit_log (environment_id, actor_profile_id, station_id, event_type, entity_type, entity_id, metadata, occurred_at)
    VALUES (v_environment, v_actor, v_station, 'vehicle.created', 'vehicle', v_vehicle.id,
        jsonb_build_object('unit_number', v_next, 'operational_code', v_vehicle.operational_code, 'note', v_note), now());
    RETURN v_vehicle;
END;
$function$;

REVOKE ALL ON FUNCTION public.console_create_test_vehicle(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.console_create_test_vehicle(text, text, text) TO authenticated;

COMMENT ON FUNCTION public.console_create_test_vehicle(text, text, text) IS
'Creates the next available BYD Dolphin Mini P. unit only in TEST for the station supervisor; direct table writes remain denied.';
