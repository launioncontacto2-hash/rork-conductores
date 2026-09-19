-- DORI identity contract: administration and station-scoped console.

ALTER TABLE public.staff_memberships DROP CONSTRAINT IF EXISTS staff_memberships_role_check;
ALTER TABLE public.staff_memberships ADD CONSTRAINT staff_memberships_role_check CHECK (role = ANY (ARRAY['driver','supervisor','maintenance','management','direction','recruitment','hr','lab','administration','console']));

CREATE OR REPLACE FUNCTION app.auth_station_ids()
RETURNS SETOF uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp' AS $function$
DECLARE v_profile_id uuid; v_now timestamptz;
BEGIN
  v_profile_id := app.auth_profile_id(); IF v_profile_id IS NULL THEN RETURN; END IF;
  v_now := app.env_now();
  RETURN QUERY SELECT DISTINCT m.station_id FROM public.staff_memberships m JOIN public.stations s ON s.id=m.station_id
  WHERE m.profile_id=v_profile_id AND m.role <> 'administration' AND m.starts_at<=v_now AND (m.ends_at IS NULL OR m.ends_at>v_now)
    AND s.environment_id=app.current_environment_id() AND s.status='active';
END; $function$;

CREATE OR REPLACE FUNCTION app.auth_can_operate_station(p_station_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp' AS $function$
  SELECT app.auth_has_role('supervisor',p_station_id) OR app.auth_has_role('console',p_station_id)
$function$;

CREATE OR REPLACE VIEW public.console_identity WITH (security_invoker=true) AS
SELECT p.id AS profile_id,p.environment_id,p.display_name,p.employee_number,m.id AS membership_id,m.station_id,m.role,m.starts_at,m.ends_at,s.code AS station_code,s.name AS station_name,s.timezone AS station_timezone
FROM public.profiles p JOIN public.staff_memberships m ON m.profile_id=p.id AND m.environment_id=p.environment_id JOIN public.stations s ON s.id=m.station_id AND s.environment_id=m.environment_id
WHERE p.id=app.auth_profile_id() AND p.status='active' AND m.role IN ('supervisor','console') AND m.starts_at<=app.auth_env_now(m.environment_id) AND (m.ends_at IS NULL OR m.ends_at>app.auth_env_now(m.environment_id)) AND s.status='active';
REVOKE ALL ON TABLE public.console_identity FROM anon,authenticated;
GRANT SELECT ON TABLE public.console_identity TO authenticated;
GRANT ALL ON TABLE public.console_identity TO postgres,service_role;

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff_memberships' AND policyname='staff_memberships_console_driver_read') THEN
    CREATE POLICY staff_memberships_console_driver_read ON public.staff_memberships FOR SELECT TO authenticated USING (role='driver' AND app.auth_has_role('console',station_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='incidents' AND policyname='incidents_console_read') THEN CREATE POLICY incidents_console_read ON public.incidents FOR SELECT TO authenticated USING (app.auth_has_role('console',station_id)); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='work_orders' AND policyname='work_orders_console_read') THEN CREATE POLICY work_orders_console_read ON public.work_orders FOR SELECT TO authenticated USING (app.auth_has_role('console',station_id)); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='work_order_updates' AND policyname='work_order_updates_console_read') THEN CREATE POLICY work_order_updates_console_read ON public.work_order_updates FOR SELECT TO authenticated USING (app.auth_has_role('console',station_id)); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='absences' AND policyname='absences_console_read') THEN CREATE POLICY absences_console_read ON public.absences FOR SELECT TO authenticated USING (app.auth_has_role('console',station_id)); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='coverage_vacancies' AND policyname='coverage_vacancies_console_read') THEN CREATE POLICY coverage_vacancies_console_read ON public.coverage_vacancies FOR SELECT TO authenticated USING (app.auth_has_role('console',station_id)); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='coverage_claims' AND policyname='coverage_claims_console_read') THEN CREATE POLICY coverage_claims_console_read ON public.coverage_claims FOR SELECT TO authenticated USING (app.auth_has_role('console',station_id)); END IF;
END $do$;

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='shift_evidence' AND policyname='shift_evidence_console_read') THEN
    CREATE POLICY shift_evidence_console_read ON public.shift_evidence FOR SELECT TO authenticated USING (environment_id=app.current_environment_id() AND app.auth_has_role('console',station_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='shifts' AND policyname='shifts_console_read') THEN
    CREATE POLICY shifts_console_read ON public.shifts FOR SELECT TO authenticated USING (environment_id=app.current_environment_id() AND app.auth_has_role('console',station_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='shift_readings' AND policyname='shift_readings_console_read') THEN
    CREATE POLICY shift_readings_console_read ON public.shift_readings FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.shifts s WHERE s.id=shift_readings.shift_id AND s.environment_id=app.current_environment_id() AND app.auth_has_role('console',s.station_id)));
  END IF;
END $do$;

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='shift_evidence_console_select') THEN
    CREATE POLICY shift_evidence_console_select ON storage.objects FOR SELECT TO authenticated USING (bucket_id='shift-evidence' AND array_length(storage.foldername(name),1)>=4 AND (storage.foldername(name))[1]=app.current_environment_id()::text AND app.auth_has_role('console',(storage.foldername(name))[2]::uuid));
  END IF;
END $do$;

DO $do$
DECLARE d text;
BEGIN
  FOREACH d IN ARRAY ARRAY[pg_get_functiondef('public.assign_vehicle(uuid,uuid,text,text,uuid,text)'::regprocedure),pg_get_functiondef('public.update_incident(uuid,bigint,text,text,text)'::regprocedure),pg_get_functiondef('public.approve_guard(uuid,bigint,text,text)'::regprocedure),pg_get_functiondef('public.resolve_absence(uuid,bigint,text,text,text)'::regprocedure),pg_get_functiondef('public.revoke_driver_device(uuid,text,text)'::regprocedure)] LOOP
    d:=replace(d,'app.auth_has_role(''supervisor'', v_station)','app.auth_can_operate_station(v_station)');
    d:=replace(d,'app.auth_has_role(''supervisor'', v_driver.station_id)','app.auth_can_operate_station(v_driver.station_id)');
    d:=replace(d,'app.auth_has_role(''supervisor'', p_station_id)','app.auth_can_operate_station(p_station_id)');
    d:=replace(d,'app.auth_has_role(''supervisor'', v_incident.station_id)','app.auth_can_operate_station(v_incident.station_id)');
    d:=replace(d,'app.auth_has_role(''supervisor'', v_vacancy.station_id)','app.auth_can_operate_station(v_vacancy.station_id)');
    d:=replace(d,'app.auth_has_role(''supervisor'', v_absence.station_id)','app.auth_can_operate_station(v_absence.station_id)');
    d:=replace(d,'app.auth_has_role(''supervisor'', v_device.station_id)','app.auth_can_operate_station(v_device.station_id)');
    d:=replace(d,'app.auth_has_role(''supervisor'', v_station_id)','app.auth_can_operate_station(v_station_id)');
    EXECUTE d;
  END LOOP;
END $do$;

CREATE OR REPLACE FUNCTION public.console_audit_history(p_limit integer DEFAULT 100)
RETURNS TABLE (id uuid, station_id uuid, actor_profile_id uuid, actor_name text,
  actor_employee_number text, event_type text, entity_type text, entity_id uuid,
  metadata jsonb, occurred_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path TO 'pg_catalog','public','app','auth','pg_temp' AS $function$
DECLARE v_environment_id uuid; v_actor_profile_id uuid; v_limit integer;
BEGIN
  v_actor_profile_id := app.auth_profile_id();
  IF v_actor_profile_id IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  v_environment_id := app.current_environment_id();
  v_limit := least(greatest(coalesce(p_limit,100),1),200);
  IF NOT EXISTS (SELECT 1 FROM public.staff_memberships membership
    WHERE membership.profile_id=v_actor_profile_id AND membership.environment_id=v_environment_id
      AND membership.role IN ('supervisor','console')
      AND membership.starts_at<=app.env_now(v_environment_id)
      AND (membership.ends_at IS NULL OR membership.ends_at>app.env_now(v_environment_id)))
  THEN RAISE EXCEPTION 'console_or_supervisor_role_required' USING ERRCODE='42501'; END IF;
  RETURN QUERY SELECT event.id,event.station_id,event.actor_profile_id,
    coalesce(actor.display_name,'Sistema'),coalesce(actor.employee_number,'—'),event.event_type,
    event.entity_type,event.entity_id,event.metadata,event.occurred_at
  FROM public.audit_log event LEFT JOIN public.profiles actor ON actor.id=event.actor_profile_id
  WHERE event.environment_id=v_environment_id AND event.station_id IS NOT NULL
    AND app.auth_can_operate_station(event.station_id)
  ORDER BY event.occurred_at DESC,event.id DESC LIMIT v_limit;
END; $function$;
REVOKE ALL ON FUNCTION public.console_audit_history(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.console_audit_history(integer) TO authenticated,service_role;

DO $do$ DECLARE d text; BEGIN
  d:=pg_get_functiondef('app.update_test_clock_authorized(uuid,timestamptz,timestamptz,double precision,boolean,bigint)'::regprocedure);
  d:=replace(d,'IF NOT app.auth_has_role(''supervisor'') THEN','IF NOT (app.auth_has_role(''supervisor'') OR app.auth_has_role(''console'')) THEN');
  d:=replace(d,'supervisor_role_required_for_test_clock','console_or_supervisor_role_required_for_test_clock'); EXECUTE d;
END $do$;

CREATE OR REPLACE FUNCTION public.console_create_test_vehicle(p_color text DEFAULT NULL,p_note text DEFAULT NULL,p_idempotency_key text DEFAULT NULL)
RETURNS public.vehicles LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public','app','auth','pg_temp' AS $function$
DECLARE v_actor uuid:=app.auth_profile_id(); v_environment uuid:=app.current_environment_id(); v_station uuid; v_next integer; v_vehicle public.vehicles%ROWTYPE; v_existing public.command_log%ROWTYPE; v_payload jsonb; v_command uuid;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF v_environment IS NULL OR NOT EXISTS(SELECT 1 FROM public.environments WHERE id=v_environment AND code='test') THEN RAISE EXCEPTION 'test_environment_required' USING ERRCODE='42501'; END IF;
  SELECT m.station_id INTO STRICT v_station FROM public.staff_memberships m WHERE m.profile_id=v_actor AND m.environment_id=v_environment AND m.role IN ('supervisor','console') AND m.starts_at<=app.auth_env_now(v_environment) AND (m.ends_at IS NULL OR m.ends_at>app.auth_env_now(v_environment));
  IF NOT app.auth_can_operate_station(v_station) THEN RAISE EXCEPTION 'console_station_role_required' USING ERRCODE='42501'; END IF;
  IF p_idempotency_key IS NULL OR btrim(p_idempotency_key)='' THEN RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE='22023'; END IF;
  v_payload:=jsonb_build_object('color',NULLIF(btrim(coalesce(p_color,'')),''),'note',NULLIF(btrim(coalesce(p_note,'')),''));
  SELECT * INTO v_existing FROM public.command_log WHERE environment_id=v_environment AND idempotency_key=p_idempotency_key AND command_name='console_create_test_vehicle' LIMIT 1;
  IF FOUND THEN
    IF v_existing.request_payload IS DISTINCT FROM v_payload THEN RAISE EXCEPTION 'idempotency_payload_mismatch' USING ERRCODE='40001'; END IF;
    IF v_existing.status<>'completed' OR v_existing.result_payload->>'vehicle_id' IS NULL THEN RAISE EXCEPTION 'idempotency_incomplete' USING ERRCODE='40001'; END IF;
    SELECT * INTO v_vehicle FROM public.vehicles WHERE id=(v_existing.result_payload->>'vehicle_id')::uuid; RETURN v_vehicle;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_environment::text||':vehicle-number',0));
  SELECT coalesce(max(unit_number),0)+1 INTO v_next FROM public.vehicles WHERE environment_id=v_environment;
  INSERT INTO public.command_log(environment_id,actor_profile_id,command_name,idempotency_key,request_payload,status) VALUES(v_environment,v_actor,'console_create_test_vehicle',p_idempotency_key,v_payload,'accepted') RETURNING id INTO v_command;
  INSERT INTO public.vehicles(environment_id,station_id,internal_number,qr_code,legacy_code,model,manufacturer,model_display,unit_number,operational_code,color,status) VALUES(v_environment,v_station,'DMP-'||lpad(v_next::text,3,'0'),'DMP-'||lpad(v_next::text,3,'0'),'DMP-'||lpad(v_next::text,3,'0'),'Dolphin Mini Plus','BYD','Dolphin Mini P.',v_next,'DMP-'||lpad(v_next::text,3,'0'),NULLIF(btrim(p_color),''),'available') RETURNING * INTO v_vehicle;
  INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,command_id,event_type,entity_type,entity_id,metadata) VALUES(v_environment,v_actor,v_station,v_command,'vehicle.created','vehicle',v_vehicle.id,jsonb_build_object('unit_number',v_next,'operational_code',v_vehicle.operational_code,'note',NULLIF(btrim(coalesce(p_note,'')),'')));
  UPDATE public.command_log SET status='completed',result_payload=jsonb_build_object('vehicle_id',v_vehicle.id) WHERE id=v_command; RETURN v_vehicle;
END; $function$;
REVOKE ALL ON FUNCTION public.console_create_test_vehicle(text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.console_create_test_vehicle(text,text,text) TO authenticated,service_role;
COMMENT ON FUNCTION app.update_test_clock_authorized(uuid,timestamptz,timestamptz,double precision,boolean,bigint) IS 'Updates TEST clock for an authorized console or supervision identity.';
COMMENT ON FUNCTION public.console_create_test_vehicle(text,text,text) IS 'Creates the next available BYD Dolphin Mini P. unit only in TEST for an authorized console or supervisor identity; direct table writes remain denied.';
