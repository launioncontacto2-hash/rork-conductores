-- TEST-only continuity fix. Heartbeat uses the operational clock; recovery
-- skips batches whose every offer already has a result.
create or replace function public.uber_test_heartbeat_receiver(p_installation_id text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_profile uuid:=app.auth_profile_id(); v_env uuid:=app.current_environment_id(); v_count integer; v_now timestamptz:=clock_timestamp();
begin
  update public.uber_test_receiver_sessions set last_seen_at=v_now, auth_session_id=app.auth_session_id()
   where environment_id=v_env and profile_id=v_profile and installation_id=btrim(p_installation_id) and active_receiver=true;
  get diagnostics v_count = row_count;
  return jsonb_build_object('activeReceiver',v_count=1,'lastSeenAt',case when v_count=1 then v_now else null end);
end; $$;
revoke all on function public.uber_test_heartbeat_receiver(text) from public, anon;
grant execute on function public.uber_test_heartbeat_receiver(text) to authenticated;

create or replace function public.driver_get_uber_test_batch(p_installation_id text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_batch public.uber_test_offer_batches%rowtype; v_offers jsonb; e public.uber_test_offer_events%rowtype; presented jsonb;
begin
  if not public.uber_test_assert_active_receiver(p_installation_id) then raise exception 'uber_test_receiver_inactive' using errcode='42501'; end if;
  select b.* into v_batch from public.uber_test_offer_batches b join public.driver_profiles d on d.id=b.driver_profile_id
   where d.profile_id=app.auth_profile_id() and b.environment='TEST' and b.status in ('queued','active')
     and exists (select 1 from public.uber_test_offers o where o.batch_id=b.id and not exists (select 1 from public.uber_test_offer_results r where r.offer_id=o.id))
   order by b.created_at asc limit 1;
  if v_batch.id is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'service',o.service,'fare',o.fare_mxn,'currency','MXN','pickup',o.pickup,'pickupDistanceKm',o.pickup_distance_km,'pickupMinutes',o.pickup_minutes,'tripDurationMinutes',o.trip_duration_minutes,'tripDistanceKm',o.trip_distance_km,'riderRating',o.rider_rating,'expiresAfterSeconds',o.expires_after_seconds) order by o.sequence_no),'[]'::jsonb) into v_offers from public.uber_test_offers o where o.batch_id=v_batch.id;
  select * into e from public.uber_test_offer_events where batch_id=v_batch.id for update;
  if e.presented_offer_id is null then presented:=public.present_next_uber_test_offer(v_batch.id); else select jsonb_build_object('status','already_presented','offer',to_jsonb(o)) into presented from public.uber_test_offers o where o.id=e.presented_offer_id; end if;
  return jsonb_build_object('id',v_batch.id,'environment',v_batch.environment,'createdAt',v_batch.created_at,'offers',v_offers,'presented',coalesce(presented->'offer','null'::jsonb),'presentationStatus',presented->>'status');
end; $$;
revoke all on function public.driver_get_uber_test_batch(text) from public, anon;
grant execute on function public.driver_get_uber_test_batch(text) to authenticated;
