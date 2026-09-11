BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(21);

SELECT has_table('public', 'acquisition_chat_threads', 'existen conversaciones institucionales');
SELECT has_table('public', 'acquisition_chat_messages', 'existen mensajes institucionales');
SELECT has_table('public', 'acquisition_chat_read_receipts', 'existen lecturas por usuario');
SELECT has_function(
    'public', 'ensure_acquisition_chat_thread', ARRAY['uuid', 'uuid'],
    'existe RPC para resolver chat general o por unidad'
);
SELECT has_function(
    'public', 'send_acquisition_chat_message', ARRAY['uuid', 'text', 'text', 'text'],
    'existe RPC para enviar mensajes inmutables'
);
SELECT has_function(
    'public', 'mark_acquisition_chat_read', ARRAY['uuid', 'bigint'],
    'existe RPC para marcar lectura'
);

CREATE TEMP TABLE test_chat_scope AS
SELECT id AS environment_id FROM public.environments ORDER BY created_at, id LIMIT 1;

INSERT INTO public.profiles(id, environment_id, employee_number, display_name, status)
SELECT fixture.id, scope.environment_id, fixture.employee_number, fixture.display_name, 'active'
FROM test_chat_scope scope
CROSS JOIN (VALUES
    ('ad800000-0000-4000-8000-000000000001'::uuid, 'CHAT-ADMIN', 'Administrador Chat'),
    ('ad800000-0000-4000-8000-000000000002'::uuid, 'CHAT-PROV-A', 'Proveedor Chat A'),
    ('ad800000-0000-4000-8000-000000000003'::uuid, 'CHAT-PROV-B', 'Proveedor Chat B')
) fixture(id, employee_number, display_name);

INSERT INTO public.acquisition_suppliers(id, environment_id, code, name, city)
SELECT fixture.id, scope.environment_id, fixture.code, fixture.name, 'Puebla'
FROM test_chat_scope scope
CROSS JOIN (VALUES
    ('ad810000-0000-4000-8000-000000000001'::uuid, 'CHAT-A', 'Agencia Chat A'),
    ('ad810000-0000-4000-8000-000000000002'::uuid, 'CHAT-B', 'Agencia Chat B')
) fixture(id, code, name);

INSERT INTO public.acquisition_memberships(
    id, environment_id, profile_id, supplier_id, role, status, starts_at
)
SELECT fixture.id, scope.environment_id, fixture.profile_id, fixture.supplier_id,
       fixture.role, 'active', app.env_now(scope.environment_id) - interval '1 day'
FROM test_chat_scope scope
CROSS JOIN (VALUES
    ('ad820000-0000-4000-8000-000000000001'::uuid, 'ad800000-0000-4000-8000-000000000001'::uuid, NULL::uuid, 'dori_admin'),
    ('ad820000-0000-4000-8000-000000000002'::uuid, 'ad800000-0000-4000-8000-000000000002'::uuid, 'ad810000-0000-4000-8000-000000000001'::uuid, 'provider'),
    ('ad820000-0000-4000-8000-000000000003'::uuid, 'ad800000-0000-4000-8000-000000000003'::uuid, 'ad810000-0000-4000-8000-000000000002'::uuid, 'provider')
) fixture(id, profile_id, supplier_id, role);

INSERT INTO public.acquisition_requests(
    id, environment_id, code, title, target_quantity, model, versions,
    minimum_year, maximum_year, maximum_mileage, delivery_city,
    status, published_by, published_at
)
SELECT 'ad830000-0000-4000-8000-000000000001', scope.environment_id,
       'CHAT-REQ', 'Solicitud chat', 2, 'Dolphin Mini', ARRAY['Plus'],
       2025, 2026, 20000, 'Puebla', 'evaluating',
       'ad800000-0000-4000-8000-000000000001', app.env_now(scope.environment_id)
FROM test_chat_scope scope;

INSERT INTO public.acquisition_offers(
    id, environment_id, request_id, supplier_id, created_by, vin,
    model, version, year, mileage, color, price_mxn,
    transfer_included, status, submitted_at, updated_at
)
SELECT fixture.offer_id, scope.environment_id,
       'ad830000-0000-4000-8000-000000000001', fixture.supplier_id,
       fixture.profile_id, fixture.vin, 'Dolphin Mini', 'Plus', 2025,
       8400, 'Blanco', 274000, true, 'submitted',
       app.env_now(scope.environment_id), app.env_now(scope.environment_id)
FROM test_chat_scope scope
CROSS JOIN (VALUES
    ('ad840000-0000-4000-8000-000000000001'::uuid, 'ad810000-0000-4000-8000-000000000001'::uuid, 'ad800000-0000-4000-8000-000000000002'::uuid, 'LGXCE6CB1S0084011'::text),
    ('ad840000-0000-4000-8000-000000000002'::uuid, 'ad810000-0000-4000-8000-000000000002'::uuid, 'ad800000-0000-4000-8000-000000000003'::uuid, 'LGXCE6CB1S0084022'::text)
) fixture(offer_id, supplier_id, profile_id, vin);

CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

SELECT set_config('request.jwt.claim.sub', 'ad800000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.ensure_acquisition_chat_thread(
        'ad810000-0000-4000-8000-000000000001',
        'ad840000-0000-4000-8000-000000000001'
    ) $sql$,
    'DORI abre chat por unidad del proveedor A'
);
RESET ROLE;

CREATE TEMP TABLE test_chat_thread AS
SELECT id AS thread_id, environment_id
FROM public.acquisition_chat_threads
WHERE offer_id = 'ad840000-0000-4000-8000-000000000001';
GRANT SELECT ON test_chat_thread TO authenticated;

SELECT set_config('request.jwt.claim.sub', 'ad800000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.ensure_acquisition_chat_thread(
        'ad810000-0000-4000-8000-000000000001', NULL
    ) $sql$,
    'Proveedor abre su chat general'
);
SELECT lives_ok(
    $sql$ SELECT public.send_acquisition_chat_message(
        (SELECT thread_id FROM test_chat_thread),
        'La unidad está disponible para revisión.', NULL, 'chat-provider-message-1'
    ) $sql$,
    'Proveedor envia mensaje por RPC'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.acquisition_chat_messages
     WHERE thread_id = (SELECT thread_id FROM test_chat_thread)),
    1::bigint,
    'Proveedor ve el mensaje de su unidad'
);
RESET ROLE;

SELECT ok(
    NOT has_table_privilege('authenticated', 'public.acquisition_chat_messages', 'INSERT'),
    'authenticated no inserta mensajes directamente'
);
SELECT ok(
    NOT has_table_privilege('authenticated', 'public.acquisition_chat_messages', 'UPDATE'),
    'mensajes no se modifican'
);
SELECT ok(
    NOT has_table_privilege('authenticated', 'public.acquisition_chat_messages', 'DELETE'),
    'mensajes no se eliminan'
);

SELECT set_config('request.jwt.claim.sub', 'ad800000-0000-4000-8000-000000000003', true);
SET LOCAL ROLE authenticated;
SELECT is(
    (SELECT count(*)::bigint FROM public.acquisition_chat_messages
     WHERE thread_id = (SELECT thread_id FROM test_chat_thread)),
    0::bigint,
    'Proveedor B no lee mensajes del proveedor A'
);
SELECT throws_ok(
    $sql$ SELECT public.send_acquisition_chat_message(
        (SELECT thread_id FROM test_chat_thread), 'Intento ajeno', NULL, 'chat-cross-provider'
    ) $sql$,
    '42501', 'acquisition_chat_access_denied',
    'Proveedor B no escribe en chat del proveedor A'
);
RESET ROLE;

INSERT INTO storage.objects(id, bucket_id, name, owner_id, metadata)
SELECT gen_random_uuid(), 'acquisition-chat-attachments',
       scope.environment_id::text
           || '/ad810000-0000-4000-8000-000000000001/'
           || thread.thread_id::text || '/evidencia.jpg',
       'ad800000-0000-4000-8000-000000000002',
       jsonb_build_object('mimetype', 'image/jpeg')
FROM test_chat_scope scope CROSS JOIN test_chat_thread thread;

SELECT set_config('request.jwt.claim.sub', 'ad800000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.send_acquisition_chat_message(
        (SELECT thread_id FROM test_chat_thread), 'Adjunto de la unidad',
        (SELECT environment_id::text
            || '/ad810000-0000-4000-8000-000000000001/'
            || thread_id::text || '/evidencia.jpg' FROM test_chat_thread),
        'chat-provider-attachment-1'
    ) $sql$,
    'Proveedor envia adjunto privado propio'
);
SELECT lives_ok(
    $sql$ SELECT public.mark_acquisition_chat_read(
        (SELECT thread_id FROM test_chat_thread), 999999
    ) $sql$,
    'Proveedor marca la conversacion como leida'
);
SELECT is(
    (SELECT unread_count FROM public.list_acquisition_chat_threads()
     WHERE thread_id = (SELECT thread_id FROM test_chat_thread)),
    0::bigint,
    'El contador del proveedor queda en cero'
);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad800000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT is(
    (SELECT unread_count FROM public.list_acquisition_chat_threads()
     WHERE thread_id = (SELECT thread_id FROM test_chat_thread)),
    2::bigint,
    'DORI recibe badge por los dos mensajes del proveedor'
);
SELECT lives_ok(
    $sql$ SELECT public.send_acquisition_chat_message(
        (SELECT thread_id FROM test_chat_thread),
        'Recibido. Revisaremos la unidad.', NULL, 'chat-dori-message-1'
    ) $sql$,
    'DORI responde dentro del mismo chat'
);
RESET ROLE;

INSERT INTO public.audit_log(
    environment_id, actor_profile_id, event_type, entity_type,
    entity_id, metadata, occurred_at
)
SELECT scope.environment_id, 'ad800000-0000-4000-8000-000000000001',
       'acquisition.offer.counteroffer', 'acquisition_offer',
       'ad840000-0000-4000-8000-000000000001',
       jsonb_build_object('actor_role', 'dori_admin'), app.env_now(scope.environment_id)
FROM test_chat_scope scope;

SELECT is(
    (SELECT body FROM public.acquisition_chat_messages
     WHERE system_event_type = 'acquisition.offer.counteroffer'
     ORDER BY event_sequence DESC LIMIT 1),
    'DORI envió una oferta.',
    'La accion comercial genera un evento automatico en español'
);

SELECT finish();
ROLLBACK;
