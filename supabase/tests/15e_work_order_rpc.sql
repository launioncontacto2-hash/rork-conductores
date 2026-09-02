BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(35);

SELECT has_table('public', 'incidents', 'existe la tabla incidents');
SELECT has_table('public', 'work_orders', 'existe la tabla work_orders');
SELECT has_table('public', 'work_order_updates', 'existe la bitacora append-only de taller');
SELECT has_function(
    'public', 'report_incident', ARRAY['uuid', 'text', 'text', 'text', 'text'],
    'existe report_incident con sesion de dispositivo'
);
SELECT has_function(
    'public', 'update_incident', ARRAY['uuid', 'bigint', 'text', 'text', 'text'],
    'existe update_incident con revision optimista'
);
SELECT has_function(
    'public', 'open_work_order', ARRAY['uuid', 'text', 'integer', 'text'],
    'existe open_work_order'
);
SELECT has_function(
    'public', 'close_work_order', ARRAY['uuid', 'bigint', 'text', 'text'],
    'existe close_work_order con revision optimista'
);

INSERT INTO public.stations (
    id, environment_id, region_id, code, name, status, timezone
)
SELECT
    '15e40000-0000-4000-8000-000000000001'::uuid,
    r.environment_id,
    r.id,
    '15e-rpc-station',
    '15E RPC Station',
    'active',
    'America/Mexico_City'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE test_15e_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = '15e40000-0000-4000-8000-000000000001'::uuid;

UPDATE app.env_clock c
SET is_simulated = true,
    anchor_logical_at = '2026-08-31 12:00:00+00'::timestamptz,
    anchor_real_at = now(),
    speed = 1,
    is_paused = true
FROM test_15e_scope scope
WHERE c.environment_id = scope.environment_id;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT fixture.profile_id, scope.environment_id,
       fixture.employee_number, fixture.display_name, 'active'
FROM test_15e_scope scope
CROSS JOIN (
    VALUES
        (
            '15e00000-0000-4000-8000-000000000001'::uuid,
            '15E-RPC-DRIVER', '15E RPC Driver'
        ),
        (
            '15e00000-0000-4000-8000-000000000002'::uuid,
            '15E-RPC-OTHER', '15E RPC Other Driver'
        ),
        (
            '15e00000-0000-4000-8000-000000000003'::uuid,
            '15E-RPC-SUPERVISOR', '15E RPC Supervisor'
        ),
        (
            '15e00000-0000-4000-8000-000000000004'::uuid,
            '15E-RPC-MAINTENANCE', '15E RPC Maintenance'
        )
) AS fixture(profile_id, employee_number, display_name);

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role,
    starts_at, shift_group, shift_slot
)
SELECT fixture.membership_id, scope.environment_id,
       fixture.profile_id, scope.station_id, fixture.role,
       '2026-01-01 00:00:00+00'::timestamptz,
       fixture.shift_group, fixture.shift_slot
FROM test_15e_scope scope
CROSS JOIN (
    VALUES
        (
            '15e10000-0000-4000-8000-000000000001'::uuid,
            '15e00000-0000-4000-8000-000000000001'::uuid,
            'driver', 'weekday', 'morning'
        ),
        (
            '15e10000-0000-4000-8000-000000000002'::uuid,
            '15e00000-0000-4000-8000-000000000002'::uuid,
            'driver', 'weekday', 'morning'
        ),
        (
            '15e10000-0000-4000-8000-000000000003'::uuid,
            '15e00000-0000-4000-8000-000000000003'::uuid,
            'supervisor', NULL::text, NULL::text
        ),
        (
            '15e10000-0000-4000-8000-000000000004'::uuid,
            '15e00000-0000-4000-8000-000000000004'::uuid,
            'maintenance', NULL::text, NULL::text
        )
) AS fixture(membership_id, profile_id, role, shift_group, shift_slot);

INSERT INTO public.driver_profiles (
    id, environment_id, station_id, profile_id, membership_id,
    employee_number, status
)
SELECT fixture.driver_profile_id, scope.environment_id, scope.station_id,
       fixture.profile_id, fixture.membership_id,
       fixture.employee_number, 'active'
FROM test_15e_scope scope
CROSS JOIN (
    VALUES
        (
            '15e20000-0000-4000-8000-000000000001'::uuid,
            '15e00000-0000-4000-8000-000000000001'::uuid,
            '15e10000-0000-4000-8000-000000000001'::uuid,
            '15E-RPC-DRIVER'
        ),
        (
            '15e20000-0000-4000-8000-000000000002'::uuid,
            '15e00000-0000-4000-8000-000000000002'::uuid,
            '15e10000-0000-4000-8000-000000000002'::uuid,
            '15E-RPC-OTHER'
        )
) AS fixture(driver_profile_id, profile_id, membership_id, employee_number);

INSERT INTO public.vehicles (
    id, environment_id, station_id, internal_number, qr_code,
    model, odometer_km, battery_pct, status
)
SELECT
    '15e30000-0000-4000-8000-000000000001'::uuid,
    scope.environment_id, scope.station_id,
    '15E-RPC-V1', '15E-RPC-QR1', '15E RPC Vehicle',
    1000, 80, 'occupied'
FROM test_15e_scope scope;

INSERT INTO public.assignments (
    id, environment_id, station_id, driver_profile_id, vehicle_id,
    kind, assigned_by, assigned_at
)
SELECT
    '15e50000-0000-4000-8000-000000000001'::uuid,
    scope.environment_id, scope.station_id,
    '15e20000-0000-4000-8000-000000000001'::uuid,
    '15e30000-0000-4000-8000-000000000001'::uuid,
    'titular', '15e00000-0000-4000-8000-000000000003'::uuid,
    '2026-08-31 11:00:00+00'::timestamptz
FROM test_15e_scope scope;

INSERT INTO public.shifts (
    id, environment_id, station_id, driver_profile_id, vehicle_id,
    assignment_id, folio, status, shift_group, shift_slot, operating_date,
    scheduled_start_at, scheduled_end_at, started_at, late_minutes,
    start_odometer_km, start_battery_pct
)
SELECT
    '15e60000-0000-4000-8000-000000000001'::uuid,
    scope.environment_id, scope.station_id,
    '15e20000-0000-4000-8000-000000000001'::uuid,
    '15e30000-0000-4000-8000-000000000001'::uuid,
    '15e50000-0000-4000-8000-000000000001'::uuid,
    'SH-15E-TEST', 'open', 'weekday', 'morning', '2026-08-31'::date,
    '2026-08-31 11:00:00+00'::timestamptz,
    '2026-08-31 20:00:00+00'::timestamptz,
    '2026-08-31 11:05:00+00'::timestamptz,
    5, 1000, 80
FROM test_15e_scope scope;

CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

-- Otro conductor conserva una sesion valida, pero no puede reportar el turno ajeno.
SELECT set_config(
    'request.jwt.claim.sub',
    '15e00000-0000-4000-8000-000000000002', true
);
SELECT set_config(
    'request.jwt.claims',
    '{"session_id":"15e70000-0000-4000-8000-000000000002"}', true
);
SET LOCAL ROLE authenticated;
DO $block$
BEGIN
    PERFORM public.claim_driver_device('15e-install-other', 'pgtap');
END
$block$;

SELECT throws_ok(
    $sql$
        SELECT public.report_incident(
            '15e60000-0000-4000-8000-000000000001'::uuid,
            'damage', 'Reporte que pertenece al conductor titular.',
            '15e-report-other', '15e-install-other'
        )
    $sql$,
    '42501', 'shift_not_owned_by_authenticated_driver',
    'otro conductor no puede reportar el turno ajeno'
);
RESET ROLE;

-- El conductor titular toma el dispositivo y reporta.
SELECT set_config(
    'request.jwt.claim.sub',
    '15e00000-0000-4000-8000-000000000001', true
);
SELECT set_config(
    'request.jwt.claims',
    '{"session_id":"15e70000-0000-4000-8000-000000000001"}', true
);
SET LOCAL ROLE authenticated;
DO $block$
BEGIN
    PERFORM public.claim_driver_device('15e-install-driver', 'pgtap');
END
$block$;

SELECT lives_ok(
    $sql$
        SELECT public.report_incident(
            '15e60000-0000-4000-8000-000000000001'::uuid,
            'mechanical', 'El vehiculo presenta una falla mecanica verificable.',
            '15e-report-1', '15e-install-driver'
        )
    $sql$,
    'el conductor reporta su incidencia desde el dispositivo vigente'
);
RESET ROLE;

SELECT is(
    (SELECT count(*)::bigint FROM public.incidents), 1::bigint,
    'queda exactamente una incidencia'
);
SELECT results_eq(
    $sql$ SELECT kind, severity, status, revision FROM public.incidents $sql$,
    $sql$ VALUES ('mechanical'::text, 'high'::text, 'open'::text, 1::bigint) $sql$,
    'el servidor deriva severidad y estado inicial'
);

SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$
        SELECT public.report_incident(
            '15e60000-0000-4000-8000-000000000001'::uuid,
            'mechanical', 'El vehiculo presenta una falla mecanica verificable.',
            '15e-report-1', '15e-install-driver'
        )
    $sql$,
    'repetir la clave devuelve la misma incidencia'
);
SELECT throws_ok(
    $sql$
        SELECT public.report_incident(
            '15e60000-0000-4000-8000-000000000001'::uuid,
            'damage', 'El payload diferente no puede reutilizar la clave.',
            '15e-report-1', '15e-install-driver'
        )
    $sql$,
    '23505', 'idempotency_key_conflict',
    'una clave de reporte no admite otro payload'
);
RESET ROLE;

SELECT is(
    (SELECT count(*)::bigint FROM public.incidents), 1::bigint,
    'la repeticion idempotente no duplica incidencias'
);

-- Supervision acusa recibo, pero no puede ejecutar las acciones de taller.
SELECT set_config(
    'request.jwt.claim.sub',
    '15e00000-0000-4000-8000-000000000003', true
);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$
        SELECT public.update_incident(
            (SELECT id FROM public.incidents), 1, 'review',
            'Supervision confirma la recepcion.', '15e-review-1'
        )
    $sql$,
    'supervision lleva la incidencia a revision'
);
SELECT throws_ok(
    $sql$
        SELECT public.open_work_order(
            (SELECT id FROM public.incidents), 'high', 90, '15e-open-denied'
        )
    $sql$,
    '42501', 'maintenance_role_required_for_station',
    'supervision no suplanta al taller al abrir la orden'
);
RESET ROLE;

SELECT results_eq(
    $sql$ SELECT status, revision FROM public.incidents $sql$,
    $sql$ VALUES ('review'::text, 2::bigint) $sql$,
    'la incidencia avanza revision bajo supervision'
);

-- Taller abre la OT y la unidad queda fuera de operacion.
SELECT set_config(
    'request.jwt.claim.sub',
    '15e00000-0000-4000-8000-000000000004', true
);
SET LOCAL ROLE authenticated;
SELECT lives_ok(
    $sql$
        SELECT public.open_work_order(
            (SELECT id FROM public.incidents), 'high', 90, '15e-open-1'
        )
    $sql$,
    'taller abre la orden de la incidencia'
);
RESET ROLE;

SELECT results_eq(
    $sql$ SELECT priority, status, revision, estimated_minutes FROM public.work_orders $sql$,
    $sql$ VALUES ('high'::text, 'pending'::text, 1::bigint, 90) $sql$,
    'la orden nace pendiente con la prioridad y estimacion pedidas'
);
SELECT is(
    (
        SELECT status FROM public.vehicles
        WHERE id = '15e30000-0000-4000-8000-000000000001'::uuid
    ),
    'maintenance'::text,
    'abrir la orden mueve la unidad a mantenimiento'
);
SELECT results_eq(
    $sql$ SELECT status, revision FROM public.incidents $sql$,
    $sql$ VALUES ('review'::text, 3::bigint) $sql$,
    'abrir la orden conserva la incidencia en revision y avanza su revision'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.work_order_updates), 1::bigint,
    'la apertura queda en la bitacora de taller'
);

SET LOCAL ROLE authenticated;
SELECT throws_ok(
    $sql$
        SELECT public.close_work_order(
            (SELECT id FROM public.work_orders), 99,
            'Se reemplazo el componente y se verifico la unidad.', '15e-close-stale'
        )
    $sql$,
    '40001', 'work_order_revision_conflict',
    'el cierre rechaza una revision obsoleta'
);
SELECT lives_ok(
    $sql$
        SELECT public.close_work_order(
            (SELECT id FROM public.work_orders), 1,
            'Se reemplazo el componente y se verifico la unidad.', '15e-close-1'
        )
    $sql$,
    'taller cierra la orden con la revision vigente'
);
RESET ROLE;

SELECT results_eq(
    $sql$ SELECT status, revision FROM public.work_orders $sql$,
    $sql$ VALUES ('closed'::text, 2::bigint) $sql$,
    'la orden queda cerrada y avanza revision'
);
SELECT results_eq(
    $sql$ SELECT status, revision FROM public.incidents $sql$,
    $sql$ VALUES ('closed'::text, 4::bigint) $sql$,
    'cerrar la orden cierra tambien la incidencia'
);
SELECT is(
    (
        SELECT status FROM public.vehicles
        WHERE id = '15e30000-0000-4000-8000-000000000001'::uuid
    ),
    'occupied'::text,
    'la unidad asignada vuelve a ocupada al cerrar la orden'
);
SELECT is(
    (
        SELECT count(*)::bigint FROM public.vehicle_state_transitions
        WHERE vehicle_id = '15e30000-0000-4000-8000-000000000001'::uuid
          AND reason IN ('work_order_opened', 'work_order_closed')
    ),
    2::bigint,
    'las dos transiciones de la unidad quedan registradas'
);
SELECT is(
    (SELECT count(*)::bigint FROM public.work_order_updates), 2::bigint,
    'apertura y cierre quedan en la bitacora append-only'
);
SELECT is(
    (
        SELECT count(*)::bigint FROM public.audit_log
        WHERE event_type IN (
            'incident.reported', 'incident.updated',
            'work_order.opened', 'work_order.closed'
        )
    ),
    4::bigint,
    'el flujo completo queda auditado'
);
SELECT is(
    (
        SELECT count(*)::bigint FROM public.command_log
        WHERE command_name IN (
            'report_incident', 'update_incident',
            'open_work_order', 'close_work_order'
        ) AND status = 'completed'
    ),
    4::bigint,
    'los cuatro comandos quedan completados'
);

SELECT throws_ok(
    $sql$
        UPDATE public.work_order_updates
        SET note = 'No se permite editar hechos.'
    $sql$,
    '42501', 'work_order_updates_append_only',
    'la bitacora de taller no se puede editar'
);
SELECT is(
    has_table_privilege('authenticated', 'public.incidents', 'SELECT'),
    true,
    'authenticated puede leer incidencias sujeto a RLS'
);
SELECT is(
    has_table_privilege(
        'authenticated', 'public.incidents', 'INSERT, UPDATE, DELETE'
    ),
    false,
    'authenticated no puede escribir incidencias directamente'
);
SELECT is(
    has_function_privilege(
        'anon', 'public.report_incident(uuid,text,text,text,text)', 'EXECUTE'
    ),
    false,
    'anon no puede reportar incidencias'
);

SELECT * FROM finish();
ROLLBACK;
