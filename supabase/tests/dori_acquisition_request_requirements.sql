BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(19);

SELECT has_table(
    'public', 'acquisition_request_requirements',
    'existe el contrato flexible de requisitos por solicitud'
);
SELECT has_column('public', 'acquisition_request_requirements', 'request_id', 'cada requisito pertenece a una solicitud');
SELECT has_column('public', 'acquisition_request_requirements', 'category', 'los requisitos admiten categorías flexibles');
SELECT has_column('public', 'acquisition_request_requirements', 'metadata', 'los requisitos admiten metadatos extensibles');
SELECT col_type_is(
    'public', 'acquisition_request_requirements', 'metadata', 'jsonb',
    'los metadatos flexibles se almacenan como jsonb'
);
SELECT has_function(
    'public', 'publish_acquisition_request',
    ARRAY['text','text[]','integer','integer','integer','integer','text','timestamp with time zone','jsonb','text'],
    'existe el RPC público sin reglas internas en el cliente'
);
SELECT policies_are(
    'public', 'acquisition_request_requirements',
    ARRAY['acquisition_request_requirements_read'],
    'los requisitos solo tienen política de lectura autenticada'
);
SELECT table_privs_are(
    'public', 'acquisition_request_requirements', 'authenticated',
    ARRAY['SELECT'],
    'el cliente no escribe requisitos directamente'
);

CREATE TEMP TABLE test_request_requirement_scope AS
SELECT id AS environment_id FROM public.environments ORDER BY created_at, id LIMIT 1;

INSERT INTO public.profiles(id, environment_id, employee_number, display_name, status)
SELECT fixture.id, scope.environment_id, fixture.employee_number, fixture.display_name, 'active'
FROM test_request_requirement_scope scope
CROSS JOIN (VALUES
    ('ad700000-0000-4000-8000-000000000001'::uuid, 'ADQ-REQ-ADMIN', 'Administrador requisitos'),
    ('ad700000-0000-4000-8000-000000000002'::uuid, 'ADQ-REQ-PROV', 'Proveedor requisitos')
) fixture(id, employee_number, display_name);

INSERT INTO public.acquisition_suppliers(id, environment_id, code, name, city)
SELECT 'ad710000-0000-4000-8000-000000000001', environment_id,
       'ADQ-REQ-PROV', 'Proveedor requisitos', 'Puebla'
FROM test_request_requirement_scope;

INSERT INTO public.acquisition_memberships(
    id, environment_id, profile_id, supplier_id, role, status, starts_at
)
SELECT fixture.id, scope.environment_id, fixture.profile_id, fixture.supplier_id,
       fixture.role, 'active', app.env_now(scope.environment_id) - interval '1 day'
FROM test_request_requirement_scope scope
CROSS JOIN (VALUES
    ('ad720000-0000-4000-8000-000000000001'::uuid, 'ad700000-0000-4000-8000-000000000001'::uuid, NULL::uuid, 'dori_admin'),
    ('ad720000-0000-4000-8000-000000000002'::uuid, 'ad700000-0000-4000-8000-000000000002'::uuid, 'ad710000-0000-4000-8000-000000000001'::uuid, 'provider')
) fixture(id, profile_id, supplier_id, role);

CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

SELECT set_config('request.jwt.claim.sub', 'ad700000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
    $sql$
    SELECT public.publish_acquisition_request(
        'BYD King', ARRAY['GL'], 4, 2025, 2026, 15000, 'Puebla', NULL,
        '[
          {"code":"charger_110v","category":"condition","title":"Cargador 110V","value":"Incluido","required":true,"display_order":1},
          {"code":"exterior_driver_side","category":"evidence","title":"Exterior lateral conductor","value":"Fotografía completa","required":true,"display_order":2}
        ]'::jsonb,
        'adq-request-requirements-1'
    )
    $sql$,
    'DORI publica una solicitud con requisitos propios'
);
SELECT lives_ok(
    $sql$
    SELECT public.publish_acquisition_request(
        'BYD King', ARRAY['GL'], 4, 2025, 2026, 15000, 'Puebla', NULL,
        '[
          {"code":"charger_110v","category":"condition","title":"Cargador 110V","value":"Incluido","required":true,"display_order":1},
          {"code":"exterior_driver_side","category":"evidence","title":"Exterior lateral conductor","value":"Fotografía completa","required":true,"display_order":2}
        ]'::jsonb,
        'adq-request-requirements-1'
    )
    $sql$,
    'la publicación es idempotente'
);
RESET ROLE;

SELECT is(
    (SELECT count(*)::bigint FROM public.acquisition_requests WHERE model = 'BYD King'),
    1::bigint,
    'la repetición no duplica la solicitud'
);
SELECT is(
    (SELECT count(*)::bigint
     FROM public.acquisition_request_requirements requirement
     JOIN public.acquisition_requests request ON request.id = requirement.request_id
     WHERE request.model = 'BYD King'),
    2::bigint,
    'los requisitos se persisten como datos de la solicitud'
);
SELECT is(
    (SELECT internal_price_limit_mxn
     FROM public.acquisition_request_rules rules
     JOIN public.acquisition_requests request ON request.id = rules.request_id
     WHERE request.model = 'BYD King'),
    NULL::numeric,
    'la publicación visible no inventa un límite interno en el cliente'
);

SELECT set_config('request.jwt.claim.sub', 'ad700000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT is(
    (SELECT count(*)::bigint
     FROM public.acquisition_request_requirements requirement
     JOIN public.acquisition_requests request ON request.id = requirement.request_id
     WHERE request.model = 'BYD King'),
    2::bigint,
    'el proveedor autorizado ve los requisitos públicos'
);
SELECT throws_ok(
    $sql$
    SELECT public.publish_acquisition_request(
        'No autorizado', ARRAY[]::text[], 1, 2025, 2026, 1000, 'Puebla', NULL,
        '[{"code":"x","category":"condition","title":"X","value":"X"}]'::jsonb,
        'adq-request-provider-denied'
    )
    $sql$,
    '42501', 'dori_acquisition_admin_required',
    'el proveedor no puede publicar solicitudes'
);
SELECT throws_ok(
    $sql$
    INSERT INTO public.acquisition_request_requirements(
        environment_id, request_id, code, category, title, value, created_at
    )
    SELECT environment_id, id, 'direct', 'condition', 'Directo', 'No permitido', now()
    FROM public.acquisition_requests WHERE model = 'BYD King'
    $sql$,
    '42501',
    'permission denied for table acquisition_request_requirements',
    'el proveedor no escribe requisitos directamente'
);
RESET ROLE;

SELECT throws_ok(
    $sql$
    SELECT public.publish_acquisition_request(
        'Sin requisitos', ARRAY[]::text[], 1, 2025, 2025, 1000, 'Puebla', NULL,
        '[]'::jsonb, 'adq-request-empty'
    )
    $sql$,
    '42501', 'dori_acquisition_admin_required',
    'sin identidad tampoco se publica'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.acquisition_request_requirements WHERE category = 'evidence'),
    1::bigint,
    'la evidencia requerida queda identificable por categoría'
);
SELECT throws_ok(
    $sql$
    INSERT INTO public.acquisition_offers(
        id, environment_id, request_id, supplier_id, created_by, vin,
        model, year, mileage, color, price_mxn, transfer_included,
        status, submitted_at, updated_at
    )
    SELECT 'ad740000-0000-4000-8000-000000000001', request.environment_id,
           request.id, 'ad710000-0000-4000-8000-000000000001',
           'ad700000-0000-4000-8000-000000000002', 'LGXCE6CB1S0074001',
           request.model, 2025, 1000, 'Blanco', 290000, false,
           'submitted', app.env_now(request.environment_id), app.env_now(request.environment_id)
    FROM public.acquisition_requests request WHERE request.model = 'BYD King';
    SET CONSTRAINTS acquisition_offer_required_evidence IMMEDIATE
    $sql$,
    '23514',
    'required_acquisition_evidence_missing:exterior_driver_side',
    'la transacción rechaza una oferta sin la evidencia exigida por su solicitud'
);

SELECT * FROM finish();
ROLLBACK;
