-- TEST only. Apply immediately before the physical Puebla Gate run.
-- Preconditions: DMP-002 and DMP-003 are physically at the station.
begin;

update public.dori_copilot_test_vehicle_parameters p
set parameter_version = 'gate-puebla-station-v1',
    distance_to_station_km = 0
from public.vehicles v, public.environments e
where p.vehicle_id = v.id
  and p.environment_id = e.id
  and v.environment_id = e.id
  and e.code = 'test'
  and v.operational_code in ('DMP-002','DMP-003');

do $$
begin
  if (select count(*) from public.dori_copilot_test_vehicle_parameters p
      join public.vehicles v on v.id=p.vehicle_id
      join public.environments e on e.id=p.environment_id
      where e.code='test' and v.operational_code in ('DMP-002','DMP-003')
        and p.parameter_version='gate-puebla-station-v1'
        and p.distance_to_station_km=0) <> 2 then
    raise exception 'Gate Puebla station distance fixture incomplete';
  end if;
end $$;

commit;