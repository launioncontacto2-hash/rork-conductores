BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(50);

SELECT has_function(
    'public', 'publish_acquisition_request',
    ARRAY['text','text','integer','text','text[]','integer','integer','integer','text','timestamp with time zone','numeric','numeric','numeric','text'],
    'existe el RPC para publicar solicitudes'
);
SELECT has_function(
    'public', 'submit_acquisition_offer',
    ARRAY['uuid','uuid','text','text','text','integer','integer','numeric','text','numeric','boolean','jsonb','text'],
    'existe el RPC para enviar ofertas'
);
SELECT has_function(
    'public', 'respond_acquisition_offer', ARRAY['uuid','text','numeric','text','text'],
    'existe el RPC para negociacion y adjudicacion'
);
SELECT has_function(
    'public', 'complete_acquisition_delivery', ARRAY['uuid','text','jsonb','text','text','numeric','text'],
    'existe el RPC para entrega, recepcion y retencion'
);

CREATE TEMP TABLE test_acquisition_rpc_scope AS
SELECT id AS environment_id FROM public.environments ORDER BY created_at, id LIMIT 1;

INSERT INTO public.profiles(id, environment_id, employee_number, display_name, status)
SELECT fixture.id, scope.environment_id, fixture.employee_number, fixture.display_name, 'active'
FROM test_acquisition_rpc_scope scope
CROSS JOIN (VALUES
    ('ad200000-0000-4000-8000-000000000001'::uuid, 'ADQ-RPC-ADMIN', 'Administrador DORI RPC'),
    ('ad200000-0000-4000-8000-000000000002'::uuid, 'ADQ-RPC-PROV-A', 'Proveedor A RPC'),
    ('ad200000-0000-4000-8000-000000000003'::uuid, 'ADQ-RPC-PROV-B', 'Proveedor B RPC')
) fixture(id, employee_number, display_name);

INSERT INTO public.acquisition_suppliers(id, environment_id, code, name, city)
SELECT fixture.id, scope.environment_id, fixture.code, fixture.name, 'Puebla'
FROM test_acquisition_rpc_scope scope
CROSS JOIN (VALUES
    ('ad210000-0000-4000-8000-000000000001'::uuid, 'ADQ-RPC-A', 'Agencia A RPC'),
    ('ad210000-0000-4000-8000-000000000002'::uuid, 'ADQ-RPC-B', 'Agencia B RPC')
) fixture(id, code, name);

INSERT INTO public.acquisition_memberships(
    id, environment_id, profile_id, supplier_id, role, status, starts_at
)
SELECT fixture.id, scope.environment_id, fixture.profile_id, fixture.supplier_id,
       fixture.role, 'active', app.env_now(scope.environment_id) - interval '1 day'
FROM test_acquisition_rpc_scope scope
CROSS JOIN (VALUES
    ('ad220000-0000-4000-8000-000000000001'::uuid, 'ad200000-0000-4000-8000-000000000001'::uuid, NULL::uuid, 'dori_admin'),
    ('ad220000-0000-4000-8000-000000000002'::uuid, 'ad200000-0000-4000-8000-000000000002'::uuid, 'ad210000-0000-4000-8000-000000000001'::uuid, 'provider'),
    ('ad220000-0000-4000-8000-000000000003'::uuid, 'ad200000-0000-4000-8000-000000000003'::uuid, 'ad210000-0000-4000-8000-000000000002'::uuid, 'provider')
) fixture(id, profile_id, supplier_id, role);

CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

-- Administrador DORI publica una solicitud. La repeticion es idempotente.
SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.publish_acquisition_request(
        'ADQ-RPC-001', '15 autos requeridos', 15, 'Dolphin Mini', ARRAY['Plus'],
        2024, 2026, 30000, 'Puebla', NULL, 95, 85, 280000, 'adq-rpc-publish-1'
    ) $sql$,
    'Administrador DORI publica la solicitud'
);
SELECT lives_ok(
    $sql$ SELECT public.publish_acquisition_request(
        'ADQ-RPC-001', '15 autos requeridos', 15, 'Dolphin Mini', ARRAY['Plus'],
        2024, 2026, 30000, 'Puebla', NULL, 95, 85, 280000, 'adq-rpc-publish-1'
    ) $sql$,
    'publicar la misma solicitud con la misma llave es idempotente'
);
RESET ROLE;

SELECT is(
    (SELECT count(*)::bigint FROM public.acquisition_requests WHERE code = 'ADQ-RPC-001'),
    1::bigint,
    'la repeticion no duplica la solicitud'
);

CREATE TEMP TABLE test_acquisition_rpc_entities AS
SELECT request.id AS request_id,
       'ad240000-0000-4000-8000-000000000001'::uuid AS offer_id,
       scope.environment_id,
       scope.environment_id::text || '/ad210000-0000-4000-8000-000000000001/ad240000-0000-4000-8000-000000000001/' AS path_prefix
FROM public.acquisition_requests request
JOIN test_acquisition_rpc_scope scope ON scope.environment_id = request.environment_id
WHERE request.code = 'ADQ-RPC-001';
GRANT SELECT ON test_acquisition_rpc_entities TO authenticated;

INSERT INTO storage.objects(id, bucket_id, name, owner_id, metadata)
SELECT gen_random_uuid(), 'acquisition-evidence', entity.path_prefix || fixture.file_name,
       'ad200000-0000-4000-8000-000000000002',
       jsonb_build_object('mimetype', 'image/jpeg')
FROM test_acquisition_rpc_entities entity
CROSS JOIN (VALUES ('vin.jpg'), ('front.jpg'), ('dashboard.jpg')) fixture(file_name);

INSERT INTO public.acquisition_offers(
    id, environment_id, request_id, supplier_id, created_by, vin,
    model, version, year, mileage, declared_soh, color, price_mxn,
    transfer_included, status, submitted_at, updated_at
)
SELECT
    'ad240000-0000-4000-8000-000000000002', entity.environment_id,
    entity.request_id, 'ad210000-0000-4000-8000-000000000001',
    'ad200000-0000-4000-8000-000000000002', 'LGXCE6CB1S0000022',
    'Dolphin Mini', 'Plus', 2025, 9100, NULL, 'Azul', 279000,
    false, 'submitted', app.env_now(entity.environment_id), app.env_now(entity.environment_id)
FROM test_acquisition_rpc_entities entity;

-- Dos contraofertas con el mismo reloj de negocio deben conservar el orden de
-- registro. Los UUID se eligen en orden inverso para demostrar que no se usan
-- como desempate comercial.
INSERT INTO public.acquisition_offers(
    id, environment_id, request_id, supplier_id, created_by, vin,
    model, version, year, mileage, declared_soh, color, price_mxn,
    transfer_included, status, submitted_at, updated_at
)
SELECT
    'ad240000-0000-4000-8000-000000000006', entity.environment_id,
    entity.request_id, 'ad210000-0000-4000-8000-000000000001',
    'ad200000-0000-4000-8000-000000000002', 'LGXCE6CB1S0000066',
    'Dolphin Mini', 'Plus', 2025, 7600, 94, 'Plata', 274000,
    true, 'negotiating', app.env_now(entity.environment_id), app.env_now(entity.environment_id)
FROM test_acquisition_rpc_entities entity;

INSERT INTO public.acquisition_negotiations(
    id, environment_id, offer_id, actor_profile_id, actor_role,
    action, amount_mxn, message, created_at
)
SELECT 'ffffffff-ffff-4fff-8fff-fffffffffff1', entity.environment_id,
       'ad240000-0000-4000-8000-000000000006',
       'ad200000-0000-4000-8000-000000000001', 'dori_admin',
       'counteroffer', 268000, 'Oferta DORI con reloj congelado.',
       app.env_now(entity.environment_id)
FROM test_acquisition_rpc_entities entity;

INSERT INTO public.acquisition_negotiations(
    id, environment_id, offer_id, actor_profile_id, actor_role,
    action, amount_mxn, message, created_at
)
SELECT '00000000-0000-4000-8000-000000000001', entity.environment_id,
       'ad240000-0000-4000-8000-000000000006',
       'ad200000-0000-4000-8000-000000000002', 'provider',
       'counteroffer', 271000, 'Respuesta posterior del proveedor.',
       app.env_now(entity.environment_id)
FROM test_acquisition_rpc_entities entity;

INSERT INTO public.acquisition_offers(
    id, environment_id, request_id, supplier_id, created_by, vin,
    model, version, year, mileage, declared_soh, color, price_mxn,
    transfer_included, status, submitted_at, updated_at
)
SELECT
    'ad240000-0000-4000-8000-000000000003', entity.environment_id,
    entity.request_id, 'ad210000-0000-4000-8000-000000000001',
    'ad200000-0000-4000-8000-000000000002', 'LGXCE6CB1S0000033',
    'Dolphin Mini', 'Plus', 2025, 7300, 94, 'Gris', 276000,
    true, 'submitted', app.env_now(entity.environment_id), app.env_now(entity.environment_id)
FROM test_acquisition_rpc_entities entity;

-- Proveedor A envia la unidad. Toda recomendacion se calcula dentro del RPC.
SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.submit_acquisition_offer(
        'ad240000-0000-4000-8000-000000000001',
        (SELECT request_id FROM test_acquisition_rpc_entities),
        'LGXCE6CB1S0000011', 'Dolphin Mini', 'Plus', 2025, 8400, 96,
        'Blanco', 274000, true,
        jsonb_build_array(
            jsonb_build_object('kind','vin','path',(SELECT path_prefix || 'vin.jpg' FROM test_acquisition_rpc_entities)),
            jsonb_build_object('kind','front','path',(SELECT path_prefix || 'front.jpg' FROM test_acquisition_rpc_entities)),
            jsonb_build_object('kind','dashboard','path',(SELECT path_prefix || 'dashboard.jpg' FROM test_acquisition_rpc_entities))
        ),
        'adq-rpc-submit-1'
    ) $sql$,
    'Proveedor A envia una oferta con tres evidencias propias'
);
SELECT lives_ok(
    $sql$ SELECT public.submit_acquisition_offer(
        'ad240000-0000-4000-8000-000000000001',
        (SELECT request_id FROM test_acquisition_rpc_entities),
        'LGXCE6CB1S0000011', 'Dolphin Mini', 'Plus', 2025, 8400, 96,
        'Blanco', 274000, true,
        jsonb_build_array(
            jsonb_build_object('kind','vin','path',(SELECT path_prefix || 'vin.jpg' FROM test_acquisition_rpc_entities)),
            jsonb_build_object('kind','front','path',(SELECT path_prefix || 'front.jpg' FROM test_acquisition_rpc_entities)),
            jsonb_build_object('kind','dashboard','path',(SELECT path_prefix || 'dashboard.jpg' FROM test_acquisition_rpc_entities))
        ),
        'adq-rpc-submit-1'
    ) $sql$,
    'reenviar con la misma llave es idempotente'
);
SELECT throws_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000001', 'award', NULL, NULL, 'adq-provider-award-denied'
    ) $sql$,
    '42501', 'dori_award_not_allowed',
    'el proveedor no puede adjudicarse su propia unidad'
);
SELECT throws_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000002', 'reject', NULL, NULL, 'adq-provider-reject-denied'
    ) $sql$,
    '42501', 'dori_reject_not_allowed',
    'el proveedor no puede rechazar una propuesta en nombre de DORI'
);
SELECT lives_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000003', 'counteroffer', 271000,
        'Podemos ajustar a este importe.', 'adq-provider-counter-1'
    ) $sql$,
    'el proveedor envia una contraoferta a DORI'
);
RESET ROLE;

SELECT is((SELECT count(*)::bigint FROM public.acquisition_offers WHERE id = 'ad240000-0000-4000-8000-000000000001'), 1::bigint, 'la oferta idempotente existe una sola vez');
SELECT is((SELECT count(*)::bigint FROM public.acquisition_evidence WHERE offer_id = 'ad240000-0000-4000-8000-000000000001'), 3::bigint, 'la oferta conserva tres evidencias');
SELECT is((SELECT recommendation FROM public.acquisition_offer_assessments WHERE offer_id = 'ad240000-0000-4000-8000-000000000001'), 'buy', 'el servidor recomienda comprar la unidad viable');

-- Proveedor B no puede leer ni actuar sobre la oferta de A.
SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000003', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000001', 'counteroffer', 260000, 'Intento ajeno', 'adq-rpc-cross-provider'
    ) $sql$,
    '42501', 'acquisition_offer_access_denied',
    'Proveedor B no puede negociar la oferta de Proveedor A'
);
RESET ROLE;

-- DORI contraoferta y el proveedor acepta.
SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000006', 'accept', NULL,
        'Aceptamos la ultima contraoferta.', 'adq-rpc-frozen-clock-accept'
    ) $sql$,
    'DORI acepta la ultima contraoferta aunque el reloj TEST este congelado'
);
SELECT is(
    (SELECT agreed_price_mxn FROM public.acquisition_offers
     WHERE id = 'ad240000-0000-4000-8000-000000000006'),
    271000::numeric,
    'el orden transaccional conserva la ultima contraoferta del proveedor'
);
SELECT lives_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000001', 'counteroffer', 268000,
        'Podemos cerrar en este precio.', 'adq-rpc-counter-1'
    ) $sql$,
    'DORI envia una contraoferta'
);
SELECT lives_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000002', 'reject', NULL,
        'No continuaremos con esta unidad.', 'adq-rpc-reject-1'
    ) $sql$,
    'DORI cierra una propuesta sin compra'
);
SELECT is(
    (SELECT status FROM public.acquisition_offers WHERE id = 'ad240000-0000-4000-8000-000000000002'),
    'rejected',
    'la propuesta rechazada conserva su estado comercial final'
);
SELECT throws_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000002', 'reject', NULL, NULL, 'adq-rpc-reject-invalid-repeat'
    ) $sql$,
    '42501', 'dori_reject_not_allowed',
    'el backend rechaza una transicion repetida desde un estado final'
);
SELECT is(
    (SELECT actor_role FROM public.acquisition_negotiations
     WHERE offer_id = 'ad240000-0000-4000-8000-000000000003'
     ORDER BY created_at DESC, id DESC LIMIT 1),
    'provider',
    'DORI recibe la contraoferta persistida del proveedor'
);
SELECT lives_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000003', 'award', 271000,
        'Compra confirmada al importe contraofertado.', 'adq-rpc-award-provider-counter-1'
    ) $sql$,
    'DORI adjudica al importe contraofertado por el proveedor'
);
SELECT is(
    (SELECT final_price_mxn FROM public.acquisition_orders
     WHERE offer_id = 'ad240000-0000-4000-8000-000000000003'),
    271000::numeric,
    'la adjudicacion conserva el importe comercial visible'
);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000001', 'accept', NULL,
        'Aceptamos.', 'adq-rpc-accept-1'
    ) $sql$,
    'Proveedor A acepta la contraoferta de DORI'
);
RESET ROLE;

SELECT results_eq(
    $sql$ SELECT status, agreed_price_mxn FROM public.acquisition_offers WHERE id = 'ad240000-0000-4000-8000-000000000001' $sql$,
    $sql$ VALUES ('price_agreed'::text, 268000::numeric) $sql$,
    'la oferta conserva el precio acordado'
);

-- Solo DORI adjudica.
SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.respond_acquisition_offer(
        'ad240000-0000-4000-8000-000000000001', 'award', NULL,
        'Unidad adjudicada.', 'adq-rpc-award-1'
    ) $sql$,
    'DORI adjudica la unidad al precio acordado'
);
RESET ROLE;

CREATE TEMP TABLE test_acquisition_order AS
SELECT id AS order_id FROM public.acquisition_orders
WHERE offer_id = 'ad240000-0000-4000-8000-000000000001';
GRANT SELECT ON test_acquisition_order TO authenticated;

CREATE TEMP TABLE test_acquisition_second_order AS
SELECT id AS order_id FROM public.acquisition_orders
WHERE offer_id = 'ad240000-0000-4000-8000-000000000003';
GRANT SELECT ON test_acquisition_second_order TO authenticated;

INSERT INTO public.acquisition_offers(
    id, environment_id, request_id, supplier_id, created_by, vin,
    model, version, year, mileage, declared_soh, color, price_mxn,
    transfer_included, status, agreed_price_mxn, submitted_at, updated_at
)
SELECT fixture.offer_id, entity.environment_id, entity.request_id,
       'ad210000-0000-4000-8000-000000000001',
       'ad200000-0000-4000-8000-000000000002', fixture.vin,
       'Dolphin Mini', 'Plus', 2025, fixture.mileage, 94, 'Blanco', 270000,
       true, 'ready_for_delivery', 268000,
       app.env_now(entity.environment_id), app.env_now(entity.environment_id)
FROM test_acquisition_rpc_entities entity
CROSS JOIN (VALUES
    ('ad240000-0000-4000-8000-000000000004'::uuid, 'LGXCE6CB1S0000044'::text, 8700),
    ('ad240000-0000-4000-8000-000000000005'::uuid, 'LGXCE6CB1S0000055'::text, 8800)
) fixture(offer_id, vin, mileage);

INSERT INTO public.acquisition_orders(
    id, environment_id, code, offer_id, supplier_id, final_price_mxn,
    payment_status, status, awarded_by, awarded_at
)
SELECT fixture.order_id, entity.environment_id, fixture.code, fixture.offer_id,
       'ad210000-0000-4000-8000-000000000001', 268000,
       'simulated', 'ready_for_delivery',
       'ad200000-0000-4000-8000-000000000001', app.env_now(entity.environment_id)
FROM test_acquisition_rpc_entities entity
CROSS JOIN (VALUES
    ('ad250000-0000-4000-8000-000000000004'::uuid, 'ADQ-RPC-OBS'::text, 'ad240000-0000-4000-8000-000000000004'::uuid),
    ('ad250000-0000-4000-8000-000000000005'::uuid, 'ADQ-RPC-REJECT'::text, 'ad240000-0000-4000-8000-000000000005'::uuid)
) fixture(order_id, code, offer_id);

INSERT INTO public.acquisition_deliveries(environment_id, order_id, status, ready_at)
SELECT entity.environment_id, fixture.order_id, 'ready', app.env_now(entity.environment_id)
FROM test_acquisition_rpc_entities entity
CROSS JOIN (VALUES
    ('ad250000-0000-4000-8000-000000000004'::uuid),
    ('ad250000-0000-4000-8000-000000000005'::uuid)
) fixture(order_id);

SELECT results_eq(
    $sql$ SELECT status, final_price_mxn, payment_status FROM public.acquisition_orders WHERE id = (SELECT order_id FROM test_acquisition_order) $sql$,
    $sql$ VALUES ('awarded'::text, 268000::numeric, 'simulated'::text) $sql$,
    'la orden nace adjudicada con pago simulado'
);

-- Proveedor prepara; DORI recibe con una segunda llave faltante.
SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        (SELECT order_id FROM test_acquisition_order), 'ready', NULL, NULL,
        'Unidad lista para entregar.', NULL, 'adq-rpc-ready-1'
    ) $sql$,
    'Proveedor A marca la unidad lista para entregar'
);
SELECT lives_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        (SELECT order_id FROM test_acquisition_second_order), 'ready', NULL, NULL,
        'Segunda unidad lista.', NULL, 'adq-rpc-ready-normal'
    ) $sql$,
    'Proveedor A prepara una segunda unidad para recepcion normal'
);
SELECT throws_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        (SELECT order_id FROM test_acquisition_order), 'receive',
        '{"vin_correct":true,"mileage_correct":true,"chargers_complete":true,"keys_complete":false,"new_damage":false}'::jsonb,
        'accepted_with_condition', 'Falta segunda llave.', 6000, 'adq-provider-receive-denied'
    ) $sql$,
    '42501', 'dori_reception_not_allowed',
    'el proveedor no puede recibir su propia unidad'
);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        (SELECT order_id FROM test_acquisition_second_order), 'receive',
        '{"vin_correct":true,"mileage_correct":true,"chargers_complete":true,"keys_complete":true,"new_damage":false}'::jsonb,
        'rejected', 'Intento de contradecir el resultado.', NULL, 'adq-rpc-result-mismatch'
    ) $sql$,
    '22023', 'reception_result_must_match_server_recommendation',
    'el backend impide que el cliente contradiga el resultado calculado'
);
SELECT lives_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        (SELECT order_id FROM test_acquisition_second_order), 'receive',
        '{"vin_correct":true,"mileage_correct":true,"chargers_complete":true,"keys_complete":true,"new_damage":false}'::jsonb,
        NULL, NULL, NULL, 'adq-rpc-receive-normal'
    ) $sql$,
    'DORI recibe una unidad correcta con resultado decidido por backend'
);
SELECT results_eq(
    $sql$ SELECT recommended_result, result, hold_amount_mxn
          FROM public.acquisition_receptions
          WHERE order_id = (SELECT order_id FROM test_acquisition_second_order) $sql$,
    $sql$ VALUES ('accepted'::text, 'accepted'::text, 0::numeric) $sql$,
    'la recepcion normal queda aceptada sin retencion'
);
SELECT lives_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        'ad250000-0000-4000-8000-000000000004', 'receive',
        '{"vin_correct":true,"mileage_correct":true,"chargers_complete":true,"keys_complete":true,"new_damage":true}'::jsonb,
        NULL, 'Rayon menor en defensa.', NULL, 'adq-rpc-receive-observation'
    ) $sql$,
    'DORI recibe una unidad con observaciones'
);
SELECT results_eq(
    $sql$ SELECT recommended_result, result, issue_summary
          FROM public.acquisition_receptions
          WHERE order_id = 'ad250000-0000-4000-8000-000000000004' $sql$,
    $sql$ VALUES ('accepted_with_observations'::text, 'accepted_with_observations'::text, 'Rayon menor en defensa.'::text) $sql$,
    'la observacion queda persistida con el resultado del backend'
);
SELECT lives_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        'ad250000-0000-4000-8000-000000000005', 'receive',
        '{"vin_correct":false,"mileage_correct":true,"chargers_complete":true,"keys_complete":true,"new_damage":false}'::jsonb,
        NULL, 'El VIN no corresponde a la orden.', NULL, 'adq-rpc-receive-rejected'
    ) $sql$,
    'DORI registra una no aceptacion material con causa'
);
SELECT results_eq(
    $sql$ SELECT status, payment_status, closed_at IS NOT NULL
          FROM public.acquisition_orders
          WHERE id = 'ad250000-0000-4000-8000-000000000005' $sql$,
    $sql$ VALUES ('rejected'::text, 'cancelled'::text, true) $sql$,
    'la no aceptacion material cierra la orden simulada sin pago'
);
SELECT lives_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        (SELECT order_id FROM test_acquisition_order), 'receive',
        '{"vin_correct":true,"mileage_correct":true,"chargers_complete":true,"keys_complete":false,"new_damage":false}'::jsonb,
        NULL, 'Falta segunda llave.', NULL, 'adq-rpc-receive-1'
    ) $sql$,
    'DORI acepta con condicion y retencion'
);
RESET ROLE;

SELECT results_eq(
    $sql$ SELECT recommended_result, result, hold_amount_mxn FROM public.acquisition_receptions WHERE order_id = (SELECT order_id FROM test_acquisition_order) $sql$,
    $sql$ VALUES ('accepted_with_condition'::text, 'accepted_with_condition'::text, 6000::numeric) $sql$,
    'el servidor recomienda y registra la condicion por llave faltante'
);
SELECT results_eq(
    $sql$ SELECT status, amount_mxn FROM public.acquisition_holds WHERE order_id = (SELECT order_id FROM test_acquisition_order) $sql$,
    $sql$ VALUES ('pending_supplier'::text, 6000::numeric) $sql$,
    'la retencion queda pendiente del proveedor'
);

SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        (SELECT order_id FROM test_acquisition_order), 'close_condition', NULL, NULL,
        'Intento del proveedor.', NULL, 'adq-provider-close-denied'
    ) $sql$,
    '42501', 'dori_condition_close_not_allowed',
    'el proveedor no puede confirmar ni cerrar su propia condicion'
);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        (SELECT order_id FROM test_acquisition_second_order), 'receive',
        '{"vin_correct":true,"mileage_correct":true,"chargers_complete":true,"keys_complete":true,"new_damage":false}'::jsonb,
        NULL, NULL, NULL, 'adq-dori-repeat-receive-denied'
    ) $sql$,
    '42501', 'dori_reception_not_allowed',
    'DORI no puede recibir una orden que ya salio del estado esperado'
);
RESET ROLE;

-- El proveedor resuelve y DORI confirma el cierre.
SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        (SELECT order_id FROM test_acquisition_order), 'resolve_condition', NULL, NULL,
        'Segunda llave entregada.', NULL, 'adq-rpc-resolve-1'
    ) $sql$,
    'Proveedor A informa que resolvio el faltante'
);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad200000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.complete_acquisition_delivery(
        (SELECT order_id FROM test_acquisition_order), 'close_condition', NULL, NULL,
        'Llave recibida y verificada.', NULL, 'adq-rpc-close-1'
    ) $sql$,
    'DORI confirma el faltante y cierra la adquisicion'
);
RESET ROLE;

SELECT results_eq(
    $sql$ SELECT status, payment_status, closed_at IS NOT NULL FROM public.acquisition_orders WHERE id = (SELECT order_id FROM test_acquisition_order) $sql$,
    $sql$ VALUES ('closed'::text, 'simulated'::text, true) $sql$,
    'la orden termina cerrada y el pago sigue simulado'
);
SELECT results_eq(
    $sql$ SELECT status, supplier_resolution_note, resolved_at IS NOT NULL FROM public.acquisition_holds WHERE order_id = (SELECT order_id FROM test_acquisition_order) $sql$,
    $sql$ VALUES ('resolved'::text, 'Segunda llave entregada.'::text, true) $sql$,
    'la retencion conserva la resolucion y confirmacion'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.command_log WHERE idempotency_key LIKE 'adq-%'),
    17::bigint,
    'las diecisiete decisiones exitosas quedan en command_log sin duplicados'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.audit_log WHERE event_type LIKE 'acquisition.%' AND actor_profile_id IN (
        'ad200000-0000-4000-8000-000000000001'::uuid,
        'ad200000-0000-4000-8000-000000000002'::uuid
    )),
    17::bigint,
    'las diecisiete decisiones exitosas reutilizan audit_log'
);

SELECT * FROM finish();
ROLLBACK;
