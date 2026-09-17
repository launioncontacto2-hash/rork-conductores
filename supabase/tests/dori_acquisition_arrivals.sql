BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

SELECT has_table('public', 'acquisition_arrival_inspections', 'existe el registro autoritativo de llegadas');
SELECT has_column('public', 'acquisition_arrival_inspections', 'order_id', 'la inspeccion pertenece a una compra');
SELECT col_type_is('public', 'acquisition_arrival_inspections', 'checks', 'jsonb', 'los 11 resultados quedan persistidos');
SELECT col_type_is('public', 'acquisition_arrival_inspections', 'evidence_paths', 'jsonb', 'las evidencias privadas quedan referenciadas');
SELECT has_function(
    'public', 'complete_acquisition_arrival',
    ARRAY['uuid','jsonb','jsonb','text'],
    'existe el comando transaccional de recepcion por llegada'
);
SELECT policies_are(
    'public', 'acquisition_arrival_inspections',
    ARRAY['acquisition_arrival_inspections_read'],
    'la tabla expone solo lectura aislada por RLS'
);
SELECT table_privs_are(
    'public', 'acquisition_arrival_inspections', 'authenticated',
    ARRAY['SELECT'],
    'el cliente no escribe inspecciones directamente'
);
SELECT function_privs_are(
    'public', 'complete_acquisition_arrival', ARRAY['uuid','jsonb','jsonb','text'],
    'authenticated', ARRAY['EXECUTE'],
    'el cliente autenticado solo puede usar el RPC protegido'
);

SELECT * FROM finish();
ROLLBACK;
