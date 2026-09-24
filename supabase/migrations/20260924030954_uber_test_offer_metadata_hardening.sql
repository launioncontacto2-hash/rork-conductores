-- TEST-only hardening for the Consola UBER Test -> Copiloto contract.
-- Missing metadata must fail before a batch can become inevaluable.
alter table public.uber_test_offers
  add column if not exists pickup_minutes numeric(8,2),
  add column if not exists destination_to_station_km numeric(8,2),
  add column if not exists destination_value numeric(12,2);

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
  v_pickup_minutes numeric;
  v_destination_to_station_km numeric;
  v_destination_value numeric;
begin
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'idempotency_key_required';
  end if;
  if jsonb_typeof(p_offers) <> 'array' or jsonb_array_length(p_offers) not between 1 and 10 then
    raise exception 'invalid_uber_test_batch_size';
  end if;
  select * into strict v_driver
    from public.driver_profiles
   where id = p_driver_profile_id
     and environment_id = app.current_environment_id();
  if not app.auth_has_role('console', v_driver.station_id) then
    raise exception 'console_station_forbidden';
  end if;
  if exists (
    select 1 from public.audit_log
     where event_type = 'uber_test.batch.sent'
       and metadata->>'idempotency_key' = p_idempotency_key
  ) then
    return jsonb_build_object('status','duplicate');
  end if;

  insert into public.uber_test_offer_batches(environment, driver_profile_id, created_by_profile_id)
    values ('TEST', v_driver.id, v_actor)
    returning id into v_batch_id;

  for v_offer in select value from jsonb_array_elements(p_offers) loop
    v_index := v_index + 1;
    if v_offer->>'service' not in ('UberX', 'Uber Comfort') then
      raise exception 'unsupported_uber_test_service';
    end if;
    if coalesce(jsonb_typeof(v_offer->'pickupMinutes'), 'null') <> 'number'
       or coalesce(jsonb_typeof(v_offer->'destinationToStationKm'), 'null') <> 'number'
       or coalesce(jsonb_typeof(v_offer->'destinationValue'), 'null') <> 'number' then
      raise exception 'invalid_uber_test_copilot_metadata' using errcode = '22023';
    end if;
    begin
      v_pickup_minutes := (v_offer->>'pickupMinutes')::numeric;
      v_destination_to_station_km := (v_offer->>'destinationToStationKm')::numeric;
      v_destination_value := (v_offer->>'destinationValue')::numeric;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'invalid_uber_test_copilot_metadata' using errcode = '22023';
    end;
    if v_pickup_minutes <= 0 or v_pickup_minutes > 180
       or v_destination_to_station_km < 0 or v_destination_to_station_km > 500
       or v_destination_value < 0 or v_destination_value > 100 then
      raise exception 'invalid_uber_test_copilot_metadata' using errcode = '22023';
    end if;
    insert into public.uber_test_offers(
      batch_id, sequence_no, service, fare_mxn, pickup, pickup_distance_km,
      pickup_minutes, trip_duration_minutes, trip_distance_km, rider_rating,
      expires_after_seconds, destination_to_station_km, destination_value
    ) values (
      v_batch_id, v_index, v_offer->>'service', (v_offer->>'fare')::numeric,
      v_offer->>'pickup', (v_offer->>'pickupDistanceKm')::numeric,
      v_pickup_minutes, (v_offer->>'tripDurationMinutes')::numeric,
      (v_offer->>'tripDistanceKm')::numeric, nullif(v_offer->>'riderRating','')::numeric,
      coalesce((v_offer->>'expiresAfterSeconds')::smallint,15),
      v_destination_to_station_km, v_destination_value
    );
  end loop;
  insert into public.uber_test_offer_events(batch_id, driver_profile_id, payload)
    values (v_batch_id, v_driver.id, jsonb_build_object('kind','uber_test.offer_batch','environment','TEST','batchId',v_batch_id,'offers',p_offers));
  insert into public.audit_log(environment_id, actor_profile_id, station_id, event_type, entity_type, entity_id, metadata)
    values (v_driver.environment_id, v_actor, v_driver.station_id, 'uber_test.batch.sent', 'uber_test_offer_batch', v_batch_id, jsonb_build_object('idempotency_key',p_idempotency_key,'offer_count',v_index));
  return jsonb_build_object('status','sent','batch_id',v_batch_id,'offer_count',v_index);
end;
$$;

revoke all on function public.console_send_uber_test_batch(uuid,jsonb,text) from public, anon;
grant execute on function public.console_send_uber_test_batch(uuid,jsonb,text) to authenticated;
