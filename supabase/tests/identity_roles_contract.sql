BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

SELECT ok(
    EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'staff_memberships_role_check'
        AND pg_get_constraintdef(oid) LIKE '%administration%'
        AND pg_get_constraintdef(oid) LIKE '%console%'
        AND pg_get_constraintdef(oid) NOT LIKE '%copilot%'),
    'staff role contract includes administration and console, not copilot'
);
SELECT has_view('public', 'console_identity', 'console identity read model exists');
SELECT ok(
    pg_get_viewdef('public.console_identity'::regclass, true) LIKE '%supervisor%'
        AND pg_get_viewdef('public.console_identity'::regclass, true) LIKE '%console%',
    'console identity keeps supervisor compatibility and accepts console'
);
SELECT ok(
    NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
        AND tablename = 'console_identity' AND cmd IN ('INSERT','UPDATE','DELETE')),
    'console identity has no direct write policy'
);
SELECT has_function('public', 'console_create_test_vehicle', ARRAY['text','text','text'],
    'console vehicle RPC remains present');
SELECT ok(
    has_function_privilege('authenticated', 'public.console_create_test_vehicle(text,text,text)', 'EXECUTE'),
    'authenticated can execute the protected console RPC'
);
SELECT ok(
    NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'copilot'),
    'copilot is not a database role'
);
SELECT ok(
    EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'staff_memberships_role_check'),
    'staff role constraint remains present'
);

SELECT * FROM finish();
ROLLBACK;
