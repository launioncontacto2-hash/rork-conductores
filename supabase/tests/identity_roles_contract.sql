BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(18);

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

-- Functional contract probes run in this transaction and are rolled back below.
-- They intentionally inspect the effective authorization functions without creating
-- Auth users or relying on email addresses.
SELECT ok(
    pg_get_functiondef('app.auth_station_ids()'::regprocedure) LIKE '%role <> ''administration''%',
    'administration is excluded from station scope'
);
SELECT ok(
    pg_get_functiondef('app.auth_has_role(text,uuid)'::regprocedure) NOT LIKE '%copilot%',
    'auth_has_role has no copilot grant'
);
SELECT ok(
    pg_get_functiondef('public.console_audit_history(integer)'::regprocedure) LIKE '%membership.role IN (''supervisor'',''console'')%',
    'audit history accepts supervisor or console memberships'
);
SELECT ok(
    pg_get_functiondef('public.console_audit_history(integer)'::regprocedure) LIKE '%auth_can_operate_station(event.station_id)%',
    'audit history remains station scoped'
);
SELECT ok(
    pg_get_functiondef('public.console_audit_history(integer)'::regprocedure) LIKE '%console_or_supervisor_role_required%',
    'audit history uses neutral authorization error'
);
SELECT ok(
    pg_get_functiondef('app.update_test_clock_authorized(uuid,timestamptz,timestamptz,double precision,boolean,bigint)'::regprocedure) LIKE '%auth_has_role(''console'')%',
    'test clock accepts console authorization'
);
SELECT ok(
    pg_get_functiondef('app.update_test_clock_authorized(uuid,timestamptz,timestamptz,double precision,boolean,bigint)'::regprocedure) NOT LIKE '%administration%',
    'test clock does not accept administration'
);
SELECT ok(
    pg_get_functiondef('public.console_create_test_vehicle(text,text,text)'::regprocedure) LIKE '%pg_advisory_xact_lock%',
    'vehicle creation serializes unit numbering'
);
SELECT ok(
    pg_get_functiondef('public.console_create_test_vehicle(text,text,text)'::regprocedure) LIKE '%result_payload%',
    'vehicle creation records idempotent result payload'
);
SELECT ok(
    EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='shift_evidence' AND policyname='shift_evidence_console_read'),
    'console shift evidence read policy exists'
);

SELECT * FROM finish();
ROLLBACK;
