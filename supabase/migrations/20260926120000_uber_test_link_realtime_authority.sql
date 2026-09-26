-- TEST-only forward correction: link state is based on a valid identity,
-- active shift and non-revoked device. Heartbeat freshness is telemetry,
-- not the authority for an all-day active link.
create or replace function public.get_dori_copilot_link_status()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare
  v_environment uuid := app.current_environment_id();
  v_profile uuid := app.auth_profile_id();
  v_now timestamptz;
  v_has_device boolean;
  v_has_shift boolean;
begin
  if v_environment is null or v_profile is null or app.auth_session_id() is null then
    return jsonb_build_object('status','waiting');
  end if;
  if not exists (select 1 from public.environments e where e.id=v_environment and lower(e.code)='test') then
    return jsonb_build_object('status','waiting','environment_id',v_environment,'profile_id',v_profile);
  end if;
  v_now := app.env_now(v_environment);
  select exists (
    select 1 from public.dori_copilot_push_devices d
    where d.environment_id=v_environment and d.profile_id=v_profile and d.status='active'
  ) into v_has_device;
  select exists (
    select 1
    from public.driver_profiles dp
    join public.shifts s on s.driver_profile_id=dp.id and s.environment_id=v_environment
    where dp.profile_id=v_profile and dp.environment_id=v_environment and dp.status='active'
      and s.status='open' and s.started_at <= v_now and s.scheduled_end_at > v_now
  ) into v_has_shift;
  return jsonb_build_object(
    'status', case when v_has_device and v_has_shift then 'linked' when v_has_device then 'interrupted' else 'waiting' end,
    'environment_id',v_environment,'profile_id',v_profile,
    'active_shift',v_has_shift,'active_device',v_has_device
  );
end;
$$;
revoke all on function public.get_dori_copilot_link_status() from public, anon;
grant execute on function public.get_dori_copilot_link_status() to authenticated;
