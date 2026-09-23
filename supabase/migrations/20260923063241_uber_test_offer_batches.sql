-- UBER Test: isolated TEST-only offer batches. No production tables are touched.
create table public.uber_test_offer_batches (
  id uuid primary key default gen_random_uuid(),
  environment text not null default 'TEST' check (environment = 'TEST'),
  driver_profile_id uuid not null references public.driver_profiles(id),
  created_by_profile_id uuid not null,
  status text not null default 'queued' check (status in ('queued','active','completed')),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.uber_test_offers (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.uber_test_offer_batches(id) on delete restrict,
  sequence_no smallint not null check (sequence_no between 1 and 10),
  service text not null,
  fare_mxn numeric(12,2) not null check (fare_mxn >= 0),
  pickup text not null,
  pickup_distance_km numeric(8,2) not null check (pickup_distance_km >= 0),
  trip_duration_minutes numeric(8,2) not null check (trip_duration_minutes >= 0),
  trip_distance_km numeric(8,2) not null check (trip_distance_km >= 0),
  rider_rating numeric(3,2) check (rider_rating between 1 and 5),
  expires_after_seconds smallint not null default 15 check (expires_after_seconds between 1 and 120),
  unique(batch_id, sequence_no)
);

create table public.uber_test_offer_results (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.uber_test_offer_batches(id) on delete restrict,
  offer_id uuid not null unique references public.uber_test_offers(id) on delete restrict,
  outcome text not null check (outcome in ('accepted','discarded','expired')),
  occurred_at timestamptz not null default now(),
  idempotency_key text not null unique
);

create table public.uber_test_copilot_dispatches (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null unique references public.uber_test_offer_batches(id) on delete restrict,
  driver_profile_id uuid not null references public.driver_profiles(id),
  status text not null default 'pending' check (status in ('pending','processed','ignored')),
  input_payload jsonb not null,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

alter table public.uber_test_offer_batches enable row level security;
alter table public.uber_test_offers enable row level security;
alter table public.uber_test_offer_results enable row level security;
alter table public.uber_test_copilot_dispatches enable row level security;
revoke all on public.uber_test_offer_batches, public.uber_test_offers, public.uber_test_offer_results from anon;
revoke all on public.uber_test_copilot_dispatches from anon;
grant select on public.uber_test_offer_batches, public.uber_test_offers, public.uber_test_offer_results, public.uber_test_copilot_dispatches to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'uber_test_offer_batches') then alter publication supabase_realtime add table public.uber_test_offer_batches; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'uber_test_offers') then alter publication supabase_realtime add table public.uber_test_offers; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'uber_test_offer_results') then alter publication supabase_realtime add table public.uber_test_offer_results; end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'uber_test_copilot_dispatches') then alter publication supabase_realtime add table public.uber_test_copilot_dispatches; end if;
  end if;
end $$;

create policy uber_test_batch_driver_read on public.uber_test_offer_batches for select to authenticated
  using (exists (select 1 from public.driver_profiles d where d.id = driver_profile_id and d.profile_id = (select auth.uid())));
create policy uber_test_offer_driver_read on public.uber_test_offers for select to authenticated
  using (exists (select 1 from public.uber_test_offer_batches b join public.driver_profiles d on d.id = b.driver_profile_id where b.id = batch_id and d.profile_id = (select auth.uid())));
create policy uber_test_result_driver_read on public.uber_test_offer_results for select to authenticated
  using (exists (select 1 from public.uber_test_offer_batches b join public.driver_profiles d on d.id = b.driver_profile_id where b.id = batch_id and d.profile_id = (select auth.uid())));
create policy uber_test_batch_console_read on public.uber_test_offer_batches for select to authenticated
  using (app.auth_has_role('console', (select station_id from public.driver_profiles where id = driver_profile_id)));
create policy uber_test_offer_console_read on public.uber_test_offers for select to authenticated
  using (exists (select 1 from public.uber_test_offer_batches b where b.id = batch_id and app.auth_has_role('console', (select station_id from public.driver_profiles where id = b.driver_profile_id))));
create policy uber_test_result_console_read on public.uber_test_offer_results for select to authenticated
  using (exists (select 1 from public.uber_test_offer_batches b where b.id = batch_id and app.auth_has_role('console', (select station_id from public.driver_profiles where id = b.driver_profile_id))));
create policy uber_test_result_driver_insert on public.uber_test_offer_results for insert to authenticated
  with check (exists (select 1 from public.uber_test_offer_batches b join public.driver_profiles d on d.id = b.driver_profile_id where b.id = batch_id and d.profile_id = (select auth.uid()) and b.environment = 'TEST'));
create policy uber_test_dispatch_driver_read on public.uber_test_copilot_dispatches for select to authenticated
  using (exists (select 1 from public.driver_profiles d where d.id = driver_profile_id and d.profile_id = (select auth.uid())));
create policy uber_test_dispatch_console_read on public.uber_test_copilot_dispatches for select to authenticated
  using (app.auth_has_role('console', (select station_id from public.driver_profiles where id = driver_profile_id)));

create or replace function public.console_send_uber_test_batch(
  p_driver_profile_id uuid,
  p_offers jsonb,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare
  v_driver public.driver_profiles%rowtype;
  v_batch_id uuid;
  v_actor uuid := app.auth_profile_id();
  v_offer jsonb;
  v_index integer := 0;
begin
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then raise exception 'idempotency_key_required'; end if;
  if jsonb_typeof(p_offers) <> 'array' or jsonb_array_length(p_offers) not between 1 and 10 then raise exception 'invalid_uber_test_batch_size'; end if;
  select * into strict v_driver from public.driver_profiles where id = p_driver_profile_id and environment_id = app.current_environment_id();
  if not app.auth_has_role('console', v_driver.station_id) then raise exception 'console_station_forbidden'; end if;
  if exists (select 1 from public.audit_log where event_type = 'uber_test.batch.sent' and metadata->>'idempotency_key' = p_idempotency_key) then
    return jsonb_build_object('status','duplicate');
  end if;
  insert into public.uber_test_offer_batches(environment, driver_profile_id, created_by_profile_id)
    values ('TEST', v_driver.id, v_actor) returning id into v_batch_id;
  for v_offer in select value from jsonb_array_elements(p_offers) loop
    v_index := v_index + 1;
    insert into public.uber_test_offers(batch_id, sequence_no, service, fare_mxn, pickup, pickup_distance_km, trip_duration_minutes, trip_distance_km, rider_rating, expires_after_seconds)
    values (v_batch_id, v_index, v_offer->>'service', (v_offer->>'fare')::numeric, v_offer->>'pickup', (v_offer->>'pickupDistanceKm')::numeric, (v_offer->>'tripDurationMinutes')::numeric, (v_offer->>'tripDistanceKm')::numeric, nullif(v_offer->>'riderRating','')::numeric, coalesce((v_offer->>'expiresAfterSeconds')::smallint,15));
  end loop;
  if exists (select 1 from public.shifts where driver_profile_id = v_driver.id and status = 'open' and environment_id = v_driver.environment_id) then
    insert into public.uber_test_copilot_dispatches(batch_id, driver_profile_id, input_payload)
      values (v_batch_id, v_driver.id, jsonb_build_object('kind','uber_test.offer_batch','environment','TEST','batchId',v_batch_id,'offers',p_offers,'turno','open'));
  end if;
  insert into public.audit_log(environment_id, actor_profile_id, station_id, event_type, entity_type, entity_id, metadata)
    values (v_driver.environment_id, v_actor, v_driver.station_id, 'uber_test.batch.sent', 'uber_test_offer_batch', v_batch_id, jsonb_build_object('idempotency_key',p_idempotency_key,'offer_count',v_index));
  return jsonb_build_object('status','sent','batch_id',v_batch_id,'offer_count',v_index);
end;
$$;
revoke all on function public.console_send_uber_test_batch(uuid,jsonb,text) from public, anon;
grant execute on function public.console_send_uber_test_batch(uuid,jsonb,text) to authenticated;

create or replace function public.record_uber_test_result(
  p_offer_id uuid,
  p_outcome text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_offer public.uber_test_offers%rowtype; v_result public.uber_test_offer_results%rowtype;
begin
  if p_idempotency_key is null or char_length(btrim(p_idempotency_key)) not between 8 and 200 then raise exception 'idempotency_key_required'; end if;
  if p_outcome not in ('accepted','discarded','expired') then raise exception 'invalid_uber_test_outcome'; end if;
  select o.* into strict v_offer from public.uber_test_offers o join public.uber_test_offer_batches b on b.id=o.batch_id join public.driver_profiles d on d.id=b.driver_profile_id where o.id=p_offer_id and d.profile_id=(select auth.uid()) and b.environment='TEST';
  insert into public.uber_test_offer_results(batch_id,offer_id,outcome,idempotency_key) values (v_offer.batch_id,v_offer.id,p_outcome,p_idempotency_key) on conflict (idempotency_key) do nothing returning * into v_result;
  if v_result.id is null then select * into strict v_result from public.uber_test_offer_results where idempotency_key=p_idempotency_key; end if;
  if (select count(*) from public.uber_test_offers where batch_id=v_offer.batch_id)=(select count(*) from public.uber_test_offer_results where batch_id=v_offer.batch_id) then update public.uber_test_offer_batches set status='completed', completed_at=now() where id=v_offer.batch_id; else update public.uber_test_offer_batches set status='active' where id=v_offer.batch_id; end if;
  return jsonb_build_object('id',v_result.id,'batch_id',v_result.batch_id,'offer_id',v_result.offer_id,'outcome',v_result.outcome);
end;
$$;
revoke all on function public.record_uber_test_result(uuid,text,text) from public, anon;
grant execute on function public.record_uber_test_result(uuid,text,text) to authenticated;

create or replace function public.driver_get_uber_test_batch()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare v_batch public.uber_test_offer_batches%rowtype; v_offers jsonb;
begin
  select b.* into v_batch
  from public.uber_test_offer_batches b
  join public.driver_profiles d on d.id=b.driver_profile_id
  where d.profile_id=(select auth.uid()) and b.environment='TEST' and b.status in ('queued','active')
  order by b.created_at asc limit 1;
  if v_batch.id is null then return null; end if;
  select coalesce(jsonb_agg(to_jsonb(o) order by o.sequence_no),'[]'::jsonb) into v_offers from public.uber_test_offers o where o.batch_id=v_batch.id;
  return jsonb_build_object('id',v_batch.id,'environment',v_batch.environment,'createdAt',v_batch.created_at,'offers',v_offers);
end;
$$;
revoke all on function public.driver_get_uber_test_batch() from public, anon;
grant execute on function public.driver_get_uber_test_batch() to authenticated;
