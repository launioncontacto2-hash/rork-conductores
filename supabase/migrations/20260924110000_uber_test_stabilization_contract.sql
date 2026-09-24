-- Stabilization contract for TEST Uber -> DORI bridge.
-- TEST only; preserves existing live/event contracts.
create or replace function public.register_dori_copilot_push_device(p_device_token text, p_bundle_id text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp as $$
declare env uuid := app.current_environment_id(); profile uuid := app.auth_profile_id();
begin
  if env is null or profile is null or not exists (select 1 from public.environments e where e.id=env and lower(e.code)='test') then
    raise exception 'test_environment_required' using errcode='42501';
  end if;
  if not exists (select 1 from public.driver_profiles d where d.profile_id=profile and d.environment_id=env and d.status='active') then
    raise exception 'active_driver_required' using errcode='42501';
  end if;
  if not exists (select 1 from public.driver_profiles d join public.shifts sh on sh.driver_profile_id=d.id and sh.environment_id=env where d.profile_id=profile and sh.status='open') then
    raise exception 'active_shift_required' using errcode='42501';
  end if;
  if p_device_token is null or p_device_token !~ '^[0-9a-fA-F]{64,200}$' or coalesce(btrim(p_bundle_id),'')='' then raise exception 'invalid_device_registration' using errcode='22023'; end if;
  insert into public.dori_copilot_push_devices(environment_id,profile_id,device_token,bundle_id)
  values(env,profile,lower(p_device_token),btrim(p_bundle_id))
  on conflict(environment_id,profile_id,device_token,bundle_id) do update set status='active',updated_at=now();
  return jsonb_build_object('status','registered','environment_id',env,'bundle_id',btrim(p_bundle_id));
end; $$;
revoke all on function public.register_dori_copilot_push_device(text,text) from public,anon;
grant execute on function public.register_dori_copilot_push_device(text,text) to authenticated;

-- The receiver-bound overload is canonical; remove the legacy bypass.
revoke all on function public.driver_get_uber_test_batch() from public, anon, authenticated;
drop function if exists public.driver_get_uber_test_batch();

create or replace function public.record_uber_test_result(
  p_offer_id uuid, p_outcome text, p_idempotency_key text
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app, auth, pg_temp as $$
declare v_offer public.uber_test_offers%rowtype; v_result public.uber_test_offer_results%rowtype; v_next uuid;
begin
  if p_idempotency_key is null or char_length(btrim(p_idempotency_key)) not between 8 and 200 then raise exception 'idempotency_key_required'; end if;
  if p_outcome not in ('accepted','discarded','expired') then raise exception 'invalid_uber_test_outcome'; end if;
  select o.* into strict v_offer from public.uber_test_offers o join public.uber_test_offer_batches b on b.id=o.batch_id join public.driver_profiles d on d.id=b.driver_profile_id
   where o.id=p_offer_id and d.profile_id=app.auth_profile_id() and b.environment='TEST';
  select * into v_result from public.uber_test_offer_results where offer_id=p_offer_id;
  if v_result.id is not null then
    if v_result.outcome <> p_outcome or v_result.idempotency_key <> p_idempotency_key then
      return jsonb_build_object('status','conflict','error','offer_already_resolved','offer_id',p_offer_id,'result',jsonb_build_object('id',v_result.id,'outcome',v_result.outcome,'idempotency_key',v_result.idempotency_key));
    end if;
    return jsonb_build_object('status','idempotent','id',v_result.id,'batch_id',v_result.batch_id,'offer_id',v_result.offer_id,'outcome',v_result.outcome,'next_offer_id',null);
  end if;
  select * into v_result from public.uber_test_offer_results where idempotency_key=p_idempotency_key;
  if v_result.id is not null then
    return jsonb_build_object('status','conflict','error','idempotency_key_conflict','offer_id',p_offer_id,'result_id',v_result.id);
  end if;
  insert into public.uber_test_offer_results(batch_id,offer_id,outcome,idempotency_key)
    values(v_offer.batch_id,v_offer.id,p_outcome,p_idempotency_key) returning * into v_result;
  if (select count(*) from public.uber_test_offers where batch_id=v_offer.batch_id)=(select count(*) from public.uber_test_offer_results where batch_id=v_offer.batch_id) then
    update public.uber_test_offer_batches set status='completed',completed_at=now() where id=v_offer.batch_id;
  else
    update public.uber_test_offer_batches set status='active' where id=v_offer.batch_id;
    select o.id into v_next from public.uber_test_offers o where o.batch_id=v_offer.batch_id and not exists(select 1 from public.uber_test_offer_results r where r.offer_id=o.id) order by o.sequence_no asc limit 1;
  end if;
  return jsonb_build_object('status','recorded','id',v_result.id,'batch_id',v_result.batch_id,'offer_id',v_result.offer_id,'outcome',v_result.outcome,'next_offer_id',v_next);
end; $$;
revoke all on function public.record_uber_test_result(uuid,text,text) from public,anon;
grant execute on function public.record_uber_test_result(uuid,text,text) to authenticated;