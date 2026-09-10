-- DORI final identity naming preparation.
--
-- This migration deliberately does not update auth.users.email and does not create Auth
-- users.  Supabase Auth keeps authenticating the current TEST accounts by their existing
-- email while public.profiles.auth_user_id remains the immutable business link to the
-- stable auth.users.id.  The records below only reserve the future @dori.mx names.

CREATE TABLE app.station_identity_codes (
    code text PRIMARY KEY,
    display_name text NOT NULL,
    status text NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT station_identity_codes_code_shape
        CHECK (code = lower(btrim(code)) AND code ~ '^[a-z][a-z0-9]{1,11}$'),
    CONSTRAINT station_identity_codes_name_not_blank
        CHECK (btrim(display_name) <> ''),
    CONSTRAINT station_identity_codes_status_check
        CHECK (status IN ('active', 'inactive'))
);
INSERT INTO app.station_identity_codes(code, display_name)
VALUES
    ('pue', 'Puebla'),
    ('cdmx', 'Ciudad de México'),
    ('qro', 'Querétaro'),
    ('mty', 'Monterrey'),
    ('gda', 'Guadalajara'),
    ('cue', 'Cuernavaca');
ALTER TABLE public.stations
    ADD COLUMN identity_code text,
    ADD CONSTRAINT stations_identity_code_fkey
        FOREIGN KEY (identity_code)
        REFERENCES app.station_identity_codes(code)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;
-- The existing Puebla TEST station already has a stable PUE prefix.  No other station is
-- guessed: a future station must explicitly choose one catalogued code.
UPDATE public.stations
SET identity_code = 'pue'
WHERE identity_code IS NULL
  AND (
      lower(code) ~ '^pue([_-]|$)'
      OR lower(name) LIKE 'puebla%'
  );
ALTER TABLE public.profiles
    ADD COLUMN account_kind text NOT NULL DEFAULT 'person',
    ADD COLUMN responsible_profile_id uuid,
    ADD CONSTRAINT profiles_account_kind_check
        CHECK (account_kind IN ('person', 'functional')),
    ADD CONSTRAINT profiles_responsible_not_self
        CHECK (responsible_profile_id IS NULL OR responsible_profile_id <> id),
    ADD CONSTRAINT profiles_responsible_environment_fkey
        FOREIGN KEY (responsible_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT;
CREATE OR REPLACE FUNCTION app.guard_profile_auth_user_id_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $$
BEGIN
    -- Hiring may link a previously unlinked profile exactly once.  Once linked, changing
    -- or clearing the Auth user would make the email a de-facto business key.
    IF OLD.auth_user_id IS NOT NULL
       AND NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id THEN
        RAISE EXCEPTION 'profile_auth_user_id_immutable'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER profiles_auth_user_id_immutable
BEFORE UPDATE OF auth_user_id ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION app.guard_profile_auth_user_id_immutable();
CREATE TABLE app.identity_aliases (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    profile_id uuid NOT NULL,
    station_id uuid,
    identity_type text NOT NULL,
    role text,
    base_local_part text NOT NULL,
    collision_sequence integer NOT NULL DEFAULT 1,
    local_part text NOT NULL,
    domain text NOT NULL DEFAULT 'dori.mx',
    future_email text NOT NULL,
    status text NOT NULL DEFAULT 'reserved',
    created_at timestamptz NOT NULL DEFAULT now(),
    applied_at timestamptz,

    CONSTRAINT identity_aliases_profile_environment_fkey
        FOREIGN KEY (profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT identity_aliases_station_environment_fkey
        FOREIGN KEY (station_id, environment_id)
        REFERENCES public.stations(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT identity_aliases_type_check
        CHECK (identity_type IN ('driver', 'station_role')),
    CONSTRAINT identity_aliases_role_check
        CHECK (role IS NULL OR role IN ('supervisor', 'recruitment', 'management', 'direction', 'hr')),
    CONSTRAINT identity_aliases_shape_check
        CHECK (
            (identity_type = 'driver' AND station_id IS NULL AND role IS NULL)
            OR
            (identity_type = 'station_role' AND station_id IS NOT NULL AND role IS NOT NULL)
        ),
    CONSTRAINT identity_aliases_base_shape
        CHECK (base_local_part = lower(btrim(base_local_part)) AND base_local_part ~ '^[a-z0-9]+\.[a-z0-9]+$'),
    CONSTRAINT identity_aliases_sequence_positive
        CHECK (collision_sequence >= 1),
    CONSTRAINT identity_aliases_local_part_shape
        CHECK (local_part = lower(btrim(local_part)) AND local_part ~ '^[a-z0-9]+(?:\.[a-z0-9]+)+[0-9]*$'),
    CONSTRAINT identity_aliases_domain_check
        CHECK (domain = 'dori.mx'),
    CONSTRAINT identity_aliases_email_consistent
        CHECK (future_email = local_part || '@' || domain),
    CONSTRAINT identity_aliases_status_check
        CHECK (status IN ('reserved', 'applied', 'released')),
    CONSTRAINT identity_aliases_applied_at_check
        CHECK ((status = 'applied') = (applied_at IS NOT NULL))
);
CREATE UNIQUE INDEX identity_aliases_active_email_unique
    ON app.identity_aliases(future_email)
    WHERE status <> 'released';
CREATE UNIQUE INDEX identity_aliases_active_profile_unique
    ON app.identity_aliases(profile_id)
    WHERE status <> 'released';
CREATE INDEX identity_aliases_station_role_idx
    ON app.identity_aliases(station_id, role)
    WHERE status <> 'released';
CREATE OR REPLACE FUNCTION app.normalize_dori_identity_component(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path TO 'pg_catalog', 'app', 'pg_temp'
AS $$
    SELECT regexp_replace(
        translate(
            lower(btrim(p_value)),
            'áàäâãéèëêíìïîóòöôõúùüûñç',
            'aaaaaeeeeiiiiooooouuuunc'
        ),
        '[^a-z0-9]+',
        '',
        'g'
    );
$$;
CREATE OR REPLACE FUNCTION app.dori_driver_identity_base(
    p_first_name text,
    p_first_surname text
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path TO 'pg_catalog', 'app', 'pg_temp'
AS $$
DECLARE
    v_name text := app.normalize_dori_identity_component(p_first_name);
    v_surname text := app.normalize_dori_identity_component(p_first_surname);
BEGIN
    IF v_name = '' OR v_surname = '' THEN
        RAISE EXCEPTION 'dori_identity_name_required'
            USING ERRCODE = '22023';
    END IF;
    RETURN v_name || '.' || v_surname;
END;
$$;
CREATE OR REPLACE FUNCTION app.dori_station_role_local_part(
    p_role text,
    p_station_code text
)
RETURNS text
LANGUAGE plpgsql
STABLE
STRICT
SET search_path TO 'pg_catalog', 'app', 'pg_temp'
AS $$
DECLARE
    v_prefix text;
    v_code text := lower(btrim(p_station_code));
BEGIN
    v_prefix := CASE p_role
        WHEN 'supervisor' THEN 'supervision'
        WHEN 'recruitment' THEN 'reclutamiento'
        WHEN 'management' THEN 'gerencia'
        WHEN 'direction' THEN 'direccion'
        WHEN 'hr' THEN 'rh'
        ELSE NULL
    END;

    IF v_prefix IS NULL THEN
        RAISE EXCEPTION 'dori_station_identity_role_invalid'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM app.station_identity_codes catalog
        WHERE catalog.code = v_code
          AND catalog.status = 'active'
    ) THEN
        RAISE EXCEPTION 'dori_station_identity_code_invalid'
            USING ERRCODE = '22023';
    END IF;

    RETURN v_prefix || '.' || v_code;
END;
$$;
CREATE OR REPLACE FUNCTION app.next_dori_driver_email(
    p_first_name text,
    p_first_surname text
)
RETURNS text
LANGUAGE plpgsql
STABLE
STRICT
SET search_path TO 'pg_catalog', 'app', 'pg_temp'
AS $$
DECLARE
    v_base text := app.dori_driver_identity_base(p_first_name, p_first_surname);
    v_sequence integer := 1;
    v_local_part text;
    v_email text;
BEGIN
    LOOP
        v_local_part := v_base || CASE WHEN v_sequence = 1 THEN '' ELSE v_sequence::text END;
        v_email := v_local_part || '@dori.mx';
        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM app.identity_aliases alias
            WHERE alias.future_email = v_email
              AND alias.status <> 'released'
        );
        v_sequence := v_sequence + 1;
    END LOOP;

    RETURN v_email;
END;
$$;
CREATE OR REPLACE FUNCTION app.reserve_dori_driver_identity(
    p_profile_id uuid,
    p_first_name text,
    p_first_surname text
)
RETURNS app.identity_aliases
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $$
DECLARE
    v_profile public.profiles%ROWTYPE;
    v_existing app.identity_aliases%ROWTYPE;
    v_alias app.identity_aliases%ROWTYPE;
    v_base text := app.dori_driver_identity_base(p_first_name, p_first_surname);
    v_sequence integer := 1;
    v_local_part text;
BEGIN
    SELECT * INTO STRICT v_profile
    FROM public.profiles profile
    WHERE profile.id = p_profile_id
    FOR UPDATE;

    IF v_profile.account_kind <> 'person' THEN
        RAISE EXCEPTION 'dori_driver_identity_requires_person_profile'
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_existing
    FROM app.identity_aliases alias
    WHERE alias.profile_id = p_profile_id
      AND alias.status <> 'released';

    IF FOUND THEN
        IF v_existing.identity_type <> 'driver' THEN
            RAISE EXCEPTION 'dori_identity_profile_already_reserved'
                USING ERRCODE = '23505';
        END IF;
        RETURN v_existing;
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_base || '@dori.mx', 0));

    LOOP
        v_local_part := v_base || CASE WHEN v_sequence = 1 THEN '' ELSE v_sequence::text END;
        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM app.identity_aliases alias
            WHERE alias.future_email = v_local_part || '@dori.mx'
              AND alias.status <> 'released'
        );
        v_sequence := v_sequence + 1;
    END LOOP;

    INSERT INTO app.identity_aliases(
        environment_id, profile_id, identity_type, base_local_part,
        collision_sequence, local_part, future_email
    ) VALUES (
        v_profile.environment_id, v_profile.id, 'driver', v_base,
        v_sequence, v_local_part, v_local_part || '@dori.mx'
    )
    RETURNING * INTO v_alias;

    RETURN v_alias;
END;
$$;
CREATE OR REPLACE FUNCTION app.reserve_dori_station_identity(
    p_profile_id uuid,
    p_station_id uuid,
    p_role text
)
RETURNS app.identity_aliases
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $$
DECLARE
    v_profile public.profiles%ROWTYPE;
    v_station public.stations%ROWTYPE;
    v_existing app.identity_aliases%ROWTYPE;
    v_alias app.identity_aliases%ROWTYPE;
    v_local_part text;
BEGIN
    SELECT * INTO STRICT v_profile
    FROM public.profiles profile
    WHERE profile.id = p_profile_id
    FOR UPDATE;

    SELECT * INTO STRICT v_station
    FROM public.stations station
    WHERE station.id = p_station_id;

    IF v_profile.account_kind <> 'functional' THEN
        RAISE EXCEPTION 'dori_station_identity_requires_functional_profile'
            USING ERRCODE = '22023';
    END IF;
    IF v_profile.responsible_profile_id IS NULL THEN
        RAISE EXCEPTION 'dori_station_identity_responsible_person_required'
            USING ERRCODE = '22023';
    END IF;
    IF v_profile.environment_id <> v_station.environment_id THEN
        RAISE EXCEPTION 'dori_station_identity_environment_mismatch'
            USING ERRCODE = '23514';
    END IF;
    IF v_station.identity_code IS NULL THEN
        RAISE EXCEPTION 'dori_station_identity_code_required'
            USING ERRCODE = '22023';
    END IF;

    v_local_part := app.dori_station_role_local_part(p_role, v_station.identity_code);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_local_part || '@dori.mx', 0));

    SELECT * INTO v_existing
    FROM app.identity_aliases alias
    WHERE alias.profile_id = p_profile_id
      AND alias.status <> 'released';

    IF FOUND THEN
        IF v_existing.identity_type <> 'station_role'
           OR v_existing.station_id <> p_station_id
           OR v_existing.role <> p_role THEN
            RAISE EXCEPTION 'dori_identity_profile_already_reserved'
                USING ERRCODE = '23505';
        END IF;
        RETURN v_existing;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM app.identity_aliases alias
        WHERE alias.future_email = v_local_part || '@dori.mx'
          AND alias.status <> 'released'
    ) THEN
        RAISE EXCEPTION 'dori_station_identity_already_reserved'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO app.identity_aliases(
        environment_id, profile_id, station_id, identity_type, role,
        base_local_part, collision_sequence, local_part, future_email
    ) VALUES (
        v_profile.environment_id, v_profile.id, v_station.id, 'station_role', p_role,
        v_local_part, 1, v_local_part, v_local_part || '@dori.mx'
    )
    RETURNING * INTO v_alias;

    RETURN v_alias;
END;
$$;
CREATE OR REPLACE FUNCTION app.audit_responsible_profile_id(p_actor_profile_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $$
    SELECT CASE profile.account_kind
        WHEN 'functional' THEN profile.responsible_profile_id
        ELSE profile.id
    END
    FROM public.profiles profile
    WHERE profile.id = p_actor_profile_id;
$$;
ALTER TABLE public.audit_log
    ADD COLUMN responsible_profile_id uuid,
    ADD CONSTRAINT audit_log_responsible_profile_id_fkey
        FOREIGN KEY (responsible_profile_id)
        REFERENCES public.profiles(id)
        ON DELETE RESTRICT;
-- Existing audit rows are append-only and remain byte-for-byte untouched.  Responsibility
-- is captured at INSERT time for every event created after this migration; attempting to
-- rewrite history would correctly trip audit_log_is_append_only.

CREATE INDEX audit_log_responsible_profile_idx
    ON public.audit_log(responsible_profile_id);
CREATE OR REPLACE FUNCTION app.capture_audit_responsible_profile()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $$
BEGIN
    IF NEW.actor_profile_id IS NOT NULL AND NEW.responsible_profile_id IS NULL THEN
        NEW.responsible_profile_id := app.audit_responsible_profile_id(NEW.actor_profile_id);
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER audit_log_capture_responsible_profile
BEFORE INSERT ON public.audit_log
FOR EACH ROW
EXECUTE FUNCTION app.capture_audit_responsible_profile();
ALTER TABLE app.station_identity_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.identity_aliases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE app.station_identity_codes FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE app.identity_aliases FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE app.station_identity_codes TO postgres, service_role;
GRANT ALL ON TABLE app.identity_aliases TO postgres, service_role;
REVOKE ALL ON FUNCTION app.guard_profile_auth_user_id_immutable() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.normalize_dori_identity_component(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.dori_driver_identity_base(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.dori_station_role_local_part(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.next_dori_driver_email(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.reserve_dori_driver_identity(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.reserve_dori_station_identity(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.audit_responsible_profile_id(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.capture_audit_responsible_profile() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.normalize_dori_identity_component(text) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION app.dori_driver_identity_base(text, text) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION app.dori_station_role_local_part(text, text) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION app.next_dori_driver_email(text, text) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION app.reserve_dori_driver_identity(uuid, text, text) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION app.reserve_dori_station_identity(uuid, uuid, text) TO postgres, service_role;
COMMENT ON TABLE app.identity_aliases IS
    'Reserved future DORI login names. Reservation never changes auth.users.email or profiles.auth_user_id.';
COMMENT ON COLUMN public.profiles.auth_user_id IS
    'Immutable link to auth.users.id. Email is a replaceable sign-in identity, never a business key.';
COMMENT ON COLUMN public.audit_log.responsible_profile_id IS
    'Human responsible at event creation time; copied into append-only audit history for functional accounts.';
