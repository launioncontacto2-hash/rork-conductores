BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(31);

SELECT has_table('public','dori_copilot_simulation_cases','tabla de casos simulados');
SELECT has_table('public','dori_copilot_simulation_expectations','tabla de expectativas separadas');
SELECT has_table('public','dori_copilot_simulation_evaluations','tabla de evaluaciones');
SELECT has_function('public','console_create_dori_simulation_case',ARRAY['uuid','text','text','uuid','jsonb','text','text','text','timestamp with time zone'],'RPC de creación para Consola');
SELECT has_function('public','driver_get_dori_simulation_case',ARRAY['uuid','uuid'],'RPC de lectura para conductor');
SELECT has_function('public','driver_next_dori_simulation_case',ARRAY['uuid'],'RPC de siguiente caso');
SELECT has_function('public','record_dori_simulation_evaluation',ARRAY['uuid','uuid','text','jsonb'],'RPC de evaluación');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.dori_copilot_simulation_cases'::regclass),'RLS casos activo');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.dori_copilot_simulation_expectations'::regclass),'RLS expectativas activo');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.dori_copilot_simulation_evaluations'::regclass),'RLS evaluaciones activo');
SELECT ok(NOT has_table_privilege('anon','public.dori_copilot_simulation_cases','SELECT'),'anon no lee casos');
SELECT ok(NOT has_table_privilege('anon','public.dori_copilot_simulation_expectations','SELECT'),'anon no lee expectativas');
SELECT ok(NOT has_table_privilege('anon','public.dori_copilot_simulation_evaluations','SELECT'),'anon no lee evaluaciones');
SELECT ok(NOT has_function_privilege('authenticated','public.console_create_dori_simulation_case(uuid,text,text,uuid,jsonb,text,text,text,timestamptz)','EXECUTE'),'cliente no ejecuta RPC consola');
SELECT ok(NOT has_function_privilege('authenticated','public.driver_get_dori_simulation_case(uuid,uuid)','EXECUTE'),'cliente no ejecuta RPC conductor directamente');
SELECT ok(NOT has_function_privilege('authenticated','public.record_dori_simulation_evaluation(uuid,uuid,text,jsonb)','EXECUTE'),'cliente no ejecuta RPC evaluación directamente');
SELECT ok(NOT has_table_privilege('authenticated','public.dori_copilot_simulation_cases','INSERT,UPDATE,DELETE'),'cliente no escribe casos directamente');
SELECT ok(NOT has_table_privilege('authenticated','public.dori_copilot_simulation_expectations','INSERT,UPDATE,DELETE'),'cliente no escribe expectativas directamente');
SELECT ok(NOT has_table_privilege('authenticated','public.dori_copilot_simulation_evaluations','INSERT,UPDATE,DELETE'),'cliente no escribe evaluaciones directamente');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename LIKE 'dori_copilot_simulation_%' AND (qual::text ILIKE '%supervisor%' OR with_check::text ILIKE '%supervisor%')),'no existe policy de supervisor en laboratorio');
SELECT ok((SELECT convalidated FROM pg_constraint WHERE conname='dori_sim_case_simulation_check'),'casos siempre simulation');
SELECT ok((SELECT convalidated FROM pg_constraint WHERE conname='dori_sim_case_source_check'),'casos source separado');
SELECT ok((SELECT convalidated FROM pg_constraint WHERE conname='dori_sim_eval_classification_check'),'clasificación acotada');
SELECT ok((SELECT convalidated FROM pg_constraint WHERE conname='dori_sim_case_payload_check'),'payload exige source simulated');
SELECT ok((SELECT indexrelid IS NOT NULL FROM pg_index WHERE indexrelid='public.dori_sim_case_driver_pending_idx'::regclass),'índice de pendientes por conductor');
SELECT ok((SELECT EXISTS (SELECT 1 FROM (
  SELECT i.indisunique, array_to_string(array_agg(a.attname ORDER BY k.n), ',') AS cols
  FROM pg_index i JOIN unnest(i.indkey) WITH ORDINALITY k(attnum,n) ON true
  JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum
  WHERE i.indrelid='public.dori_copilot_simulation_evaluations'::regclass
  GROUP BY i.indexrelid, i.indisunique
 ) q WHERE q.indisunique AND q.cols='idempotency_key')),'idempotencia global UNIQUE sobre idempotency_key');
SELECT ok(pg_get_functiondef('public.console_create_dori_simulation_case(uuid,text,text,uuid,jsonb,text,text,text,timestamptz)'::regprocedure) LIKE '%idempotency_key_conflict%','create rechaza clave con payload/comando diferente');
SELECT ok(pg_get_functiondef('public.console_create_dori_simulation_case(uuid,text,text,uuid,jsonb,text,text,text,timestamptz)'::regprocedure) LIKE '%driverId%','create valida identidad del conductor en payload');
SELECT ok(pg_get_functiondef('public.record_dori_simulation_evaluation(uuid,uuid,text,jsonb)'::regprocedure) LIKE '%case_id=c.id%','evaluate reutiliza sólo la misma clave dentro del caso');
SELECT ok(pg_get_functiondef('public.record_dori_simulation_evaluation(uuid,uuid,text,jsonb)'::regprocedure) LIKE '%other.case_id<>c.id%','evaluate rechaza contaminación entre casos');
SELECT ok(pg_get_functiondef('public.driver_next_dori_simulation_case(uuid)'::regprocedure) LIKE '%expires_at>app.env_now%','next excluye casos expirados');
SELECT * FROM finish();
ROLLBACK;
