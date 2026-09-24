-- Corrective TEST migration: remove PL/pgSQL variable/alias ambiguity.
-- It is intentionally additive and does not rewrite migration history.
create or replace function public.resolve_uber_test_dori_context(p_offer_id uuid)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp
as $$
declare
  v_offer public.uber_test_offers%rowtype;
  v_batch public.uber_test_offer_batches%rowtype;
  v_driver public.driver_profiles%rowtype;
  v_shift public.shifts%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_params public.dori_copilot_test_vehicle_parameters%rowtype;
  v_reading public.shift_readings%rowtype;
  v_timezone text;
  v_battery numeric;
  v_input jsonb;
begin
  select uo.* into strict v_offer
    from public.uber_test_offers as uo
    join public.uber_test_offer_batches as ub on ub.id = uo.batch_id
    join public.driver_profiles as dp on dp.id = ub.driver_profile_id
   where uo.id = p_offer_id
     and ub.environment = 'TEST'
     and dp.profile_id = app.auth_profile_id();

  select ub2.* into strict v_batch
    from public.uber_test_offer_batches as ub2
   where ub2.id = v_offer.batch_id;
  select dp2.* into strict v_driver
    from public.driver_profiles as dp2
   where dp2.id = v_batch.driver_profile_id;
  select sh2.* into v_shift
    from public.shifts as sh2
   where sh2.driver_profile_id = v_driver.id
     and sh2.environment_id = v_driver.environment_id
     and sh2.status = 'open'
   order by sh2.started_at desc
   limit 1;
  if v_shift.id is null then
    return jsonb_build_object('status','no_active_shift','offer_id',v_offer.id);
  end if;

  select vh.* into strict v_vehicle
    from public.vehicles as vh
   where vh.id = v_shift.vehicle_id
     and vh.environment_id = v_shift.environment_id;
  select vp.* into v_params
    from public.dori_copilot_test_vehicle_parameters as vp
   where vp.environment_id = v_shift.environment_id
     and vp.vehicle_id = v_vehicle.id;
  if v_params.id is null then
    return jsonb_build_object('status','context_missing','reason','vehicle_parameters');
  end if;

  select sr.* into v_reading
    from public.shift_readings as sr
   where sr.shift_id = v_shift.id
   order by sr.captured_at desc, sr.id desc
   limit 1;
  v_battery := coalesce(v_reading.battery_pct, v_vehicle.battery_pct, v_shift.start_battery_pct);
  select st.timezone into v_timezone
    from public.stations as st
   where st.id = v_shift.station_id
     and st.environment_id = v_shift.environment_id;
  if v_offer.service not in ('UberX','Uber Comfort') then
    return jsonb_build_object('status','unsupported','reason','service');
  end if;
  if v_offer.pickup_minutes is null
     or v_offer.destination_to_station_km is null
     or v_offer.destination_value is null then
    return jsonb_build_object('status','context_missing','reason','offer_metadata');
  end if;

  v_input := jsonb_build_object(
    'trip', jsonb_build_object('fare',v_offer.fare_mxn,'pickupMinutes',v_offer.pickup_minutes,'pickupKm',v_offer.pickup_distance_km,'tripMinutes',v_offer.trip_duration_minutes,'tripKm',v_offer.trip_distance_km,'origin',v_offer.pickup,'destination','TEST','timestamp',now()::text,'service',v_offer.service),
    'market', jsonb_build_object('now',now()::text,'hour',extract(hour from (now() at time zone coalesce(v_timezone,'America/Mexico_City')))::int,'weekday',extract(isodow from (now() at time zone coalesce(v_timezone,'America/Mexico_City')))::int,'originZone',v_offer.pickup,'destinationZone','TEST','demand','automatic','historicalDemand',null,'forecastDemand',null,'nextWaitMinutes',null,'destinationValue',v_offer.destination_value,'repositionKm',0,'repositionMinutes',0,'traffic',jsonb_build_object(),'events',jsonb_build_object(),'weather',jsonb_build_object()),
    'vehicle', jsonb_build_object('vehicleId',v_vehicle.id,'batteryPercent',v_battery,'rangeKm',v_params.full_charge_range_km*v_battery/100,'consumptionKwhPerKm',v_params.consumption_kwh_per_km,'energyCostPerKm',v_params.energy_cost_per_km,'odometerKm',coalesce(v_reading.odometer_km,v_vehicle.odometer_km,v_shift.start_odometer_km),'distanceToStationKm',v_params.distance_to_station_km,'destinationToStationKm',v_offer.destination_to_station_km,'requiredReturnAt',v_shift.scheduled_end_at::text),
    'driver', jsonb_build_object('driverId',v_driver.profile_id,'shiftStart',v_shift.started_at::text,'shiftEnd',v_shift.scheduled_end_at::text,'remainingMinutes',greatest(0,extract(epoch from (v_shift.scheduled_end_at-now()))/60),'connectedMinutes',greatest(0,extract(epoch from (now()-v_shift.started_at))/60),'accumulatedIncome',coalesce((select sum(inc.amount_mxn) from public.incomes as inc where inc.shift_id=v_shift.id),0),'completedTrips',coalesce((select sum(inc2.trips) from public.incomes as inc2 where inc2.shift_id=v_shift.id),0)),
    'source','historical');
  return jsonb_build_object('status','ready','offer_id',v_offer.id,'batch_id',v_offer.batch_id,'driver_profile_id',v_driver.id,'environment_id',v_driver.environment_id,'station_id',v_driver.station_id,'parameter_version',v_params.parameter_version,'input',v_input);
end;
$$;

revoke all on function public.resolve_uber_test_dori_context(uuid) from public, anon;
grant execute on function public.resolve_uber_test_dori_context(uuid) to authenticated, service_role;
