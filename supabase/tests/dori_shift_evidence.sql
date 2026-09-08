BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(25);

SELECT has_table('public', 'shift_evidence', 'existe la evidencia de turno');
SELECT has_column('public', 'shift_evidence', 'object_path', 'la evidencia conserva su ruta privada');
SELECT has_column('public', 'shift_evidence', 'kind', 'la evidencia declara su tipo');
SELECT has_column('public', 'shift_evidence', 'captured_at', 'la evidencia conserva la hora operativa');
SELECT has_function(
    'public', 'start_shift_v3',
    ARRAY['uuid', 'bigint', 'integer', 'text', 'text', 'text', 'text'],
    'existe start_shift_v3 con evidencia y sesion de dispositivo'
);
SELECT has_function(
    'public', 'finish_shift_v3',
    ARRAY['uuid', 'bigint', 'bigint', 'integer', 'text', 'text', 'text'],
    'existe finish_shift_v3 con evidencia y sesion de dispositivo'
);
SELECT ok(
    has_function_privilege(
        'authenticated',
        'public.start_shift_v3(uuid,bigint,integer,text,text,text,text)', 'EXECUTE'
    ),
    'authenticated puede abrir turno con evidencia'
);
SELECT ok(
    has_function_privilege(
        'authenticated',
        'public.finish_shift_v3(uuid,bigint,bigint,integer,text,text,text)', 'EXECUTE'
    ),
    'authenticated puede cerrar turno con evidencia'
);
SELECT is(
    has_function_privilege(
        'anon',
        'public.start_shift_v3(uuid,bigint,integer,text,text,text,text)', 'EXECUTE'
    ), false,
    'anon no puede abrir turno'
);
SELECT is(
    has_function_privilege(
        'anon',
        'public.finish_shift_v3(uuid,bigint,bigint,integer,text,text,text)', 'EXECUTE'
    ), false,
    'anon no puede cerrar turno'
);
SELECT is(
    has_function_privilege(
        'authenticated',
        'public.start_shift_v2(uuid,bigint,integer,text,text)', 'EXECUTE'
    ), false,
    'el cliente ya no puede omitir evidencia al abrir'
);
SELECT is(
    has_function_privilege(
        'authenticated',
        'public.finish_shift_v2(uuid,bigint,bigint,integer,text,text)', 'EXECUTE'
    ), false,
    'el cliente ya no puede omitir evidencia al cerrar'
);
SELECT is(
    (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.shift_evidence'::regclass),
    true,
    'shift_evidence tiene RLS activo'
);
SELECT ok(
    has_table_privilege('authenticated', 'public.shift_evidence', 'SELECT'),
    'authenticated puede leer evidencia dentro de RLS'
);
SELECT is(
    has_table_privilege('authenticated', 'public.shift_evidence', 'INSERT'),
    false,
    'authenticated no puede insertar evidencia fuera del RPC'
);
SELECT is(
    (
        SELECT bucket.public = false
           AND bucket.file_size_limit = 5242880
           AND bucket.allowed_mime_types = ARRAY['image/jpeg']::text[]
        FROM storage.buckets bucket
        WHERE bucket.id = 'shift-evidence'
    ),
    true,
    'el deposito de evidencia es privado y acepta solo JPEG de hasta 5 MB'
);
SELECT has_function(
    'public', 'console_audit_history', ARRAY['integer'],
    'existe el lector protegido de auditoria para la consola'
);
SELECT ok(
    has_function_privilege(
        'authenticated', 'public.console_audit_history(integer)', 'EXECUTE'
    ),
    'authenticated puede invocar el lector que valida el rol internamente'
);
SELECT is(
    has_function_privilege(
        'anon', 'public.console_audit_history(integer)', 'EXECUTE'
    ), false,
    'anon no puede consultar la auditoria'
);
SELECT has_function(
    'app', 'enforce_sensitive_command_reason', ARRAY[]::text[],
    'existe la barrera central de motivos sensibles'
);
SELECT has_trigger(
    'public', 'command_log', 'command_log_sensitive_reason_guard',
    'command_log aplica la barrera antes de insertar'
);
SELECT throws_ok(
    $sql$
        INSERT INTO public.command_log(
            environment_id, command_name, idempotency_key, status, request_payload
        ) VALUES (
            NULL, 'assign_vehicle', 'dori-missing-reason', 'accepted', '{"note":null}'::jsonb
        )
    $sql$,
    '22023', 'sensitive_command_reason_required',
    'la base rechaza una asignacion sin motivo suficiente'
);
SELECT has_function(
    'public', 'revoke_driver_device', ARRAY['uuid', 'text', 'text'],
    'existe el retiro auditado de dispositivos de conductor'
);
SELECT ok(
    has_function_privilege(
        'authenticated', 'public.revoke_driver_device(uuid,text,text)', 'EXECUTE'
    ),
    'authenticated puede invocar el retiro que valida supervision internamente'
);
SELECT is(
    has_function_privilege(
        'anon', 'public.revoke_driver_device(uuid,text,text)', 'EXECUTE'
    ), false,
    'anon no puede retirar dispositivos'
);

SELECT * FROM finish();
ROLLBACK;
