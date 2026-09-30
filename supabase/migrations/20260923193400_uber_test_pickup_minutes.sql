-- Additive TEST offer contract extension.
alter table public.uber_test_offers add column if not exists pickup_minutes numeric(6,2);
comment on column public.uber_test_offers.pickup_minutes is 'TEST-only estimated minutes to pickup; informational, never a recommendation.';

create or replace function public.driver_get_uber_test_batch()
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_batch public.uber_test_offer_batches%rowtype; v_offers jsonb; v_event public.uber_test_offer_events%rowtype; v_presented jsonb;
begin
  select b.* into v_batch from public.uber_test_offer_batches b join public.driver_profiles d on d.id=b.driver_profile_id
   where d.profile_id=app.auth_profile_id() and b.environment='TEST' and b.status in ('queued','active') order by b.created_at asc limit 1;
  if v_batch.id is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'service',o.service,'fare',o.fare_mxn,'currency','MXN','pickup',o.pickup,'pickupMinutes',o.pickup_minutes,'pickupDistanceKm',o.pickup_distance_km,'tripDurationMinutes',o.trip_duration_minutes,'tripDistanceKm',o.trip_distance_km,'riderRating',o.rider_rating,'expiresAfterSeconds',o.expires_after_seconds) order by o.sequence_no),'[]'::jsonb) into v_offers from public.uber_test_offers o where o.batch_id=v_batch.id;
  select e.* into v_event from public.uber_test_offer_events e where e.batch_id=v_batch.id for update;
  if v_event.presented_offer_id is null then v_presented:=public.present_next_uber_test_offer(v_batch.id);
  else select jsonb_build_object('status','already_presented','offer',to_jsonb(o)) into v_presented from public.uber_test_offers o where o.id=v_event.presented_offer_id; end if;
  return jsonb_build_object('id',v_batch.id,'environment',v_batch.environment,'createdAt',v_batch.created_at,'offers',v_offers,'presented',coalesce(v_presented->'offer','null'::jsonb),'presentationStatus',v_presented->>'status');
end $$;

create or replace function public.driver_get_uber_test_batch(p_installation_id text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_active boolean;
begin
  select active_receiver and last_seen_at > app.env_now(app.current_environment_id()) - interval '90 seconds'
    into v_active
    from public.uber_test_receiver_sessions
   where environment_id=app.current_environment_id() and profile_id=app.auth_profile_id() and installation_id=btrim(p_installation_id)
     and auth_session_id=app.auth_session_id();
  if coalesce(v_active,false) is not true then return jsonb_build_object('receiverInactive',true); end if;
  update public.uber_test_receiver_sessions set last_seen_at=app.env_now(app.current_environment_id()) where environment_id=app.current_environment_id() and profile_id=app.auth_profile_id() and installation_id=btrim(p_installation_id);
  return public.driver_get_uber_test_batch();
end $$;
revoke all on function public.driver_get_uber_test_batch(text) from public, anon;
grant execute on function public.driver_get_uber_test_batch(text) to authenticated;

