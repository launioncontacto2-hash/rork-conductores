-- DORI Copiloto · eventos privados, inmutables y recalculados en servidor.
--
-- El cliente aporta la oferta/contexto o el resultado observado. La Edge Function
-- ejecuta el motor canonico y construye el evento. Estas RPC solo aceptan llamadas
-- de service_role, derivan la identidad desde auth.users y escriben en una transaccion.

CREATE TABLE public.dori_decision_events (
    id uuid PRIMARY KEY,
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    actor_profile_id uuid NOT NULL,
    command_id uuid NOT NULL UNIQUE,
    source text NOT NULL,
    event_schema_version text NOT NULL,
    model_version text NOT NULL,
    rules_version text NOT NULL,
    parameter_version text NOT NULL,
    evaluated_at timestamptz NOT NULL,
    recommendation text NOT NULL,
    reasons text[] NOT NULL,
    scores jsonb NOT NULL,
    total_score numeric NOT NULL,
    threshold numeric NOT NULL,
    expected_accept_value numeric NOT NULL,
    expected_reject_value numeric NOT NULL,
    opportunity_cost numeric NOT NULL,
    operational_blocks text[] NOT NULL,
    near_boundary boolean NOT NULL,
    input_payload jsonb NOT NULL,
    result_payload jsonb NOT NULL,
    event_payload jsonb NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT dori_decision_environment_fkey
        FOREIGN KEY (environment_id) REFERENCES public.environments(id) ON DELETE RESTRICT,
    CONSTRAINT dori_decision_station_environment_fkey
        FOREIGN KEY (station_id, environment_id)
        REFERENCES public.stations(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT dori_decision_driver_scope_fkey
        FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT dori_decision_actor_environment_fkey
        FOREIGN KEY (actor_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT dori_decision_command_fkey
        FOREIGN KEY (command_id) REFERENCES public.command_log(id) ON DELETE RESTRICT,
    CONSTRAINT dori_decision_source_check
        CHECK (source IN ('simulated', 'historical', 'manual')),
    CONSTRAINT dori_decision_schema_check CHECK (event_schema_version = '1.0.0'),
    CONSTRAINT dori_decision_recommendation_check
        CHECK (recommendation IN ('RECOMENDADO', 'NO RECOMENDADO')),
    CONSTRAINT dori_decision_reasons_check
        CHECK (cardinality(reasons) BETWEEN 1 AND 3 AND array_position(reasons, NULL) IS NULL),
    CONSTRAINT dori_decision_operational_blocks_check
        CHECK (array_position(operational_blocks, NULL) IS NULL),
    CONSTRAINT dori_decision_scores_object_check CHECK (jsonb_typeof(scores) = 'object'),
    CONSTRAINT dori_decision_input_object_check CHECK (jsonb_typeof(input_payload) = 'object'),
    CONSTRAINT dori_decision_result_object_check CHECK (jsonb_typeof(result_payload) = 'object'),
    CONSTRAINT dori_decision_event_object_check CHECK (jsonb_typeof(event_payload) = 'object'),
    CONSTRAINT dori_decision_score_range_check CHECK (total_score BETWEEN 0 AND 100),
    CONSTRAINT dori_decision_threshold_range_check CHECK (threshold BETWEEN 0 AND 100),
    CONSTRAINT dori_decision_model_version_not_blank CHECK (btrim(model_version) <> ''),
    CONSTRAINT dori_decision_rules_version_not_blank CHECK (btrim(rules_version) <> ''),
    CONSTRAINT dori_decision_parameter_version_not_blank CHECK (btrim(parameter_version) <> '')
);

CREATE INDEX dori_decision_driver_evaluated_idx
ON public.dori_decision_events(driver_profile_id, evaluated_at DESC, id DESC);

CREATE INDEX dori_decision_station_evaluated_idx
ON public.dori_decision_events(station_id, evaluated_at DESC, id DESC);

CREATE INDEX dori_decision_versions_idx
ON public.dori_decision_events(model_version, rules_version, parameter_version);

CREATE TABLE public.dori_outcome_events (
    id uuid PRIMARY KEY,
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    actor_profile_id uuid NOT NULL,
    command_id uuid NOT NULL UNIQUE,
    decision_event_id uuid NOT NULL UNIQUE,
    source text NOT NULL,
    event_schema_version text NOT NULL,
    observed_at timestamptz NOT NULL,
    driver_action text NOT NULL,
    actual_fare numeric,
    actual_trip_minutes numeric,
    actual_trip_km numeric,
    next_wait_minutes numeric,
    next_fare numeric,
    prediction_error jsonb NOT NULL,
    observation_payload jsonb NOT NULL,
    event_payload jsonb NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT dori_outcome_environment_fkey
        FOREIGN KEY (environment_id) REFERENCES public.environments(id) ON DELETE RESTRICT,
    CONSTRAINT dori_outcome_station_environment_fkey
        FOREIGN KEY (station_id, environment_id)
        REFERENCES public.stations(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT dori_outcome_driver_scope_fkey
        FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT dori_outcome_actor_environment_fkey
        FOREIGN KEY (actor_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT dori_outcome_command_fkey
        FOREIGN KEY (command_id) REFERENCES public.command_log(id) ON DELETE RESTRICT,
    CONSTRAINT dori_outcome_decision_fkey
        FOREIGN KEY (decision_event_id) REFERENCES public.dori_decision_events(id) ON DELETE RESTRICT,
    CONSTRAINT dori_outcome_source_check
        CHECK (source IN ('simulated', 'historical', 'manual')),
    CONSTRAINT dori_outcome_schema_check CHECK (event_schema_version = '1.0.0'),
    CONSTRAINT dori_outcome_action_check CHECK (driver_action IN ('accepted', 'rejected', 'unknown')),
    CONSTRAINT dori_outcome_nonnegative_check CHECK (
        (actual_fare IS NULL OR actual_fare >= 0)
        AND (actual_trip_minutes IS NULL OR actual_trip_minutes >= 0)
        AND (actual_trip_km IS NULL OR actual_trip_km >= 0)
        AND (next_wait_minutes IS NULL OR next_wait_minutes >= 0)
        AND (next_fare IS NULL OR next_fare >= 0)
    ),
    CONSTRAINT dori_outcome_unaccepted_trip_check CHECK (
        driver_action = 'accepted'
        OR (actual_fare IS NULL AND actual_trip_minutes IS NULL AND actual_trip_km IS NULL)
    ),
    CONSTRAINT dori_outcome_prediction_error_object_check
        CHECK (jsonb_typeof(prediction_error) = 'object'),
    CONSTRAINT dori_outcome_observation_object_check
        CHECK (jsonb_typeof(observation_payload) = 'object'),
    CONSTRAINT dori_outcome_event_object_check CHECK (jsonb_typeof(event_payload) = 'object')
);

CREATE INDEX dori_outcome_driver_observed_idx
ON public.dori_outcome_events(driver_profile_id, observed_at DESC, id DESC);

CREATE INDEX dori_outcome_station_observed_idx
ON public.dori_outcome_events(station_id, observed_at DESC, id DESC);

ALTER TABLE public.dori_decision_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dori_outcome_events ENABLE ROW LEVEL SECURITY;

-- Las politicas RLS de turnos/evidencia instaladas por DORI consultan este
-- resolvedor como authenticated. Sin EXECUTE, sus SELECT fallan antes de poder
-- aplicar el filtro de entorno.
GRANT EXECUTE ON FUNCTION app.current_environment_id() TO authenticated;

REVOKE ALL ON TABLE public.dori_decision_events FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dori_outcome_events FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.dori_decision_events TO authenticated, service_role;
GRANT SELECT ON TABLE public.dori_outcome_events TO authenticated, service_role;
GRANT ALL ON TABLE public.dori_decision_events TO postgres;
GRANT ALL ON TABLE public.dori_outcome_events TO postgres;

CREATE POLICY dori_decision_authorized_read
ON public.dori_decision_events FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.driver_profiles driver
        WHERE driver.id = dori_decision_events.driver_profile_id
          AND driver.profile_id = app.auth_profile_id()
    )
    OR app.auth_has_role('supervisor', station_id)
);

CREATE POLICY dori_outcome_authorized_read
ON public.dori_outcome_events FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.driver_profiles driver
        WHERE driver.id = dori_outcome_events.driver_profile_id
          AND driver.profile_id = app.auth_profile_id()
    )
    OR app.auth_has_role('supervisor', station_id)
);

CREATE OR REPLACE FUNCTION app.guard_dori_copilot_events_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
BEGIN
    RAISE EXCEPTION 'dori_copilot_events_are_append_only' USING ERRCODE = '42501';
END;
$function$;

CREATE TRIGGER dori_decision_block_update_delete
BEFORE UPDATE OR DELETE ON public.dori_decision_events
FOR EACH ROW EXECUTE FUNCTION app.guard_dori_copilot_events_append_only();

CREATE TRIGGER dori_outcome_block_update_delete
BEFORE UPDATE OR DELETE ON public.dori_outcome_events
FOR EACH ROW EXECUTE FUNCTION app.guard_dori_copilot_events_append_only();

REVOKE ALL ON FUNCTION app.guard_dori_copilot_events_append_only()
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION app.guard_dori_copilot_events_append_only() TO postgres;

CREATE OR REPLACE FUNCTION app.dori_driver_scope(p_auth_user_id uuid)
RETURNS TABLE (
    profile_id uuid,
    driver_profile_id uuid,
    environment_id uuid,
    station_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
    SELECT profile.id, driver.id, driver.environment_id, driver.station_id
    FROM public.profiles profile
    JOIN public.driver_profiles driver
      ON driver.profile_id = profile.id
     AND driver.environment_id = profile.environment_id
    JOIN public.staff_memberships membership
      ON membership.id = driver.membership_id
     AND membership.profile_id = profile.id
     AND membership.environment_id = driver.environment_id
     AND membership.station_id = driver.station_id
    WHERE profile.auth_user_id = p_auth_user_id
      AND profile.status = 'active'
      AND driver.status = 'active'
      AND membership.role = 'driver'
      AND membership.starts_at <= app.env_now(driver.environment_id)
      AND (membership.ends_at IS NULL OR membership.ends_at > app.env_now(driver.environment_id))
$function$;

REVOKE ALL ON FUNCTION app.dori_driver_scope(uuid)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION app.dori_driver_scope(uuid) TO postgres;

CREATE OR REPLACE FUNCTION public.record_dori_decision_event(
    p_auth_user_id uuid,
    p_idempotency_key text,
    p_event jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_profile_id uuid;
    v_driver_profile_id uuid;
    v_environment_id uuid;
    v_station_id uuid;
    v_command public.command_log%ROWTYPE;
    v_existing public.dori_decision_events%ROWTYPE;
    v_request jsonb;
    v_input jsonb;
    v_result jsonb;
    v_parameters jsonb;
    v_scores jsonb;
    v_event_id uuid;
    v_created_at timestamptz;
    v_evaluated_at timestamptz;
    v_source text;
    v_recommendation text;
    v_reasons text[];
    v_operational_blocks text[];
    v_total numeric;
    v_threshold numeric;
    v_expected_accept numeric;
    v_expected_reject numeric;
    v_opportunity_cost numeric;
    v_weighted_total numeric;
    v_should_recommend boolean;
    v_now timestamptz;
BEGIN
    IF p_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_idempotency_key IS NULL OR char_length(btrim(p_idempotency_key)) NOT BETWEEN 8 AND 200 THEN
        RAISE EXCEPTION 'invalid_idempotency_key' USING ERRCODE = '22023';
    END IF;

    SELECT scope.profile_id, scope.driver_profile_id, scope.environment_id, scope.station_id
    INTO v_profile_id, v_driver_profile_id, v_environment_id, v_station_id
    FROM app.dori_driver_scope(p_auth_user_id) scope;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_driver_identity_required' USING ERRCODE = '42501';
    END IF;

    IF coalesce(jsonb_typeof(p_event), 'null') <> 'object'
       OR p_event ->> 'kind' <> 'decision'
       OR p_event ->> 'schemaVersion' <> '1.0.0'
       OR coalesce(jsonb_typeof(p_event -> 'input'), 'null') <> 'object'
       OR coalesce(jsonb_typeof(p_event -> 'result'), 'null') <> 'object'
    THEN
        RAISE EXCEPTION 'invalid_decision_event' USING ERRCODE = '22023';
    END IF;

    BEGIN
        v_event_id := (p_event ->> 'id')::uuid;
        v_created_at := (p_event ->> 'createdAt')::timestamptz;
        v_input := p_event -> 'input';
        v_result := p_event -> 'result';
        v_parameters := v_result -> 'parameters';
        v_scores := v_result -> 'scores';
        v_evaluated_at := (v_input -> 'market' ->> 'now')::timestamptz;
        v_source := v_input ->> 'source';
        v_recommendation := v_result ->> 'recommendation';
        v_total := (v_result ->> 'total')::numeric;
        v_threshold := (v_result ->> 'threshold')::numeric;
        v_expected_accept := (v_result ->> 'expectedAcceptValue')::numeric;
        v_expected_reject := (v_result ->> 'expectedRejectValue')::numeric;
        v_opportunity_cost := (v_result ->> 'opportunityCost')::numeric;
        v_reasons := ARRAY(SELECT jsonb_array_elements_text(v_result -> 'reasons'));
        v_operational_blocks := ARRAY(SELECT jsonb_array_elements_text(v_result -> 'operationalBlocks'));
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'invalid_decision_event' USING ERRCODE = '22023';
    END;

    IF v_event_id IS NULL OR v_created_at IS NULL OR v_evaluated_at IS NULL
       OR v_source NOT IN ('simulated', 'historical', 'manual')
       OR v_input -> 'driver' ->> 'driverId' <> v_profile_id::text
       OR v_recommendation NOT IN ('RECOMENDADO', 'NO RECOMENDADO')
       OR coalesce(jsonb_typeof(v_result -> 'reasons'), 'null') <> 'array'
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_result -> 'reasons') item WHERE jsonb_typeof(item) <> 'string')
       OR cardinality(v_reasons) NOT BETWEEN 1 AND 3
       OR coalesce(jsonb_typeof(v_result -> 'operationalBlocks'), 'null') <> 'array'
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_result -> 'operationalBlocks') item WHERE jsonb_typeof(item) <> 'string')
       OR coalesce(jsonb_typeof(v_scores), 'null') <> 'object'
       OR coalesce(jsonb_typeof(v_parameters), 'null') <> 'object'
       OR v_result ->> 'modelVersion' IS DISTINCT FROM v_parameters ->> 'modelVersion'
       OR v_result ->> 'rulesVersion' IS DISTINCT FROM v_parameters ->> 'rulesVersion'
       OR v_result ->> 'parameterVersion' IS DISTINCT FROM v_parameters ->> 'parameterVersion'
       OR coalesce(v_result ->> 'modelVersion', '') <> 'deterministic-0.1'
       OR coalesce(v_result ->> 'rulesVersion', '') <> '0.1.0'
       OR coalesce(btrim(v_result ->> 'parameterVersion'), '') = ''
       OR coalesce(v_result ->> 'demand', '') NOT IN ('low', 'normal', 'high')
       OR v_total NOT BETWEEN 0 AND 100
       OR v_threshold NOT BETWEEN 0 AND 100
       OR abs(v_opportunity_cost - (v_expected_reject - v_expected_accept)) > 0.00000001
       OR v_threshold IS DISTINCT FROM (v_parameters -> 'thresholds' ->> (v_result ->> 'demand'))::numeric
    THEN
        RAISE EXCEPTION 'invalid_decision_event' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM (VALUES ('time'), ('distance'), ('pickup'), ('destination'), ('operational')) expected(key)
        WHERE coalesce(jsonb_typeof(v_scores -> expected.key), 'null') <> 'number'
           OR coalesce(jsonb_typeof(v_parameters -> 'weights' -> expected.key), 'null') <> 'number'
    ) THEN
        RAISE EXCEPTION 'invalid_decision_event' USING ERRCODE = '22023';
    END IF;

    v_weighted_total :=
        (v_scores ->> 'time')::numeric * (v_parameters -> 'weights' ->> 'time')::numeric
        + (v_scores ->> 'distance')::numeric * (v_parameters -> 'weights' ->> 'distance')::numeric
        + (v_scores ->> 'pickup')::numeric * (v_parameters -> 'weights' ->> 'pickup')::numeric
        + (v_scores ->> 'destination')::numeric * (v_parameters -> 'weights' ->> 'destination')::numeric
        + (v_scores ->> 'operational')::numeric * (v_parameters -> 'weights' ->> 'operational')::numeric;
    IF v_weighted_total IS NULL OR abs(v_weighted_total - v_total) > 0.00000001 THEN
        RAISE EXCEPTION 'invalid_decision_event' USING ERRCODE = '22023';
    END IF;

    v_should_recommend := cardinality(v_operational_blocks) = 0
        AND v_total >= v_threshold
        AND v_expected_accept >= v_expected_reject;
    IF (v_recommendation = 'RECOMENDADO') IS DISTINCT FROM v_should_recommend THEN
        RAISE EXCEPTION 'invalid_decision_event' USING ERRCODE = '22023';
    END IF;

    v_request := jsonb_build_object('input', v_input);
    SELECT command.* INTO v_command
    FROM public.command_log command
    WHERE command.environment_id = v_environment_id
      AND command.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'record_dori_decision_event'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
        THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT event.* INTO STRICT v_existing
        FROM public.dori_decision_events event
        WHERE event.command_id = v_command.id;
        RETURN v_existing.event_payload;
    END IF;

    v_now := app.env_now(v_environment_id);
    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_profile_id, 'record_dori_decision_event',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    INSERT INTO public.dori_decision_events (
        id, environment_id, station_id, driver_profile_id, actor_profile_id,
        command_id, source, event_schema_version, model_version, rules_version,
        parameter_version, evaluated_at, recommendation, reasons, scores,
        total_score, threshold, expected_accept_value, expected_reject_value,
        opportunity_cost, operational_blocks, near_boundary,
        input_payload, result_payload, event_payload
    ) VALUES (
        v_event_id, v_environment_id, v_station_id, v_driver_profile_id, v_profile_id,
        v_command.id, v_source, p_event ->> 'schemaVersion',
        v_result ->> 'modelVersion', v_result ->> 'rulesVersion',
        v_result ->> 'parameterVersion', v_evaluated_at, v_recommendation,
        v_reasons, v_scores, v_total, v_threshold, v_expected_accept,
        v_expected_reject, v_opportunity_cost, v_operational_blocks,
        (v_result ->> 'nearBoundary')::boolean, v_input, v_result, p_event
    );

    UPDATE public.command_log
    SET status = 'completed', result_payload = jsonb_build_object('event_id', v_event_id)
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_profile_id, v_station_id, v_command.id,
        'dori.decision.recorded', 'dori_decision_event', v_event_id,
        jsonb_build_object(
            'source', v_source,
            'recommendation', v_recommendation,
            'model_version', v_result ->> 'modelVersion',
            'rules_version', v_result ->> 'rulesVersion',
            'parameter_version', v_result ->> 'parameterVersion'
        ), v_now
    );

    RETURN p_event;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_dori_decision_event(uuid, text, jsonb)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_dori_decision_event(uuid, text, jsonb)
TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.record_dori_outcome_event(
    p_auth_user_id uuid,
    p_idempotency_key text,
    p_event jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_profile_id uuid;
    v_driver_profile_id uuid;
    v_environment_id uuid;
    v_station_id uuid;
    v_command public.command_log%ROWTYPE;
    v_decision public.dori_decision_events%ROWTYPE;
    v_existing public.dori_outcome_events%ROWTYPE;
    v_request jsonb;
    v_observation jsonb;
    v_error jsonb;
    v_event_id uuid;
    v_decision_id uuid;
    v_created_at timestamptz;
    v_observed_at timestamptz;
    v_action text;
    v_actual_fare numeric;
    v_actual_trip_minutes numeric;
    v_actual_trip_km numeric;
    v_next_wait numeric;
    v_next_fare numeric;
    v_now timestamptz;
BEGIN
    IF p_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_idempotency_key IS NULL OR char_length(btrim(p_idempotency_key)) NOT BETWEEN 8 AND 200 THEN
        RAISE EXCEPTION 'invalid_idempotency_key' USING ERRCODE = '22023';
    END IF;

    SELECT scope.profile_id, scope.driver_profile_id, scope.environment_id, scope.station_id
    INTO v_profile_id, v_driver_profile_id, v_environment_id, v_station_id
    FROM app.dori_driver_scope(p_auth_user_id) scope;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_driver_identity_required' USING ERRCODE = '42501';
    END IF;

    IF coalesce(jsonb_typeof(p_event), 'null') <> 'object'
       OR p_event ->> 'kind' <> 'outcome'
       OR p_event ->> 'schemaVersion' <> '1.0.0'
       OR coalesce(jsonb_typeof(p_event -> 'observation'), 'null') <> 'object'
       OR coalesce(jsonb_typeof(p_event -> 'predictionError'), 'null') <> 'object'
    THEN
        RAISE EXCEPTION 'invalid_outcome_event' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM (VALUES
            ('observedAt'), ('driverAction'), ('actualFare'), ('actualTripMinutes'),
            ('actualTripKm'), ('nextWaitMinutes'), ('nextFare')
        ) expected(key)
        WHERE NOT (p_event -> 'observation' ? expected.key)
    ) OR EXISTS (
        SELECT 1 FROM (VALUES
            ('fare'), ('tripMinutes'), ('tripKm'), ('nextWaitMinutes')
        ) expected(key)
        WHERE NOT (p_event -> 'predictionError' ? expected.key)
    ) THEN
        RAISE EXCEPTION 'invalid_outcome_event' USING ERRCODE = '22023';
    END IF;

    BEGIN
        v_event_id := (p_event ->> 'id')::uuid;
        v_decision_id := (p_event ->> 'decisionId')::uuid;
        v_created_at := (p_event ->> 'createdAt')::timestamptz;
        v_observation := p_event -> 'observation';
        v_error := p_event -> 'predictionError';
        v_observed_at := (v_observation ->> 'observedAt')::timestamptz;
        v_action := v_observation ->> 'driverAction';
        v_actual_fare := (v_observation ->> 'actualFare')::numeric;
        v_actual_trip_minutes := (v_observation ->> 'actualTripMinutes')::numeric;
        v_actual_trip_km := (v_observation ->> 'actualTripKm')::numeric;
        v_next_wait := (v_observation ->> 'nextWaitMinutes')::numeric;
        v_next_fare := (v_observation ->> 'nextFare')::numeric;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'invalid_outcome_event' USING ERRCODE = '22023';
    END;

    SELECT decision.* INTO v_decision
    FROM public.dori_decision_events decision
    WHERE decision.id = v_decision_id
      AND decision.environment_id = v_environment_id
      AND decision.station_id = v_station_id
      AND decision.driver_profile_id = v_driver_profile_id
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'owned_decision_event_not_found' USING ERRCODE = 'P0002';
    END IF;

    IF v_event_id IS NULL OR v_event_id = v_decision_id
       OR v_created_at < (v_decision.event_payload ->> 'createdAt')::timestamptz
       OR v_observed_at < v_decision.evaluated_at
       OR p_event ->> 'driverId' <> v_decision.input_payload -> 'driver' ->> 'driverId'
       OR p_event ->> 'source' <> v_decision.source
       OR v_action NOT IN ('accepted', 'rejected', 'unknown')
       OR v_actual_fare < 0 OR v_actual_trip_minutes < 0 OR v_actual_trip_km < 0
       OR v_next_wait < 0 OR v_next_fare < 0
       OR (v_action <> 'accepted' AND (
           v_actual_fare IS NOT NULL OR v_actual_trip_minutes IS NOT NULL OR v_actual_trip_km IS NOT NULL
       ))
    THEN
        RAISE EXCEPTION 'invalid_outcome_event' USING ERRCODE = '22023';
    END IF;

    IF (v_actual_fare IS NULL) IS DISTINCT FROM (v_error -> 'fare' = 'null'::jsonb)
       OR (v_actual_trip_minutes IS NULL) IS DISTINCT FROM (v_error -> 'tripMinutes' = 'null'::jsonb)
       OR (v_actual_trip_km IS NULL) IS DISTINCT FROM (v_error -> 'tripKm' = 'null'::jsonb)
       OR (
            v_action = 'accepted'
            AND (v_next_wait IS NULL) IS DISTINCT FROM (v_error -> 'nextWaitMinutes' = 'null'::jsonb)
       )
       OR (
            v_action <> 'accepted'
            AND v_error -> 'nextWaitMinutes' IS DISTINCT FROM 'null'::jsonb
       )
    THEN
        RAISE EXCEPTION 'invalid_outcome_event' USING ERRCODE = '22023';
    END IF;

    IF (v_actual_fare IS NOT NULL AND abs(
            (v_error ->> 'fare')::numeric
            - (v_actual_fare - (v_decision.input_payload -> 'trip' ->> 'fare')::numeric)
        ) > 0.00000001)
       OR (v_actual_trip_minutes IS NOT NULL AND abs(
            (v_error ->> 'tripMinutes')::numeric
            - (v_actual_trip_minutes - (v_decision.input_payload -> 'trip' ->> 'tripMinutes')::numeric)
        ) > 0.00000001)
       OR (v_actual_trip_km IS NOT NULL AND abs(
            (v_error ->> 'tripKm')::numeric
            - (v_actual_trip_km - (v_decision.input_payload -> 'trip' ->> 'tripKm')::numeric)
        ) > 0.00000001)
       OR (v_action = 'accepted' AND v_next_wait IS NOT NULL AND abs(
            (v_error ->> 'nextWaitMinutes')::numeric
            - (v_next_wait - (v_decision.result_payload ->> 'nextWaitMinutes')::numeric)
        ) > 0.00000001)
    THEN
        RAISE EXCEPTION 'invalid_outcome_event' USING ERRCODE = '22023';
    END IF;

    v_request := jsonb_build_object(
        'decision_id', v_decision_id,
        'observation', v_observation
    );
    SELECT command.* INTO v_command
    FROM public.command_log command
    WHERE command.environment_id = v_environment_id
      AND command.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'record_dori_outcome_event'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
        THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT event.* INTO STRICT v_existing
        FROM public.dori_outcome_events event
        WHERE event.command_id = v_command.id;
        RETURN v_existing.event_payload;
    END IF;

    v_now := app.env_now(v_environment_id);
    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_profile_id, 'record_dori_outcome_event',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    INSERT INTO public.dori_outcome_events (
        id, environment_id, station_id, driver_profile_id, actor_profile_id,
        command_id, decision_event_id, source, event_schema_version,
        observed_at, driver_action, actual_fare, actual_trip_minutes,
        actual_trip_km, next_wait_minutes, next_fare, prediction_error,
        observation_payload, event_payload
    ) VALUES (
        v_event_id, v_environment_id, v_station_id, v_driver_profile_id,
        v_profile_id, v_command.id, v_decision_id, v_decision.source,
        p_event ->> 'schemaVersion', v_observed_at, v_action, v_actual_fare,
        v_actual_trip_minutes, v_actual_trip_km, v_next_wait, v_next_fare,
        v_error, v_observation, p_event
    );

    UPDATE public.command_log
    SET status = 'completed', result_payload = jsonb_build_object('event_id', v_event_id)
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_profile_id, v_station_id, v_command.id,
        'dori.outcome.recorded', 'dori_outcome_event', v_event_id,
        jsonb_build_object(
            'decision_event_id', v_decision_id,
            'source', v_decision.source,
            'driver_action', v_action
        ), v_now
    );

    RETURN p_event;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_dori_outcome_event(uuid, text, jsonb)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_dori_outcome_event(uuid, text, jsonb)
TO postgres, service_role;

COMMENT ON TABLE public.dori_decision_events IS
    'DecisionEvent append-only: entrada aportada, resultado recalculado en servidor y versiones para reproduccion.';
COMMENT ON TABLE public.dori_outcome_events IS
    'OutcomeEvent append-only: hechos observados despues de una decision y errores derivados.';
COMMENT ON COLUMN public.dori_decision_events.input_payload IS
    'Cliente: oferta y contexto completos normalizados; source declara simulado, historical o manual.';
COMMENT ON COLUMN public.dori_decision_events.result_payload IS
    'Motor: recomendacion, razones, puntuaciones, parametros, valores esperados y bloqueos.';
COMMENT ON COLUMN public.dori_decision_events.event_payload IS
    'Servidor: DecisionEvent completo e inmutable devuelto por el motor canonico.';
COMMENT ON COLUMN public.dori_outcome_events.observation_payload IS
    'Observado posteriormente: accion, tarifa, duracion, distancia, espera y siguiente tarifa; null significa desconocido.';
COMMENT ON COLUMN public.dori_outcome_events.prediction_error IS
    'Calculado por el motor al enlazar el resultado observado con la decision original.';
COMMENT ON COLUMN public.dori_outcome_events.event_payload IS
    'Servidor: OutcomeEvent completo e inmutable; reservado como evidencia para aprendizaje futuro.';
COMMENT ON FUNCTION public.record_dori_decision_event(uuid, text, jsonb) IS
    'Persistencia interna de decisiones recalculadas por la Edge Function; no ejecutable por clientes.';
COMMENT ON FUNCTION public.record_dori_outcome_event(uuid, text, jsonb) IS
    'Persistencia interna de resultados observados enlazados a una decision propia; no ejecutable por clientes.';
