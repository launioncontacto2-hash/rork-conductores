-- GATE Puebla: reconcile verified live TEST behavior into versioned history.
-- Source effects were verified against Supabase TEST before being consolidated here.

-- Forward-only TEST correction: reject stale open shifts before economic evaluation.
-- The canonical engine remains strict; this migration normalizes its producer.
create or replace function public.resolve_uber_test_dori_context(p_offer_id uuid)
returns jsonb language plpgsql security definer
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
  v_now timestamptz;
  v_iso text;
  v_shift_start text;
  v_shift_end text;
  v_local_ts timestamp;
  v_offset_minutes integer;
  v_offset_sign text;
  battery numeric;
  input jsonb;
begin
  select offer_row.* into strict o
    from public.uber_test_offers offer_row
    join public.uber_test_offer_batches b0 on b0.id=offer_row.batch_id
    join public.driver_profiles d0 on d0.id=b0.driver_profile_id
   where offer_row.id=p_offer_id and b0.environment='TEST' and d0.profile_id=app.auth_profile_id();
  select * into strict b from public.uber_test_offer_batches where id=o.batch_id;
  select * into strict d from public.driver_profiles where id=b.driver_profile_id;
  select * into sh from public.shifts
   where driver_profile_id=d.id and environment_id=d.environment_id and status='open'
   order by started_at desc limit 1;
  if sh.id is null then return jsonb_build_object('status','no_active_shift','offer_id',o.id); end if;
  -- A stale row marked open is not an operationally valid shift. Use the
  -- simulated environment clock so TEST remains deterministic, while preserving
  -- the existing economic engine and schedule rules.
  v_now := app.env_now(d.environment_id);
  if v_now < sh.started_at then
    return jsonb_build_object('status','shift_not_current','reason','shift_not_started','offer_id',o.id);
  end if;
  if v_now >= sh.scheduled_end_at then
    return jsonb_build_object('status','shift_not_current','reason','shift_expired','offer_id',o.id);
  end if;
  select * into strict v from public.vehicles where id=sh.vehicle_id and environment_id=sh.environment_id;
  select * into p from public.dori_copilot_test_vehicle_parameters
   where environment_id=sh.environment_id and vehicle_id=v.id;
  if p.id is null then return jsonb_build_object('status','context_missing','reason','vehicle_parameters'); end if;
  select * into r from public.shift_readings where shift_id=sh.id order by captured_at desc, id desc limit 1;
  battery := coalesce(r.battery_pct, v.battery_pct, sh.start_battery_pct);
  tz := (select timezone from public.stations where id=sh.station_id and environment_id=sh.environment_id);
  if o.service not in ('UberX','Uber Comfort') then return jsonb_build_object('status','unsupported','reason','service'); end if;
  if o.pickup_minutes is null or o.destination_to_station_km is null or o.destination_value is null then
    return jsonb_build_object('status','context_missing','reason','offer_metadata');
  end if;
  v_now := app.env_now(d.environment_id);
  -- Format the local wall-clock and its offset explicitly.  Do not rely on
  -- the database connection timezone or on to_char(... OF), which inserts a
  -- space and can produce a non-canonical offset for the engine contract.
  v_local_ts := v_now at time zone coalesce(tz,'America/Mexico_City');
  v_offset_minutes := round(extract(epoch from
    (v_local_ts - (v_now at time zone 'UTC')))/60)::integer;
  v_offset_sign := case when v_offset_minutes < 0 then '-' else '+' end;
  v_iso := to_char(v_local_ts, 'YYYY-MM-DD"T"HH24:MI:SS.MS') || v_offset_sign ||
    lpad((abs(v_offset_minutes)/60)::text, 2, '0') || ':' ||
    lpad((abs(v_offset_minutes)%60)::text, 2, '0');

  v_local_ts := sh.started_at at time zone coalesce(tz,'America/Mexico_City');
  v_offset_minutes := round(extract(epoch from
    (v_local_ts - (sh.started_at at time zone 'UTC')))/60)::integer;
  v_offset_sign := case when v_offset_minutes < 0 then '-' else '+' end;
  v_shift_start := to_char(v_local_ts, 'YYYY-MM-DD"T"HH24:MI:SS.MS') || v_offset_sign ||
    lpad((abs(v_offset_minutes)/60)::text, 2, '0') || ':' ||
    lpad((abs(v_offset_minutes)%60)::text, 2, '0');

  v_local_ts := sh.scheduled_end_at at time zone coalesce(tz,'America/Mexico_City');
  v_offset_minutes := round(extract(epoch from
    (v_local_ts - (sh.scheduled_end_at at time zone 'UTC')))/60)::integer;
  v_offset_sign := case when v_offset_minutes < 0 then '-' else '+' end;
  v_shift_end := to_char(v_local_ts, 'YYYY-MM-DD"T"HH24:MI:SS.MS') || v_offset_sign ||
    lpad((abs(v_offset_minutes)/60)::text, 2, '0') || ':' ||
    lpad((abs(v_offset_minutes)%60)::text, 2, '0');
  input := jsonb_build_object(
    'trip', jsonb_build_object('fare',o.fare_mxn,'pickupMinutes',o.pickup_minutes,'pickupKm',o.pickup_distance_km,'tripMinutes',o.trip_duration_minutes,'tripKm',o.trip_distance_km,'origin',o.pickup,'destination','TEST','timestamp',v_iso,'service',o.service),
    'market', jsonb_build_object('now',v_iso,'hour',extract(hour from (v_now at time zone coalesce(tz,'America/Mexico_City')))::int,'weekday',extract(isodow from (v_now at time zone coalesce(tz,'America/Mexico_City')))::int,'originZone',o.pickup,'destinationZone','TEST','demand','automatic','historicalDemand',null,'forecastDemand',null,'nextWaitMinutes',0,'destinationValue',o.destination_value,'repositionKm',0,'repositionMinutes',0,'traffic',jsonb_build_object(),'events',jsonb_build_object(),'weather',jsonb_build_object()),
    'vehicle', jsonb_build_object('vehicleId',v.id,'batteryPercent',battery,'rangeKm',p.full_charge_range_km*battery/100,'consumptionKwhPerKm',p.consumption_kwh_per_km,'energyCostPerKm',p.energy_cost_per_km,'odometerKm',coalesce(r.odometer_km,v.odometer_km,sh.start_odometer_km),'distanceToStationKm',p.distance_to_station_km,'destinationToStationKm',o.destination_to_station_km,'requiredReturnAt',v_shift_end),
    'driver', jsonb_build_object('driverId',d.profile_id,'shiftStart',v_shift_start,'shiftEnd',v_shift_end,'remainingMinutes',greatest(0,extract(epoch from (sh.scheduled_end_at-v_now))/60),'connectedMinutes',greatest(0,extract(epoch from (v_now-sh.started_at))/60),'accumulatedIncome',coalesce((select sum(i.amount_mxn) from public.incomes i where i.shift_id=sh.id),0),'completedTrips',coalesce((select sum(i.trips) from public.incomes i where i.shift_id=sh.id),0)),
    'source','simulated');
  return jsonb_build_object('status','ready','offer_id',o.id,'batch_id',o.batch_id,'driver_profile_id',d.id,'environment_id',d.environment_id,'station_id',d.station_id,'parameter_version',p.parameter_version,'input',input);
end;
$$;

revoke all on function public.resolve_uber_test_dori_context(uuid) from public, anon;
grant execute on function public.resolve_uber_test_dori_context(uuid) to authenticated, service_role;

-- TEST-only forward correction: link state is based on a valid identity,
-- active shift and non-revoked device. Heartbeat freshness is telemetry,
-- not the authority for an all-day active link.
create or replace function public.get_dori_copilot_link_status()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare
  v_environment uuid := app.current_environment_id();
  v_profile uuid := app.auth_profile_id();
  v_now timestamptz;
  v_has_device boolean;
  v_has_shift boolean;
begin
  if v_environment is null or v_profile is null or app.auth_session_id() is null then
    return jsonb_build_object('status','waiting');
  end if;
  if not exists (select 1 from public.environments e where e.id=v_environment and lower(e.code)='test') then
    return jsonb_build_object('status','waiting','environment_id',v_environment,'profile_id',v_profile);
  end if;
  v_now := app.env_now(v_environment);
  select exists (
    select 1 from public.dori_copilot_push_devices d
    where d.environment_id=v_environment and d.profile_id=v_profile and d.status='active'
  ) into v_has_device;
  select exists (
    select 1
    from public.driver_profiles dp
    join public.shifts s on s.driver_profile_id=dp.id and s.environment_id=v_environment
    where dp.profile_id=v_profile and dp.environment_id=v_environment and dp.status='active'
      and s.status='open' and s.started_at <= v_now and s.scheduled_end_at > v_now
  ) into v_has_shift;
  return jsonb_build_object(
    'status', case when v_has_device and v_has_shift then 'linked' when v_has_device then 'interrupted' else 'waiting' end,
    'environment_id',v_environment,'profile_id',v_profile,
    'active_shift',v_has_shift,'active_device',v_has_device
  );
end;
$$;
revoke all on function public.get_dori_copilot_link_status() from public, anon;
grant execute on function public.get_dori_copilot_link_status() to authenticated;

-- TEST-only forward correction: Realtime postgres_changes evaluates the
-- subscriber's SELECT policy. Resolve the conductor through the canonical
-- profile identity instead of comparing driver_profiles.profile_id to the
-- auth user UUID directly.
drop policy if exists uber_test_batch_driver_read on public.uber_test_offer_batches;
create policy uber_test_batch_driver_read on public.uber_test_offer_batches
for select to authenticated
using (
  exists (
    select 1 from public.driver_profiles d
    where d.id = driver_profile_id
      and d.profile_id = app.auth_profile_id()
  )
);

drop policy if exists uber_test_offer_driver_read on public.uber_test_offers;
create policy uber_test_offer_driver_read on public.uber_test_offers
for select to authenticated
using (
  exists (
    select 1
    from public.uber_test_offer_batches b
    join public.driver_profiles d on d.id = b.driver_profile_id
    where b.id = batch_id
      and d.profile_id = app.auth_profile_id()
  )
);

drop policy if exists uber_test_result_driver_read on public.uber_test_offer_results;
create policy uber_test_result_driver_read on public.uber_test_offer_results
for select to authenticated
using (
  exists (
    select 1
    from public.uber_test_offer_batches b
    join public.driver_profiles d on d.id = b.driver_profile_id
    where b.id = batch_id
      and d.profile_id = app.auth_profile_id()
  )
);

drop policy if exists uber_test_event_driver_read on public.uber_test_offer_events;
create policy uber_test_event_driver_read on public.uber_test_offer_events
for select to authenticated
using (
  exists (
    select 1 from public.driver_profiles d
    where d.id = driver_profile_id
      and d.profile_id = app.auth_profile_id()
  )
);

drop policy if exists uber_test_result_driver_insert on public.uber_test_offer_results;
create policy uber_test_result_driver_insert on public.uber_test_offer_results
for insert to authenticated
with check (
  exists (
    select 1
    from public.uber_test_offer_batches b
    join public.driver_profiles d on d.id = b.driver_profile_id
    where b.id = batch_id
      and d.profile_id = app.auth_profile_id()
      and b.environment = 'TEST'
  )
);
