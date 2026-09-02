-- 16A: una sola sesion operativa por conductor.
--
-- Supabase Auth permite varias sesiones por usuario. Para la operacion de TurnoEV
-- la regla es mas estricta: el ultimo iPhone que inicia sesion toma el control y
-- cualquier sesion anterior deja de poder abrir o cerrar turnos. Supervisores y
-- consola conservan sus sesiones simultaneas.

CREATE TABLE app.driver_device_sessions (
    profile_id uuid PRIMARY KEY,
    environment_id uuid NOT NULL,
    device_id uuid NOT NULL UNIQUE,
    auth_session_id uuid NOT NULL,
    claimed_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT driver_device_sessions_profile_environment_fkey
        FOREIGN KEY (profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE CASCADE,
    CONSTRAINT driver_device_sessions_device_fkey
        FOREIGN KEY (device_id)
        REFERENCES public.devices(id)
        ON DELETE CASCADE
);

ALTER TABLE app.driver_device_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE app.driver_device_sessions FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE app.driver_device_sessions TO postgres, service_role;

CREATE OR REPLACE FUNCTION app.auth_session_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, app, auth, pg_temp
AS $function$
DECLARE
    v_session_id text;
BEGIN
    v_session_id := NULLIF(auth.jwt() ->> 'session_id', '');
    IF v_session_id IS NULL THEN
        RETURN NULL;
    END IF;

    BEGIN
        RETURN v_session_id::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'invalid_auth_session' USING ERRCODE = '42501';
    END;
END;
$function$;

REVOKE ALL ON FUNCTION app.auth_session_id() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.auth_session_id() TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.claim_driver_device(
    p_install_id text,
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
    v_session_id uuid;
    v_now timestamptz;
    v_membership public.staff_memberships%ROWTYPE;
    v_device public.devices%ROWTYPE;
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

    SELECT m.*
    INTO STRICT v_membership
    FROM public.staff_memberships m
    WHERE m.profile_id = v_profile_id
      AND m.environment_id = v_environment_id
      AND m.role = 'driver'
      AND m.starts_at <= v_now
      AND (m.ends_at IS NULL OR m.ends_at > v_now);

    PERFORM pg_advisory_xact_lock(hashtextextended(v_profile_id::text, 0));

    -- touch_device conserva el inventario comun de dispositivos y valida que el
    -- install_id no pertenezca a otra persona.
    v_device := public.touch_device(
        btrim(p_install_id), v_membership.id, 'ios', p_app_version
    );

    -- La nueva sesion invalida los otros iPhone del conductor. Las filas se
    -- conservan como evidencia y solo se retiran de las lecturas activas.
    UPDATE public.devices
    SET deleted_at = now()
    WHERE profile_id = v_profile_id
      AND environment_id = v_environment_id
      AND id <> v_device.id
      AND platform IN ('ios', 'android')
      AND deleted_at IS NULL;

    INSERT INTO app.driver_device_sessions (
        profile_id, environment_id, device_id, auth_session_id,
        claimed_at, last_seen_at
    ) VALUES (
        v_profile_id, v_environment_id, v_device.id, v_session_id,
        now(), now()
    )
    ON CONFLICT (profile_id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        device_id = EXCLUDED.device_id,
        auth_session_id = EXCLUDED.auth_session_id,
        claimed_at = now(),
        last_seen_at = now();

    RETURN v_device;
EXCEPTION
    WHEN no_data_found THEN
        RAISE EXCEPTION 'active_driver_membership_required' USING ERRCODE = '42501';
    WHEN too_many_rows THEN
        RAISE EXCEPTION 'multiple_active_driver_memberships' USING ERRCODE = '23514';
END;
$function$;

CREATE OR REPLACE FUNCTION app.assert_driver_device_session(p_install_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, app, auth, pg_temp
AS $function$
DECLARE
    v_profile_id uuid;
    v_environment_id uuid;
    v_session_id uuid;
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

    IF NOT EXISTS (
        SELECT 1
        FROM app.driver_device_sessions lease
        JOIN public.devices d ON d.id = lease.device_id
        WHERE lease.profile_id = v_profile_id
          AND lease.environment_id = v_environment_id
          AND lease.auth_session_id = v_session_id
          AND d.profile_id = v_profile_id
          AND d.environment_id = v_environment_id
          AND d.install_id = btrim(p_install_id)
          AND d.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'driver_session_replaced' USING ERRCODE = '42501';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION app.assert_driver_device_session(text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.assert_driver_device_session(text)
TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.heartbeat_driver_device(p_install_id text)
RETURNS public.devices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, app, auth, pg_temp
AS $function$
DECLARE
    v_profile_id uuid;
    v_session_id uuid;
    v_device public.devices%ROWTYPE;
BEGIN
    PERFORM app.assert_driver_device_session(p_install_id);
    v_profile_id := app.auth_profile_id();
    v_session_id := app.auth_session_id();

    UPDATE public.devices d
    SET last_seen_at = now()
    FROM app.driver_device_sessions lease
    WHERE lease.profile_id = v_profile_id
      AND lease.auth_session_id = v_session_id
      AND lease.device_id = d.id
      AND d.install_id = btrim(p_install_id)
      AND d.deleted_at IS NULL
    RETURNING d.* INTO STRICT v_device;

    UPDATE app.driver_device_sessions
    SET last_seen_at = now()
    WHERE profile_id = v_profile_id
      AND auth_session_id = v_session_id;

    RETURN v_device;
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_shift_v2(
    p_assignment_id uuid,
    p_odometer_km bigint,
    p_battery_pct integer,
    p_idempotency_key text,
    p_install_id text
)
RETURNS public.shifts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, app, auth, pg_temp
AS $function$
BEGIN
    PERFORM app.assert_driver_device_session(p_install_id);
    RETURN public.start_shift(
        p_assignment_id, p_odometer_km, p_battery_pct, p_idempotency_key
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.finish_shift_v2(
    p_shift_id uuid,
    p_expected_revision bigint,
    p_odometer_km bigint,
    p_battery_pct integer,
    p_idempotency_key text,
    p_install_id text
)
RETURNS public.shifts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, app, auth, pg_temp
AS $function$
BEGIN
    PERFORM app.assert_driver_device_session(p_install_id);
    RETURN public.finish_shift(
        p_shift_id, p_expected_revision, p_odometer_km,
        p_battery_pct, p_idempotency_key
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_driver_device(text, text)
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.heartbeat_driver_device(text)
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.start_shift_v2(uuid, bigint, integer, text, text)
FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finish_shift_v2(uuid, bigint, bigint, integer, text, text)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.claim_driver_device(text, text)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.heartbeat_driver_device(text)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.start_shift_v2(uuid, bigint, integer, text, text)
TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finish_shift_v2(uuid, bigint, bigint, integer, text, text)
TO authenticated, service_role;

-- Las rutas 15D anteriores quedan disponibles solo para tareas administrativas.
-- El cliente autenticado debe presentar su sesion y su install_id mediante v2.
REVOKE EXECUTE ON FUNCTION public.start_shift(uuid, bigint, integer, text)
FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.finish_shift(uuid, bigint, bigint, integer, text)
FROM authenticated;

COMMENT ON TABLE app.driver_device_sessions IS
    'Arrendamiento interno de la unica sesion operativa permitida por conductor.';
COMMENT ON FUNCTION public.claim_driver_device(text, text) IS
    'Entrega el control operativo al iPhone de la sesion Auth actual e invalida los anteriores.';
COMMENT ON FUNCTION public.heartbeat_driver_device(text) IS
    'Confirma que este iPhone conserva el control operativo del conductor.';
COMMENT ON FUNCTION public.start_shift_v2(uuid, bigint, integer, text, text) IS
    'Abre turno solo desde la sesion y el dispositivo activos del conductor.';
COMMENT ON FUNCTION public.finish_shift_v2(uuid, bigint, bigint, integer, text, text) IS
    'Cierra turno solo desde la sesion y el dispositivo activos del conductor.';
