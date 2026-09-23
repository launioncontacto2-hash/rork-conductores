-- UBER Test corrective migration: map authenticated users through the DORI
-- profile identity. TEST only; no production tables or DORI Copiloto changes.

drop policy if exists uber_test_batch_driver_read on public.uber_test_offer_batches;
create policy uber_test_batch_driver_read on public.uber_test_offer_batches for select to authenticated
  using (exists (select 1 from public.driver_profiles d where d.id = driver_profile_id and d.profile_id = app.auth_profile_id()));

drop policy if exists uber_test_offer_driver_read on public.uber_test_offers;
create policy uber_test_offer_driver_read on public.uber_test_offers for select to authenticated
  using (exists (select 1 from public.uber_test_offer_batches b join public.driver_profiles d on d.id = b.driver_profile_id where b.id = batch_id and d.profile_id = app.auth_profile_id()));

drop policy if exists uber_test_result_driver_read on public.uber_test_offer_results;
create policy uber_test_result_driver_read on public.uber_test_offer_results for select to authenticated
  using (exists (select 1 from public.uber_test_offer_batches b join public.driver_profiles d on d.id = b.driver_profile_id where b.id = batch_id and d.profile_id = app.auth_profile_id()));

drop policy if exists uber_test_result_driver_insert on public.uber_test_offer_results;
create policy uber_test_result_driver_insert on public.uber_test_offer_results for insert to authenticated
  with check (exists (select 1 from public.uber_test_offers o join public.uber_test_offer_batches b on b.id = o.batch_id join public.driver_profiles d on d.id = b.driver_profile_id where o.id = offer_id and b.id = batch_id and d.profile_id = app.auth_profile_id() and b.environment = 'TEST'));

drop policy if exists uber_test_event_driver_read on public.uber_test_offer_events;
create policy uber_test_event_driver_read on public.uber_test_offer_events for select to authenticated
  using (exists (select 1 from public.driver_profiles d where d.id = driver_profile_id and d.profile_id = app.auth_profile_id()));

create or replace function public.record_uber_test_result(
  p_offer_id uuid, p_outcome text, p_idempotency_key text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_offer public.uber_test_offers%rowtype; v_result public.uber_test_offer_results%rowtype;
begin
  if p_idempotency_key is null or char_length(btrim(p_idempotency_key)) not between 8 and 200 then raise exception 'idempotency_key_required'; end if;
  if p_outcome not in ('accepted','discarded','expired') then raise exception 'invalid_uber_test_outcome'; end if;
  select o.* into strict v_offer from public.uber_test_offers o
    join public.uber_test_offer_batches b on b.id=o.batch_id
    join public.driver_profiles d on d.id=b.driver_profile_id
    where o.id=p_offer_id and d.profile_id=app.auth_profile_id() and b.environment='TEST';
  insert into public.uber_test_offer_results(batch_id,offer_id,outcome,idempotency_key)
    values (v_offer.batch_id,v_offer.id,p_outcome,p_idempotency_key)
    on conflict (idempotency_key) do nothing returning * into v_result;
  if v_result.id is null then select * into strict v_result from public.uber_test_offer_results where idempotency_key=p_idempotency_key; end if;
  if (select count(*) from public.uber_test_offers where batch_id=v_offer.batch_id)=(select count(*) from public.uber_test_offer_results where batch_id=v_offer.batch_id) then
    update public.uber_test_offer_batches set status='completed', completed_at=now() where id=v_offer.batch_id;
  else
    update public.uber_test_offer_batches set status='active' where id=v_offer.batch_id;
  end if;
  return jsonb_build_object('id',v_result.id,'batch_id',v_result.batch_id,'offer_id',v_result.offer_id,'outcome',v_result.outcome);
end;
$$;

create or replace function public.driver_get_uber_test_batch()
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_batch public.uber_test_offer_batches%rowtype; v_offers jsonb;
begin
  select b.* into v_batch from public.uber_test_offer_batches b
    join public.driver_profiles d on d.id=b.driver_profile_id
    where d.profile_id=app.auth_profile_id() and b.environment='TEST' and b.status in ('queued','active')
    order by b.created_at asc limit 1;
  if v_batch.id is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,'service',o.service,'fare',o.fare_mxn,'currency','MXN','pickup',o.pickup,
    'pickupDistanceKm',o.pickup_distance_km,'tripDurationMinutes',o.trip_duration_minutes,
    'tripDistanceKm',o.trip_distance_km,'riderRating',o.rider_rating,
    'expiresAfterSeconds',o.expires_after_seconds) order by o.sequence_no),'[]'::jsonb)
    into v_offers from public.uber_test_offers o where o.batch_id=v_batch.id;
  return jsonb_build_object('id',v_batch.id,'environment',v_batch.environment,'createdAt',v_batch.created_at,'offers',v_offers);
end;
$$;

revoke all on function public.record_uber_test_result(uuid,text,text) from public, anon;
grant execute on function public.record_uber_test_result(uuid,text,text) to authenticated;
revoke all on function public.driver_get_uber_test_batch() from public, anon;
grant execute on function public.driver_get_uber_test_batch() to authenticated;
