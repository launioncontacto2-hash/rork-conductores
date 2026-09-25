create table if not exists public.uber_test_transport_events (
  id uuid primary key default gen_random_uuid(),
  environment_id uuid not null references public.environments(id),
  profile_id uuid not null references public.profiles(id),
  installation_id text not null,
  app_build text not null,
  session_generation text not null,
  event_name text not null,
  event_at timestamptz not null default now(),
  batch_id uuid,
  transport text,
  metadata jsonb not null default '{}'::jsonb,
  constraint uber_test_transport_events_test_only check (transport is null or transport in ('realtime','fallback')),
  constraint uber_test_transport_events_name check (event_name in (
    'app_foreground','realtime_start_requested','realtime_subscribing','realtime_subscribed',
    'realtime_insert_received','realtime_closed','realtime_error','realtime_reconnect',
    'fallback_tick','recover_started','batch_loaded','offer_presented','expiry_started',
    'result_flush_started','result_flush_reused','result_sent','result_flush_finished'
  ))
);
alter table public.uber_test_transport_events enable row level security;
revoke all on public.uber_test_transport_events from public, anon, authenticated;
grant all on public.uber_test_transport_events to postgres, service_role;

create or replace function public.record_uber_test_transport_event(
  p_installation_id text,
  p_app_build text,
  p_session_generation text,
  p_event_name text,
  p_event_at timestamptz default now(),
  p_batch_id uuid default null,
  p_transport text default null,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_id uuid; v_env uuid; v_profile uuid;
begin
  v_env := app.current_environment_id();
  v_profile := app.auth_profile_id();
  if v_env is null or v_profile is null then raise exception 'uber_test_transport_identity_required' using errcode='42501'; end if;
  if not exists (select 1 from public.environments e where e.id=v_env and lower(e.code)='test') then raise exception 'uber_test_transport_test_only' using errcode='42501'; end if;
  if length(btrim(coalesce(p_installation_id,'')))=0 or length(btrim(coalesce(p_app_build,'')))=0 or length(btrim(coalesce(p_session_generation,'')))=0 then raise exception 'uber_test_transport_fields_required'; end if;
  insert into public.uber_test_transport_events(environment_id,profile_id,installation_id,app_build,session_generation,event_name,event_at,batch_id,transport,metadata)
  values(v_env,v_profile,btrim(p_installation_id),btrim(p_app_build),btrim(p_session_generation),p_event_name,p_event_at,p_batch_id,p_transport,coalesce(p_metadata,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.record_uber_test_transport_event(text,text,text,text,timestamptz,uuid,text,jsonb) from public, anon;
grant execute on function public.record_uber_test_transport_event(text,text,text,text,timestamptz,uuid,text,jsonb) to authenticated;
