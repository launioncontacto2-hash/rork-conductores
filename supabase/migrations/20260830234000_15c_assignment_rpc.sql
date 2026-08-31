-- =====================================================================
-- TurnoEV · 15C · RPC transaccional de asignacion de vehiculos
--
-- Un cliente autenticado no escribe assignments ni vehicles directamente.
-- Esta funcion valida identidad, rol, estacion, idempotencia y exclusividad,
-- y registra el cambio de estado y la auditoria en la misma transaccion.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.assign_vehicle(
    p_driver_profile_id uuid,
    p_vehicle_id uuid,
    p_idempotency_key text,
    p_kind text DEFAULT 'titular',
    p_titular_vehicle_id uuid DEFAULT NULL,
    p_note text DEFAULT NULL
)
RETURNS public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_now timestamptz;
    v_request jsonb;

    v_driver public.driver_profiles%ROWTYPE;
    v_target_vehicle public.vehicles%ROWTYPE;
    v_titular_vehicle public.vehicles%ROWTYPE;
    v_current_assignment public.assignments%ROWTYPE;
    v_target_assignment public.assignments%ROWTYPE;
    v_result public.assignments%ROWTYPE;
    v_command public.command_log%ROWTYPE;
BEGIN
    v_actor_profile_id := app.auth_profile_id();

    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required'
            USING ERRCODE = '42501';
    END IF;

    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required'
            USING ERRCODE = '22023';
    END IF;

    IF p_kind NOT IN ('titular', 'substitute') THEN
        RAISE EXCEPTION 'invalid_assignment_kind'
            USING ERRCODE = '22023';
    END IF;

    IF p_kind = 'titular' AND p_titular_vehicle_id IS NOT NULL THEN
        RAISE EXCEPTION 'titular_assignment_cannot_reference_titular_vehicle'
            USING ERRCODE = '22023';
    END IF;

    IF p_kind = 'substitute'
       AND (
            p_titular_vehicle_id IS NULL
            OR p_titular_vehicle_id = p_vehicle_id
       ) THEN
        RAISE EXCEPTION 'substitute_requires_distinct_titular_vehicle'
            USING ERRCODE = '22023';
    END IF;

    SELECT dp.*
    INTO v_driver
    FROM public.driver_profiles dp
    WHERE dp.id = p_driver_profile_id
      AND dp.status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_driver_profile_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    v_environment_id := app.current_environment_id();

    IF v_driver.environment_id <> v_environment_id THEN
        RAISE EXCEPTION 'driver_outside_current_environment'
            USING ERRCODE = '42501';
    END IF;

    IF NOT app.auth_has_role('supervisor', v_driver.station_id) THEN
        RAISE EXCEPTION 'supervisor_role_required_for_station'
            USING ERRCODE = '42501';
    END IF;

    -- Serializa las decisiones de asignacion de una estacion. Asi se evita
    -- que dos supervisores cierren o abran exclusividades en orden distinto.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(v_driver.station_id::text, 15)
    );

    v_request := jsonb_build_object(
        'driver_profile_id', p_driver_profile_id,
        'vehicle_id', p_vehicle_id,
        'kind', p_kind,
        'titular_vehicle_id', p_titular_vehicle_id,
        'note', NULLIF(btrim(p_note), '')
    );

    SELECT cl.*
    INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;

    IF FOUND THEN
        IF v_command.command_name <> 'assign_vehicle'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'assignment_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict'
                USING ERRCODE = '23505';
        END IF;

        SELECT a.*
        INTO STRICT v_result
        FROM public.assignments a
        WHERE a.id = (v_command.result_payload->>'assignment_id')::uuid;

        RETURN v_result;
    END IF;

    SELECT a.*
    INTO v_current_assignment
    FROM public.assignments a
    WHERE a.driver_profile_id = p_driver_profile_id
      AND a.ended_at IS NULL
    FOR UPDATE;

    SELECT v.*
    INTO v_target_vehicle
    FROM public.vehicles v
    WHERE v.id = p_vehicle_id
      AND v.environment_id = v_driver.environment_id
      AND v.station_id = v_driver.station_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'vehicle_not_found_in_driver_station'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_target_vehicle.status <> 'available' THEN
        RAISE EXCEPTION 'vehicle_not_available'
            USING ERRCODE = '55000';
    END IF;

    SELECT a.*
    INTO v_target_assignment
    FROM public.assignments a
    WHERE a.vehicle_id = p_vehicle_id
      AND a.ended_at IS NULL
    FOR UPDATE;

    IF FOUND THEN
        RAISE EXCEPTION 'vehicle_already_assigned'
            USING ERRCODE = '23505';
    END IF;

    IF p_kind = 'substitute' THEN
        SELECT v.*
        INTO v_titular_vehicle
        FROM public.vehicles v
        WHERE v.id = p_titular_vehicle_id
          AND v.environment_id = v_driver.environment_id
          AND v.station_id = v_driver.station_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'titular_vehicle_not_found_in_driver_station'
                USING ERRCODE = 'P0002';
        END IF;

        IF v_current_assignment.id IS NULL
           OR NOT (
                (
                    v_current_assignment.kind = 'titular'
                    AND v_current_assignment.vehicle_id = p_titular_vehicle_id
                )
                OR
                (
                    v_current_assignment.kind = 'substitute'
                    AND v_current_assignment.titular_vehicle_id = p_titular_vehicle_id
                )
           ) THEN
            RAISE EXCEPTION 'substitute_does_not_match_current_titular'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    v_now := app.env_now(v_environment_id);

    INSERT INTO public.command_log (
        environment_id,
        actor_profile_id,
        command_name,
        idempotency_key,
        status,
        request_payload,
        occurred_at
    )
    VALUES (
        v_environment_id,
        v_actor_profile_id,
        'assign_vehicle',
        btrim(p_idempotency_key),
        'accepted',
        v_request,
        v_now
    )
    RETURNING * INTO v_command;

    IF v_current_assignment.id IS NOT NULL THEN
        UPDATE public.assignments
        SET ended_at = v_now
        WHERE id = v_current_assignment.id;

        UPDATE public.vehicles
        SET status = 'available',
            revision = revision + 1
        WHERE id = v_current_assignment.vehicle_id
          AND status = 'occupied';

        IF FOUND THEN
            INSERT INTO public.vehicle_state_transitions (
                environment_id,
                station_id,
                vehicle_id,
                actor_profile_id,
                from_status,
                to_status,
                reason,
                created_at
            )
            VALUES (
                v_environment_id,
                v_driver.station_id,
                v_current_assignment.vehicle_id,
                v_actor_profile_id,
                'occupied',
                'available',
                'assignment_replaced',
                v_now
            );
        END IF;
    END IF;

    INSERT INTO public.assignments (
        environment_id,
        station_id,
        driver_profile_id,
        vehicle_id,
        kind,
        titular_vehicle_id,
        note,
        assigned_by,
        assigned_at
    )
    VALUES (
        v_environment_id,
        v_driver.station_id,
        p_driver_profile_id,
        p_vehicle_id,
        p_kind,
        p_titular_vehicle_id,
        NULLIF(btrim(p_note), ''),
        v_actor_profile_id,
        v_now
    )
    RETURNING * INTO v_result;

    UPDATE public.vehicles
    SET status = 'occupied',
        revision = revision + 1
    WHERE id = p_vehicle_id;

    INSERT INTO public.vehicle_state_transitions (
        environment_id,
        station_id,
        vehicle_id,
        actor_profile_id,
        from_status,
        to_status,
        reason,
        created_at
    )
    VALUES (
        v_environment_id,
        v_driver.station_id,
        p_vehicle_id,
        v_actor_profile_id,
        'available',
        'occupied',
        'assignment_created',
        v_now
    );

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'assignment_id', v_result.id,
            'assigned_at', v_result.assigned_at
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id,
        actor_profile_id,
        station_id,
        command_id,
        event_type,
        entity_type,
        entity_id,
        metadata,
        occurred_at
    )
    VALUES (
        v_environment_id,
        v_actor_profile_id,
        v_driver.station_id,
        v_command.id,
        'assignment.created',
        'assignment',
        v_result.id,
        jsonb_build_object(
            'driver_profile_id', p_driver_profile_id,
            'vehicle_id', p_vehicle_id,
            'kind', p_kind
        ),
        v_now
    );

    RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.assign_vehicle(
    uuid, uuid, text, text, uuid, text
) IS
    'Unica via autenticada para asignar una unidad en 15C. Exige supervisor de la estacion, serializa la operacion, conserva historial y aplica idempotencia.';

REVOKE ALL ON FUNCTION public.assign_vehicle(
    uuid, uuid, text, text, uuid, text
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.assign_vehicle(
    uuid, uuid, text, text, uuid, text
) TO authenticated, service_role;
