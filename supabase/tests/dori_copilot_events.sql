BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(34);

SELECT has_table('public', 'dori_decision_events', 'existe el registro de decisiones');
SELECT has_table('public', 'dori_outcome_events', 'existe el registro de resultados');
SELECT has_function('public', 'record_dori_decision_event', ARRAY['uuid','text','jsonb'], 'existe RPC interno de decisiones');
SELECT has_function('public', 'record_dori_outcome_event', ARRAY['uuid','text','jsonb'], 'existe RPC interno de resultados');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.dori_decision_events'::regclass), 'RLS activo en decisiones');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.dori_outcome_events'::regclass), 'RLS activo en resultados');
SELECT ok(NOT has_table_privilege('anon','public.dori_decision_events','SELECT') AND NOT has_table_privilege('anon','public.dori_outcome_events','SELECT'), 'anon no lee eventos');
SELECT ok(has_table_privilege('authenticated','public.dori_decision_events','SELECT') AND has_table_privilege('authenticated','public.dori_outcome_events','SELECT'), 'authenticated puede leer bajo RLS');
SELECT ok(NOT has_table_privilege('authenticated','public.dori_decision_events','INSERT, UPDATE, DELETE') AND NOT has_table_privilege('authenticated','public.dori_outcome_events','INSERT, UPDATE, DELETE'), 'authenticated no escribe eventos directamente');
SELECT ok(NOT has_function_privilege('authenticated','public.record_dori_decision_event(uuid,text,jsonb)','EXECUTE') AND NOT has_function_privilege('authenticated','public.record_dori_outcome_event(uuid,text,jsonb)','EXECUTE'), 'cliente autenticado no ejecuta RPC internos');
SELECT ok(NOT has_function_privilege('anon','public.record_dori_decision_event(uuid,text,jsonb)','EXECUTE') AND NOT has_function_privilege('anon','public.record_dori_outcome_event(uuid,text,jsonb)','EXECUTE'), 'anon no ejecuta RPC internos');
SELECT ok(has_function_privilege('service_role','public.record_dori_decision_event(uuid,text,jsonb)','EXECUTE') AND has_function_privilege('service_role','public.record_dori_outcome_event(uuid,text,jsonb)','EXECUTE'), 'solo backend puede ejecutar RPC');
SELECT ok(NOT has_table_privilege('service_role','public.dori_decision_events','INSERT, UPDATE, DELETE') AND NOT has_table_privilege('service_role','public.dori_outcome_events','INSERT, UPDATE, DELETE'), 'service_role tampoco evita los RPC para escribir');

INSERT INTO public.stations(id,environment_id,region_id,code,name,status,timezone)
SELECT '16030000-0000-4000-8000-000000000001',r.environment_id,r.id,'dori-events-test','DORI Events Test','active','America/Mexico_City'
FROM public.regions r ORDER BY r.created_at,r.id LIMIT 1;
CREATE TEMP TABLE test_dori_scope AS
SELECT environment_id,id station_id FROM public.stations WHERE id='16030000-0000-4000-8000-000000000001';
GRANT SELECT ON TABLE test_dori_scope TO authenticated;
UPDATE app.env_clock c SET is_simulated=true,anchor_logical_at='2026-09-08 18:00:00+00',anchor_real_at=now(),speed=1,is_paused=true
FROM test_dori_scope s WHERE c.environment_id=s.environment_id;

INSERT INTO auth.users(id,email) VALUES
('16090000-0000-4000-8000-000000000001','dori.driver.1@test.invalid'),
('16090000-0000-4000-8000-000000000002','dori.driver.2@test.invalid'),
('16090000-0000-4000-8000-000000000003','dori.supervisor@test.invalid');
INSERT INTO public.profiles(id,environment_id,auth_user_id,employee_number,display_name,status)
SELECT f.id,s.environment_id,f.auth_id,f.employee_number,f.display_name,'active' FROM test_dori_scope s CROSS JOIN (VALUES
('16000000-0000-4000-8000-000000000001'::uuid,'16090000-0000-4000-8000-000000000001'::uuid,'DORI-DRIVER-1','DORI Driver 1'),
('16000000-0000-4000-8000-000000000002'::uuid,'16090000-0000-4000-8000-000000000002'::uuid,'DORI-DRIVER-2','DORI Driver 2'),
('16000000-0000-4000-8000-000000000003'::uuid,'16090000-0000-4000-8000-000000000003'::uuid,'DORI-SUPERVISOR','DORI Supervisor')
) f(id,auth_id,employee_number,display_name);
INSERT INTO public.staff_memberships(id,environment_id,profile_id,station_id,role,starts_at,shift_group,shift_slot)
SELECT f.id,s.environment_id,f.profile_id,s.station_id,f.role,'2026-01-01 00:00:00+00',f.shift_group,f.shift_slot
FROM test_dori_scope s CROSS JOIN (VALUES
('16010000-0000-4000-8000-000000000001'::uuid,'16000000-0000-4000-8000-000000000001'::uuid,'driver','weekday','morning'),
('16010000-0000-4000-8000-000000000002'::uuid,'16000000-0000-4000-8000-000000000002'::uuid,'driver','weekday','morning'),
('16010000-0000-4000-8000-000000000003'::uuid,'16000000-0000-4000-8000-000000000003'::uuid,'supervisor',NULL::text,NULL::text)
) f(id,profile_id,role,shift_group,shift_slot);
INSERT INTO public.driver_profiles(id,environment_id,station_id,profile_id,membership_id,employee_number,status)
SELECT f.id,s.environment_id,s.station_id,f.profile_id,f.membership_id,f.employee_number,'active'
FROM test_dori_scope s CROSS JOIN (VALUES
('16020000-0000-4000-8000-000000000001'::uuid,'16000000-0000-4000-8000-000000000001'::uuid,'16010000-0000-4000-8000-000000000001'::uuid,'DORI-DRIVER-1'),
('16020000-0000-4000-8000-000000000002'::uuid,'16000000-0000-4000-8000-000000000002'::uuid,'16010000-0000-4000-8000-000000000002'::uuid,'DORI-DRIVER-2')
) f(id,profile_id,membership_id,employee_number);

CREATE TEMP TABLE test_dori_events(decision jsonb,outcome jsonb);
GRANT SELECT ON TABLE test_dori_events TO service_role;
INSERT INTO test_dori_events VALUES (
$json${"schemaVersion":"1.0.0","kind":"decision","id":"16040000-0000-4000-8000-000000000001","createdAt":"2026-09-07T10:00:01-06:00","input":{"trip":{"fare":240,"pickupMinutes":4,"pickupKm":1,"tripMinutes":22,"tripKm":10,"origin":"Centro","destination":"Zona de oficinas","timestamp":"2026-09-07T10:00:00-06:00"},"market":{"now":"2026-09-07T10:00:00-06:00","hour":10,"weekday":1,"originZone":"Centro","destinationZone":"Oficinas","demand":"normal","historicalDemand":null,"forecastDemand":null,"nextWaitMinutes":8,"destinationValue":85,"repositionKm":1,"repositionMinutes":3,"traffic":null,"events":null,"weather":null},"vehicle":{"vehicleId":"simulated-vehicle","batteryPercent":80,"rangeKm":200,"consumptionKwhPerKm":0.16,"energyCostPerKm":0.6,"odometerKm":20000,"distanceToStationKm":3,"destinationToStationKm":8,"requiredReturnAt":"2026-09-07T16:00:00-06:00"},"driver":{"driverId":"16000000-0000-4000-8000-000000000001","shiftStart":"2026-09-07T08:00:00-06:00","shiftEnd":"2026-09-07T16:00:00-06:00","remainingMinutes":360,"connectedMinutes":120,"accumulatedIncome":300,"completedTrips":3},"source":"simulated"},"result":{"recommendation":"RECOMENDADO","reasons":["Buen pago para el tiempo","Buen pago para la distancia","Permite volver con margen"],"scores":{"time":100,"distance":100,"pickup":86.66666666666667,"destination":85,"operational":100},"total":95,"threshold":65,"expectedAcceptValue":218.4,"expectedRejectValue":74,"opportunityCost":-144.4,"netConnectedHourly":354.1621621621622,"connectedMinutes":37,"nextWaitMinutes":8,"demand":"normal","operationalBlocks":[],"requiredRangeKm":44,"requiredReturnMinutes":55.2,"availableMinutes":360,"nearBoundary":false,"modelVersion":"deterministic-0.1","rulesVersion":"0.1.0","parameterVersion":"mxn-lab-0.1.0","parameters":{"modelVersion":"deterministic-0.1","rulesVersion":"0.1.0","parameterVersion":"mxn-lab-0.1.0","weights":{"time":0.35,"distance":0.2,"pickup":0.15,"destination":0.2,"operational":0.1},"thresholds":{"low":58,"normal":65,"high":70},"referenceNetHourly":180,"referenceNetPerKm":12,"wearCostPerKm":1.2,"pickupLimitMinutes":30,"batteryReservePercent":10,"rangeReserveKm":10,"stationSpeedKmh":25,"returnBufferMinutes":10,"boundaryBand":3,"economicBoundaryBand":3,"maxOfferAgeSeconds":60,"alternativeNetHourly":{"low":65,"normal":120,"high":190},"destinationWaitMinutes":{"low":25,"normal":12,"high":5},"hourlyDemand":["low","low","low","low","low","low","normal","high","high","normal","normal","normal","normal","normal","normal","normal","normal","high","high","normal","normal","normal","low","low"]},"assumptions":["Valores provisionales de laboratorio","Demanda y espera simuladas; sin datos de Uber"]}}$json$::jsonb,
$json${"schemaVersion":"1.0.0","kind":"outcome","id":"16050000-0000-4000-8000-000000000001","createdAt":"2026-09-07T11:00:01-06:00","decisionId":"16040000-0000-4000-8000-000000000001","driverId":"16000000-0000-4000-8000-000000000001","source":"simulated","observation":{"observedAt":"2026-09-07T11:00:00-06:00","driverAction":"accepted","actualFare":250,"actualTripMinutes":24,"actualTripKm":11,"nextWaitMinutes":10,"nextFare":180},"predictionError":{"fare":10,"tripMinutes":2,"tripKm":1,"nextWaitMinutes":2}}$json$::jsonb
);

SET LOCAL ROLE service_role;
SELECT lives_ok($sql$ SELECT public.record_dori_decision_event('16090000-0000-4000-8000-000000000001','dori-decision-1',(SELECT decision FROM test_dori_events)) $sql$, 'backend persiste decision canonica');
RESET ROLE;
SELECT is((SELECT count(*)::bigint FROM public.dori_decision_events),1::bigint,'se persiste una decision');
SELECT results_eq($sql$ SELECT recommendation,total_score::text,threshold::text,expected_accept_value::text,expected_reject_value::text,opportunity_cost::text FROM public.dori_decision_events $sql$,$sql$ VALUES('RECOMENDADO'::text,'95'::text,'65'::text,'218.4'::text,'74'::text,'-144.4'::text) $sql$,'columnas auditables conservan calculos del motor');
SELECT is((SELECT status FROM public.command_log WHERE idempotency_key='dori-decision-1'),'completed','comando queda completado');
SELECT is((SELECT count(*)::bigint FROM public.audit_log WHERE event_type='dori.decision.recorded'),1::bigint,'decision genera auditoria');
SET LOCAL ROLE service_role;
SELECT lives_ok($sql$ SELECT public.record_dori_decision_event('16090000-0000-4000-8000-000000000001','dori-decision-1',(SELECT decision FROM test_dori_events)) $sql$, 'reintento de decision es idempotente');
RESET ROLE;
SELECT is((SELECT count(*)::bigint FROM public.dori_decision_events),1::bigint,'reintento no duplica decision');
SET LOCAL ROLE service_role;
SELECT throws_ok($sql$ SELECT public.record_dori_decision_event('16090000-0000-4000-8000-000000000001','dori-forged-rec',jsonb_set((SELECT decision FROM test_dori_events),'{result,recommendation}','"NO RECOMENDADO"')) $sql$,'22023','invalid_decision_event','RPC rechaza recomendacion contradictoria');
SELECT throws_ok($sql$ SELECT public.record_dori_decision_event('16090000-0000-4000-8000-000000000001','dori-forged-value',jsonb_set((SELECT decision FROM test_dori_events),'{result,opportunityCost}','0')) $sql$,'22023','invalid_decision_event','RPC rechaza costo de oportunidad alterado');
SELECT lives_ok($sql$ SELECT public.record_dori_outcome_event('16090000-0000-4000-8000-000000000001','dori-outcome-1',(SELECT outcome FROM test_dori_events)) $sql$,'backend persiste resultado canonico');
RESET ROLE;
SELECT results_eq($sql$ SELECT driver_action,actual_fare::text,prediction_error->>'fare' FROM public.dori_outcome_events $sql$,$sql$ VALUES('accepted'::text,'250'::text,'10'::text) $sql$,'resultado conserva observacion y error calculado');
SET LOCAL ROLE service_role;
SELECT lives_ok($sql$ SELECT public.record_dori_outcome_event('16090000-0000-4000-8000-000000000001','dori-outcome-1',(SELECT outcome FROM test_dori_events)) $sql$,'reintento de resultado es idempotente');
RESET ROLE;
SELECT is((SELECT count(*)::bigint FROM public.dori_outcome_events),1::bigint,'reintento no duplica resultado');
SET LOCAL ROLE service_role;
SELECT throws_ok($sql$ SELECT public.record_dori_outcome_event('16090000-0000-4000-8000-000000000001','dori-forged-error',jsonb_set((SELECT outcome FROM test_dori_events),'{predictionError,fare}','999')) $sql$,'22023','invalid_outcome_event','RPC rechaza error observado alterado');
SELECT throws_ok($sql$ SELECT public.record_dori_outcome_event('16090000-0000-4000-8000-000000000002','dori-other-driver',(SELECT outcome FROM test_dori_events)) $sql$,'P0002','owned_decision_event_not_found','otro conductor no puede adjuntar resultado');
RESET ROLE;
SELECT throws_ok($sql$ UPDATE public.dori_decision_events SET recommendation='NO RECOMENDADO' $sql$,'42501','dori_copilot_events_are_append_only','decision es inmutable');
SELECT throws_ok($sql$ DELETE FROM public.dori_outcome_events $sql$,'42501','dori_copilot_events_are_append_only','resultado es inmutable');

CREATE OR REPLACE FUNCTION app.auth_profile_id() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp'
AS $function$ SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid $function$;
SELECT set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*)::bigint FROM public.dori_decision_events),1::bigint,'conductor lee su decision');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000002',true);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*)::bigint FROM public.dori_decision_events),0::bigint,'otro conductor no lee decision ajena');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000003',true);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*)::bigint FROM public.dori_decision_events),1::bigint,'supervisor de estacion lee decisiones');
SELECT is((SELECT count(*)::bigint FROM public.dori_outcome_events),1::bigint,'supervisor de estacion lee resultados');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
