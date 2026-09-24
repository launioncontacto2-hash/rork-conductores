create or replace function public.heartbeat_dori_copilot_push_device(p_device_token text, p_bundle_id text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, app, auth, pg_temp as $$
declare v_environment uuid := app.current_environment_id(); v_profile uuid := app.auth_profile_id();
begin
  if v_environment is null or v_profile is null then raise exception 'authenticated_session_required' using errcode='42501'; end if;
  update public.dori_copilot_push_devices
     set status='active', updated_at=now()
   where environment_id=v_environment and profile_id=v_profile and device_token=lower(btrim(p_device_token)) and bundle_id=btrim(p_bundle_id);
  if not found then raise exception 'dori_device_not_registered' using errcode='P0002'; end if;
  return jsonb_build_object('status','alive','updated_at',now());
end; $$;
revoke all on function public.heartbeat_dori_copilot_push_device(text,text) from public, anon;
grant execute on function public.heartbeat_dori_copilot_push_device(text,text) to authenticated;

create or replace function public.revoke_dori_copilot_push_device(p_device_token text, p_bundle_id text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, app, auth, pg_temp as $$
declare v_environment uuid := app.current_environment_id(); v_profile uuid := app.auth_profile_id();
begin
  if v_environment is null or v_profile is null then raise exception 'authenticated_session_required' using errcode='42501'; end if;
  update public.dori_copilot_push_devices set status='revoked', updated_at=now()
   where environment_id=v_environment and profile_id=v_profile and device_token=lower(btrim(p_device_token)) and bundle_id=btrim(p_bundle_id);
  return jsonb_build_object('status','revoked');
end; $$;
revoke all on function public.revoke_dori_copilot_push_device(text,text) from public, anon;
grant execute on function public.revoke_dori_copilot_push_device(text,text) to authenticated;

create or replace function public.get_dori_copilot_link_status()
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, app, auth, pg_temp as $$
declare v_environment uuid := app.current_environment_id(); v_profile uuid := app.auth_profile_id(); v_exists boolean; v_active boolean;
begin
  if v_environment is null or v_profile is null then return jsonb_build_object('status','waiting'); end if;
  select exists(select 1 from public.dori_copilot_push_devices d where d.environment_id=v_environment and d.profile_id=v_profile),
         exists(select 1 from public.dori_copilot_push_devices d where d.environment_id=v_environment and d.profile_id=v_profile and d.status='active' and d.updated_at > now() - interval '2 minutes')
    into v_exists, v_active;
  return jsonb_build_object('status',case when not v_exists then 'waiting' when v_active then 'linked' else 'interrupted' end,'environment_id',v_environment,'profile_id',v_profile);
end; $$;
revoke all on function public.get_dori_copilot_link_status() from public, anon;
grant execute on function public.get_dori_copilot_link_status() to authenticated;
