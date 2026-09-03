BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(53);

SELECT has_table('public','incomes','existe incomes');
SELECT has_table('public','cash_deposits','existe cash_deposits');
SELECT has_table('public','cash_charges','existe cash_charges');
SELECT has_table('public','bank_accounts','existe bank_accounts');
SELECT has_table('public','settlements','existe settlements');
SELECT has_table('public','transfers','existe transfers');
SELECT has_table('app','bank_account_secrets','la CLABE completa vive fuera del esquema expuesto');

SELECT has_function('public','register_income',ARRAY['uuid','text','integer','integer','text','text','text','uuid','text','text'],'existe register_income');
SELECT has_function('public','register_cash_deposit',ARRAY['uuid','integer','text','text','text','text','text'],'existe register_cash_deposit');
SELECT has_function('public','set_bank_account',ARRAY['uuid','text','text','text','text'],'existe set_bank_account');
SELECT has_function('public','approve_bank_account',ARRAY['uuid','boolean','text'],'existe approve_bank_account');
SELECT has_function('public','close_settlement',ARRAY['uuid','date','date','text'],'existe close_settlement');
SELECT has_function('public','record_cash_charge',ARRAY['uuid','text','integer','uuid','text'],'existe record_cash_charge');
SELECT has_function('public','authorize_transfer',ARRAY['uuid','bigint','text'],'existe authorize_transfer');
SELECT has_function('app','auth_has_region_role',ARRAY['text','uuid'],'gerencia se autoriza por region');

SELECT has_index('public','incomes','incomes_single_reversal_unique','un ingreso solo se revierte una vez');
SELECT has_index('public','cash_charges','cash_charges_single_reversal_unique','un cargo solo se revierte una vez');
SELECT has_index('public','bank_accounts','bank_accounts_active_driver_unique','solo hay una cuenta activa por conductor');
SELECT has_index('public','bank_accounts','bank_accounts_pending_driver_unique','solo hay una cuenta pendiente por conductor');
SELECT has_index('public','transfers','transfers_active_settlement_unique','una liquidacion no admite dos transferencias activas');
SELECT has_index('public','incomes','incomes_shift_scope_fkey_idx','ingresos cubre la relacion de turno');
SELECT has_index('public','incomes','incomes_driver_scope_fkey_idx','ingresos cubre la relacion de conductor');
SELECT has_index('public','cash_deposits','cash_deposits_shift_scope_fkey_idx','depositos cubre la relacion de turno');
SELECT has_index('public','cash_deposits','cash_deposits_driver_scope_fkey_idx','depositos cubre la relacion de conductor');
SELECT has_index('public','cash_charges','cash_charges_driver_scope_fkey_idx','cargos cubre la relacion de conductor');
SELECT has_index('public','cash_charges','cash_charges_creator_environment_fkey_idx','cargos cubre la relacion de creador');
SELECT has_index('public','bank_accounts','bank_accounts_driver_scope_fkey_idx','cuentas cubre la relacion de conductor');
SELECT has_index('public','bank_accounts','bank_accounts_creator_environment_fkey_idx','cuentas cubre la relacion de creador');
SELECT has_index('public','bank_accounts','bank_accounts_approver_environment_fkey_idx','cuentas cubre la relacion de aprobador');
SELECT has_index('public','settlements','settlements_driver_scope_fkey_idx','liquidaciones cubre la relacion de conductor');
SELECT has_index('public','settlements','settlements_closer_environment_fkey_idx','liquidaciones cubre la relacion de cierre');
SELECT has_index('public','transfers','transfers_settlement_scope_fkey_idx','transferencias cubre la relacion de liquidacion');
SELECT has_index('public','transfers','transfers_bank_account_scope_fkey_idx','transferencias cubre la relacion de cuenta');
SELECT has_index('public','transfers','transfers_authorizer_environment_fkey_idx','transferencias cubre la relacion de autorizador');

SELECT is(
  (SELECT bool_and(c.relrowsecurity) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname IN ('incomes','cash_deposits','cash_charges','bank_accounts','settlements','transfers')),
  true,'todas las tablas financieras expuestas tienen RLS'
);
SELECT is(
  (SELECT count(*)::bigint FROM pg_policies WHERE schemaname='public'
   AND tablename IN ('incomes','cash_deposits','cash_charges','bank_accounts','settlements','transfers') AND cmd='SELECT'),
  6::bigint,'cada tabla financiera tiene solo su politica de lectura'
);
SELECT is(
  (SELECT bool_and(NOT has_table_privilege('anon',format('public.%I',t),'SELECT'))
   FROM unnest(ARRAY['incomes','cash_deposits','cash_charges','bank_accounts','settlements','transfers']) t),
  true,'anon no lee finanzas'
);
SELECT is(
  (SELECT bool_and(has_table_privilege('authenticated',format('public.%I',t),'SELECT'))
   FROM unnest(ARRAY['incomes','cash_deposits','cash_charges','bank_accounts','settlements','transfers']) t),
  true,'authenticated lee sujeto a RLS'
);
SELECT is(
  (SELECT bool_and(NOT has_table_privilege('authenticated',format('public.%I',t),'INSERT, UPDATE, DELETE'))
   FROM unnest(ARRAY['incomes','cash_deposits','cash_charges','bank_accounts','settlements','transfers']) t),
  true,'authenticated no escribe tablas financieras directamente'
);
SELECT is(
  (SELECT bool_and(NOT has_function_privilege('anon',p.oid,'EXECUTE'))
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('register_income','register_cash_deposit','set_bank_account','approve_bank_account','close_settlement','record_cash_charge','authorize_transfer')),
  true,'anon no ejecuta comandos financieros'
);
SELECT is(has_table_privilege('authenticated','app.bank_account_secrets','SELECT'),false,'authenticated nunca lee CLABE completa');

SELECT has_view('public','bank_account_current','existe la vista de cuenta vigente');
SELECT has_view('public','station_daily_billing','existe la facturacion diaria derivada');
SELECT is(
  (SELECT bool_and('security_invoker=true'=ANY(coalesce(c.reloptions,ARRAY[]::text[])))
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname IN ('bank_account_current','station_daily_billing')),
  true,'las vistas respetan RLS del invocador'
);
SELECT is(
  (SELECT count(*)::bigint FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname IN ('incomes','cash_deposits','cash_charges')
     AND t.tgname IN ('incomes_block_update','incomes_block_delete','cash_deposits_block_update','cash_deposits_block_delete','cash_charges_block_update','cash_charges_block_delete')),
  6::bigint,'hechos financieros protegidos contra update y delete'
);

SELECT is(
  (SELECT count(*)::bigint FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
   WHERE n.nspname='public' AND t.relname='incomes' AND c.conname='incomes_reversal_sign_check' AND c.contype='c'),
  1::bigint,'reversion de ingreso exige signo opuesto'
);
SELECT is(
  (SELECT count(*)::bigint FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
   WHERE n.nspname='public' AND t.relname='bank_accounts' AND c.conname='bank_accounts_approval_consistent' AND c.contype='c'),
  1::bigint,'cuenta activa exige aprobacion'
);
SELECT is(
  (SELECT count(*)::bigint FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
   WHERE n.nspname='public' AND t.relname='settlements' AND c.conname='settlements_amounts_check' AND c.contype='c'),
  1::bigint,'neto de liquidacion debe cuadrar'
);

SELECT is(
  (SELECT count(*)::bigint FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='transfers'),
  1::bigint,'transfers publica cambios de estado en realtime'
);
SELECT is(
  (SELECT count(*)::bigint FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='incomes'),
  0::bigint,'incomes no se publica en realtime'
);
SELECT is(
  (SELECT bool_and(p.prosecdef) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('register_income','register_cash_deposit','set_bank_account','approve_bank_account','close_settlement','record_cash_charge','authorize_transfer')),
  true,'las RPC financieras elevan solo dentro del servidor'
);
SELECT is(
  (SELECT bool_and(array_to_string(p.proconfig,',') LIKE '%search_path=%pg_catalog%')
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('register_income','register_cash_deposit','set_bank_account','approve_bank_account','close_settlement','record_cash_charge','authorize_transfer')),
  true,'cada RPC fija un search_path seguro'
);
SELECT is(
  (SELECT count(*)::bigint FROM information_schema.columns
   WHERE table_schema='public' AND table_name='bank_accounts' AND column_name='clabe'),
  0::bigint,'la tabla expuesta no contiene la CLABE completa'
);

SELECT * FROM finish();
ROLLBACK;
