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
