BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(31);

SELECT has_table('app', 'station_identity_codes', 'existe el catalogo estable de estaciones');
SELECT has_table('app', 'identity_aliases', 'existe el registro privado de nombres futuros');
SELECT has_column('public', 'stations', 'identity_code', 'estaciones enlazan un codigo estable');
SELECT has_column('public', 'profiles', 'account_kind', 'perfiles distinguen persona y cuenta funcional');
SELECT has_column('public', 'profiles', 'responsible_profile_id', 'cuenta funcional puede señalar persona responsable');
SELECT has_column('public', 'audit_log', 'responsible_profile_id', 'auditoria conserva la persona responsable');
SELECT has_function('app', 'normalize_dori_identity_component', ARRAY['text'], 'existe normalizador DORI');
SELECT has_function('app', 'dori_driver_identity_base', ARRAY['text', 'text'], 'existe generador base de conductor');
SELECT has_function('app', 'dori_station_role_local_part', ARRAY['text', 'text'], 'existe generador por puesto y estacion');
SELECT has_function('app', 'next_dori_driver_email', ARRAY['text', 'text'], 'existe resolvedor de colisiones');
SELECT has_function('app', 'reserve_dori_driver_identity', ARRAY['uuid', 'text', 'text'], 'existe reserva transaccional de conductor');
SELECT has_function('app', 'reserve_dori_station_identity', ARRAY['uuid', 'uuid', 'text'], 'existe reserva transaccional de puesto');

SELECT set_eq(
    $sql$ SELECT code FROM app.station_identity_codes WHERE status = 'active' $sql$,
    $sql$ VALUES ('pue'::text), ('cdmx'), ('qro'), ('mty'), ('gda'), ('cue') $sql$,
    'catalogo inicial contiene exclusivamente los seis codigos aprobados'
);
SELECT is(app.normalize_dori_identity_component('Jórge'), 'jorge', 'normalizador elimina acentos y mayusculas');
SELECT is(app.normalize_dori_identity_component('Ra-mos!'), 'ramos', 'normalizador elimina caracteres incompatibles');
SELECT is(app.dori_driver_identity_base('Jórge', 'Rámos'), 'jorge.ramos', 'base usa nombre y primer apellido');
SELECT is(app.dori_station_role_local_part('supervisor', 'PUE'), 'supervision.pue', 'supervision usa codigo estable');
SELECT is(app.dori_station_role_local_part('management', 'qro'), 'gerencia.qro', 'roles internos se traducen a nomenclatura visible');
SELECT throws_ok(
    $sql$ SELECT app.dori_station_role_local_part('supervisor', 'libre') $sql$,
    '22023', 'dori_station_identity_code_invalid',
    'un codigo de estacion no catalogado se rechaza'
);
SELECT is(
    has_function_privilege('authenticated', 'app.reserve_dori_driver_identity(uuid,text,text)', 'EXECUTE'),
    false,
    'el cliente autenticado no puede reservar identidades'
);
SELECT is(
    has_table_privilege('authenticated', 'app.identity_aliases', 'SELECT'),
    false,
    'el registro de alias no se expone al cliente'
);

INSERT INTO public.stations(id, environment_id, region_id, code, identity_code, name, status, timezone)
SELECT
    'd0100000-0000-4000-8000-000000000001', region.environment_id, region.id,
    'pue-identity-test', 'pue', 'Puebla Identity Test', 'active', 'America/Mexico_City'
FROM public.regions region
ORDER BY region.created_at, region.id
LIMIT 1;

CREATE TEMP TABLE identity_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = 'd0100000-0000-4000-8000-000000000001';

INSERT INTO auth.users(id, email)
VALUES
    ('d0190000-0000-4000-8000-000000000001', 'test.identity.1@joramza.test'),
    ('d0190000-0000-4000-8000-000000000002', 'test.identity.2@joramza.test'),
    ('d0190000-0000-4000-8000-000000000003', 'test.identity.3@joramza.test'),
    ('d0190000-0000-4000-8000-000000000004', 'test.identity.supervisor@joramza.test'),
    ('d0190000-0000-4000-8000-000000000005', 'test.identity.link@joramza.test');

INSERT INTO public.profiles(
    id, environment_id, auth_user_id, employee_number, display_name,
    status, account_kind, responsible_profile_id
)
SELECT fixture.profile_id, scope.environment_id, fixture.auth_user_id,
       fixture.employee_number, fixture.display_name, 'active', fixture.account_kind,
       fixture.responsible_profile_id
FROM identity_scope scope
CROSS JOIN (VALUES
    ('d0110000-0000-4000-8000-000000000001'::uuid, 'd0190000-0000-4000-8000-000000000001'::uuid, 'DORI-ID-001', 'Jorge Ramos Uno', 'person', NULL::uuid),
    ('d0110000-0000-4000-8000-000000000002'::uuid, 'd0190000-0000-4000-8000-000000000002'::uuid, 'DORI-ID-002', 'Jorge Ramos Dos', 'person', NULL::uuid),
    ('d0110000-0000-4000-8000-000000000003'::uuid, 'd0190000-0000-4000-8000-000000000003'::uuid, 'DORI-ID-003', 'Jorge Ramos Tres', 'person', NULL::uuid),
    ('d0110000-0000-4000-8000-000000000004'::uuid, 'd0190000-0000-4000-8000-000000000004'::uuid, 'DORI-ID-SUP', 'Supervision Puebla', 'functional', 'd0110000-0000-4000-8000-000000000001'::uuid),
    ('d0110000-0000-4000-8000-000000000005'::uuid, NULL::uuid, 'DORI-ID-LINK', 'Persona por enlazar', 'person', NULL::uuid)
) fixture(profile_id, auth_user_id, employee_number, display_name, account_kind, responsible_profile_id);

SELECT is(
    app.next_dori_driver_email('Jórge', 'Rámos'),
    'jorge.ramos@dori.mx',
    'primer nombre futuro no tiene sufijo'
);
SELECT is(
    (app.reserve_dori_driver_identity('d0110000-0000-4000-8000-000000000001', 'Jórge', 'Rámos')).future_email,
    'jorge.ramos@dori.mx',
    'primer conductor reserva nombre.apellido'
);
SELECT is(
    (app.reserve_dori_driver_identity('d0110000-0000-4000-8000-000000000002', 'Jorge', 'Ramos')).future_email,
    'jorge.ramos2@dori.mx',
    'primera colision recibe sufijo 2'
);
SELECT is(
    (app.reserve_dori_driver_identity('d0110000-0000-4000-8000-000000000003', 'JORGE', 'RAMOS')).future_email,
    'jorge.ramos3@dori.mx',
    'segunda colision recibe sufijo 3'
);
SELECT is(
    (app.reserve_dori_driver_identity('d0110000-0000-4000-8000-000000000001', 'Jorge', 'Ramos')).future_email,
    'jorge.ramos@dori.mx',
    'reintento de reserva es idempotente para el perfil'
);
SELECT is(
    (app.reserve_dori_station_identity(
        'd0110000-0000-4000-8000-000000000004',
        'd0100000-0000-4000-8000-000000000001',
        'supervisor'
    )).future_email,
    'supervision.pue@dori.mx',
    'cuenta funcional usa puesto y codigo estable'
);

SELECT results_eq(
    $sql$
        SELECT id, email
        FROM auth.users
        WHERE id IN (
            'd0190000-0000-4000-8000-000000000001',
            'd0190000-0000-4000-8000-000000000002',
            'd0190000-0000-4000-8000-000000000003',
            'd0190000-0000-4000-8000-000000000004'
        )
        ORDER BY id
    $sql$,
    $sql$
        VALUES
            ('d0190000-0000-4000-8000-000000000001'::uuid, 'test.identity.1@joramza.test'::varchar),
            ('d0190000-0000-4000-8000-000000000002'::uuid, 'test.identity.2@joramza.test'::varchar),
            ('d0190000-0000-4000-8000-000000000003'::uuid, 'test.identity.3@joramza.test'::varchar),
            ('d0190000-0000-4000-8000-000000000004'::uuid, 'test.identity.supervisor@joramza.test'::varchar)
    $sql$,
    'reservar nombres futuros no cambia los correos Auth TEST actuales'
);

SELECT throws_ok(
    $sql$
        UPDATE public.profiles
        SET auth_user_id = 'd0190000-0000-4000-8000-000000000002'
        WHERE id = 'd0110000-0000-4000-8000-000000000001'
    $sql$,
    '23514', 'profile_auth_user_id_immutable',
    'un perfil enlazado no puede cambiar de user_id interno'
);

SELECT lives_ok(
    $sql$
        UPDATE public.profiles
        SET auth_user_id = 'd0190000-0000-4000-8000-000000000005'
        WHERE id = 'd0110000-0000-4000-8000-000000000005'
    $sql$,
    'un perfil nuevo puede enlazarse una sola vez con Auth'
);

INSERT INTO public.audit_log(
    environment_id, actor_profile_id, station_id, event_type, entity_type, metadata
)
SELECT scope.environment_id, 'd0110000-0000-4000-8000-000000000004', scope.station_id,
       'identity.trace.test', 'profile', '{}'::jsonb
FROM identity_scope scope;

SELECT is(
    (
        SELECT responsible_profile_id
        FROM public.audit_log
        WHERE event_type = 'identity.trace.test'
    ),
    'd0110000-0000-4000-8000-000000000001'::uuid,
    'auditoria copia la persona responsable de una cuenta funcional'
);

SELECT * FROM finish();
ROLLBACK;
