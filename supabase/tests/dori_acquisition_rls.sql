BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

CREATE TEMP TABLE test_acquisition_tables(table_name name PRIMARY KEY);
INSERT INTO test_acquisition_tables(table_name) VALUES
    ('acquisition_suppliers'), ('acquisition_memberships'),
    ('acquisition_requests'), ('acquisition_request_rules'),
    ('acquisition_offers'), ('acquisition_evidence'),
    ('acquisition_offer_assessments'), ('acquisition_negotiations'),
    ('acquisition_orders'), ('acquisition_deliveries'),
    ('acquisition_receptions'), ('acquisition_holds');

SELECT is(
    (SELECT count(*)::bigint FROM pg_catalog.pg_class c
     JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     JOIN test_acquisition_tables expected ON expected.table_name = c.relname
     WHERE n.nspname = 'public' AND c.relrowsecurity),
    12::bigint,
    'RLS esta habilitado en las doce tablas de adquisicion'
);

SELECT is(
    (SELECT count(*)::bigint FROM pg_catalog.pg_policies p
     JOIN test_acquisition_tables expected ON expected.table_name = p.tablename
     WHERE p.schemaname = 'public'),
    12::bigint,
    'cada tabla de adquisicion tiene su politica de lectura'
);

SELECT is(
    (SELECT bool_and(has_table_privilege('authenticated', format('public.%I', table_name), 'SELECT'))
     FROM test_acquisition_tables),
    true,
    'authenticated tiene solo la lectura necesaria para RLS'
);

SELECT is(
    (SELECT bool_or(has_table_privilege('authenticated', format('public.%I', table_name), 'INSERT, UPDATE, DELETE'))
     FROM test_acquisition_tables),
    false,
    'authenticated no puede escribir directamente tablas de adquisicion'
);

SELECT is(
    (SELECT bool_or(has_table_privilege('anon', format('public.%I', table_name), 'SELECT'))
     FROM test_acquisition_tables),
    false,
    'anon no puede leer tablas de adquisicion'
);

CREATE TEMP TABLE test_acquisition_scope AS
SELECT id AS environment_id FROM public.environments ORDER BY created_at, id LIMIT 1;
GRANT SELECT ON test_acquisition_scope TO authenticated;

INSERT INTO public.profiles(id, environment_id, employee_number, display_name, status)
SELECT fixture.id, scope.environment_id, fixture.employee_number, fixture.display_name, 'active'
FROM test_acquisition_scope scope
CROSS JOIN (VALUES
    ('ad100000-0000-4000-8000-000000000001'::uuid, 'ADQ-RLS-ADMIN', 'Administrador DORI RLS'),
    ('ad100000-0000-4000-8000-000000000002'::uuid, 'ADQ-RLS-PROV-A', 'Proveedor A RLS'),
    ('ad100000-0000-4000-8000-000000000003'::uuid, 'ADQ-RLS-PROV-B', 'Proveedor B RLS'),
    ('ad100000-0000-4000-8000-000000000004'::uuid, 'ADQ-RLS-OUT', 'Sin membresia RLS')
) fixture(id, employee_number, display_name);

INSERT INTO public.acquisition_suppliers(id, environment_id, code, name, city)
SELECT fixture.id, scope.environment_id, fixture.code, fixture.name, 'Puebla'
FROM test_acquisition_scope scope
CROSS JOIN (VALUES
    ('ad110000-0000-4000-8000-000000000001'::uuid, 'ADQ-RLS-A', 'Agencia A RLS'),
    ('ad110000-0000-4000-8000-000000000002'::uuid, 'ADQ-RLS-B', 'Agencia B RLS')
) fixture(id, code, name);

INSERT INTO public.acquisition_memberships(
    id, environment_id, profile_id, supplier_id, role, status, starts_at
)
SELECT fixture.id, scope.environment_id, fixture.profile_id, fixture.supplier_id,
       fixture.role, 'active', app.env_now(scope.environment_id) - interval '1 day'
FROM test_acquisition_scope scope
CROSS JOIN (VALUES
    ('ad120000-0000-4000-8000-000000000001'::uuid, 'ad100000-0000-4000-8000-000000000001'::uuid, NULL::uuid, 'dori_admin'),
    ('ad120000-0000-4000-8000-000000000002'::uuid, 'ad100000-0000-4000-8000-000000000002'::uuid, 'ad110000-0000-4000-8000-000000000001'::uuid, 'provider'),
    ('ad120000-0000-4000-8000-000000000003'::uuid, 'ad100000-0000-4000-8000-000000000003'::uuid, 'ad110000-0000-4000-8000-000000000002'::uuid, 'provider')
) fixture(id, profile_id, supplier_id, role);

INSERT INTO public.acquisition_requests(
    id, environment_id, code, title, target_quantity, model, versions,
    minimum_year, maximum_year, maximum_mileage, delivery_city,
    status, created_by, created_at, updated_at
)
SELECT
    'ad130000-0000-4000-8000-000000000001'::uuid,
    scope.environment_id, 'ADQ-RLS-001', '15 autos requeridos', 15,
    'Dolphin Mini', ARRAY['Plus'], 2024, 2026, 30000, 'Puebla',
    'published', 'ad100000-0000-4000-8000-000000000001'::uuid,
    app.env_now(scope.environment_id), app.env_now(scope.environment_id)
FROM test_acquisition_scope scope;

INSERT INTO public.acquisition_request_rules(
    request_id, environment_id, target_soh, minimum_soh, internal_price_limit_mxn
)
SELECT 'ad130000-0000-4000-8000-000000000001'::uuid,
       environment_id, 95, 85, 280000
FROM test_acquisition_scope;

INSERT INTO public.acquisition_offers(
    id, environment_id, request_id, supplier_id, created_by, vin,
    model, version, year, mileage, declared_soh, color, price_mxn,
    transfer_included, status, submitted_at, updated_at
)
SELECT fixture.id, scope.environment_id,
       'ad130000-0000-4000-8000-000000000001'::uuid,
       fixture.supplier_id, fixture.profile_id, fixture.vin,
       'Dolphin Mini', 'Plus', 2025, fixture.mileage, 96, 'Blanco',
       fixture.price, true, 'submitted',
       app.env_now(scope.environment_id), app.env_now(scope.environment_id)
FROM test_acquisition_scope scope
CROSS JOIN (VALUES
    ('ad140000-0000-4000-8000-000000000001'::uuid, 'ad110000-0000-4000-8000-000000000001'::uuid, 'ad100000-0000-4000-8000-000000000002'::uuid, 'LGXCE6CB1S0000001', 8400, 274000::numeric),
    ('ad140000-0000-4000-8000-000000000002'::uuid, 'ad110000-0000-4000-8000-000000000002'::uuid, 'ad100000-0000-4000-8000-000000000003'::uuid, 'LGXCE6CB1S0000002', 9200, 279000::numeric)
) fixture(id, supplier_id, profile_id, vin, mileage, price);

INSERT INTO public.acquisition_offer_assessments(
    offer_id, environment_id, estimated_value_mxn, maximum_recommended_mxn,
    risk, recommendation, evidence_status, summary, calculated_at
)
SELECT offer.id, offer.environment_id, 280000, 280000, 'low', 'buy',
       'complete', 'Unidad de prueba.', app.env_now(offer.environment_id)
FROM public.acquisition_offers offer
WHERE offer.id IN (
    'ad140000-0000-4000-8000-000000000001'::uuid,
    'ad140000-0000-4000-8000-000000000002'::uuid
);

-- La prueba reemplaza solo dentro de esta transaccion el resolvedor de identidad.
CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

SELECT set_config('request.jwt.claim.sub', 'ad100000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$
    INSERT INTO storage.objects(id, bucket_id, name, owner_id, metadata)
    SELECT gen_random_uuid(), 'acquisition-evidence',
           environment_id::text
               || '/ad110000-0000-4000-8000-000000000001'
               || '/ad150000-0000-4000-8000-000000000001/vin.jpg',
           'ad100000-0000-4000-8000-000000000002',
           jsonb_build_object('mimetype', 'image/jpeg')
    FROM test_acquisition_scope
    $sql$,
    'el proveedor puede subir evidencia a la ruta contractual de tres carpetas'
);
RESET ROLE;

CREATE TEMP TABLE test_acquisition_visibility(
    actor text PRIMARY KEY,
    suppliers bigint NOT NULL,
    offers bigint NOT NULL,
    assessments bigint NOT NULL,
    requests bigint NOT NULL
);
GRANT SELECT, INSERT ON test_acquisition_visibility TO authenticated;

SELECT set_config('request.jwt.claim.sub', 'ad100000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
INSERT INTO test_acquisition_visibility
SELECT 'provider_a',
       (SELECT count(*) FROM public.acquisition_suppliers WHERE id IN ('ad110000-0000-4000-8000-000000000001'::uuid, 'ad110000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_offers WHERE id IN ('ad140000-0000-4000-8000-000000000001'::uuid, 'ad140000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_offer_assessments WHERE offer_id IN ('ad140000-0000-4000-8000-000000000001'::uuid, 'ad140000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_requests WHERE id = 'ad130000-0000-4000-8000-000000000001'::uuid);
SELECT throws_ok(
    $sql$ INSERT INTO public.acquisition_offers(
        id, environment_id, request_id, supplier_id, created_by, vin,
        model, year, mileage, price_mxn, submitted_at, updated_at
    ) SELECT gen_random_uuid(), environment_id,
        'ad130000-0000-4000-8000-000000000001'::uuid,
        'ad110000-0000-4000-8000-000000000001'::uuid,
        'ad100000-0000-4000-8000-000000000002'::uuid,
        'LGXCE6CB1S0000099', 'Dolphin Mini', 2025, 1, 1,
        app.env_now(environment_id), app.env_now(environment_id)
    FROM test_acquisition_scope $sql$,
    '42501', NULL,
    'un proveedor no puede insertar ofertas directamente'
);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad100000-0000-4000-8000-000000000003', true);
SET LOCAL ROLE authenticated;
INSERT INTO test_acquisition_visibility
SELECT 'provider_b',
       (SELECT count(*) FROM public.acquisition_suppliers WHERE id IN ('ad110000-0000-4000-8000-000000000001'::uuid, 'ad110000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_offers WHERE id IN ('ad140000-0000-4000-8000-000000000001'::uuid, 'ad140000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_offer_assessments WHERE offer_id IN ('ad140000-0000-4000-8000-000000000001'::uuid, 'ad140000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_requests WHERE id = 'ad130000-0000-4000-8000-000000000001'::uuid);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad100000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
INSERT INTO test_acquisition_visibility
SELECT 'admin',
       (SELECT count(*) FROM public.acquisition_suppliers WHERE id IN ('ad110000-0000-4000-8000-000000000001'::uuid, 'ad110000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_offers WHERE id IN ('ad140000-0000-4000-8000-000000000001'::uuid, 'ad140000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_offer_assessments WHERE offer_id IN ('ad140000-0000-4000-8000-000000000001'::uuid, 'ad140000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_requests WHERE id = 'ad130000-0000-4000-8000-000000000001'::uuid);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad100000-0000-4000-8000-000000000004', true);
SET LOCAL ROLE authenticated;
INSERT INTO test_acquisition_visibility
SELECT 'outsider',
       (SELECT count(*) FROM public.acquisition_suppliers WHERE id IN ('ad110000-0000-4000-8000-000000000001'::uuid, 'ad110000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_offers WHERE id IN ('ad140000-0000-4000-8000-000000000001'::uuid, 'ad140000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_offer_assessments WHERE offer_id IN ('ad140000-0000-4000-8000-000000000001'::uuid, 'ad140000-0000-4000-8000-000000000002'::uuid)),
       (SELECT count(*) FROM public.acquisition_requests WHERE id = 'ad130000-0000-4000-8000-000000000001'::uuid);
RESET ROLE;

SELECT is((SELECT suppliers FROM test_acquisition_visibility WHERE actor = 'provider_a'), 1::bigint, 'proveedor A solo ve su organizacion');
SELECT is((SELECT offers FROM test_acquisition_visibility WHERE actor = 'provider_a'), 1::bigint, 'proveedor A solo ve su oferta');
SELECT is((SELECT assessments FROM test_acquisition_visibility WHERE actor = 'provider_a'), 0::bigint, 'proveedor A no ve evaluaciones internas');
SELECT is((SELECT requests FROM test_acquisition_visibility WHERE actor = 'provider_a'), 1::bigint, 'proveedor A ve la solicitud publicada');
SELECT is((SELECT suppliers FROM test_acquisition_visibility WHERE actor = 'provider_b'), 1::bigint, 'proveedor B solo ve su organizacion');
SELECT is((SELECT offers FROM test_acquisition_visibility WHERE actor = 'provider_b'), 1::bigint, 'proveedor B solo ve su oferta');
SELECT is((SELECT suppliers FROM test_acquisition_visibility WHERE actor = 'admin'), 2::bigint, 'Administrador DORI ve ambos proveedores');
SELECT is((SELECT offers FROM test_acquisition_visibility WHERE actor = 'admin'), 2::bigint, 'Administrador DORI ve ambas ofertas');
SELECT is((SELECT assessments FROM test_acquisition_visibility WHERE actor = 'admin'), 2::bigint, 'Administrador DORI ve evaluaciones internas');
SELECT is((SELECT suppliers + offers + assessments + requests FROM test_acquisition_visibility WHERE actor = 'outsider'), 0::bigint, 'un perfil sin membresia no ve el modulo');

SELECT * FROM finish();
ROLLBACK;
