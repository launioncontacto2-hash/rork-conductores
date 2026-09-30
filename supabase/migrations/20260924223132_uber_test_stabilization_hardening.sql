-- TEST-only hardening: server-authoritative recovery, outcome idempotency,
-- and recoverable push leases. Production is intentionally untouched.

alter table public.dori_copilot_notifications
  add column if not exists claimed_at timestamptz;

create or replace function public.claim_dori_copilot_notifications(p_limit integer default 25)
returns setof public.dori_copilot_notifications language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp as $$
begin
  if current_user <> 'service_role' and current_user <> 'postgres' then
    raise exception 'copilot_push_service_role_required' using errcode='42501';
  end if;
  return query update public.dori_copilot_notifications n
    set status='sending', claimed_at=clock_timestamp()
    where n.id in (
      select id from public.dori_copilot_notifications
      where status='pending'
         or (status='sending' and claimed_at < clock_timestamp() - interval '2 minutes')
      order by created_at,id for update skip locked
      limit greatest(1,least(p_limit,100))
    ) returning n.*;
end; $$;

create or replace function public.driver_get_uber_test_batch(p_installation_id text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp as $$
declare v_batch public.uber_test_offer_batches%rowtype; v_offers jsonb; v_offer public.uber_test_offers%rowtype; v_status text;
begin
  if not public.uber_test_assert_active_receiver(p_installation_id) then
    raise exception 'uber_test_receiver_inactive' using errcode='42501';
  end if;
  select b.* into v_batch
    from public.uber_test_offer_batches b
    join public.driver_profiles d on d.id=b.driver_profile_id
   where d.profile_id=app.auth_profile_id() and b.environment='TEST'
     and b.status in ('queued','active')
     and exists (select 1 from public.uber_test_offers o
                  where o.batch_id=b.id
                    and not exists (select 1 from public.uber_test_offer_results r where r.offer_id=o.id))
   order by b.created_at asc limit 1;
  if v_batch.id is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'service',o.service,'fare',o.fare_mxn,'currency','MXN','pickup',o.pickup,'pickupDistanceKm',o.pickup_distance_km,'pickupMinutes',o.pickup_minutes,'tripDurationMinutes',o.trip_duration_minutes,'tripDistanceKm',o.trip_distance_km,'riderRating',o.rider_rating,'expiresAfterSeconds',o.expires_after_seconds) order by o.sequence_no),'[]'::jsonb)
    into v_offers from public.uber_test_offers o
   where o.batch_id=v_batch.id and not exists (select 1 from public.uber_test_offer_results r where r.offer_id=o.id);
  select o.* into v_offer from public.uber_test_offers o
   where o.batch_id=v_batch.id and not exists (select 1 from public.uber_test_offer_results r where r.offer_id=o.id)
   order by o.sequence_no limit 1;
  if v_offer.id is null then return null; end if;
  v_status := case when public.present_next_uber_test_offer(v_batch.id)->>'offer' is null then 'already_presented' else 'presented' end;
  return jsonb_build_object('id',v_batch.id,'environment',v_batch.environment,'createdAt',v_batch.created_at,'offers',v_offers,'presented',to_jsonb(v_offer),'presentationStatus',v_status);
end; $$;

create or replace function public.record_uber_test_result(p_offer_id uuid, p_outcome text, p_idempotency_key text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp as $$
declare v_offer public.uber_test_offers%rowtype; v_existing public.uber_test_offer_results%rowtype; v_next uuid;
begin
  if p_outcome not in ('accepted','discarded','expired') then raise exception 'invalid_uber_test_outcome'; end if;
  select o.* into strict v_offer from public.uber_test_offers o join public.uber_test_offer_batches b on b.id=o.batch_id join public.driver_profiles d on d.id=b.driver_profile_id where o.id=p_offer_id and d.profile_id=app.auth_profile_id() and b.environment='TEST';
  select * into v_existing from public.uber_test_offer_results where offer_id=p_offer_id;
  if v_existing.id is not null then
    if v_existing.outcome=p_outcome then return jsonb_build_object('status','idempotent','id',v_existing.id,'batch_id',v_existing.batch_id,'offer_id',v_existing.offer_id,'outcome',v_existing.outcome,'next_offer_id',null); end if;
    return jsonb_build_object('status','conflict','error','offer_already_resolved','offer_id',p_offer_id,'existing_outcome',v_existing.outcome);
  end if;
  if exists(select 1 from public.uber_test_offer_results where idempotency_key=p_idempotency_key) then raise exception 'idempotency_key_conflict'; end if;
  insert into public.uber_test_offer_results(batch_id,offer_id,outcome,idempotency_key) values(v_offer.batch_id,v_offer.id,p_outcome,p_idempotency_key);
  select o.id into v_next from public.uber_test_offers o where o.batch_id=v_offer.batch_id and not exists(select 1 from public.uber_test_offer_results r where r.offer_id=o.id) order by o.sequence_no limit 1;
  if v_next is null then update public.uber_test_offer_batches set status='completed',completed_at=now() where id=v_offer.batch_id; else update public.uber_test_offer_batches set status='active' where id=v_offer.batch_id; end if;
  return jsonb_build_object('status','recorded','batch_id',v_offer.batch_id,'offer_id',p_offer_id,'outcome',p_outcome,'next_offer_id',v_next);
end; $$;
