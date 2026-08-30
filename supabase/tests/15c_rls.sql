BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(7);

CREATE TEMP TABLE test_15c_rls_tables (table_name name PRIMARY KEY);

INSERT INTO test_15c_rls_tables (table_name)
VALUES
    ('vehicles'),
    ('driver_profiles'),
    ('assignments'),
    ('vehicle_state_transitions');

SELECT is(
    (
        SELECT count(*)::bigint
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        JOIN test_15c_rls_tables expected ON expected.table_name = c.relname
        WHERE n.nspname = 'public'
          AND c.relrowsecurity
    ),
    4::bigint,
    'RLS esta habilitado en las cuatro tablas de 15C'
);

SELECT is(
    (
        SELECT count(*)::bigint
        FROM pg_catalog.pg_policies p
        JOIN test_15c_rls_tables expected ON expected.table_name = p.tablename
        WHERE p.schemaname = 'public'
    ),
    6::bigint,
    'existen las seis politicas de lectura previstas'
);

SELECT is(
    (
        SELECT bool_and(p.cmd = 'SELECT')
        FROM pg_catalog.pg_policies p
        JOIN test_15c_rls_tables expected ON expected.table_name = p.tablename
        WHERE p.schemaname = 'public'
    ),
    true,
    'todas las politicas de 15C son solo SELECT'
);

SELECT is(
    (
        SELECT bool_and(p.roles = ARRAY['authenticated']::name[])
        FROM pg_catalog.pg_policies p
        JOIN test_15c_rls_tables expected ON expected.table_name = p.tablename
        WHERE p.schemaname = 'public'
    ),
    true,
    'todas las politicas aplican exclusivamente a authenticated'
);

SELECT is(
    (
        SELECT bool_and(
            has_table_privilege(
                'authenticated',
                format('public.%I', table_name),
                'SELECT'
            )
        )
        FROM test_15c_rls_tables
    ),
    true,
    'authenticated tiene SELECT en las cuatro tablas'
);

SELECT is(
    (
        SELECT bool_or(
            has_table_privilege(
                'authenticated',
                format('public.%I', table_name),
                'INSERT, UPDATE, DELETE'
            )
        )
        FROM test_15c_rls_tables
    ),
    false,
    'authenticated no tiene escritura directa'
);

SELECT is(
    (
        SELECT bool_or(
            has_table_privilege(
                'anon',
                format('public.%I', table_name),
                'SELECT'
            )
        )
        FROM test_15c_rls_tables
    ),
    false,
    'anon no tiene lectura directa de tablas 15C'
);

SELECT * FROM finish();
ROLLBACK;
