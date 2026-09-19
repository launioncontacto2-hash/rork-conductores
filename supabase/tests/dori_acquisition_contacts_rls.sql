BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

SELECT has_table('public', 'acquisition_contacts', 'existe el directorio institucional');
SELECT is(
    (SELECT relrowsecurity FROM pg_catalog.pg_class
     WHERE oid = 'public.acquisition_contacts'::regclass),
    true,
    'RLS esta habilitado en contactos'
);
SELECT ok(
    has_table_privilege('authenticated', 'public.acquisition_contacts', 'SELECT'),
    'authenticated puede consultar contactos mediante RLS'
);
SELECT ok(
    NOT has_table_privilege('authenticated', 'public.acquisition_contacts', 'INSERT, UPDATE, DELETE'),
    'el cliente no puede modificar contactos directamente'
);

CREATE TEMP TABLE test_contact_scope AS
SELECT id AS environment_id FROM public.environments ORDER BY created_at, id LIMIT 1;
GRANT SELECT ON test_contact_scope TO authenticated;

INSERT INTO public.profiles(id, environment_id, employee_number, display_name, status)
SELECT fixture.id, scope.environment_id, fixture.employee_number, fixture.display_name, 'active'
FROM test_contact_scope scope
CROSS JOIN (VALUES
    ('ad600000-0000-4000-8000-000000000001'::uuid, 'ADQ-CONTACT-ADMIN', 'Administrador contactos'),
    ('ad600000-0000-4000-8000-000000000002'::uuid, 'ADQ-CONTACT-PROV-A', 'Proveedor contactos A'),
    ('ad600000-0000-4000-8000-000000000003'::uuid, 'ADQ-CONTACT-PROV-B', 'Proveedor contactos B'),
    ('ad600000-0000-4000-8000-000000000004'::uuid, 'ADQ-CONTACT-OUT', 'Sin membresia contactos')
) fixture(id, employee_number, display_name);

INSERT INTO public.acquisition_suppliers(id, environment_id, code, name, city)
SELECT fixture.id, scope.environment_id, fixture.code, fixture.name, 'Puebla'
FROM test_contact_scope scope
CROSS JOIN (VALUES
    ('ad610000-0000-4000-8000-000000000001'::uuid, 'ADQ-CONTACT-A', 'Agencia contactos A'),
    ('ad610000-0000-4000-8000-000000000002'::uuid, 'ADQ-CONTACT-B', 'Agencia contactos B')
) fixture(id, code, name);

INSERT INTO public.acquisition_memberships(
    id, environment_id, profile_id, supplier_id, role, status, starts_at
)
SELECT fixture.id, scope.environment_id, fixture.profile_id, fixture.supplier_id,
       fixture.role, 'active', app.env_now(scope.environment_id) - interval '1 day'
FROM test_contact_scope scope
CROSS JOIN (VALUES
    ('ad620000-0000-4000-8000-000000000001'::uuid, 'ad600000-0000-4000-8000-000000000001'::uuid, NULL::uuid, 'dori_admin'),
    ('ad620000-0000-4000-8000-000000000002'::uuid, 'ad600000-0000-4000-8000-000000000002'::uuid, 'ad610000-0000-4000-8000-000000000001'::uuid, 'provider'),
    ('ad620000-0000-4000-8000-000000000003'::uuid, 'ad600000-0000-4000-8000-000000000003'::uuid, 'ad610000-0000-4000-8000-000000000002'::uuid, 'provider')
) fixture(id, profile_id, supplier_id, role);

INSERT INTO public.acquisition_contacts(
    id, environment_id, supplier_id, organization_name, person_name,
    job_title, phone, email, business_hours, is_primary
)
SELECT fixture.id, scope.environment_id, fixture.supplier_id, fixture.organization_name,
       fixture.person_name, fixture.job_title, '222 000 0000', fixture.email,
       '09:00 a 18:00', true
FROM test_contact_scope scope
CROSS JOIN (VALUES
    ('ad630000-0000-4000-8000-000000000001'::uuid, NULL::uuid, 'DORI Puebla', 'Jorge Ramos', 'Supervisor de adquisiciones', 'adquisiciones@dori.test'),
    ('ad630000-0000-4000-8000-000000000002'::uuid, 'ad610000-0000-4000-8000-000000000001'::uuid, 'Agencia contactos A', 'Laura Méndez', 'Gerente de seminuevos', 'ventas-a@agencia.test'),
    ('ad630000-0000-4000-8000-000000000003'::uuid, 'ad610000-0000-4000-8000-000000000002'::uuid, 'Agencia contactos B', 'Ana López', 'Gerente de seminuevos', 'ventas-b@agencia.test')
) fixture(id, supplier_id, organization_name, person_name, job_title, email);

CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

CREATE TEMP TABLE test_contact_visibility(actor text PRIMARY KEY, visible bigint NOT NULL);
GRANT SELECT, INSERT ON test_contact_visibility TO authenticated;

SELECT set_config('request.jwt.claim.sub', 'ad600000-0000-4000-8000-000000000002', true);
SET LOCAL ROLE authenticated;
INSERT INTO test_contact_visibility SELECT 'provider_a', count(*) FROM public.acquisition_contacts;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad600000-0000-4000-8000-000000000003', true);
SET LOCAL ROLE authenticated;
INSERT INTO test_contact_visibility SELECT 'provider_b', count(*) FROM public.acquisition_contacts;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad600000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
INSERT INTO test_contact_visibility SELECT 'admin', count(*) FROM public.acquisition_contacts;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', 'ad600000-0000-4000-8000-000000000004', true);
SET LOCAL ROLE authenticated;
INSERT INTO test_contact_visibility SELECT 'outsider', count(*) FROM public.acquisition_contacts;
RESET ROLE;

SELECT is((SELECT visible FROM test_contact_visibility WHERE actor = 'provider_a'), 2::bigint,
          'proveedor A ve DORI y su propio contacto');
SELECT is((SELECT visible FROM test_contact_visibility WHERE actor = 'provider_b'), 2::bigint,
          'proveedor B ve DORI y su propio contacto');
SELECT is((SELECT visible FROM test_contact_visibility WHERE actor = 'admin'), 3::bigint,
          'Administrador DORI ve todos los contactos del entorno');
SELECT is((SELECT visible FROM test_contact_visibility WHERE actor = 'outsider'), 0::bigint,
          'un perfil sin membresia no ve contactos');

SELECT * FROM finish();
ROLLBACK;
