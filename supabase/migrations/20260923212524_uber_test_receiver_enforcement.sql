-- TEST-only receiver enforcement. The active installation is bound to the
-- authenticated DORI profile; stale phones must not recover or submit.
create or replace function public.uber_test_assert_active_receiver(p_installation_id text)
returns boolean
language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
begin
  return exists (
    select 1 from public.uber_test_receiver_sessions s
    where s.environment_id=app.current_environment_id()
      and s.profile_id=app.auth_profile_id()
      and s.installation_id=btrim(p_installation_id)
      and s.active_receiver=true
  );
end;
$$;
revoke all on function public.uber_test_assert_active_receiver(text) from public, anon;
grant execute on function public.uber_test_assert_active_receiver(text) to authenticated;

-- A released installation cannot resurrect itself through heartbeat.
create or replace function public.uber_test_heartbeat_receiver(p_installation_id text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_profile uuid:=app.auth_profile_id(); v_env uuid:=app.current_environment_id(); v_count integer;
begin
  update public.uber_test_receiver_sessions
     set last_seen_at=app.env_now(v_env), auth_session_id=app.auth_session_id()
   where environment_id=v_env and profile_id=v_profile and installation_id=btrim(p_installation_id) and active_receiver=true;
  get diagnostics v_count = row_count;
  return jsonb_build_object('activeReceiver',v_count=1,'lastSeenAt',case when v_count=1 then app.env_now(v_env) else null end);
end;
$$;
revoke all on function public.uber_test_heartbeat_receiver(text) from public, anon;
grant execute on function public.uber_test_heartbeat_receiver(text) to authenticated;

-- Keep direct presentation safe even when a client bypasses the Edge Function.
create or replace function public.present_next_uber_test_offer(p_batch_id uuid)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_event public.uber_test_offer_events%rowtype; v_offer public.uber_test_offers%rowtype;
begin
  if not exists (select 1 from public.uber_test_receiver_sessions where environment_id=app.current_environment_id() and profile_id=app.auth_profile_id() and active_receiver=true) then raise exception 'uber_test_receiver_inactive' using errcode='42501'; end if;
  select e.* into v_event from public.uber_test_offer_events e join public.uber_test_offer_batches b on b.id=e.batch_id join public.driver_profiles d on d.id=b.driver_profile_id where e.batch_id=p_batch_id and d.profile_id=app.auth_profile_id() and b.environment='TEST' for update;
  if v_event.id is null then raise exception 'uber_test_batch_not_available'; end if;
  if v_event.presented_offer_id is not null then select * into strict v_offer from public.uber_test_offers where id=v_event.presented_offer_id; return jsonb_build_object('status','already_presented','offer',to_jsonb(v_offer)); end if;
  select o.* into v_offer from public.uber_test_offers o where o.batch_id=p_batch_id and not exists(select 1 from public.uber_test_offer_results r where r.offer_id=o.id) order by o.sequence_no asc limit 1;
  if v_offer.id is null then update public.uber_test_offer_events set status='acknowledged',processed_at=coalesce(processed_at,now()) where id=v_event.id; return jsonb_build_object('status','batch_completed'); end if;
  update public.uber_test_offer_events set presented_offer_id=v_offer.id,presented_at=coalesce(presented_at,now()),status='acknowledged',processed_at=coalesce(processed_at,now()) where id=v_event.id;
  update public.uber_test_offer_batches set status='active' where id=p_batch_id and status='queued';
  return jsonb_build_object('status','presented','offer',to_jsonb(v_offer));
end;
$$;
revoke all on function public.present_next_uber_test_offer(uuid) from public, anon;
grant execute on function public.present_next_uber_test_offer(uuid) to authenticated;

-- Installation-aware entry point used by uber-test-next.
create or replace function public.driver_get_uber_test_batch(p_installation_id text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_batch public.uber_test_offer_batches%rowtype; v_offers jsonb; e public.uber_test_offer_events%rowtype; presented jsonb;
begin
  if not public.uber_test_assert_active_receiver(p_installation_id) then raise exception 'uber_test_receiver_inactive' using errcode='42501'; end if;
  select b.* into v_batch from public.uber_test_offer_batches b join public.driver_profiles d on d.id=b.driver_profile_id where d.profile_id=app.auth_profile_id() and b.environment='TEST' and b.status in ('queued','active') order by b.created_at asc limit 1;
  if v_batch.id is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'service',o.service,'fare',o.fare_mxn,'currency','MXN','pickup',o.pickup,'pickupDistanceKm',o.pickup_distance_km,'pickupMinutes',o.pickup_minutes,'tripDurationMinutes',o.trip_duration_minutes,'tripDistanceKm',o.trip_distance_km,'riderRating',o.rider_rating,'expiresAfterSeconds',o.expires_after_seconds) order by o.sequence_no),'[]'::jsonb) into v_offers from public.uber_test_offers o where o.batch_id=v_batch.id;
  select * into e from public.uber_test_offer_events where batch_id=v_batch.id for update;
  if e.presented_offer_id is null then presented:=public.present_next_uber_test_offer(v_batch.id); else select jsonb_build_object('status','already_presented','offer',to_jsonb(o)) into presented from public.uber_test_offers o where o.id=e.presented_offer_id; end if;
  return jsonb_build_object('id',v_batch.id,'environment',v_batch.environment,'createdAt',v_batch.created_at,'offers',v_offers,'presented',coalesce(presented->'offer','null'::jsonb),'presentationStatus',presented->>'status');
end;
$$;
revoke all on function public.driver_get_uber_test_batch(text) from public, anon;
grant execute on function public.driver_get_uber_test_batch(text) to authenticated;
