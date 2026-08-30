SET local check_function_bodies = off;

REVOKE ALL ON FUNCTION "public"."test_clock_touch"() FROM "anon";

REVOKE ALL ON FUNCTION "public"."test_clock_touch"() FROM "authenticated";

REVOKE ALL ON FUNCTION "public"."update_test_clock"(uuid, timestamp WITH time zone, timestamp WITH time zone, double precision, boolean, bigint) FROM "authenticated";

CREATE SCHEMA "app";

CREATE EXTENSION "btree_gist" SCHEMA "extensions";

CREATE TABLE "app"."env_clock" (
  "environment_id"    uuid                     NOT NULL,
  "is_simulated"      boolean                  NOT NULL DEFAULT false,
  "anchor_logical_at" timestamp with time zone NOT NULL,
  "anchor_real_at"    timestamp with time zone NOT NULL,
  "speed"             double precision         NOT NULL DEFAULT 1,
  "is_paused"         boolean                  NOT NULL DEFAULT false,
  CONSTRAINT "env_clock_pkey" PRIMARY KEY (environment_id),
  CONSTRAINT "env_clock_speed_positive" CHECK ((speed > (0)::double precision))
);

ALTER TABLE "app"."env_clock"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."audit_log" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "environment_id"   uuid                     NOT NULL,
  "actor_profile_id" uuid,
  "station_id"       uuid,
  "command_id"       uuid,
  "event_type"       text                     NOT NULL,
  "recorded_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "entity_type"      text,
  "entity_id"        uuid,
  "metadata"         jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT "audit_log_entity_type_not_blank" CHECK (((entity_type IS NULL) OR (btrim(entity_type) <> ''::text))),
  CONSTRAINT "audit_log_event_type_not_blank" CHECK ((btrim(event_type) <> ''::text)),
  CONSTRAINT "audit_log_metadata_object" CHECK ((jsonb_typeof(metadata) = 'object'::text)),
  CONSTRAINT "audit_log_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."audit_log"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."command_log" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "environment_id"   uuid                     NOT NULL,
  "actor_profile_id" uuid,
  "command_name"     text                     NOT NULL,
  "idempotency_key"  text                     NOT NULL,
  "status"           text                     NOT NULL DEFAULT 'accepted'::text,
  "recorded_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "request_payload"  jsonb,
  "result_payload"   jsonb,
  CONSTRAINT "command_log_command_name_not_blank" CHECK ((btrim(command_name) <> ''::text)),
  CONSTRAINT "command_log_idempotency_key_not_blank" CHECK ((btrim(idempotency_key) <> ''::text)),
  CONSTRAINT "command_log_pkey" PRIMARY KEY (id),
  CONSTRAINT "command_log_status_check" CHECK ((status = ANY (ARRAY['accepted'::text, 'completed'::text, 'rejected'::text, 'conflict'::text])))
);

ALTER TABLE "public"."command_log"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."environments" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "code"       text                     NOT NULL,
  "name"       text                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "environments_code_check" CHECK ((code = ANY (ARRAY['test'::text, 'prod'::text]))),
  CONSTRAINT "environments_code_key" UNIQUE (code),
  CONSTRAINT "environments_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."environments"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."profiles" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "auth_user_id"    uuid,
  "employee_number" text                     NOT NULL,
  "display_name"    text                     NOT NULL,
  "status"          text                     NOT NULL DEFAULT 'active'::text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "profiles_auth_user_id_unique" UNIQUE (auth_user_id),
  CONSTRAINT "profiles_display_name_not_blank" CHECK ((btrim(display_name) <> ''::text)),
  CONSTRAINT "profiles_employee_number_not_blank" CHECK ((btrim(employee_number) <> ''::text)),
  CONSTRAINT "profiles_employee_number_unique" UNIQUE (employee_number),
  CONSTRAINT "profiles_pkey" PRIMARY KEY (id),
  CONSTRAINT "profiles_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'inactive'::text])))
);

ALTER TABLE "public"."profiles"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."staff_memberships" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "profile_id"  uuid                     NOT NULL,
  "station_id"  uuid                     NOT NULL,
  "role"        text                     NOT NULL,
  "ends_at"     timestamp with time zone,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "shift_group" text,
  "shift_slot"  text,
  CONSTRAINT "staff_memberships_pkey" PRIMARY KEY (id),
  CONSTRAINT "staff_memberships_role_check"
    CHECK ((role = ANY (ARRAY['driver'::text, 'supervisor'::text, 'maintenance'::text, 'management'::text, 'direction'::text, 'recruitment'::text, 'hr'::text, 'lab'::text]))),
  CONSTRAINT "staff_memberships_shift_group_check" CHECK (((shift_group IS NULL) OR (shift_group = ANY (ARRAY['weekday'::text, 'weekend'::text])))),
  CONSTRAINT "staff_memberships_shift_slot_check" CHECK (((shift_slot IS NULL) OR (shift_slot = ANY (ARRAY['morning'::text, 'evening'::text]))))
);

ALTER TABLE "public"."staff_memberships"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."stations" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "environment_id" uuid                     NOT NULL,
  "code"           text                     NOT NULL,
  "name"           text                     NOT NULL,
  "status"         text                     NOT NULL DEFAULT 'active'::text,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "stations_code_not_blank" CHECK ((btrim(code) <> ''::text)),
  CONSTRAINT "stations_name_not_blank" CHECK ((btrim(name) <> ''::text)),
  CONSTRAINT "stations_pkey" PRIMARY KEY (id),
  CONSTRAINT "stations_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])))
);

ALTER TABLE "public"."stations"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION app.auth_has_role (
  p_role       text,
  p_station_id uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
  AS $function$
declare
    v_profile_id uuid;
    v_now timestamptz;
begin
    v_profile_id := app.auth_profile_id();

    if v_profile_id is null then
        return false;
    end if;

    v_now := app.env_now();

    return exists (
        select 1
          from public.staff_memberships m
          join public.stations s
            on s.id = m.station_id
         where m.profile_id = v_profile_id
           and m.role = p_role
           and m.starts_at <= v_now
           and (m.ends_at is null or m.ends_at > v_now)
           and s.environment_id = app.current_environment_id()
           and s.status = 'active'
           and (
                p_station_id is null
                or m.station_id = p_station_id
           )
    );
end;
$function$;

CREATE OR REPLACE FUNCTION app.auth_profile_id()
  RETURNS uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
  AS $function$
declare
    v_auth_user_id uuid;
    v_profile_id uuid;
begin
    v_auth_user_id := auth.uid();

    if v_auth_user_id is null then
        return null;
    end if;

    select p.id
      into v_profile_id
      from public.profiles p
     where p.auth_user_id = v_auth_user_id
       and p.status = 'active';

    return v_profile_id;
end;
$function$;

CREATE OR REPLACE FUNCTION app.auth_station_ids()
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
  AS $function$
declare
    v_profile_id uuid;
    v_now timestamptz;
begin
    v_profile_id := app.auth_profile_id();

    if v_profile_id is null then
        return;
    end if;

    v_now := app.env_now();

    return query
    select distinct m.station_id
      from public.staff_memberships m
      join public.stations s
        on s.id = m.station_id
     where m.profile_id = v_profile_id
       and m.starts_at <= v_now
       and (m.ends_at is null or m.ends_at > v_now)
       and s.environment_id = app.current_environment_id()
       and s.status = 'active';
end;
$function$;

CREATE OR REPLACE FUNCTION app.current_environment_id()
  RETURNS uuid
  LANGUAGE plpgsql
  STABLE
  SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
  AS $function$
declare
    v_count          bigint;
    v_environment_id uuid;
begin
    select count(*)
      into v_count
      from public.environments;

    if v_count = 0 then
        raise exception 'environment_missing'
            using errcode = 'P0002';
    end if;

    if v_count <> 1 then
        raise exception 'environment_ambiguous'
            using errcode = 'P0003';
    end if;

    select id
      into strict v_environment_id
      from public.environments;

    return v_environment_id;
end;
$function$;

CREATE OR REPLACE FUNCTION app.env_now (
  p_environment_id uuid DEFAULT NULL::uuid
)
  RETURNS timestamp WITH time zone
  LANGUAGE plpgsql
  STABLE
  SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
  AS $function$
declare
    v_environment_id uuid;
    v_code           text;
    v_count          bigint;
    v_clock          app.env_clock%rowtype;
begin
    v_environment_id :=
        coalesce(
            p_environment_id,
            app.current_environment_id()
        );

    select e.code
      into v_code
      from public.environments e
     where e.id = v_environment_id;

    if v_code is null then
        raise exception 'environment_not_found'
            using errcode = 'P0002';
    end if;

    select count(*)
      into v_count
      from app.env_clock c
     where c.environment_id = v_environment_id;

    if v_count = 0 then
        raise exception 'env_clock_missing'
            using errcode = 'P0002';
    end if;

    if v_count <> 1 then
        raise exception 'env_clock_ambiguous'
            using errcode = 'P0003';
    end if;

    select *
      into strict v_clock
      from app.env_clock c
     where c.environment_id = v_environment_id;

    if v_code = 'prod' and v_clock.is_simulated then
        raise exception 'env_simulation_forbidden_in_prod'
            using errcode = '42501';
    end if;

    if not v_clock.is_simulated then
        return now();
    end if;

    if v_clock.is_paused then
        return v_clock.anchor_logical_at;
    end if;

    return
        v_clock.anchor_logical_at
        + ((now() - v_clock.anchor_real_at) * v_clock.speed);
end;
$function$;

CREATE OR REPLACE FUNCTION app.guard_audit_log_append_only()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
  AS $function$
begin
    raise exception 'audit_log_is_append_only'
        using errcode = '42501';
end;
$function$;

CREATE OR REPLACE FUNCTION app.guard_env_clock()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
  AS $function$
declare
    v_code text;
begin
    select e.code
      into v_code
      from public.environments e
     where e.id = new.environment_id;

    if v_code is null then
        raise exception 'env_clock_environment_missing'
            using errcode = '23503';
    end if;

    if v_code = 'prod' and new.is_simulated then
        raise exception 'env_simulation_forbidden_in_prod'
            using errcode = '42501';
    end if;

    return new;
end;
$function$;

CREATE OR REPLACE FUNCTION app.sync_test_clock_to_env_clock()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
  AS $function$
declare
    v_code text;
begin
    select e.code
      into v_code
      from public.environments e
     where e.id = new.environment_id;

    if v_code is null then
        raise exception 'bridge_environment_missing'
            using errcode = 'P0002';
    end if;

    if v_code <> 'test' then
        raise exception 'bridge_environment_not_test'
            using errcode = '42501';
    end if;

    insert into app.env_clock (
        environment_id,
        is_simulated,
        anchor_logical_at,
        anchor_real_at,
        speed,
        is_paused
    )
    values (
        new.environment_id,
        true,
        new.anchor_simulated_at,
        new.anchor_real_at,
        new.speed,
        new.is_paused
    )
    on conflict (environment_id)
    do update set
        is_simulated      = true,
        anchor_logical_at = excluded.anchor_logical_at,
        anchor_real_at    = excluded.anchor_real_at,
        speed              = excluded.speed,
        is_paused          = excluded.is_paused;

    return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.test_clock_touch()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public', 'pg_temp'
  AS $function$
begin
    new.updated_at := now();
    return new;
end;
$function$;

ALTER TABLE "public"."audit_log"
  ADD CONSTRAINT "audit_log_command_id_fkey" FOREIGN KEY (command_id) REFERENCES public.command_log(id) ON DELETE RESTRICT;

ALTER TABLE "app"."env_clock"
  ADD CONSTRAINT "env_clock_environment_id_fkey" FOREIGN KEY (environment_id) REFERENCES public.environments(id) ON DELETE RESTRICT;

ALTER TABLE "public"."audit_log"
  ADD CONSTRAINT "audit_log_environment_id_fkey" FOREIGN KEY (environment_id) REFERENCES public.environments(id) ON DELETE RESTRICT;

ALTER TABLE "public"."command_log"
  ADD CONSTRAINT "command_log_environment_id_fkey" FOREIGN KEY (environment_id) REFERENCES public.environments(id) ON DELETE RESTRICT;

ALTER TABLE "public"."profiles"
  ADD CONSTRAINT "profiles_auth_user_fk" FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."audit_log"
  ADD CONSTRAINT "audit_log_actor_profile_id_fkey" FOREIGN KEY (actor_profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "public"."command_log"
  ADD CONSTRAINT "command_log_actor_profile_id_fkey" FOREIGN KEY (actor_profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "public"."staff_memberships"
  ADD CONSTRAINT "staff_memberships_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "public"."stations"
  ADD CONSTRAINT "stations_environment_id_fkey" FOREIGN KEY (environment_id) REFERENCES public.environments(id) ON DELETE RESTRICT;

ALTER TABLE "public"."audit_log"
  ADD CONSTRAINT "audit_log_station_id_fkey" FOREIGN KEY (station_id) REFERENCES public.stations(id) ON DELETE RESTRICT;

ALTER TABLE "public"."staff_memberships"
  ADD CONSTRAINT "staff_memberships_station_id_fkey" FOREIGN KEY (station_id) REFERENCES public.stations(id) ON DELETE RESTRICT;

CREATE INDEX audit_log_actor_idx ON public.audit_log USING btree (actor_profile_id);

CREATE INDEX audit_log_command_idx ON public.audit_log USING btree (command_id);

CREATE INDEX audit_log_entity_idx ON public.audit_log USING btree (entity_type, entity_id);

CREATE INDEX audit_log_environment_recorded_idx ON public.audit_log USING btree (environment_id, recorded_at);

CREATE INDEX audit_log_station_idx ON public.audit_log USING btree (station_id);

CREATE INDEX command_log_actor_idx ON public.command_log USING btree (actor_profile_id);

CREATE INDEX command_log_command_idx ON public.command_log USING btree (command_name);

CREATE UNIQUE INDEX command_log_idempotency_unique ON public.command_log USING btree (environment_id, idempotency_key);

CREATE INDEX command_log_recorded_at_idx ON public.command_log USING btree (recorded_at);

CREATE INDEX staff_memberships_profile_idx ON public.staff_memberships USING btree (profile_id);

CREATE INDEX staff_memberships_profile_role_idx ON public.staff_memberships USING btree (profile_id, ROLE);

CREATE INDEX staff_memberships_station_idx ON public.staff_memberships USING btree (station_id);

CREATE INDEX staff_memberships_station_role_idx ON public.staff_memberships USING btree (station_id, ROLE);

CREATE UNIQUE INDEX stations_environment_code_unique ON public.stations USING btree (environment_id, code);

CREATE INDEX stations_environment_idx ON public.stations USING btree (environment_id);

CREATE TRIGGER env_clock_guard
  BEFORE INSERT OR UPDATE ON app.env_clock
  FOR EACH ROW
  EXECUTE FUNCTION app.guard_env_clock();

CREATE TRIGGER audit_log_block_delete
  BEFORE DELETE ON public.audit_log
  FOR EACH ROW
  EXECUTE FUNCTION app.guard_audit_log_append_only();

CREATE TRIGGER audit_log_block_update
  BEFORE UPDATE ON public.audit_log
  FOR EACH ROW
  EXECUTE FUNCTION app.guard_audit_log_append_only();

CREATE TRIGGER sync_test_clock_to_env_clock
  AFTER INSERT OR UPDATE OF anchor_simulated_at, anchor_real_at, speed, is_paused, revision ON public.test_clock
  FOR EACH ROW
  EXECUTE FUNCTION app.sync_test_clock_to_env_clock();

CREATE POLICY "environments_authenticated_read" ON "public"."environments"
  FOR SELECT
  TO "authenticated"
  USING (true);

CREATE POLICY "profiles_self_read" ON "public"."profiles"
  FOR SELECT
  TO "authenticated"
  USING ((id = app.auth_profile_id()));

CREATE POLICY "staff_memberships_self_read" ON "public"."staff_memberships"
  FOR SELECT
  TO "authenticated"
  USING ((profile_id = app.auth_profile_id()));

CREATE POLICY "stations_membership_read" ON "public"."stations"
  FOR SELECT
  TO "authenticated"
  USING ((id IN ( SELECT station_id.station_id
   FROM app.auth_station_ids() station_id(station_id))));

COMMENT ON EXTENSION "btree_gist" IS 'support for indexing common datatypes in GiST';

REVOKE ALL ON FUNCTION "app"."auth_has_role"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "app"."auth_has_role"(text, uuid) TO "authenticated", "postgres";

REVOKE ALL ON FUNCTION "app"."auth_profile_id"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "app"."auth_profile_id"() TO "authenticated", "postgres";

REVOKE ALL ON FUNCTION "app"."auth_station_ids"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "app"."auth_station_ids"() TO "authenticated", "postgres";

REVOKE ALL ON FUNCTION "app"."current_environment_id"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "app"."current_environment_id"() TO "postgres";

REVOKE ALL ON FUNCTION "app"."env_now"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "app"."env_now"(uuid) TO "postgres";

REVOKE ALL ON FUNCTION "app"."guard_audit_log_append_only"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "app"."guard_audit_log_append_only"() TO "postgres";

REVOKE ALL ON FUNCTION "app"."guard_env_clock"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "app"."guard_env_clock"() TO "postgres";

REVOKE ALL ON FUNCTION "app"."sync_test_clock_to_env_clock"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "app"."sync_test_clock_to_env_clock"() TO "postgres";

GRANT USAGE ON SCHEMA "app" TO "authenticated";

GRANT CREATE, USAGE ON SCHEMA "app" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "app"."env_clock" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."audit_log" TO "postgres", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."command_log" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."environments" FROM "authenticated";

GRANT SELECT ON TABLE "public"."environments" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."environments" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ON TABLE "public"."profiles" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."staff_memberships" FROM "authenticated";

GRANT SELECT ON TABLE "public"."staff_memberships" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."staff_memberships" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."stations" FROM "authenticated";

GRANT SELECT ON TABLE "public"."stations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."stations" TO "postgres", "service_role";

-- ---------------------------------------------------------------------
-- Baseline estructural del proyecto TEST.
-- El esquema remoto ya dependía de estas filas antes de que existiera
-- historial reproducible de migraciones. No son datos de usuario.
-- ---------------------------------------------------------------------

INSERT INTO public.environments (id, code, name)
VALUES (
  '9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10',
  'test',
  'Turno EV Laboratorio'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO app.env_clock (
  environment_id,
  is_simulated,
  anchor_logical_at,
  anchor_real_at,
  speed,
  is_paused
)
SELECT
  environment_id,
  true,
  anchor_simulated_at,
  anchor_real_at,
  speed,
  is_paused
FROM public.test_clock
WHERE environment_id = '9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10'
ON CONFLICT (environment_id) DO NOTHING;
ALTER TABLE "public"."audit_log"
  ADD COLUMN "occurred_at" timestamp WITH time zone NOT NULL DEFAULT app.env_now();

ALTER TABLE "public"."command_log"
  ADD COLUMN "occurred_at" timestamp WITH time zone NOT NULL DEFAULT app.env_now();

ALTER TABLE "public"."staff_memberships"
  ADD COLUMN "starts_at" timestamp WITH time zone NOT NULL DEFAULT app.env_now();

ALTER TABLE "public"."staff_memberships"
  ADD CONSTRAINT "staff_memberships_driver_no_overlap" EXCLUDE USING gist (profile_id WITH =, tstzrange(starts_at, ends_at, '[)'::text) WITH &&) WHERE ((ROLE = 'driver'::text));

ALTER TABLE "public"."staff_memberships"
  ADD CONSTRAINT "staff_memberships_no_overlap_same_role_station" EXCLUDE USING gist (profile_id WITH =, station_id WITH =, ROLE WITH =, tstzrange(starts_at, ends_at, '[)'::text)
    WITH &&);

ALTER TABLE "public"."staff_memberships"
  ADD CONSTRAINT "staff_memberships_valid_interval" CHECK (((ends_at IS NULL) OR (ends_at > starts_at)));
