BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(40);

SELECT has_table('public', 'candidates', '15H crea candidatos');
SELECT has_table('public', 'candidate_documents', '15H crea documentos de candidatos');
SELECT has_table('public', 'hirings', '15H crea altas');
SELECT has_function(
    'public', 'upload_document',
    ARRAY['uuid', 'text', 'text', 'text', 'date', 'date', 'text', 'text'],
    'expone upload_document con contrato estable'
);
SELECT has_function(
    'public', 'sign_hiring', ARRAY['uuid', 'text', 'text'],
    'expone sign_hiring con contrato estable'
);
SELECT is(
    (SELECT public FROM storage.buckets WHERE id = 'candidate-documents'),
    false,
    'el bucket de expedientes es privado'
);
SELECT is(
    has_function_privilege('authenticated', 'public.complete_hiring(uuid,uuid)', 'EXECUTE'),
    false,
    'authenticated no puede completar un alta privilegiada'
);
SELECT is(
    has_function_privilege('service_role', 'public.complete_hiring(uuid,uuid)', 'EXECUTE'),
    true,
    'service_role puede completar un alta'
);
SELECT is(
    has_function_privilege('authenticated', 'public.resolve_hiring_auth_user(uuid)', 'EXECUTE'),
    false,
    'authenticated no puede resolver identidades de Auth'
);

INSERT INTO public.stations(id, environment_id, region_id, code, name, status, timezone)
SELECT
    '15840000-0000-4000-8000-000000000001', region.environment_id, region.id,
    '15h-rpc-station', '15H RPC Station', 'active', 'America/Mexico_City'
FROM public.regions region
ORDER BY region.created_at, region.id
LIMIT 1;

CREATE TEMP TABLE test_15h_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = '15840000-0000-4000-8000-000000000001';

UPDATE app.env_clock clock
SET is_simulated = true,
    anchor_logical_at = '2026-09-03 18:00:00+00',
    anchor_real_at = now(),
    speed = 1,
    is_paused = true
FROM test_15h_scope scope
WHERE clock.environment_id = scope.environment_id;

INSERT INTO public.profiles(id, environment_id, employee_number, display_name, status)
SELECT fixture.id, scope.environment_id, fixture.employee_number, fixture.display_name, 'active'
FROM test_15h_scope scope
CROSS JOIN (VALUES
    ('15800000-0000-4000-8000-000000000001'::uuid, '15H-RECRUITER', '15H Recruiter'),
    ('15800000-0000-4000-8000-000000000002'::uuid, '15H-MANAGER', '15H Manager')
) fixture(id, employee_number, display_name);

INSERT INTO public.staff_memberships(
    id, environment_id, profile_id, station_id, role, starts_at
)
SELECT fixture.id, scope.environment_id, fixture.profile_id, scope.station_id,
       fixture.role, '2026-01-01 00:00:00+00'
FROM test_15h_scope scope
CROSS JOIN (VALUES
    ('15810000-0000-4000-8000-000000000001'::uuid, '15800000-0000-4000-8000-000000000001'::uuid, 'recruitment'),
    ('15810000-0000-4000-8000-000000000002'::uuid, '15800000-0000-4000-8000-000000000002'::uuid, 'management')
) fixture(id, profile_id, role);

INSERT INTO public.candidates(
    id, environment_id, station_id, created_by, full_name, phone, email,
    city, age, curp, requested_shift_group, requested_shift_slot, stage,
    screening_status, interview_score, interview_decision
)
SELECT
    '15820000-0000-4000-8000-000000000001', scope.environment_id,
    scope.station_id, '15800000-0000-4000-8000-000000000001',
    'Conductor Alta 15H', '2221234567', 'driver.15h@joramza.test',
    'Puebla', 30, 'HITC960101HPLABC01', 'weekday', 'morning', 'documents',
    'fit', 95, 'recommended'
FROM test_15h_scope scope;

INSERT INTO storage.objects(bucket_id, name, owner_id, metadata)
SELECT
    'candidate-documents',
    scope.environment_id::text || '/' || scope.station_id::text ||
        '/15820000-0000-4000-8000-000000000001/' || fixture.filename,
    '15800000-0000-4000-8000-000000000001',
    jsonb_build_object('mimetype', fixture.content_type, 'size', 1024)
FROM test_15h_scope scope
CROSS JOIN (VALUES
    ('official-id.pdf', 'application/pdf'),
    ('curp.pdf', 'application/pdf'),
    ('rfc.pdf', 'application/pdf'),
    ('license.jpg', 'image/jpeg'),
    ('address.png', 'image/png'),
    ('photo.heic', 'image/heic')
) fixture(filename, content_type);

CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

SELECT set_config('request.jwt.claim.sub', '15800000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$
        SELECT public.upload_document(
            '15820000-0000-4000-8000-000000000001', 'officialId',
            (SELECT environment_id::text || '/' || station_id::text || '/15820000-0000-4000-8000-000000000001/official-id.pdf' FROM test_15h_scope),
            'official-id.pdf', NULL, NULL, NULL, '15h-forbidden'
        )
    $sql$,
    '42501', 'document_upload_forbidden',
    'gerencia no puede registrar documentos como reclutamiento'
);
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', '15800000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$
        SELECT public.upload_document(
            '15820000-0000-4000-8000-000000000001', 'officialId',
            (SELECT environment_id::text || '/' || station_id::text || '/15820000-0000-4000-8000-000000000001/official-id.pdf' FROM test_15h_scope),
            'official-id.pdf', NULL, NULL, repeat('a', 64), '15h-doc-1'
        )
    $sql$,
    'reclutamiento registra identificacion oficial'
);
SELECT lives_ok(
    $sql$
        SELECT public.upload_document(
            '15820000-0000-4000-8000-000000000001', 'officialId',
            (SELECT environment_id::text || '/' || station_id::text || '/15820000-0000-4000-8000-000000000001/official-id.pdf' FROM test_15h_scope),
            'official-id.pdf', NULL, NULL, repeat('a', 64), '15h-doc-1'
        )
    $sql$,
    'registro documental es idempotente'
);
RESET ROLE;
SELECT is((SELECT count(*)::bigint FROM public.candidate_documents), 1::bigint, 'reintento no duplica documento');

SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$
        SELECT public.upload_document(
            '15820000-0000-4000-8000-000000000001', 'officialId',
            (SELECT environment_id::text || '/' || station_id::text || '/15820000-0000-4000-8000-000000000001/curp.pdf' FROM test_15h_scope),
            'curp.pdf', NULL, NULL, NULL, '15h-doc-1'
        )
    $sql$,
    '23505', 'idempotency_key_conflict',
    'una clave no puede representar otra solicitud'
);

SELECT lives_ok(
    $sql$ SELECT public.upload_document(
        '15820000-0000-4000-8000-000000000001', 'curp',
        (SELECT environment_id::text || '/' || station_id::text || '/15820000-0000-4000-8000-000000000001/curp.pdf' FROM test_15h_scope),
        'curp.pdf', '2026-01-01', NULL, NULL, '15h-doc-2') $sql$,
    'registra CURP'
);
SELECT lives_ok(
    $sql$ SELECT public.upload_document(
        '15820000-0000-4000-8000-000000000001', 'rfc',
        (SELECT environment_id::text || '/' || station_id::text || '/15820000-0000-4000-8000-000000000001/rfc.pdf' FROM test_15h_scope),
        'rfc.pdf', '2026-01-01', NULL, NULL, '15h-doc-3') $sql$,
    'registra RFC'
);
SELECT lives_ok(
    $sql$ SELECT public.upload_document(
        '15820000-0000-4000-8000-000000000001', 'license',
        (SELECT environment_id::text || '/' || station_id::text || '/15820000-0000-4000-8000-000000000001/license.jpg' FROM test_15h_scope),
        'license.jpg', '2026-01-01', '2027-01-01', NULL, '15h-doc-4') $sql$,
    'registra licencia vigente'
);
SELECT lives_ok(
    $sql$ SELECT public.upload_document(
        '15820000-0000-4000-8000-000000000001', 'addressProof',
        (SELECT environment_id::text || '/' || station_id::text || '/15820000-0000-4000-8000-000000000001/address.png' FROM test_15h_scope),
        'address.png', '2026-08-01', NULL, NULL, '15h-doc-5') $sql$,
    'registra comprobante de domicilio'
);
SELECT lives_ok(
    $sql$ SELECT public.upload_document(
        '15820000-0000-4000-8000-000000000001', 'photo',
        (SELECT environment_id::text || '/' || station_id::text || '/15820000-0000-4000-8000-000000000001/photo.heic' FROM test_15h_scope),
        'photo.heic', NULL, NULL, NULL, '15h-doc-6') $sql$,
    'registra fotografia'
);
RESET ROLE;

SELECT is((SELECT stage FROM public.candidates), 'ready_to_hire', 'seis documentos vigentes habilitan el alta');
SELECT is((SELECT count(*)::bigint FROM public.candidate_documents WHERE status = 'accepted'), 6::bigint, 'conserva seis documentos vigentes');

SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$ SELECT public.sign_hiring(
        '15820000-0000-4000-8000-000000000001', 'DRV-15H-001', '15h-hiring-1') $sql$,
    'reclutamiento firma el alta'
);
SELECT lives_ok(
    $sql$ SELECT public.sign_hiring(
        '15820000-0000-4000-8000-000000000001', 'DRV-15H-001', '15h-hiring-1') $sql$,
    'firma del alta es idempotente'
);
RESET ROLE;

SELECT is((SELECT count(*)::bigint FROM public.hirings), 1::bigint, 'reintento no duplica el alta');
SELECT is((SELECT status FROM public.hirings), 'identity_pending', 'alta espera la identidad de Auth');
SELECT is((SELECT stage FROM public.candidates), 'approved', 'candidato queda reservado');
SELECT is((SELECT status FROM public.command_log WHERE idempotency_key = '15h-hiring-1'), 'accepted', 'comando espera finalizar Auth');

INSERT INTO auth.users(id, email)
VALUES ('15890000-0000-4000-8000-000000000001', 'driver.15h@joramza.test');

SELECT is(
    public.resolve_hiring_auth_user((SELECT id FROM public.hirings)),
    '15890000-0000-4000-8000-000000000001'::uuid,
    'servicio recupera una identidad creada antes de un reintento'
);

SELECT lives_ok(
    $sql$ SELECT public.complete_hiring(
        (SELECT id FROM public.hirings),
        '15890000-0000-4000-8000-000000000001') $sql$,
    'servicio completa perfil, membresia y conductor'
);
SELECT lives_ok(
    $sql$ SELECT public.complete_hiring(
        (SELECT id FROM public.hirings),
        '15890000-0000-4000-8000-000000000001') $sql$,
    'finalizacion privilegiada es idempotente'
);

SELECT results_eq(
    $sql$ SELECT status, revision, auth_user_id IS NOT NULL FROM public.hirings $sql$,
    $sql$ VALUES ('completed'::text, 2::bigint, true) $sql$,
    'alta termina enlazada y avanza revision'
);
SELECT results_eq(
    $sql$ SELECT stage, revision, hired_at IS NOT NULL FROM public.candidates $sql$,
    $sql$ VALUES ('hired'::text, 9::bigint, true) $sql$,
    'candidato termina contratado con historia de revision'
);
SELECT is((SELECT count(*)::bigint FROM public.profiles WHERE employee_number = 'DRV-15H-001'), 1::bigint, 'crea un perfil real');
SELECT is((SELECT count(*)::bigint FROM public.staff_memberships WHERE role = 'driver' AND profile_id = (SELECT profile_id FROM public.hirings)), 1::bigint, 'crea membresia de conductor');
SELECT is((SELECT count(*)::bigint FROM public.driver_profiles WHERE employee_number = 'DRV-15H-001'), 1::bigint, 'crea driver_profile');
SELECT is((SELECT status FROM public.command_log WHERE idempotency_key = '15h-hiring-1'), 'completed', 'comando de alta queda completado');
SELECT cmp_ok(
    (SELECT count(*) FROM public.audit_log WHERE event_type LIKE ANY(ARRAY['candidate_document.%', 'hiring.%'])),
    '>=', 8::bigint,
    'documentos y alta dejan auditoria'
);

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT profile_id::text FROM public.hirings),
    true
);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*)::bigint FROM public.hirings), 1::bigint, 'conductor lee su propia alta');
SELECT is((SELECT count(*)::bigint FROM public.candidate_documents), 6::bigint, 'conductor lee su expediente contratado');
SELECT is((SELECT count(*)::bigint FROM public.candidates), 0::bigint, 'conductor no accede al embudo de candidatos');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
