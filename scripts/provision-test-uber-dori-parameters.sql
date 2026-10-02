-- Local/TEST fixture only. It never creates vehicles or changes production.
-- Values are explicit laboratory parameters, versioned and outside UBER Test input.
begin;

insert into public.dori_copilot_test_vehicle_parameters(
  environment_id, vehicle_id, parameter_version,
  full_charge_range_km, consumption_kwh_per_km,
  energy_cost_per_km, distance_to_station_km
)
select e.id, v.id, 'uber-test-v1', 220.00, 0.1800, 3.2000, 8.00
from public.environments e
join public.vehicles v on v.environment_id = e.id
where e.code = 'test'
on conflict (environment_id, vehicle_id) do update set
  parameter_version = excluded.parameter_version,
  full_charge_range_km = excluded.full_charge_range_km,
  consumption_kwh_per_km = excluded.consumption_kwh_per_km,
  energy_cost_per_km = excluded.energy_cost_per_km,
  distance_to_station_km = excluded.distance_to_station_km;

do $$
begin
  if not exists (
    select 1 from public.dori_copilot_test_vehicle_parameters p
    join public.environments e on e.id = p.environment_id
    where e.code = 'test'
  ) then
    raise exception 'TEST vehicle parameters were not provisioned';
  end if;
end $$;

commit;
