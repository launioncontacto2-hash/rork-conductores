BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(45);

SELECT has_table('public', 'absences', 'existe la tabla absences');
SELECT has_table('public', 'coverage_vacancies', 'existe coverage_vacancies');
SELECT has_table('public', 'coverage_claims', 'existe coverage_claims');
SELECT has_function(
    'public', 'request_absence',
    ARRAY['date', 'text', 'text', 'text', 'text', 'text', 'text'],
    'existe request_absence con dispositivo'
);
SELECT has_function(
    'public', 'claim_guard', ARRAY['uuid', 'text', 'text'],
    'existe claim_guard con exclusion y dispositivo'
);
SELECT has_function(
    'public', 'approve_guard', ARRAY['uuid', 'bigint', 'text', 'text'],
    'existe approve_guard con revision'
);
SELECT has_function(
    'public', 'resolve_absence', ARRAY['uuid', 'bigint', 'text', 'text', 'text'],
    'existe resolve_absence con revision'
);
SELECT has_index(
    'public', 'coverage_claims', 'coverage_claims_winner_unique',
    'el ganador se protege con indice unico parcial'
);
SELECT is(
    (SELECT bool_and(c.relrowsecurity)
     FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname IN ('absences', 'coverage_vacancies', 'coverage_claims')),
    true,
    'las tres tablas de cobertura tienen RLS habilitado'
);
SELECT is(
    (SELECT count(*)::bigint
     FROM pg_policies p
     WHERE p.schemaname = 'public'
       AND p.tablename IN ('absences', 'coverage_vacancies', 'coverage_claims')
       AND p.cmd = 'SELECT'),
    3::bigint,
    'cada tabla expone una politica de lectura y ninguna de escritura'
);
SELECT is(
    (SELECT bool_and(NOT has_table_privilege(
        'anon', format('public.%I', table_name), 'SELECT'
    ))
     FROM unnest(ARRAY['absences', 'coverage_vacancies', 'coverage_claims']) table_name),
    true,
    'anon no puede leer cobertura'
);
SELECT is(
    (SELECT bool_and(has_table_privilege(
        'authenticated', format('public.%I', table_name), 'SELECT'
    ))
     FROM unnest(ARRAY['absences', 'coverage_vacancies', 'coverage_claims']) table_name),
    true,
    'authenticated puede leer cobertura sujeto a RLS'
);
SELECT is(
    (SELECT bool_and(NOT has_table_privilege(
        'authenticated', format('public.%I', table_name), 'INSERT, UPDATE, DELETE'
    ))
     FROM unnest(ARRAY['absences', 'coverage_vacancies', 'coverage_claims']) table_name),
    true,
    'authenticated no puede escribir cobertura directamente'
);
SELECT is(
    has_function_privilege(
        'anon', 'public.claim_guard(uuid,text,text)', 'EXECUTE'
    ),
    false,
    'anon no puede competir por una guardia'
);

INSERT INTO public.stations (
    id, environment_id, region_id, code, name, status, timezone
)
SELECT
    '15f40000-0000-4000-8000-000000000001'::uuid,
    r.environment_id, r.id, '15f-rpc-station', '15F RPC Station',
    'active', 'America/Mexico_City'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE test_15f_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = '15f40000-0000-4000-8000-000000000001'::uuid;

UPDATE app.env_clock c
SET is_simulated = true,
    anchor_logical_at = '2026-08-31 12:00:00+00'::timestamptz,
    anchor_real_at = now(),
    speed = 1,
    is_paused = true
FROM test_15f_scope scope
WHERE c.environment_id = scope.environment_id;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT fixture.profile_id, scope.environment_id,
       fixture.employee_number, fixture.display_name, 'active'
FROM test_15f_scope scope
CROSS JOIN (
    VALUES
        ('15f00000-0000-4000-8000-000000000001'::uuid, '15F-TITULAR', '15F Titular'),
        ('15f00000-0000-4000-8000-000000000002'::uuid, '15F-WINNER', '15F Winner'),
        ('15f00000-0000-4000-8000-000000000003'::uuid, '15F-LOSER', '15F Loser'),
        ('15f00000-0000-4000-8000-000000000004'::uuid, '15F-SUPERVISOR', '15F Supervisor')
) AS fixture(profile_id, employee_number, display_name);

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role,
    starts_at, shift_group, shift_slot
)
SELECT fixture.membership_id, scope.environment_id,
       fixture.profile_id, scope.station_id, fixture.role,
       '2026-01-01 00:00:00+00'::timestamptz,
       fixture.shift_group, fixture.shift_slot
FROM test_15f_scope scope
CROSS JOIN (
    VALUES
        (
            '15f10000-0000-4000-8000-000000000001'::uuid,
            '15f00000-0000-4000-8000-000000000001'::uuid,
            'driver', 'weekday', 'morning'
        ),
        (
            '15f10000-0000-4000-8000-000000000002'::uuid,
            '15f00000-0000-4000-8000-000000000002'::uuid,
            'driver', 'weekday', 'evening'
        ),
        (
            '15f10000-0000-4000-8000-000000000003'::uuid,
            '15f00000-0000-4000-8000-000000000003'::uuid,
            'driver', 'weekend', 'morning'
        ),
        (
            '15f10000-0000-4000-8000-000000000004'::uuid,
            '15f00000-0000-4000-8000-000000000004'::uuid,
            'supervisor', NULL::text, NULL::text
        )
) AS fixture(membership_id, profile_id, role, shift_group, shift_slot);

INSERT INTO public.driver_profiles (
    id, environment_id, station_id, profile_id, membership_id,
    employee_number, status
)
SELECT fixture.driver_profile_id, scope.environment_id, scope.station_id,
       fixture.profile_id, fixture.membership_id, fixture.employee_number, 'active'
FROM test_15f_scope scope
CROSS JOIN (
    VALUES
        (
            '15f20000-0000-4000-8000-000000000001'::uuid,
            '15f00000-0000-4000-8000-000000000001'::uuid,
            '15f10000-0000-4000-8000-000000000001'::uuid,
            '15F-TITULAR'
        ),
        (
            '15f20000-0000-4000-8000-000000000002'::uuid,
            '15f00000-0000-4000-8000-000000000002'::uuid,
            '15f10000-0000-4000-8000-000000000002'::uuid,
            '15F-WINNER'
        ),
        (
            '15f20000-0000-4000-8000-000000000003'::uuid,
            '15f00000-0000-4000-8000-000000000003'::uuid,
            '15f10000-0000-4000-8000-000000000003'::uuid,
            '15F-LOSER'
        )
) AS fixture(driver_profile_id, profile_id, membership_id, employee_number);

CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

-- El titular crea una ausencia; el servidor abre la vacante en la misma TXN.
SELECT set_config('request.jwt.claim.sub', '15f00000-0000-4000-8000-000000000001', true);
SELECT set_config(
    'request.jwt.claims',
    '{"session_id":"15f70000-0000-4000-8000-000000000001"}', true
);
SET LOCAL ROLE authenticated;
DO $block$
BEGIN
    PERFORM public.claim_driver_device('15f-install-titular', 'pgtap');
END
$block$;
SELECT lives_ok(
    $sql$
        SELECT public.request_absence(
            '2026-09-01'::date, 'morning', 'scheduled',
            'Cita medica programada', 'Aviso con anticipacion.',
            '15f-request-1', '15f-install-titular'
        )
    $sql$,
    'el titular solicita ausencia desde su dispositivo vigente'
);
SELECT lives_ok(
    $sql$
        SELECT public.request_absence(
            '2026-09-01'::date, 'morning', 'scheduled',
            'Cita medica programada', 'Aviso con anticipacion.',
            '15f-request-1', '15f-install-titular'
        )
    $sql$,
    'repetir la misma clave devuelve la ausencia original'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.coverage_vacancies),
    0::bigint,
    'RLS oculta al titular la vacante creada por su propia ausencia'
);
RESET ROLE;

SELECT is((SELECT count(*)::bigint FROM public.absences), 1::bigint,
    'la solicitud idempotente no duplica ausencias');
SELECT is((SELECT count(*)::bigint FROM public.coverage_vacancies), 1::bigint,
    'la ausencia abre exactamente una vacante');
SELECT results_eq(
    $sql$ SELECT status, revision FROM public.absences $sql$,
    $sql$ VALUES ('searching'::text, 1::bigint) $sql$,
    'la ausencia comienza buscando cobertura'
);
SELECT results_eq(
    $sql$ SELECT status, revision, origin, bonus_mxn FROM public.coverage_vacancies $sql$,
    $sql$ VALUES ('searching'::text, 1::bigint, 'absence'::text, 300) $sql$,
    'la vacante nace abierta con bono definido por servidor'
);

-- El conductor titular nunca puede tomar su propia plaza.
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$
        SELECT public.claim_guard(
            (SELECT vacancy_id FROM public.absences),
            '15f-claim-self', '15f-install-titular'
        )
    $sql$,
    '22023', 'titular_cannot_claim_own_vacancy',
    'el titular no puede reclamar su propia guardia'
);
RESET ROLE;

-- Primer telefono: gana la guardia.
SELECT set_config('request.jwt.claim.sub', '15f00000-0000-4000-8000-000000000002', true);
SELECT set_config(
    'request.jwt.claims',
    '{"session_id":"15f70000-0000-4000-8000-000000000002"}', true
);
SET LOCAL ROLE authenticated;
DO $block$
BEGIN
    PERFORM public.claim_driver_device('15f-install-winner', 'pgtap');
END
$block$;
SELECT is(
    (SELECT count(*)::bigint FROM public.coverage_vacancies),
    1::bigint,
    'RLS muestra la vacante al primer conductor elegible'
);
SELECT lives_ok(
    $sql$
        SELECT public.claim_guard(
            (SELECT id FROM public.coverage_vacancies),
            '15f-claim-winner', '15f-install-winner'
        )
    $sql$,
    'el primer conductor elegible gana la guardia'
);
SELECT lives_ok(
    $sql$
        SELECT public.claim_guard(
            (SELECT id FROM public.coverage_vacancies),
            '15f-claim-winner', '15f-install-winner'
        )
    $sql$,
    'el reintento idempotente del ganador devuelve el mismo claim'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.coverage_claims),
    1::bigint,
    'RLS permite al ganador leer su propio claim'
);
RESET ROLE;

SELECT is((SELECT count(*)::bigint FROM public.coverage_claims), 1::bigint,
    'existe un solo claim ganador');
SELECT results_eq(
    $sql$ SELECT status, revision FROM public.coverage_vacancies $sql$,
    $sql$ VALUES ('reserved'::text, 2::bigint) $sql$,
    'la vacante queda reservada y avanza revision'
);
SELECT results_eq(
    $sql$ SELECT status, revision FROM public.absences $sql$,
    $sql$ VALUES ('covered'::text, 2::bigint) $sql$,
    'la ausencia refleja que ya existe cobertura'
);

-- Segundo telefono: llega despues y pierde con un error de dominio estable.
SELECT set_config('request.jwt.claim.sub', '15f00000-0000-4000-8000-000000000003', true);
SELECT set_config(
    'request.jwt.claims',
    '{"session_id":"15f70000-0000-4000-8000-000000000003"}', true
);
SET LOCAL ROLE authenticated;
DO $block$
BEGIN
    PERFORM public.claim_driver_device('15f-install-loser', 'pgtap');
END
$block$;
SELECT is(
    (SELECT count(*)::bigint FROM public.coverage_vacancies),
    1::bigint,
    'RLS permite al segundo conductor ver que la plaza ya no esta abierta'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.coverage_claims),
    0::bigint,
    'RLS no revela al perdedor la identidad del ganador'
);
SELECT throws_ok(
    $sql$
        SELECT public.claim_guard(
            (SELECT id FROM public.coverage_vacancies),
            '15f-claim-loser', '15f-install-loser'
        )
    $sql$,
    '23505', 'vacancy_already_claimed',
    'el segundo conductor pierde limpiamente la carrera'
);
RESET ROLE;

SELECT is((SELECT count(*)::bigint FROM public.coverage_claims), 1::bigint,
    'el perdedor no genera una segunda reserva');
SELECT is(
    (SELECT driver_profile_id FROM public.coverage_claims),
    '15f20000-0000-4000-8000-000000000002'::uuid,
    'la guardia conserva al primer ganador'
);

-- Supervision firma la guardia y despues autoriza la ausencia.
SELECT set_config('request.jwt.claim.sub', '15f00000-0000-4000-8000-000000000004', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$
        SELECT public.approve_guard(
            (SELECT id FROM public.coverage_vacancies), 99,
            'Cobertura revisada.', '15f-approve-stale'
        )
    $sql$,
    '40001', 'vacancy_revision_conflict',
    'la aprobacion rechaza una revision obsoleta'
);
SELECT lives_ok(
    $sql$
        SELECT public.approve_guard(
            (SELECT id FROM public.coverage_vacancies), 2,
            'Cobertura revisada.', '15f-approve-1'
        )
    $sql$,
    'supervision confirma al ganador vigente'
);
RESET ROLE;

SELECT results_eq(
    $sql$ SELECT status, revision FROM public.coverage_vacancies $sql$,
    $sql$ VALUES ('confirmed'::text, 3::bigint) $sql$,
    'la vacante queda confirmada'
);
SELECT results_eq(
    $sql$ SELECT status FROM public.coverage_claims $sql$,
    $sql$ VALUES ('approved'::text) $sql$,
    'el claim ganador queda aprobado'
);
SELECT results_eq(
    $sql$ SELECT status, revision FROM public.absences $sql$,
    $sql$ VALUES ('awaiting_authorization'::text, 3::bigint) $sql$,
    'cobertura y autorizacion de ausencia siguen siendo decisiones separadas'
);

SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$
        SELECT public.resolve_absence(
            (SELECT id FROM public.absences), 3, 'approved',
            'Ausencia autorizada con reemplazo confirmado.', '15f-resolve-1'
        )
    $sql$,
    'supervision autoriza la ausencia ya cubierta'
);
RESET ROLE;

SELECT results_eq(
    $sql$ SELECT status, revision FROM public.absences $sql$,
    $sql$ VALUES ('approved'::text, 4::bigint) $sql$,
    'la ausencia termina aprobada con revision nueva'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.command_log
     WHERE command_name IN ('request_absence', 'claim_guard', 'approve_guard', 'resolve_absence')
       AND status = 'completed'),
    4::bigint,
    'los cuatro comandos quedan completados una sola vez'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.audit_log
     WHERE event_type IN (
         'absence.requested', 'coverage.claim_won',
         'coverage.guard_approved', 'absence.resolved'
     )),
    4::bigint,
    'el flujo completo queda auditado'
);
SELECT is(
    (SELECT open_vacancies FROM public.station_live
     WHERE station_id = '15f40000-0000-4000-8000-000000000001'::uuid),
    0,
    'la proyeccion de consola no deja vacantes abiertas al confirmar'
);
SELECT is(
    (SELECT count(*)::bigint FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename IN ('coverage_vacancies', 'coverage_claims')),
    2::bigint,
    'vacantes y claims estan publicados para realtime'
);

SELECT * FROM finish();
ROLLBACK;
