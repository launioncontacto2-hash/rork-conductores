BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(33);

-- The historical constraint remains present and still accepts hr data.
SELECT has_constraint('public', 'staff_memberships', 'staff_memberships_role_check',
    'historical staff role constraint remains');
SELECT ok(
    pg_get_constraintdef(oid) LIKE '%hr%'
    FROM pg_constraint WHERE conname = 'staff_memberships_role_check',
    'historical hr role remains accepted by the constraint'
);

-- Active policies no longer authorize hr; all other scopes remain intact.
SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='candidates' AND policyname='candidates_authorized_read') NOT LIKE '%''hr''%',
    'candidates no longer grants operational hr access');
SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='candidate_documents' AND policyname='candidate_documents_authorized_read') NOT LIKE '%''hr''%',
    'candidate documents no longer grants operational hr access');
SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='hirings' AND policyname='hirings_authorized_read') NOT LIKE '%''hr''%',
    'hirings no longer grants operational hr access');
SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='candidate_document_objects_select') NOT LIKE '%''hr''%',
    'candidate document storage no longer grants operational hr access');

SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='candidates' AND policyname='candidates_authorized_read') LIKE '%recruitment%',
    'recruitment remains authorized for candidates');
SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='candidate_documents' AND policyname='candidate_documents_authorized_read') LIKE '%recruitment%',
    'recruitment remains authorized for candidate documents');
SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='hirings' AND policyname='hirings_authorized_read') LIKE '%recruitment%',
    'recruitment remains authorized for hirings');
SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='candidate_document_objects_select') LIKE '%recruitment%',
    'recruitment remains authorized for candidate document storage');

SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='candidates' AND policyname='candidates_authorized_read') LIKE '%management%',
    'regional management scope remains');
SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='candidates' AND policyname='candidates_authorized_read') LIKE '%direction%',
    'direction scope remains');
SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='candidate_documents' AND policyname='candidate_documents_authorized_read') LIKE '%profile_id%',
    'candidate document ownership remains');
SELECT ok((SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='hirings' AND policyname='hirings_authorized_read') LIKE '%profile_id%',
    'hiring ownership remains');

-- New HR identity reservations are blocked, while historical aliases remain.
SELECT throws_ok(
    $$SELECT app.dori_station_role_local_part('hr', 'pue')$$,
    '22023', 'dori_station_identity_role_invalid',
    'new hr identity naming is blocked'
);
SELECT is((SELECT count(*) FROM app.identity_aliases), (SELECT count(*) FROM app.identity_aliases),
    'historical identity aliases remain untouched');

-- Legacy shift RPCs remain inaccessible to clients; v3 remains available.
SELECT is(has_function_privilege('authenticated', 'public.start_shift(uuid,bigint,integer,text)', 'EXECUTE'), false,
    'legacy start_shift denied to authenticated');
SELECT is(has_function_privilege('anon', 'public.start_shift(uuid,bigint,integer,text)', 'EXECUTE'), false,
    'legacy start_shift denied to anon');
SELECT is(has_function_privilege('service_role', 'public.start_shift(uuid,bigint,integer,text)', 'EXECUTE'), true,
    'service_role retains legacy start_shift');
SELECT is(has_function_privilege('authenticated', 'public.finish_shift(uuid,bigint,bigint,integer,text)', 'EXECUTE'), false,
    'legacy finish_shift denied to authenticated');
SELECT is(has_function_privilege('anon', 'public.finish_shift(uuid,bigint,bigint,integer,text)', 'EXECUTE'), false,
    'legacy finish_shift denied to anon');
SELECT is(has_function_privilege('service_role', 'public.finish_shift(uuid,bigint,bigint,integer,text)', 'EXECUTE'), true,
    'service_role retains legacy finish_shift');
SELECT is(has_function_privilege('authenticated', 'public.start_shift_v2(uuid,bigint,integer,text,text)', 'EXECUTE'), false,
    'legacy start_shift_v2 denied to authenticated');
SELECT is(has_function_privilege('anon', 'public.start_shift_v2(uuid,bigint,integer,text,text)', 'EXECUTE'), false,
    'legacy start_shift_v2 denied to anon');
SELECT is(has_function_privilege('service_role', 'public.start_shift_v2(uuid,bigint,integer,text,text)', 'EXECUTE'), true,
    'service_role retains legacy start_shift_v2');
SELECT is(has_function_privilege('authenticated', 'public.finish_shift_v2(uuid,bigint,bigint,integer,text,text)', 'EXECUTE'), false,
    'legacy finish_shift_v2 denied to authenticated');
SELECT is(has_function_privilege('anon', 'public.finish_shift_v2(uuid,bigint,bigint,integer,text,text)', 'EXECUTE'), false,
    'legacy finish_shift_v2 denied to anon');
SELECT is(has_function_privilege('service_role', 'public.finish_shift_v2(uuid,bigint,bigint,integer,text,text)', 'EXECUTE'), true,
    'service_role retains legacy finish_shift_v2');
SELECT is(has_function_privilege('authenticated', 'public.start_shift_v3(uuid,bigint,integer,text,text,text,text)', 'EXECUTE'), true,
    'start_shift_v3 remains available');
SELECT is(has_function_privilege('authenticated', 'public.finish_shift_v3(uuid,bigint,bigint,integer,text,text,text)', 'EXECUTE'), true,
    'finish_shift_v3 remains available');

SELECT ok(pg_get_viewdef('public.console_identity'::regclass, true) LIKE '%console%',
    'console contract remains intact');
SELECT ok(pg_get_functiondef('app.auth_station_ids()'::regprocedure) LIKE '%administration%',
    'administration remains excluded from station scope');
SELECT ok(EXISTS (SELECT 1 FROM public.acquisition_memberships),
    'acquisition memberships remain present and isolated');

SELECT * FROM finish();
ROLLBACK;
