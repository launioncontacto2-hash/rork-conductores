BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(32);

INSERT INTO public.stations(id,environment_id,region_id,code,name,status,timezone)
SELECT '15740000-0000-4000-8000-000000000001',r.environment_id,r.id,'15g-rpc-station','15G RPC Station','active','America/Mexico_City'
FROM public.regions r ORDER BY r.created_at,r.id LIMIT 1;
INSERT INTO public.stations(id,environment_id,region_id,code,name,status,timezone)
SELECT '15740000-0000-4000-8000-000000000002',s.environment_id,s.region_id,'15g-rpc-station-2','15G RPC Station 2','active',s.timezone
FROM public.stations s WHERE s.id='15740000-0000-4000-8000-000000000001';
CREATE TEMP TABLE test_15g_scope AS SELECT environment_id,id station_id FROM public.stations WHERE id='15740000-0000-4000-8000-000000000001';
UPDATE app.env_clock c SET is_simulated=true,anchor_logical_at='2026-08-31 18:00:00+00',anchor_real_at=now(),speed=1,is_paused=true
FROM test_15g_scope s WHERE c.environment_id=s.environment_id;

INSERT INTO public.profiles(id,environment_id,employee_number,display_name,status)
SELECT f.id,s.environment_id,f.employee_number,f.display_name,'active' FROM test_15g_scope s CROSS JOIN (VALUES
 ('15700000-0000-4000-8000-000000000001'::uuid,'15G-DRIVER','15G Driver'),
 ('15700000-0000-4000-8000-000000000002'::uuid,'15G-MANAGER','15G Manager')
) f(id,employee_number,display_name);
INSERT INTO public.staff_memberships(id,environment_id,profile_id,station_id,role,starts_at,shift_group,shift_slot)
SELECT f.id,s.environment_id,f.profile_id,s.station_id,f.role,'2026-01-01 00:00:00+00',f.shift_group,f.shift_slot
FROM test_15g_scope s CROSS JOIN (VALUES
 ('15710000-0000-4000-8000-000000000001'::uuid,'15700000-0000-4000-8000-000000000001'::uuid,'driver','weekday','morning'),
 ('15710000-0000-4000-8000-000000000002'::uuid,'15700000-0000-4000-8000-000000000002'::uuid,'management',NULL::text,NULL::text)
) f(id,profile_id,role,shift_group,shift_slot);
INSERT INTO public.driver_profiles(id,environment_id,station_id,profile_id,membership_id,employee_number,status)
SELECT '15720000-0000-4000-8000-000000000001',s.environment_id,s.station_id,
 '15700000-0000-4000-8000-000000000001','15710000-0000-4000-8000-000000000001','15G-DRIVER','active' FROM test_15g_scope s;
INSERT INTO public.vehicles(id,environment_id,station_id,internal_number,qr_code,model,odometer_km,battery_pct,status)
SELECT '15730000-0000-4000-8000-000000000001',s.environment_id,s.station_id,'15G-V1','15G-QR1','15G Vehicle',1200,70,'occupied' FROM test_15g_scope s;
INSERT INTO public.assignments(id,environment_id,station_id,driver_profile_id,vehicle_id,kind,assigned_by,assigned_at)
SELECT '15750000-0000-4000-8000-000000000001',s.environment_id,s.station_id,'15720000-0000-4000-8000-000000000001',
 '15730000-0000-4000-8000-000000000001','titular','15700000-0000-4000-8000-000000000002','2026-08-31 10:00:00+00' FROM test_15g_scope s;
INSERT INTO public.shifts(id,environment_id,station_id,driver_profile_id,vehicle_id,assignment_id,folio,status,shift_group,shift_slot,
 operating_date,scheduled_start_at,scheduled_end_at,started_at,finished_at,late_minutes,start_odometer_km,start_battery_pct,end_odometer_km,end_battery_pct,revision)
SELECT '15760000-0000-4000-8000-000000000001',s.environment_id,s.station_id,'15720000-0000-4000-8000-000000000001',
 '15730000-0000-4000-8000-000000000001','15750000-0000-4000-8000-000000000001','SH-15G-RPC','closed','weekday','morning',
 '2026-08-31','2026-08-31 11:00:00+00','2026-08-31 20:00:00+00','2026-08-31 11:00:00+00','2026-08-31 18:00:00+00',0,1200,70,1250,35,2
FROM test_15g_scope s;

CREATE OR REPLACE FUNCTION app.auth_profile_id() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp'
AS $function$ SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid $function$;

SELECT set_config('request.jwt.claim.sub','15700000-0000-4000-8000-000000000001',true);
SELECT set_config('request.jwt.claims','{"session_id":"15770000-0000-4000-8000-000000000001"}',true);
SET LOCAL ROLE authenticated;
DO $block$ BEGIN PERFORM public.claim_driver_device('15g-install-driver','pgtap'); END $block$;
SELECT lives_ok($sql$ SELECT public.register_income('15760000-0000-4000-8000-000000000001','uber',1000,8,'UB-1000',NULL,'turno principal',NULL,'15g-income-1','15g-install-driver') $sql$,'conductor registra ingreso');
SELECT lives_ok($sql$ SELECT public.register_income('15760000-0000-4000-8000-000000000001','uber',1000,8,'UB-1000',NULL,'turno principal',NULL,'15g-income-1','15g-install-driver') $sql$,'registro de ingreso es idempotente');
RESET ROLE;
SELECT is((SELECT count(*)::bigint FROM public.incomes),1::bigint,'la repeticion no duplica ingreso');

SET LOCAL ROLE authenticated;
SELECT lives_ok($sql$ SELECT public.register_income('15760000-0000-4000-8000-000000000001','other',200,1,NULL,NULL,'ajuste a revertir',NULL,'15g-income-2','15g-install-driver') $sql$,'registra segundo ingreso');
SELECT lives_ok($sql$ SELECT public.register_income('15760000-0000-4000-8000-000000000001','other',200,0,NULL,NULL,'reversa',
 (SELECT id FROM public.incomes WHERE amount_mxn=200),'15g-income-reversal','15g-install-driver') $sql$,'reversa crea movimiento opuesto');
SELECT lives_ok($sql$ SELECT public.register_cash_deposit('15760000-0000-4000-8000-000000000001',300,'BBVA','REC-15G-1','receipts/15g.jpg','15g-deposit-1','15g-install-driver') $sql$,'registra comprobante de deposito');
SELECT lives_ok($sql$ SELECT public.set_bank_account('15720000-0000-4000-8000-000000000001','BBVA','012345678901234567','15g-bank-1','15g-install-driver') $sql$,'conductor propone cuenta bancaria');
RESET ROLE;
SELECT results_eq($sql$ SELECT count(*)::bigint,sum(amount_mxn)::bigint FROM public.incomes $sql$,$sql$ VALUES(3::bigint,1000::bigint) $sql$,'ingresos conservan original y reversa');
SELECT results_eq($sql$ SELECT status,clabe_last4 FROM public.bank_accounts $sql$,$sql$ VALUES('pending'::text,'4567'::text) $sql$,'la cuenta queda pendiente y solo expone ultimos cuatro');
SELECT is((SELECT clabe FROM app.bank_account_secrets),'012345678901234567','la CLABE completa queda en esquema privado');

SELECT set_config('request.jwt.claim.sub','15700000-0000-4000-8000-000000000002',true);
SET LOCAL ROLE authenticated;
SELECT ok(app.auth_has_region_role('management','15740000-0000-4000-8000-000000000002'),'gerencia alcanza otra estacion de su region');
SELECT lives_ok($sql$ SELECT public.approve_bank_account((SELECT id FROM public.bank_accounts),true,'15g-bank-approve') $sql$,'gerencia aprueba con segundo actor');
SELECT lives_ok($sql$ SELECT public.record_cash_charge('15720000-0000-4000-8000-000000000001','Servicio semanal',100,NULL,'15g-charge-1') $sql$,'gerencia registra cargo');
RESET ROLE;
SELECT is((SELECT status FROM public.bank_accounts),'active','la cuenta aprobada queda activa');

UPDATE app.env_clock c SET anchor_logical_at='2026-09-07 18:00:00+00',anchor_real_at=now()
FROM test_15g_scope s WHERE c.environment_id=s.environment_id;
SET LOCAL ROLE authenticated;
SELECT lives_ok($sql$ SELECT public.close_settlement('15720000-0000-4000-8000-000000000001','2026-08-31','2026-08-31','15g-settlement-1') $sql$,'gerencia cierra liquidacion pasada');
SELECT lives_ok($sql$ SELECT public.close_settlement('15720000-0000-4000-8000-000000000001','2026-08-31','2026-08-31','15g-settlement-1') $sql$,'cierre es idempotente');
RESET ROLE;
SELECT results_eq($sql$ SELECT gross_income_mxn,cash_charges_mxn,net_mxn,status,revision FROM public.settlements $sql$,
 $sql$ VALUES(1000,100,900,'available'::text,1::bigint) $sql$,'servidor calcula y congela 900 MXN');
SELECT is((SELECT count(*)::bigint FROM public.settlements),1::bigint,'no duplica liquidacion');

SET LOCAL ROLE authenticated;
SELECT lives_ok($sql$ SELECT public.authorize_transfer((SELECT id FROM public.settlements),1,'15g-transfer-1') $sql$,'gerencia autoriza transferencia');
SELECT lives_ok($sql$ SELECT public.authorize_transfer((SELECT id FROM public.settlements),1,'15g-transfer-1') $sql$,'autorizacion es idempotente');
RESET ROLE;
SELECT results_eq($sql$ SELECT amount_mxn,status FROM public.transfers $sql$,$sql$ VALUES(900,'authorized'::text) $sql$,'transferencia usa neto y nace autorizada');
SELECT is((SELECT count(*)::bigint FROM public.transfers),1::bigint,'solo existe una transferencia');
SET LOCAL ROLE authenticated;
SELECT throws_ok($sql$ SELECT public.authorize_transfer((SELECT id FROM public.settlements),2,'15g-transfer-2') $sql$,'22023','available_settlement_required','segunda autorizacion es rechazada');
RESET ROLE;
SELECT results_eq($sql$ SELECT status,revision FROM public.settlements $sql$,$sql$ VALUES('authorized'::text,2::bigint) $sql$,'liquidacion avanza una sola vez');
SELECT throws_ok($sql$ UPDATE public.incomes SET note='mutado' WHERE amount_mxn=1000 $sql$,'42501','financial_record_append_only','ingresos no se editan');
SELECT is((SELECT billed_today_mxn FROM public.station_live WHERE station_id='15740000-0000-4000-8000-000000000001'),1000,'pulso de estacion refleja ingreso neto del dia');
SELECT cmp_ok((SELECT count(*) FROM public.audit_log WHERE event_type LIKE ANY(ARRAY['income.%','cash_deposit.%','bank_account.%','cash_charge.%','settlement.%','transfer.%'])),'>=',9::bigint,'cada comando financiero deja auditoria');
SELECT is((SELECT count(*)::bigint FROM public.command_log WHERE idempotency_key LIKE '15g-%' AND status='completed'),9::bigint,'cada operacion logica completa un comando');
SELECT is((SELECT count(*)::bigint FROM public.cash_deposits),1::bigint,'deposito queda append-only');
SELECT is((SELECT count(*)::bigint FROM public.cash_charges),1::bigint,'cargo queda append-only');
SELECT is((SELECT count(*)::bigint FROM public.bank_account_current),1::bigint,'vista vigente devuelve una cuenta');
SELECT results_eq($sql$ SELECT billed_mxn,entry_count FROM public.station_daily_billing WHERE operating_date='2026-08-31' $sql$,
 $sql$ VALUES(1000::bigint,3::bigint) $sql$,'vista diaria deriva monto y numero de movimientos');

SELECT * FROM finish();
ROLLBACK;
