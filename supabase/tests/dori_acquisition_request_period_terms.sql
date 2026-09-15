BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(18);

SELECT has_column('public','acquisition_requests','fiscal_period','solicitud conserva periodo fiscal explícito');
SELECT has_column('public','acquisition_requests','maximum_unit_price_mxn','solicitud conserva precio máximo público');
SELECT has_column('public','acquisition_requests','minimum_soh','solicitud conserva SOH mínimo público');
SELECT has_column('public','acquisition_requests','soh_diagnosis_max_age_days','solicitud conserva vigencia del diagnóstico');
SELECT has_column('public','acquisition_requests','destination_station_name','solicitud conserva estación destino');
SELECT has_column('public','acquisition_requests','delivery_terms_document_path','condiciones pertenecen a la solicitud');
SELECT has_column('public','acquisition_offers','request_fiscal_period','oferta hereda periodo contable');
SELECT has_column('public','acquisition_offers','delivery_terms_accepted_at','aceptación tiene timestamp servidor');
SELECT has_column('public','acquisition_offers','delivery_terms_accepted_by','aceptación registra usuario');
SELECT has_column('public','acquisition_offers','evidence_validation','oferta conserva validación automática');
SELECT has_function(
    'public','publish_acquisition_request_v2',
    ARRAY['text','text[]','integer','integer','integer','integer','numeric','text','text','date','numeric','integer','text','timestamp with time zone','date','jsonb','text'],
    'publicación v2 recibe periodo, límites, estación y documento'
);
SELECT has_function(
    'public','submit_acquisition_offer_v2',
    ARRAY['uuid','uuid','text','text','text','integer','integer','numeric','text','numeric','boolean','boolean','jsonb','jsonb','text'],
    'oferta v2 recibe aceptación y resultado OCR'
);
SELECT is((SELECT public FROM storage.buckets WHERE id='acquisition-request-documents'),false,'documentos de solicitud usan bucket privado');
SELECT is((SELECT file_size_limit FROM storage.buckets WHERE id='acquisition-request-documents'),10485760::bigint,'documentos tienen límite de 10 MB');
SELECT is((SELECT count(*)::bigint FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='acquisition_request_documents_insert'),1::bigint,'Storage permite alta solo por política');
SELECT is((SELECT count(*)::bigint FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='acquisition_request_documents_select'),1::bigint,'Storage permite lectura autorizada');
SELECT table_privs_are('public','acquisition_requests','authenticated',ARRAY['SELECT'],'cliente no escribe solicitudes directamente');
SELECT table_privs_are('public','acquisition_offers','authenticated',ARRAY['SELECT'],'cliente no escribe ofertas directamente');

SELECT * FROM finish();
ROLLBACK;
