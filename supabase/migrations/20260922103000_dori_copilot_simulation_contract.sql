-- Corrective contract: expose status and result_payload-compatible transport for iOS TEST.
CREATE OR REPLACE FUNCTION public.driver_get_dori_simulation_case(p_auth_user_id uuid, p_case_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public','app','auth','pg_temp' AS $function$
DECLARE s record; c record;
BEGIN
  SELECT * INTO STRICT s FROM app.dori_driver_scope(p_auth_user_id);
  SELECT * INTO c FROM public.dori_copilot_simulation_cases WHERE id=p_case_id AND driver_profile_id=s.driver_profile_id AND station_id=s.station_id AND environment_id=s.environment_id FOR UPDATE;
  IF NOT FOUND OR c.status<>'pending' OR c.expires_at<=app.env_now(c.environment_id) THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('id',c.id,'test_case_id',c.test_case_id,'status',c.status,'input_payload',c.input_payload,'expires_at',c.expires_at,'contract_version',c.contract_version);
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
  RETURN jsonb_build_object('id',c.id,'test_case_id',c.test_case_id,'status',c.status,'input_payload',c.input_payload,'expires_at',c.expires_at,'contract_version',c.contract_version);
END; $function$;

CREATE OR REPLACE FUNCTION public.driver_get_dori_simulation_evaluation(p_auth_user_id uuid, p_case_id uuid, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public','app','auth','pg_temp' AS $function$
DECLARE s record; result jsonb;
BEGIN
 SELECT * INTO STRICT s FROM app.dori_driver_scope(p_auth_user_id);
 SELECT jsonb_build_object('id',e.id,'test_case_id',c.test_case_id,'actual',e.actual_recommendation,'match',e.matches_expected,'classification',e.classification,'result',e.result_payload) INTO result FROM public.dori_copilot_simulation_evaluations e JOIN public.dori_copilot_simulation_cases c ON c.id=e.case_id WHERE e.case_id=p_case_id AND e.idempotency_key=p_idempotency_key AND e.driver_profile_id=s.driver_profile_id AND e.environment_id=s.environment_id AND e.station_id=s.station_id AND c.driver_profile_id=s.driver_profile_id AND c.environment_id=s.environment_id AND c.station_id=s.station_id;
 RETURN result;
END; $function$;

CREATE OR REPLACE FUNCTION public.record_dori_simulation_evaluation(p_auth_user_id uuid, p_case_id uuid, p_idempotency_key text, p_result_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public','app','auth','pg_temp' AS $function$
DECLARE s record; c public.dori_copilot_simulation_cases%ROWTYPE; e public.dori_copilot_simulation_expectations%ROWTYPE; actor uuid; existing public.dori_copilot_simulation_evaluations%ROWTYPE; eval_id uuid; cls text; actual text; matched boolean; result jsonb;
BEGIN
  SELECT * INTO STRICT s FROM app.dori_driver_scope(p_auth_user_id);
  actor:=s.profile_id;
  SELECT * INTO STRICT c FROM public.dori_copilot_simulation_cases WHERE id=p_case_id AND driver_profile_id=s.driver_profile_id AND station_id=s.station_id AND environment_id=s.environment_id FOR UPDATE;
  SELECT * INTO STRICT e FROM public.dori_copilot_simulation_expectations WHERE case_id=c.id;
  actual:=p_result_payload->>'recommendation'; IF actual NOT IN ('RECOMENDADO','NO RECOMENDADO') OR p_result_payload->>'modelVersion' IS NULL THEN RAISE EXCEPTION 'invalid_server_result' USING ERRCODE='22023'; END IF;
  matched:=actual=e.expected_recommendation; cls:=CASE WHEN matched AND actual='RECOMENDADO' THEN 'correct_recommend' WHEN matched THEN 'correct_reject' WHEN actual='RECOMENDADO' THEN 'false_positive' ELSE 'false_negative' END;
  SELECT * INTO existing FROM public.dori_copilot_simulation_evaluations WHERE case_id=c.id AND idempotency_key=p_idempotency_key; IF FOUND THEN RETURN jsonb_build_object('id',existing.id,'test_case_id',c.test_case_id,'actual',existing.actual_recommendation,'match',existing.matches_expected,'classification',existing.classification,'result',existing.result_payload); END IF;
  IF c.status<>'pending' OR c.expires_at<=app.env_now(c.environment_id) THEN RAISE EXCEPTION 'simulation_expired' USING ERRCODE='22023'; END IF;
  IF EXISTS (SELECT 1 FROM public.dori_copilot_simulation_evaluations other WHERE other.idempotency_key=p_idempotency_key AND other.case_id<>c.id) THEN RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE='23505'; END IF;
  INSERT INTO public.dori_copilot_simulation_evaluations(case_id,environment_id,station_id,driver_profile_id,evaluated_by_profile_id,actual_recommendation,matches_expected,classification,has_operational_block,result_payload,model_version,rules_version,parameter_version,idempotency_key) VALUES(c.id,c.environment_id,c.station_id,c.driver_profile_id,actor,actual,matched,cls,jsonb_array_length(COALESCE(p_result_payload->'operationalBlocks','[]'::jsonb))>0,p_result_payload,p_result_payload->>'modelVersion',p_result_payload->>'rulesVersion',p_result_payload->>'parameterVersion',p_idempotency_key) RETURNING id INTO eval_id;
  UPDATE public.dori_copilot_simulation_cases SET status='evaluated' WHERE id=c.id;
  INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,event_type,entity_type,entity_id,metadata) VALUES(c.environment_id,actor,c.station_id,'dori.simulation.evaluated','dori_simulation_evaluation',eval_id,jsonb_build_object('test_case_id',c.test_case_id,'classification',cls));
  result:=jsonb_build_object('id',eval_id,'test_case_id',c.test_case_id,'actual',actual,'match',matched,'classification',cls,'result',p_result_payload); RETURN result;
END; $function$;

