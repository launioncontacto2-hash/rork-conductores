-- Corrective TEST-only contract for Uber Test -> DORI Copiloto.
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
  select o.* into strict o
    from public.uber_test_offers o
    join public.uber_test_offer_batches b0 on b0.id=o.batch_id
    join public.driver_profiles d0 on d0.id=b0.driver_profile_id
   where o.id=p_offer_id and b0.environment='TEST' and d0.profile_id=app.auth_profile_id();
  select * into strict b from public.uber_test_offer_batches where id=o.batch_id;
  select * into strict d from public.driver_profiles where id=b.driver_profile_id;
  select * into sh from public.shifts
   where driver_profile_id=d.id and environment_id=d.environment_id and status='open'
   order by started_at desc limit 1;
  if sh.id is null then return jsonb_build_object('status','no_active_shift','offer_id',o.id); end if;
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
    'source','historical');
  return jsonb_build_object('status','ready','offer_id',o.id,'batch_id',o.batch_id,'driver_profile_id',d.id,'environment_id',d.environment_id,'station_id',d.station_id,'parameter_version',p.parameter_version,'input',input);
end;
$$;

revoke all on function public.resolve_uber_test_dori_context(uuid) from public, anon;
grant execute on function public.resolve_uber_test_dori_context(uuid) to authenticated, service_role;
