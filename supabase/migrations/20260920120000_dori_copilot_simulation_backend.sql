-- DORI Copiloto: isolated Console -> Driver laboratory cases.
-- These tables never write to shifts, assignments, finances or live decision events.

CREATE TABLE public.dori_copilot_simulation_cases (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    created_by_profile_id uuid NOT NULL,
    test_case_id text NOT NULL,
    contract_version text NOT NULL,
    input_payload jsonb NOT NULL,
    source text NOT NULL DEFAULT 'console_simulation',
    is_simulation boolean NOT NULL DEFAULT true,
    status text NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    CONSTRAINT dori_sim_case_scope_fkey FOREIGN KEY (driver_profile_id, station_id, environment_id)
      REFERENCES public.driver_profiles(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT dori_sim_case_actor_fkey FOREIGN KEY (created_by_profile_id, environment_id)
      REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT dori_sim_case_source_check CHECK (source = 'console_simulation'),
    CONSTRAINT dori_sim_case_simulation_check CHECK (is_simulation),
    CONSTRAINT dori_sim_case_status_check CHECK (status IN ('pending','evaluated','expired')),
    CONSTRAINT dori_sim_case_payload_check CHECK (
      jsonb_typeof(input_payload) = 'object' AND input_payload->>'source' = 'simulated'
    ),
    CONSTRAINT dori_sim_case_dates_check CHECK (expires_at > created_at),
    CONSTRAINT dori_sim_case_test_id_check CHECK (btrim(test_case_id) <> ''),
    CONSTRAINT dori_sim_case_contract_check CHECK (btrim(contract_version) <> ''),
    CONSTRAINT dori_sim_case_unique UNIQUE (environment_id, station_id, test_case_id)
);

CREATE INDEX dori_sim_case_driver_pending_idx ON public.dori_copilot_simulation_cases
  (environment_id, station_id, driver_profile_id, status, expires_at);

CREATE TABLE public.dori_copilot_simulation_expectations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id uuid NOT NULL UNIQUE REFERENCES public.dori_copilot_simulation_cases(id) ON DELETE RESTRICT,
    expected_recommendation text NOT NULL,
    expected_reason_code text,
    criterion_version text NOT NULL,
    actor_profile_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT dori_sim_expected_recommendation_check CHECK (expected_recommendation IN ('RECOMENDADO','NO RECOMENDADO')),
    CONSTRAINT dori_sim_expected_criterion_check CHECK (btrim(criterion_version) <> '')
);

CREATE TABLE public.dori_copilot_simulation_evaluations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id uuid NOT NULL UNIQUE REFERENCES public.dori_copilot_simulation_cases(id) ON DELETE RESTRICT,
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    evaluated_by_profile_id uuid NOT NULL,
    actual_recommendation text NOT NULL,
    matches_expected boolean NOT NULL,
    classification text NOT NULL,
    has_operational_block boolean NOT NULL,
    result_payload jsonb NOT NULL,
    model_version text NOT NULL,
    rules_version text NOT NULL,
    parameter_version text NOT NULL,
    idempotency_key text NOT NULL UNIQUE,
    evaluated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT dori_sim_eval_scope_fkey FOREIGN KEY (driver_profile_id, station_id, environment_id)
      REFERENCES public.driver_profiles(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT dori_sim_eval_recommendation_check CHECK (actual_recommendation IN ('RECOMENDADO','NO RECOMENDADO')),
    CONSTRAINT dori_sim_eval_classification_check CHECK (classification IN ('correct_recommend','correct_reject','false_positive','false_negative')),
    CONSTRAINT dori_sim_eval_result_check CHECK (jsonb_typeof(result_payload) = 'object')
);

ALTER TABLE public.dori_copilot_simulation_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dori_copilot_simulation_expectations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dori_copilot_simulation_evaluations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dori_copilot_simulation_cases, public.dori_copilot_simulation_expectations, public.dori_copilot_simulation_evaluations FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.dori_copilot_simulation_cases, public.dori_copilot_simulation_expectations, public.dori_copilot_simulation_evaluations TO authenticated;
GRANT ALL ON public.dori_copilot_simulation_cases, public.dori_copilot_simulation_expectations, public.dori_copilot_simulation_evaluations TO postgres, service_role;

-- Only Console can read/write the laboratory. Supervisor is intentionally absent.
CREATE POLICY dori_sim_case_console_read ON public.dori_copilot_simulation_cases FOR SELECT TO authenticated
  USING (app.auth_has_role('console', station_id));
CREATE POLICY dori_sim_expected_console_read ON public.dori_copilot_simulation_expectations FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.dori_copilot_simulation_cases c WHERE c.id=case_id AND app.auth_has_role('console', c.station_id)));
CREATE POLICY dori_sim_eval_console_read ON public.dori_copilot_simulation_evaluations FOR SELECT TO authenticated
  USING (app.auth_has_role('console', station_id));
CREATE POLICY dori_sim_case_driver_read ON public.dori_copilot_simulation_cases FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.driver_profiles d WHERE d.id=driver_profile_id AND d.profile_id=app.auth_profile_id() AND d.station_id=dori_copilot_simulation_cases.station_id AND d.environment_id=dori_copilot_simulation_cases.environment_id));
CREATE POLICY dori_sim_eval_driver_read ON public.dori_copilot_simulation_evaluations FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.driver_profiles d WHERE d.id=driver_profile_id AND d.profile_id=app.auth_profile_id() AND d.station_id=dori_copilot_simulation_evaluations.station_id AND d.environment_id=dori_copilot_simulation_evaluations.environment_id));

CREATE OR REPLACE FUNCTION public.console_create_dori_simulation_case(
  p_auth_user_id uuid, p_idempotency_key text, p_test_case_id text, p_driver_profile_id uuid,
  p_input_payload jsonb, p_expected_recommendation text, p_expected_reason_code text,
  p_criterion_version text, p_expires_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp' AS $function$
DECLARE actor uuid:=app.auth_profile_id(); env uuid:=app.current_environment_id(); station uuid; existing public.command_log%ROWTYPE; cmd uuid; case_id uuid; result jsonb; request jsonb;
BEGIN
  IF actor IS NULL OR actor<>(SELECT id FROM public.profiles WHERE auth_user_id=p_auth_user_id AND id=actor) OR NOT app.auth_has_role('console') THEN RAISE EXCEPTION 'console_role_required' USING ERRCODE='42501'; END IF;
  IF p_idempotency_key IS NULL OR btrim(p_idempotency_key)='' THEN RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE='22023'; END IF;
  SELECT m.station_id INTO STRICT station FROM public.staff_memberships m WHERE m.profile_id=actor AND m.environment_id=env AND m.role='console' AND m.starts_at<=app.env_now(env) AND (m.ends_at IS NULL OR m.ends_at>app.env_now(env));
  IF NOT EXISTS (SELECT 1 FROM public.driver_profiles d WHERE d.id=p_driver_profile_id AND d.station_id=station AND d.environment_id=env AND d.status='active') THEN RAISE EXCEPTION 'driver_station_scope_required' USING ERRCODE='42501'; END IF;
  IF p_input_payload->>'source' <> 'simulated' OR p_input_payload->>'driver' IS NULL OR p_input_payload->'driver'->>'driverId' IS DISTINCT FROM p_driver_profile_id::text THEN RAISE EXCEPTION 'simulation_driver_identity_mismatch' USING ERRCODE='22023'; END IF;
  request:=jsonb_build_object('test_case_id',p_test_case_id,'driver_profile_id',p_driver_profile_id,'input_payload',p_input_payload,'expected_recommendation',p_expected_recommendation,'expected_reason_code',p_expected_reason_code,'criterion_version',p_criterion_version,'expires_at',p_expires_at);
  SELECT cl.* INTO existing FROM public.command_log cl WHERE cl.environment_id=env AND cl.idempotency_key=btrim(p_idempotency_key) FOR UPDATE;
  IF FOUND THEN
    IF existing.command_name <> 'console_create_dori_simulation_case' OR existing.request_payload IS DISTINCT FROM request OR existing.status <> 'completed' OR existing.result_payload IS NULL THEN RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE='23505'; END IF;
    RETURN existing.result_payload;
  END IF;
  INSERT INTO public.command_log(environment_id,actor_profile_id,command_name,idempotency_key,request_payload,status) VALUES(env,actor,'console_create_dori_simulation_case',btrim(p_idempotency_key),request,'accepted') RETURNING id INTO cmd;
  INSERT INTO public.dori_copilot_simulation_cases(environment_id,station_id,driver_profile_id,created_by_profile_id,test_case_id,contract_version,input_payload,created_at,expires_at) VALUES(env,station,p_driver_profile_id,actor,p_test_case_id,'1.0.0',p_input_payload,app.env_now(env),p_expires_at) RETURNING id INTO case_id;
  INSERT INTO public.dori_copilot_simulation_expectations(case_id,expected_recommendation,expected_reason_code,criterion_version,actor_profile_id) VALUES(case_id,p_expected_recommendation,p_expected_reason_code,p_criterion_version,actor);
  result:=jsonb_build_object('id',case_id,'test_case_id',p_test_case_id,'environment_id',env,'station_id',station,'driver_profile_id',p_driver_profile_id,'status','pending');
  INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,command_id,event_type,entity_type,entity_id,metadata) VALUES(env,actor,station,cmd,'dori.simulation.created','dori_simulation_case',case_id,jsonb_build_object('test_case_id',p_test_case_id));
  UPDATE public.command_log SET status='completed',result_payload=result WHERE id=cmd; RETURN result;
END; $function$;

CREATE OR REPLACE FUNCTION public.driver_get_dori_simulation_case(p_auth_user_id uuid, p_case_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public','app','auth','pg_temp' AS $function$
DECLARE s record; c record;
BEGIN
  SELECT * INTO STRICT s FROM app.dori_driver_scope(p_auth_user_id);
  SELECT * INTO c FROM public.dori_copilot_simulation_cases WHERE id=p_case_id AND driver_profile_id=s.driver_profile_id AND station_id=s.station_id AND environment_id=s.environment_id FOR UPDATE;
  IF NOT FOUND OR c.status<>'pending' OR c.expires_at<=app.env_now(c.environment_id) THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('id',c.id,'test_case_id',c.test_case_id,'input_payload',c.input_payload,'expires_at',c.expires_at,'contract_version',c.contract_version);
END; $function$;

CREATE OR REPLACE FUNCTION public.driver_next_dori_simulation_case(p_auth_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public','app','auth','pg_temp' AS $function$
DECLARE s record; c record;
BEGIN
  SELECT * INTO STRICT s FROM app.dori_driver_scope(p_auth_user_id);
  UPDATE public.dori_copilot_simulation_cases SET status='expired'
    WHERE driver_profile_id=s.driver_profile_id AND station_id=s.station_id AND environment_id=s.environment_id
      AND status='pending' AND expires_at<=app.env_now(environment_id);
  SELECT * INTO c FROM public.dori_copilot_simulation_cases
    WHERE driver_profile_id=s.driver_profile_id AND station_id=s.station_id AND environment_id=s.environment_id
      AND status='pending' AND expires_at>app.env_now(environment_id)
    ORDER BY created_at, id LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('id',c.id,'test_case_id',c.test_case_id,'input_payload',c.input_payload,'expires_at',c.expires_at,'contract_version',c.contract_version);
END; $function$;

CREATE OR REPLACE FUNCTION public.record_dori_simulation_evaluation(p_auth_user_id uuid, p_case_id uuid, p_idempotency_key text, p_result_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public','app','auth','pg_temp' AS $function$
DECLARE s record; c public.dori_copilot_simulation_cases%ROWTYPE; e public.dori_copilot_simulation_expectations%ROWTYPE; actor uuid:=app.auth_profile_id(); existing public.dori_copilot_simulation_evaluations%ROWTYPE; eval_id uuid; cls text; actual text; matched boolean; result jsonb;
BEGIN
  SELECT * INTO STRICT s FROM app.dori_driver_scope(p_auth_user_id);
  SELECT * INTO STRICT c FROM public.dori_copilot_simulation_cases WHERE id=p_case_id AND driver_profile_id=s.driver_profile_id AND station_id=s.station_id AND environment_id=s.environment_id FOR UPDATE;
  IF c.status<>'pending' OR c.expires_at<=app.env_now(c.environment_id) THEN RAISE EXCEPTION 'simulation_expired' USING ERRCODE='22023'; END IF;
  SELECT * INTO STRICT e FROM public.dori_copilot_simulation_expectations WHERE case_id=c.id;
  actual:=p_result_payload->>'recommendation'; IF actual NOT IN ('RECOMENDADO','NO RECOMENDADO') OR p_result_payload->>'modelVersion' IS NULL THEN RAISE EXCEPTION 'invalid_server_result' USING ERRCODE='22023'; END IF;
  matched:=actual=e.expected_recommendation; cls:=CASE WHEN matched AND actual='RECOMENDADO' THEN 'correct_recommend' WHEN matched THEN 'correct_reject' WHEN actual='RECOMENDADO' THEN 'false_positive' ELSE 'false_negative' END;
  SELECT * INTO existing FROM public.dori_copilot_simulation_evaluations WHERE case_id=c.id AND idempotency_key=p_idempotency_key; IF FOUND THEN RETURN jsonb_build_object('id',existing.id,'test_case_id',c.test_case_id,'actual',existing.actual_recommendation,'match',existing.matches_expected,'classification',existing.classification,'result',existing.result_payload); END IF;
  IF EXISTS (SELECT 1 FROM public.dori_copilot_simulation_evaluations other WHERE other.idempotency_key=p_idempotency_key AND other.case_id<>c.id) THEN RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE='23505'; END IF;
  INSERT INTO public.dori_copilot_simulation_evaluations(case_id,environment_id,station_id,driver_profile_id,evaluated_by_profile_id,actual_recommendation,matches_expected,classification,has_operational_block,result_payload,model_version,rules_version,parameter_version,idempotency_key) VALUES(c.id,c.environment_id,c.station_id,c.driver_profile_id,actor,actual,matched,cls,jsonb_array_length(COALESCE(p_result_payload->'operationalBlocks','[]'::jsonb))>0,p_result_payload,p_result_payload->>'modelVersion',p_result_payload->>'rulesVersion',p_result_payload->>'parameterVersion',p_idempotency_key) RETURNING id INTO eval_id;
  UPDATE public.dori_copilot_simulation_cases SET status='evaluated' WHERE id=c.id;
  INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,event_type,entity_type,entity_id,metadata) VALUES(c.environment_id,actor,c.station_id,'dori.simulation.evaluated','dori_simulation_evaluation',eval_id,jsonb_build_object('test_case_id',c.test_case_id,'classification',cls));
  result:=jsonb_build_object('id',eval_id,'test_case_id',c.test_case_id,'actual',actual,'match',matched,'classification',cls,'result',p_result_payload); RETURN result;
END; $function$;

REVOKE ALL ON FUNCTION public.console_create_dori_simulation_case(uuid,text,text,uuid,jsonb,text,text,text,timestamptz), public.driver_get_dori_simulation_case(uuid,uuid), public.driver_next_dori_simulation_case(uuid), public.record_dori_simulation_evaluation(uuid,uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.console_create_dori_simulation_case(uuid,text,text,uuid,jsonb,text,text,text,timestamptz), public.driver_get_dori_simulation_case(uuid,uuid), public.driver_next_dori_simulation_case(uuid), public.record_dori_simulation_evaluation(uuid,uuid,text,jsonb) TO service_role;
