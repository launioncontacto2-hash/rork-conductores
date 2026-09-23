-- UBER Test receiver and identity contract. TEST-only and additive.
create table if not exists public.uber_test_receiver_sessions (
  environment_id uuid not null,
  profile_id uuid not null,
  installation_id text not null,
  last_seen_at timestamptz not null default now(),
  active_receiver boolean not null default true,
  auth_session_id uuid,
  primary key (environment_id, profile_id),
  unique (environment_id, installation_id)
);

alter table public.uber_test_receiver_sessions enable row level security;
revoke all on public.uber_test_receiver_sessions from public, anon, authenticated;
grant all on public.uber_test_receiver_sessions to postgres, service_role;

create or replace function public.uber_test_claim_receiver(p_installation_id text, p_app_version text default null)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_profile uuid; v_env uuid; v_session uuid; v_now timestamptz; v_name text; v_employee text; v_previous text;
begin
  if nullif(btrim(p_installation_id),'') is null then raise exception 'installation_id_required'; end if;
  v_profile := app.auth_profile_id(); v_env := app.current_environment_id(); v_session := app.auth_session_id(); v_now := app.env_now(v_env);
  if v_profile is null then raise exception 'not_authenticated' using errcode='42501'; end if;
  select display_name, employee_number into v_name, v_employee from public.profiles where id=v_profile and environment_id=v_env;
  if v_employee is null then raise exception 'driver_profile_not_found' using errcode='42501'; end if;
  select installation_id into v_previous from public.uber_test_receiver_sessions where environment_id=v_env and profile_id=v_profile for update;
  insert into public.uber_test_receiver_sessions(environment_id,profile_id,installation_id,last_seen_at,active_receiver,auth_session_id)
    values(v_env,v_profile,btrim(p_installation_id),v_now,true,v_session)
    on conflict(environment_id,profile_id) do update set installation_id=excluded.installation_id,last_seen_at=excluded.last_seen_at,active_receiver=true,auth_session_id=excluded.auth_session_id;
  return jsonb_build_object('profileId',v_profile,'displayName',coalesce(v_name,''),'employeeNumber',v_employee,'installationId',btrim(p_installation_id),'activeReceiver',true,'replacedInstallationId',v_previous);
end $$;

create or replace function public.uber_test_heartbeat_receiver(p_installation_id text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_profile uuid; v_env uuid; v_row public.uber_test_receiver_sessions%rowtype;
begin
  v_profile:=app.auth_profile_id(); v_env:=app.current_environment_id();
  select * into v_row from public.uber_test_receiver_sessions where environment_id=v_env and profile_id=v_profile and installation_id=btrim(p_installation_id) for update;
  if v_row.installation_id is null then return jsonb_build_object('activeReceiver',false); end if;
  update public.uber_test_receiver_sessions set last_seen_at=app.env_now(v_env), active_receiver=true, auth_session_id=app.auth_session_id() where environment_id=v_env and profile_id=v_profile and installation_id=btrim(p_installation_id);
  return jsonb_build_object('activeReceiver',true,'lastSeenAt',app.env_now(v_env));
end $$;

create or replace function public.uber_test_release_receiver(p_installation_id text)
returns void language sql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$ update public.uber_test_receiver_sessions set active_receiver=false where environment_id=app.current_environment_id() and profile_id=app.auth_profile_id() and installation_id=btrim(p_installation_id) $$;

revoke all on function public.uber_test_claim_receiver(text,text), public.uber_test_heartbeat_receiver(text), public.uber_test_release_receiver(text) from public, anon;
grant execute on function public.uber_test_claim_receiver(text,text), public.uber_test_heartbeat_receiver(text), public.uber_test_release_receiver(text) to authenticated;
