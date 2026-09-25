-- Forward-only TEST reconciliation.
-- Restores the receiver assertion required by installation-aware Uber Test RPCs
-- without replaying the historical receiver-enforcement migration.
create or replace function public.uber_test_assert_active_receiver(p_installation_id text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
begin
  return exists (
    select 1
      from public.uber_test_receiver_sessions s
     where s.environment_id = app.current_environment_id()
       and s.profile_id = app.auth_profile_id()
       and s.installation_id = btrim(p_installation_id)
       and s.active_receiver = true
  );
end;
$$;

revoke all on function public.uber_test_assert_active_receiver(text) from public, anon;
grant execute on function public.uber_test_assert_active_receiver(text) to authenticated;
