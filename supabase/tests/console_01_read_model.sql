BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(32);

SELECT has_table('public', 'station_capacity_grants', 'existe capacidad versionada');
SELECT has_view('public', 'station_capacity_current', 'existe la vista de capacidad vigente');
SELECT has_view('public', 'assignment_current', 'existe la vista de asignacion vigente');
SELECT has_view('public', 'console_identity', 'existe la identidad vigente de consola');
SELECT has_table('public', 'devices', 'existe el registro de dispositivos');
SELECT has_function(
    'public', 'touch_device', ARRAY['text', 'uuid', 'text', 'text'],
    'existe el heartbeat autenticado'
);
SELECT has_table('public', 'station_live', 'existe el pulso compacto por estacion');

SELECT is(
    (SELECT 'security_invoker=true' = ANY (coalesce(c.reloptions, ARRAY[]::text[]))
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'station_capacity_current'),
    true,
    'station_capacity_current respeta RLS de la tabla base'
);

SELECT is(
    (SELECT 'security_invoker=true' = ANY (coalesce(c.reloptions, ARRAY[]::text[]))
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'assignment_current'),
    true,
    'assignment_current respeta RLS de assignments'
);

SELECT is(
    (SELECT 'security_invoker=true' = ANY (coalesce(c.reloptions, ARRAY[]::text[]))
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'console_identity'),
    true,
    'console_identity respeta RLS de identidad, membresia y estacion'
);

SELECT is(
    (SELECT bool_and(c.relrowsecurity)
     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname IN ('station_capacity_grants', 'devices', 'station_live')),
    true,
    'las tres tablas nuevas tienen RLS habilitado'
);

SELECT is(
    has_table_privilege('anon', 'public.devices', 'SELECT'),
    false,
    'anon no puede leer dispositivos'
);

SELECT is(
    has_table_privilege('authenticated', 'public.devices', 'SELECT'),
    true,
    'authenticated puede leer dispositivos sujeto a RLS'
);

SELECT is(
    has_function_privilege(
        'anon', 'public.touch_device(text,uuid,text,text)', 'EXECUTE'
    ),
    false,
    'anon no puede registrar heartbeat'
);

SELECT is(
    has_function_privilege(
        'authenticated', 'public.touch_device(text,uuid,text,text)', 'EXECUTE'
    ),
    true,
    'authenticated puede registrar su propio heartbeat'
);

SELECT is(
    EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'station_live'
    ),
    true,
    'station_live esta publicado para Realtime'
);

SELECT is(
    EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'staff_memberships'
    ),
    true,
    'la membresia propia esta publicada para revocacion inmediata'
);

INSERT INTO public.stations (
    id, environment_id, region_id, code, name, status, timezone
)
SELECT
    'c0100000-0000-4000-8000-000000000001'::uuid,
    r.environment_id,
    r.id,
    'console-01-station',
    'Console 0.1 Station',
    'active',
    'America/Mexico_City'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE console_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = 'c0100000-0000-4000-8000-000000000001'::uuid;

INSERT INTO public.stations (
    id, environment_id, region_id, code, name, status, timezone
)
SELECT
    'c0100000-0000-4000-8000-000000000002'::uuid,
    r.environment_id,
    r.id,
    'console-01-other-station',
    'Console 0.1 Other Station',
    'active',
    'America/Mexico_City'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE console_other_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = 'c0100000-0000-4000-8000-000000000002'::uuid;

GRANT SELECT ON console_scope TO authenticated;
GRANT SELECT ON console_other_scope TO authenticated;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT fixture.profile_id, scope.environment_id,
       fixture.employee_number, fixture.display_name, 'active'
FROM console_scope scope
CROSS JOIN (
    VALUES
        (
            'c0101000-0000-4000-8000-000000000001'::uuid,
            'CONSOLE-SUPERVISOR', 'Console Supervisor'
        ),
        (
            'c0101000-0000-4000-8000-000000000002'::uuid,
            'CONSOLE-DRIVER', 'Console Driver'
        )
) AS fixture(profile_id, employee_number, display_name);

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT
    'c0101000-0000-4000-8000-000000000003'::uuid,
    scope.environment_id,
    'CONSOLE-OTHER-DRIVER',
    'Console Other Driver',
    'active'
FROM console_other_scope scope;

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role,
    starts_at, shift_group, shift_slot
)
SELECT fixture.membership_id, scope.environment_id,
       fixture.profile_id, scope.station_id, fixture.role,
       '2020-01-01 00:00:00+00'::timestamptz,
       fixture.shift_group, fixture.shift_slot
FROM console_scope scope
CROSS JOIN (
    VALUES
        (
            'c0102000-0000-4000-8000-000000000001'::uuid,
            'c0101000-0000-4000-8000-000000000001'::uuid,
            'supervisor', NULL::text, NULL::text
        ),
        (
            'c0102000-0000-4000-8000-000000000002'::uuid,
            'c0101000-0000-4000-8000-000000000002'::uuid,
            'driver', 'weekday', 'morning'
        )
) AS fixture(membership_id, profile_id, role, shift_group, shift_slot);

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role,
    starts_at, shift_group, shift_slot
)
SELECT
    'c0102000-0000-4000-8000-000000000003'::uuid,
    scope.environment_id,
    'c0101000-0000-4000-8000-000000000003'::uuid,
    scope.station_id,
    'driver',
    '2020-01-01 00:00:00+00'::timestamptz,
    'weekday',
    'morning'
FROM console_other_scope scope;

INSERT INTO public.driver_profiles (
    id, environment_id, station_id, profile_id, membership_id,
    employee_number, status
)
SELECT
    'c0103000-0000-4000-8000-000000000001'::uuid,
    scope.environment_id,
    scope.station_id,
    'c0101000-0000-4000-8000-000000000002'::uuid,
    'c0102000-0000-4000-8000-000000000002'::uuid,
    'CONSOLE-DRIVER',
    'active'
FROM console_scope scope;

INSERT INTO public.driver_profiles (
    id, environment_id, station_id, profile_id, membership_id,
    employee_number, status
)
SELECT
    'c0103000-0000-4000-8000-000000000002'::uuid,
    scope.environment_id,
    scope.station_id,
    'c0101000-0000-4000-8000-000000000003'::uuid,
    'c0102000-0000-4000-8000-000000000003'::uuid,
    'CONSOLE-OTHER-DRIVER',
    'active'
FROM console_other_scope scope;

INSERT INTO public.vehicles (
    id, environment_id, station_id, internal_number, qr_code,
    model, odometer_km, battery_pct, status
)
SELECT fixture.vehicle_id, scope.environment_id, scope.station_id,
       fixture.internal_number, fixture.qr_code,
       'Console Vehicle', 10, 90, fixture.status
FROM console_scope scope
CROSS JOIN (
    VALUES
        (
            'c0104000-0000-4000-8000-000000000001'::uuid,
            'CONSOLE-V1', 'CONSOLE-QR1', 'occupied'
        ),
        (
            'c0104000-0000-4000-8000-000000000002'::uuid,
            'CONSOLE-V2', 'CONSOLE-QR2', 'available'
        ),
        (
            'c0104000-0000-4000-8000-000000000003'::uuid,
            'CONSOLE-V3', 'CONSOLE-QR3', 'maintenance'
        )
) AS fixture(vehicle_id, internal_number, qr_code, status);

INSERT INTO public.vehicles (
    id, environment_id, station_id, internal_number, qr_code,
    model, odometer_km, battery_pct, status
)
SELECT
    'c0104000-0000-4000-8000-000000000004'::uuid,
    scope.environment_id,
    scope.station_id,
    'CONSOLE-OTHER-V1',
    'CONSOLE-OTHER-QR1',
    'Console Other Vehicle',
    20,
    80,
    'occupied'
FROM console_other_scope scope;

INSERT INTO public.assignments (
    id, environment_id, station_id, driver_profile_id, vehicle_id,
    kind, assigned_by, assigned_at
)
SELECT
    'c0105000-0000-4000-8000-000000000001'::uuid,
    scope.environment_id,
    scope.station_id,
    'c0103000-0000-4000-8000-000000000001'::uuid,
    'c0104000-0000-4000-8000-000000000001'::uuid,
    'titular',
    'c0101000-0000-4000-8000-000000000001'::uuid,
    '2026-08-31 10:00:00+00'::timestamptz
FROM console_scope scope;

INSERT INTO public.assignments (
    id, environment_id, station_id, driver_profile_id, vehicle_id,
    kind, assigned_by, assigned_at
)
SELECT
    'c0105000-0000-4000-8000-000000000002'::uuid,
    scope.environment_id,
    scope.station_id,
    'c0103000-0000-4000-8000-000000000002'::uuid,
    'c0104000-0000-4000-8000-000000000004'::uuid,
    'titular',
    'c0101000-0000-4000-8000-000000000003'::uuid,
    '2026-08-31 10:00:00+00'::timestamptz
FROM console_other_scope scope;

INSERT INTO public.shifts (
    id, environment_id, station_id, driver_profile_id, vehicle_id,
    assignment_id, shift_group, shift_slot, operating_date,
    scheduled_start_at, scheduled_end_at, started_at, late_minutes,
    start_odometer_km, start_battery_pct, status
)
SELECT
    'c0106000-0000-4000-8000-000000000001'::uuid,
    scope.environment_id,
    scope.station_id,
    'c0103000-0000-4000-8000-000000000001'::uuid,
    'c0104000-0000-4000-8000-000000000001'::uuid,
    'c0105000-0000-4000-8000-000000000001'::uuid,
    'weekday', 'morning', '2026-08-31'::date,
    '2026-08-31 11:00:00+00'::timestamptz,
    '2026-08-31 20:00:00+00'::timestamptz,
    '2026-08-31 11:00:00+00'::timestamptz,
    0, 10, 90, 'open'
FROM console_scope scope;

INSERT INTO public.shifts (
    id, environment_id, station_id, driver_profile_id, vehicle_id,
    assignment_id, shift_group, shift_slot, operating_date,
    scheduled_start_at, scheduled_end_at, started_at, late_minutes,
    start_odometer_km, start_battery_pct, status
)
SELECT
    'c0106000-0000-4000-8000-000000000002'::uuid,
    scope.environment_id,
    scope.station_id,
    'c0103000-0000-4000-8000-000000000002'::uuid,
    'c0104000-0000-4000-8000-000000000004'::uuid,
    'c0105000-0000-4000-8000-000000000002'::uuid,
    'weekday', 'morning', '2026-08-31'::date,
    '2026-08-31 11:00:00+00'::timestamptz,
    '2026-08-31 20:00:00+00'::timestamptz,
    '2026-08-31 11:00:00+00'::timestamptz,
    0, 20, 80, 'open'
FROM console_other_scope scope;

INSERT INTO public.station_capacity_grants (
    environment_id, station_id, capacity, granted_by, effective_from
)
SELECT scope.environment_id, scope.station_id, fixture.capacity,
       'c0101000-0000-4000-8000-000000000001'::uuid,
       fixture.effective_from
FROM console_scope scope
CROSS JOIN (
    VALUES
        (80, '2026-01-01 00:00:00+00'::timestamptz),
        (100, '2026-08-01 00:00:00+00'::timestamptz)
) AS fixture(capacity, effective_from);

SELECT results_eq(
    $sql$
        SELECT active_shifts, present_drivers, available_units, units_in_shop
        FROM public.station_live
        WHERE station_id = 'c0100000-0000-4000-8000-000000000001'::uuid
    $sql$,
    $sql$ VALUES (1::integer, 1::integer, 1::integer, 1::integer) $sql$,
    'los triggers reconstruyen el pulso operativo de la estacion'
);

SELECT is(
    (SELECT count(*)::bigint FROM public.assignment_current
     WHERE station_id = 'c0100000-0000-4000-8000-000000000001'::uuid),
    1::bigint,
    'assignment_current contiene solo la asignacion vigente'
);

-- Sustitucion transaccional del resolvedor. ROLLBACK restaura el real.
CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

SELECT set_config(
    'request.jwt.claim.sub',
    'c0101000-0000-4000-8000-000000000001', true
);
SET LOCAL ROLE authenticated;

SELECT results_eq(
    $sql$
        SELECT role, station_code
        FROM public.console_identity
    $sql$,
    $sql$ VALUES ('supervisor'::text, 'console-01-station'::text) $sql$,
    'la consola resuelve una membresia supervisora vigente con reloj TEST'
);

SELECT is(
    (SELECT capacity FROM public.station_capacity_current
     WHERE station_id = 'c0100000-0000-4000-8000-000000000001'::uuid),
    100,
    'la vista entrega la capacidad efectiva mas reciente'
);

SELECT lives_ok(
    $sql$
        SELECT public.touch_device(
            'console-browser-01',
            'c0102000-0000-4000-8000-000000000001'::uuid,
            'web', '0.1-test'
        )
    $sql$,
    'el supervisor registra el heartbeat de su navegador'
);

SELECT results_eq(
    $sql$
        SELECT platform, app_version
        FROM public.devices
        WHERE install_id = 'console-browser-01'
    $sql$,
    $sql$ VALUES ('web'::text, '0.1-test'::text) $sql$,
    'el dispositivo queda ligado a la identidad autenticada'
);

WITH before_heartbeat AS MATERIALIZED (
    SELECT last_seen_at
    FROM public.devices
    WHERE install_id = 'console-browser-01'
), replay AS MATERIALIZED (
    SELECT (
        public.touch_device(
            'console-browser-01',
            'c0102000-0000-4000-8000-000000000001'::uuid,
            'web', '0.1-test'
        )
    ).last_seen_at
    FROM before_heartbeat
)
SELECT is(
    (SELECT last_seen_at FROM before_heartbeat),
    (SELECT last_seen_at FROM replay),
    'un reintento dentro del minuto no vuelve a escribir el heartbeat'
);

SELECT is(
    (SELECT count(*)::bigint FROM public.station_live),
    1::bigint,
    'RLS limita el pulso a la estacion del supervisor'
);

SELECT is(
    (SELECT count(*)::bigint FROM public.vehicles),
    3::bigint,
    'RLS no filtra vehiculos de otra estacion por una referencia ambigua'
);

SELECT is(
    (SELECT count(*)::bigint FROM public.driver_profiles),
    1::bigint,
    'RLS no expone conductores de otra estacion'
);

SELECT is(
    (SELECT count(*)::bigint FROM public.assignment_current),
    1::bigint,
    'la vista vigente conserva el aislamiento de asignaciones'
);

SELECT is(
    (SELECT count(*)::bigint FROM public.shifts),
    1::bigint,
    'RLS no expone turnos de otra estacion'
);

RESET ROLE;

SELECT throws_ok(
    $sql$
        UPDATE public.station_capacity_grants
        SET capacity = 101
        WHERE station_id = 'c0100000-0000-4000-8000-000000000001'::uuid
    $sql$,
    '55000', 'station_capacity_grants_append_only',
    'una capacidad emitida no se puede reescribir'
);

UPDATE public.staff_memberships
SET ends_at = '2020-01-02 00:00:00+00'::timestamptz
WHERE id = 'c0102000-0000-4000-8000-000000000001'::uuid;

SET LOCAL ROLE authenticated;

SELECT is(
    (SELECT count(*)::bigint FROM public.station_live),
    0::bigint,
    'la siguiente consulta pierde alcance al cerrar la membresia'
);

SELECT throws_ok(
    $sql$
        SELECT public.touch_device(
            'console-browser-01',
            'c0102000-0000-4000-8000-000000000001'::uuid,
            'web', '0.1-test'
        )
    $sql$,
    '42501', 'membership_revoked',
    'el heartbeat tambien rechaza la membresia cerrada'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
