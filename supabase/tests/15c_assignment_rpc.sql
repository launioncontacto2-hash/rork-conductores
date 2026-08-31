BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(14);

SELECT has_function(
    'public',
    'assign_vehicle',
    ARRAY['uuid', 'uuid', 'text', 'text', 'uuid', 'text'],
    'existe el RPC assign_vehicle con el contrato previsto'
);

INSERT INTO public.stations (id, environment_id, region_id, code, name, status)
SELECT
    '15c46000-0000-4000-8000-000000000001'::uuid,
    r.environment_id,
    r.id,
    '15c-rpc-station',
    '15C RPC Station',
    'active'
FROM public.regions r
ORDER BY r.created_at, r.id
LIMIT 1;

CREATE TEMP TABLE test_15c_rpc_scope AS
SELECT environment_id, id AS station_id
FROM public.stations
WHERE id = '15c46000-0000-4000-8000-000000000001'::uuid;

INSERT INTO public.profiles (
    id, environment_id, employee_number, display_name, status
)
SELECT fixture.profile_id, scope.environment_id,
       fixture.employee_number, fixture.display_name, 'active'
FROM test_15c_rpc_scope scope
CROSS JOIN (
    VALUES
        (
            '15c06000-0000-4000-8000-000000000001'::uuid,
            '15C-RPC-SUPERVISOR',
            '15C RPC Supervisor'
        ),
        (
            '15c06000-0000-4000-8000-000000000002'::uuid,
            '15C-RPC-DRIVER',
            '15C RPC Driver'
        )
) AS fixture(profile_id, employee_number, display_name);

INSERT INTO public.staff_memberships (
    id, environment_id, profile_id, station_id, role,
    shift_group, shift_slot
)
SELECT fixture.membership_id, scope.environment_id,
       fixture.profile_id, scope.station_id, fixture.role,
       fixture.shift_group, fixture.shift_slot
FROM test_15c_rpc_scope scope
CROSS JOIN (
    VALUES
        (
            '15c16000-0000-4000-8000-000000000001'::uuid,
            '15c06000-0000-4000-8000-000000000001'::uuid,
            'supervisor', NULL::text, NULL::text
        ),
        (
            '15c16000-0000-4000-8000-000000000002'::uuid,
            '15c06000-0000-4000-8000-000000000002'::uuid,
            'driver', 'weekday', 'morning'
        )
) AS fixture(
    membership_id, profile_id, role, shift_group, shift_slot
);

INSERT INTO public.driver_profiles (
    id, environment_id, station_id, profile_id, membership_id,
    employee_number, status
)
SELECT
    '15c26000-0000-4000-8000-000000000001'::uuid,
    environment_id,
    station_id,
    '15c06000-0000-4000-8000-000000000002'::uuid,
    '15c16000-0000-4000-8000-000000000002'::uuid,
    '15C-RPC-DRIVER',
    'active'
FROM test_15c_rpc_scope;

INSERT INTO public.vehicles (
    id, environment_id, station_id, internal_number, qr_code,
    model, status
)
SELECT fixture.vehicle_id, scope.environment_id, scope.station_id,
       fixture.internal_number, fixture.qr_code,
       '15C RPC Vehicle', 'available'
FROM test_15c_rpc_scope scope
CROSS JOIN (
    VALUES
        (
            '15c36000-0000-4000-8000-000000000001'::uuid,
            '15C-RPC-V1', '15C-RPC-QR1'
        ),
        (
            '15c36000-0000-4000-8000-000000000002'::uuid,
            '15C-RPC-V2', '15C-RPC-QR2'
        )
) AS fixture(vehicle_id, internal_number, qr_code);

-- La prueba sustituye temporalmente el resolvedor de identidad. La transaccion
-- completa termina en ROLLBACK, por lo que la funcion real queda intacta.
CREATE OR REPLACE FUNCTION app.auth_profile_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
    SELECT NULLIF(
        current_setting('request.jwt.claim.sub', true),
        ''
    )::uuid
$function$;

SELECT set_config(
    'request.jwt.claim.sub',
    '15c06000-0000-4000-8000-000000000002',
    true
);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
    $sql$
        SELECT public.assign_vehicle(
            '15c26000-0000-4000-8000-000000000001'::uuid,
            '15c36000-0000-4000-8000-000000000001'::uuid,
            '15c-rpc-driver-denied'
        )
    $sql$,
    '42501',
    'supervisor_role_required_for_station',
    'un conductor no puede ejecutar el RPC de asignacion'
);

RESET ROLE;
SELECT set_config(
    'request.jwt.claim.sub',
    '15c06000-0000-4000-8000-000000000001',
    true
);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
    $sql$
        SELECT public.assign_vehicle(
            '15c26000-0000-4000-8000-000000000001'::uuid,
            '15c36000-0000-4000-8000-000000000001'::uuid,
            '15c-rpc-titular-1'
        )
    $sql$,
    'el supervisor crea la asignacion titular'
);

RESET ROLE;

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.assignments
        WHERE driver_profile_id =
            '15c26000-0000-4000-8000-000000000001'::uuid
          AND ended_at IS NULL
    ),
    1::bigint,
    'queda una sola asignacion activa para el conductor'
);

SELECT is(
    (
        SELECT status
        FROM public.vehicles
        WHERE id = '15c36000-0000-4000-8000-000000000001'::uuid
    ),
    'occupied',
    'la unidad titular queda ocupada'
);

SET LOCAL ROLE authenticated;

SELECT lives_ok(
    $sql$
        SELECT public.assign_vehicle(
            '15c26000-0000-4000-8000-000000000001'::uuid,
            '15c36000-0000-4000-8000-000000000001'::uuid,
            '15c-rpc-titular-1'
        )
    $sql$,
    'repetir la misma clave devuelve el resultado previo'
);

RESET ROLE;

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.assignments
        WHERE driver_profile_id =
            '15c26000-0000-4000-8000-000000000001'::uuid
    ),
    1::bigint,
    'la repeticion idempotente no duplica asignaciones'
);

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.command_log
        WHERE idempotency_key = '15c-rpc-titular-1'
    ),
    1::bigint,
    'la repeticion idempotente conserva un solo comando'
);

SET LOCAL ROLE authenticated;

SELECT throws_ok(
    $sql$
        SELECT public.assign_vehicle(
            '15c26000-0000-4000-8000-000000000001'::uuid,
            '15c36000-0000-4000-8000-000000000002'::uuid,
            '15c-rpc-titular-1'
        )
    $sql$,
    '23505',
    'idempotency_key_conflict',
    'reutilizar una clave con otro payload se rechaza'
);

SELECT lives_ok(
    $sql$
        SELECT public.assign_vehicle(
            '15c26000-0000-4000-8000-000000000001'::uuid,
            '15c36000-0000-4000-8000-000000000002'::uuid,
            '15c-rpc-substitute-1',
            'substitute',
            '15c36000-0000-4000-8000-000000000001'::uuid,
            'unidad sustituta de prueba'
        )
    $sql$,
    'el supervisor cambia de titular a sustituta'
);

RESET ROLE;

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.assignments
        WHERE driver_profile_id =
            '15c26000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'el cambio conserva el historial de ambas asignaciones'
);

SELECT results_eq(
    $sql$
        SELECT id, status
        FROM public.vehicles
        WHERE id IN (
            '15c36000-0000-4000-8000-000000000001'::uuid,
            '15c36000-0000-4000-8000-000000000002'::uuid
        )
        ORDER BY id
    $sql$,
    $sql$
        VALUES
            (
                '15c36000-0000-4000-8000-000000000001'::uuid,
                'available'::text
            ),
            (
                '15c36000-0000-4000-8000-000000000002'::uuid,
                'occupied'::text
            )
    $sql$,
    'libera la titular y ocupa la sustituta'
);

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.vehicle_state_transitions
        WHERE vehicle_id IN (
            '15c36000-0000-4000-8000-000000000001'::uuid,
            '15c36000-0000-4000-8000-000000000002'::uuid
        )
    ),
    3::bigint,
    'registra las tres transiciones de estado esperadas'
);

SELECT is(
    (
        SELECT count(*)::bigint
        FROM public.audit_log
        WHERE event_type = 'assignment.created'
          AND actor_profile_id =
            '15c06000-0000-4000-8000-000000000001'::uuid
    ),
    2::bigint,
    'audita cada asignacion aceptada'
);

SELECT * FROM finish();
ROLLBACK;
