-- UBER Test -> DORI evaluation bridge. TEST-only and additive.
-- Context is resolved from the driver's open shift and versioned TEST vehicle
-- parameters; the offer remains the sole source of offer economics.

alter table public.uber_test_offers
  add column if not exists pickup_minutes numeric(8,2),
  add column if not exists destination_to_station_km numeric(8,2),
  add column if not exists destination_value numeric(12,2);

alter table public.dori_decision_events add column if not exists offer_id uuid;
create unique index if not exists dori_decision_offer_unique on public.dori_decision_events(offer_id) where offer_id is not null;
create or replace function app.attach_uber_test_offer_to_dori_event()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, app, pg_temp as $$
begin
  if NEW.event_payload ? 'offerId' then NEW.offer_id := (NEW.event_payload ->> 'offerId')::uuid; end if;
  return NEW;
end; $$;
drop trigger if exists dori_decision_uber_offer_link on public.dori_decision_events;
create trigger dori_decision_uber_offer_link before insert on public.dori_decision_events for each row execute function app.attach_uber_test_offer_to_dori_event();

create table if not exists public.dori_copilot_test_vehicle_parameters (
  id uuid primary key default gen_random_uuid(),
  environment_id uuid not null references public.environments(id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  parameter_version text not null,
  full_charge_range_km numeric(8,2) not null check (full_charge_range_km > 0),
  consumption_kwh_per_km numeric(8,4) not null check (consumption_kwh_per_km > 0),
  energy_cost_per_km numeric(8,4) not null check (energy_cost_per_km >= 0),
  distance_to_station_km numeric(8,2) not null check (distance_to_station_km >= 0),
  created_at timestamptz not null default now(),
  unique(environment_id, vehicle_id),
  unique(id, environment_id)
);

alter table public.dori_copilot_test_vehicle_parameters enable row level security;
revoke all on public.dori_copilot_test_vehicle_parameters from public, anon, authenticated;
grant all on public.dori_copilot_test_vehicle_parameters to postgres, service_role;

create or replace function public.resolve_uber_test_dori_context(p_offer_id uuid)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare
  o public.uber_test_offers%rowtype;
  b public.uber_test_offer_batches%rowtype;
  d public.driver_profiles%rowtype;
  sh public.shifts%rowtype;
  v public.vehicles%rowtype;
  p public.dori_copilot_test_vehicle_parameters%rowtype;
  r public.shift_readings%rowtype;
  tz text;
  now_local timestamptz;
  battery numeric;
  input jsonb;
begin
  select o.* into strict o from public.uber_test_offers o
    join public.uber_test_offer_batches b0 on b0.id=o.batch_id
    join public.driver_profiles d0 on d0.id=b0.driver_profile_id
   where o.id=p_offer_id and b0.environment='TEST' and d0.profile_id=app.auth_profile_id();
  select * into strict b from public.uber_test_offer_batches where id=o.batch_id;
  select * into strict d from public.driver_profiles where id=b.driver_profile_id;
  select * into sh from public.shifts where driver_profile_id=d.id and environment_id=d.environment_id and status='open' order by started_at desc limit 1;
  if sh.id is null then return jsonb_build_object('status','no_active_shift','offer_id',o.id); end if;
  select * into strict v from public.vehicles where id=sh.vehicle_id and environment_id=sh.environment_id;
  select * into p from public.dori_copilot_test_vehicle_parameters where environment_id=sh.environment_id and vehicle_id=v.id;
  if p.id is null then return jsonb_build_object('status','context_missing','reason','vehicle_parameters'); end if;
  select * into r from public.shift_readings where shift_id=sh.id order by captured_at desc, id desc limit 1;
  battery := coalesce(r.battery_pct, v.battery_pct, sh.start_battery_pct);
  tz := (select timezone from public.stations where id=sh.station_id and environment_id=sh.environment_id);
  now_local := now() at time zone coalesce(tz,'America/Mexico_City');
  if o.service not in ('UberX','Uber Comfort') then return jsonb_build_object('status','unsupported','reason','service'); end if;
  if o.pickup_minutes is null or o.destination_to_station_km is null or o.destination_value is null then
    return jsonb_build_object('status','context_missing','reason','offer_metadata');
  end if;
  input := jsonb_build_object(
    'trip', jsonb_build_object('fare',o.fare_mxn,'pickupMinutes',o.pickup_minutes,'pickupKm',o.pickup_distance_km,'tripMinutes',o.trip_duration_minutes,'tripKm',o.trip_distance_km,'origin',o.pickup,'destination','TEST','timestamp',now()::text,'service',o.service),
    'market', jsonb_build_object('now',now()::text,'hour',extract(hour from now_local)::int,'weekday',extract(isodow from now_local)::int,'originZone',o.pickup,'destinationZone','TEST','demand','automatic','historicalDemand',null,'forecastDemand',null,'nextWaitMinutes',null,'destinationValue',o.destination_value,'repositionKm',0,'repositionMinutes',0,'traffic',jsonb_build_object(),'events',jsonb_build_object(),'weather',jsonb_build_object()),
    'vehicle', jsonb_build_object('vehicleId',v.id,'batteryPercent',battery,'rangeKm',p.full_charge_range_km*battery/100,'consumptionKwhPerKm',p.consumption_kwh_per_km,'energyCostPerKm',p.energy_cost_per_km,'odometerKm',coalesce(r.odometer_km,v.odometer_km,sh.start_odometer_km),'distanceToStationKm',p.distance_to_station_km,'destinationToStationKm',o.destination_to_station_km,'requiredReturnAt',sh.scheduled_end_at::text),
    'driver', jsonb_build_object('driverId',d.profile_id,'shiftStart',sh.started_at::text,'shiftEnd',sh.scheduled_end_at::text,'remainingMinutes',greatest(0,extract(epoch from (sh.scheduled_end_at-now()))/60),'connectedMinutes',greatest(0,extract(epoch from (now()-sh.started_at))/60),'accumulatedIncome',coalesce((select sum(i.amount_mxn) from public.incomes i where i.shift_id=sh.id),0),'completedTrips',coalesce((select sum(i.trips) from public.incomes i where i.shift_id=sh.id),0)),
    'source','historical');
  return jsonb_build_object('status','ready','offer_id',o.id,'batch_id',o.batch_id,'driver_profile_id',d.id,'environment_id',d.environment_id,'station_id',d.station_id,'parameter_version',p.parameter_version,'input',input);
end;
$$;

revoke all on function public.resolve_uber_test_dori_context(uuid) from public, anon;
grant execute on function public.resolve_uber_test_dori_context(uuid) to authenticated, service_role;

comment on table public.dori_copilot_test_vehicle_parameters is 'TEST-only, versioned vehicle context for DORI Copiloto; never client supplied.';

create or replace function public.console_send_uber_test_batch(
  p_driver_profile_id uuid, p_offers jsonb, p_idempotency_key text
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp as $$
declare d public.driver_profiles%rowtype; bid uuid; item jsonb; n integer := 0; actor uuid := app.auth_profile_id();
begin
  if jsonb_typeof(p_offers) <> 'array' or jsonb_array_length(p_offers) not between 1 and 10 then raise exception 'invalid_uber_test_batch_size'; end if;
  select * into strict d from public.driver_profiles where id=p_driver_profile_id and environment_id=app.current_environment_id();
  if not app.auth_has_role('console',d.station_id) then raise exception 'console_station_forbidden' using errcode='42501'; end if;
  if exists(select 1 from public.audit_log where event_type='uber_test.batch.sent' and metadata->>'idempotency_key'=p_idempotency_key) then return jsonb_build_object('status','duplicate'); end if;
  insert into public.uber_test_offer_batches(environment,driver_profile_id,created_by_profile_id) values('TEST',d.id,actor) returning id into bid;
  for item in select value from jsonb_array_elements(p_offers) loop
    n:=n+1;
    if item->>'service' not in ('UberX','Uber Comfort') then raise exception 'unsupported_uber_test_service'; end if;
    insert into public.uber_test_offers(batch_id,sequence_no,service,fare_mxn,pickup,pickup_distance_km,pickup_minutes,trip_duration_minutes,trip_distance_km,rider_rating,expires_after_seconds,destination_to_station_km,destination_value)
    values(bid,n,item->>'service',(item->>'fare')::numeric,item->>'pickup',(item->>'pickupDistanceKm')::numeric,(item->>'pickupMinutes')::numeric,(item->>'tripDurationMinutes')::numeric,(item->>'tripDistanceKm')::numeric,nullif(item->>'riderRating','')::numeric,coalesce((item->>'expiresAfterSeconds')::smallint,15),(item->>'destinationToStationKm')::numeric,(item->>'destinationValue')::numeric);
  end loop;
  insert into public.uber_test_offer_events(batch_id,driver_profile_id,payload) values(bid,d.id,jsonb_build_object('kind','uber_test.offer_batch','environment','TEST','batchId',bid,'offers',p_offers));
  insert into public.audit_log(environment_id,actor_profile_id,station_id,event_type,entity_type,entity_id,metadata) values(d.environment_id,actor,d.station_id,'uber_test.batch.sent','uber_test_offer_batch',bid,jsonb_build_object('idempotency_key',p_idempotency_key,'offer_count',n));
  return jsonb_build_object('status','sent','batch_id',bid,'offer_count',n);
end; $$;
revoke all on function public.console_send_uber_test_batch(uuid,jsonb,text) from public,anon;
grant execute on function public.console_send_uber_test_batch(uuid,jsonb,text) to authenticated;

create or replace function public.driver_get_uber_test_batch()
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp as $$
declare v_batch public.uber_test_offer_batches%rowtype; offers jsonb; e public.uber_test_offer_events%rowtype; presented jsonb;
begin
 select b.* into v_batch from public.uber_test_offer_batches b join public.driver_profiles d on d.id=b.driver_profile_id where d.profile_id=app.auth_profile_id() and b.environment='TEST' and b.status in ('queued','active') order by b.created_at asc limit 1;
 if v_batch.id is null then return null; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'service',o.service,'fare',o.fare_mxn,'currency','MXN','pickup',o.pickup,'pickupDistanceKm',o.pickup_distance_km,'pickupMinutes',o.pickup_minutes,'tripDurationMinutes',o.trip_duration_minutes,'tripDistanceKm',o.trip_distance_km,'riderRating',o.rider_rating,'expiresAfterSeconds',o.expires_after_seconds) order by o.sequence_no),'[]'::jsonb) into offers from public.uber_test_offers o where o.batch_id=v_batch.id;
 select * into e from public.uber_test_offer_events where batch_id=v_batch.id for update;
 if e.presented_offer_id is null then presented:=public.present_next_uber_test_offer(v_batch.id); else select jsonb_build_object('status','already_presented','offer',to_jsonb(o)) into presented from public.uber_test_offers o where o.id=e.presented_offer_id; end if;
 return jsonb_build_object('id',v_batch.id,'environment',v_batch.environment,'createdAt',v_batch.created_at,'offers',offers,'presented',coalesce(presented->'offer','null'::jsonb),'presentationStatus',presented->>'status');
end; $$;
revoke all on function public.driver_get_uber_test_batch() from public,anon;
grant execute on function public.driver_get_uber_test_batch() to authenticated;
