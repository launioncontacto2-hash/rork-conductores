drop policy if exists uber_test_driver_broadcast_read on realtime.messages;

create policy uber_test_driver_broadcast_read
on realtime.messages
for select
to authenticated
using (
  extension = 'broadcast'
  and realtime.topic() = 'uber-test-driver:' || app.auth_profile_id()::text
);

create or replace function app.broadcast_uber_test_offer_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app, realtime, pg_temp
as $$
declare
  v_profile_id uuid;
begin
  select d.profile_id into v_profile_id
  from public.driver_profiles d
  where d.id = new.driver_profile_id;

  if v_profile_id is not null then
    perform realtime.send(
      jsonb_build_object('batchId', new.batch_id::text, 'eventId', new.id::text),
      'offer-insert',
      'uber-test-driver:' || v_profile_id::text,
      true
    );
  end if;
  return new;
end;
$$;

revoke execute on function app.broadcast_uber_test_offer_event() from public, anon, authenticated;

drop trigger if exists uber_test_offer_event_broadcast on public.uber_test_offer_events;
create trigger uber_test_offer_event_broadcast
after insert on public.uber_test_offer_events
for each row execute function app.broadcast_uber_test_offer_event();
