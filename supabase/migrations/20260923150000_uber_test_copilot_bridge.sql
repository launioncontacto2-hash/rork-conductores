-- UBER Test -> Copiloto bridge foundation. TEST-only, additive and idempotent.
-- Keeps UBER Test queue authoritative while exposing one presented offer at a time.
alter table public.uber_test_offer_events
  add column if not exists presented_offer_id uuid references public.uber_test_offers(id),
  add column if not exists presented_at timestamptz,
  add column if not exists copilot_status text not null default 'pending'
    check (copilot_status in ('pending','evaluated','unsupported','no_active_shift'));

create index if not exists uber_test_offer_events_presented_offer_idx
  on public.uber_test_offer_events(presented_offer_id);

create or replace function public.present_next_uber_test_offer(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare
  v_event public.uber_test_offer_events%rowtype;
  v_offer public.uber_test_offers%rowtype;
begin
  select e.* into v_event
    from public.uber_test_offer_events e
    join public.uber_test_offer_batches b on b.id=e.batch_id
    join public.driver_profiles d on d.id=b.driver_profile_id
   where e.batch_id=p_batch_id
     and d.profile_id=(select auth.uid())
     and b.environment='TEST'
   for update;
  if v_event.id is null then raise exception 'uber_test_batch_not_available'; end if;
  if v_event.presented_offer_id is not null then
    select * into strict v_offer from public.uber_test_offers where id=v_event.presented_offer_id;
    return jsonb_build_object('status','already_presented','offer',to_jsonb(v_offer));
  end if;
  select o.* into v_offer
    from public.uber_test_offers o
   where o.batch_id=p_batch_id
     and not exists (select 1 from public.uber_test_offer_results r where r.offer_id=o.id)
   order by o.sequence_no asc
   limit 1;
  if v_offer.id is null then
    update public.uber_test_offer_events set status='acknowledged', processed_at=coalesce(processed_at,now()) where id=v_event.id;
    return jsonb_build_object('status','batch_completed');
  end if;
  update public.uber_test_offer_events
     set presented_offer_id=v_offer.id, presented_at=coalesce(presented_at,now()), status='acknowledged', processed_at=coalesce(processed_at,now())
   where id=v_event.id;
  update public.uber_test_offer_batches set status='active' where id=p_batch_id and status='queued';
  return jsonb_build_object('status','presented','offer',to_jsonb(v_offer));
end;
$$;

revoke all on function public.present_next_uber_test_offer(uuid) from public, anon;
grant execute on function public.present_next_uber_test_offer(uuid) to authenticated;

create or replace function public.record_uber_test_result(
  p_offer_id uuid,
  p_outcome text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_offer public.uber_test_offers%rowtype; v_result public.uber_test_offer_results%rowtype; v_next public.uber_test_offers%rowtype;
begin
  if p_idempotency_key is null or char_length(btrim(p_idempotency_key)) not between 8 and 200 then raise exception 'idempotency_key_required'; end if;
  if p_outcome not in ('accepted','discarded','expired') then raise exception 'invalid_uber_test_outcome'; end if;
  select o.* into strict v_offer from public.uber_test_offers o join public.uber_test_offer_batches b on b.id=o.batch_id join public.driver_profiles d on d.id=b.driver_profile_id where o.id=p_offer_id and d.profile_id=(select auth.uid()) and b.environment='TEST';
  insert into public.uber_test_offer_results(batch_id,offer_id,outcome,idempotency_key) values (v_offer.batch_id,v_offer.id,p_outcome,p_idempotency_key) on conflict (idempotency_key) do nothing returning * into v_result;
  if v_result.id is null then select * into strict v_result from public.uber_test_offer_results where idempotency_key=p_idempotency_key; end if;
  if (select count(*) from public.uber_test_offers where batch_id=v_offer.batch_id)=(select count(*) from public.uber_test_offer_results where batch_id=v_offer.batch_id) then
    update public.uber_test_offer_batches set status='completed', completed_at=now() where id=v_offer.batch_id;
  else
    update public.uber_test_offer_batches set status='active' where id=v_offer.batch_id;
    select o.* into v_next from public.uber_test_offers o where o.batch_id=v_offer.batch_id and not exists (select 1 from public.uber_test_offer_results r where r.offer_id=o.id) order by o.sequence_no asc limit 1;
    update public.uber_test_offer_events set presented_offer_id=v_next.id, presented_at=case when v_next.id is null then presented_at else now() end, status=case when v_next.id is null then status else 'acknowledged' end, processed_at=case when v_next.id is null then processed_at else now() end where batch_id=v_offer.batch_id;
  end if;
  return jsonb_build_object('id',v_result.id,'batch_id',v_result.batch_id,'offer_id',v_result.offer_id,'outcome',v_result.outcome,'next_offer_id',v_next.id);
end;
$$;
revoke all on function public.record_uber_test_result(uuid,text,text) from public, anon;
grant execute on function public.record_uber_test_result(uuid,text,text) to authenticated;
-- Make existing driver_get_uber_test_batch consumers receive the first presented offer.
create or replace function public.driver_get_uber_test_batch()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_batch public.uber_test_offer_batches%rowtype; v_offers jsonb; v_event public.uber_test_offer_events%rowtype; v_presented jsonb;
begin
  select b.* into v_batch from public.uber_test_offer_batches b join public.driver_profiles d on d.id=b.driver_profile_id
   where d.profile_id=(select auth.uid()) and b.environment='TEST' and b.status in ('queued','active') order by b.created_at asc limit 1;
  if v_batch.id is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'service',o.service,'fare',o.fare_mxn,'currency','MXN','pickup',o.pickup,'pickupDistanceKm',o.pickup_distance_km,'tripDurationMinutes',o.trip_duration_minutes,'tripDistanceKm',o.trip_distance_km,'riderRating',o.rider_rating,'expiresAfterSeconds',o.expires_after_seconds) order by o.sequence_no),'[]'::jsonb) into v_offers from public.uber_test_offers o where o.batch_id=v_batch.id;
  select e.* into v_event from public.uber_test_offer_events e where e.batch_id=v_batch.id for update;
  if v_event.presented_offer_id is null then v_presented:=public.present_next_uber_test_offer(v_batch.id);
  else select jsonb_build_object('status','already_presented','offer',to_jsonb(o)) into v_presented from public.uber_test_offers o where o.id=v_event.presented_offer_id; end if;
  return jsonb_build_object('id',v_batch.id,'environment',v_batch.environment,'createdAt',v_batch.created_at,'offers',v_offers,'presented',coalesce(v_presented->'offer','null'::jsonb),'presentationStatus',v_presented->>'status');
end;
$$;
revoke all on function public.driver_get_uber_test_batch() from public,anon;
grant execute on function public.driver_get_uber_test_batch() to authenticated;
