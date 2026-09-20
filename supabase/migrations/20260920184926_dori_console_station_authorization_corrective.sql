-- Correct console authorization without widening station or environment scope.
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
    IF NOT app.auth_can_operate_station(p_station_id) THEN
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
