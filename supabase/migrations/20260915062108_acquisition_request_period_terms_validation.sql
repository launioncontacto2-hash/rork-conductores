-- Request-owned commercial period, public limits and formal delivery terms.
-- Internal valuation remains isolated in acquisition_request_rules.

ALTER TABLE public.acquisition_requests
    ADD COLUMN fiscal_period date,
    ADD COLUMN maximum_unit_price_mxn numeric(12,2),
    ADD COLUMN minimum_soh numeric(5,2),
    ADD COLUMN soh_diagnosis_max_age_days integer,
    ADD COLUMN destination_station_name text,
    ADD COLUMN delivery_terms_document_path text;

UPDATE public.acquisition_requests
SET fiscal_period = date_trunc('month', created_at)::date,
    maximum_unit_price_mxn = COALESCE((
        SELECT rules.internal_price_limit_mxn
        FROM public.acquisition_request_rules rules
        WHERE rules.request_id = acquisition_requests.id
          AND rules.environment_id = acquisition_requests.environment_id
    ), 999999999),
    minimum_soh = COALESCE((
        SELECT rules.minimum_soh
        FROM public.acquisition_request_rules rules
        WHERE rules.request_id = acquisition_requests.id
          AND rules.environment_id = acquisition_requests.environment_id
    ), 90),
    soh_diagnosis_max_age_days = 30,
    destination_station_name = 'DORI ' || delivery_city;

ALTER TABLE public.acquisition_requests
    ALTER COLUMN fiscal_period SET NOT NULL,
    ALTER COLUMN fiscal_period SET DEFAULT date_trunc('month', CURRENT_DATE)::date,
    ALTER COLUMN maximum_unit_price_mxn SET NOT NULL,
    ALTER COLUMN maximum_unit_price_mxn SET DEFAULT 999999999,
    ALTER COLUMN minimum_soh SET NOT NULL,
    ALTER COLUMN minimum_soh SET DEFAULT 90,
    ALTER COLUMN soh_diagnosis_max_age_days SET NOT NULL,
    ALTER COLUMN soh_diagnosis_max_age_days SET DEFAULT 30,
    ALTER COLUMN destination_station_name SET NOT NULL,
    ALTER COLUMN destination_station_name SET DEFAULT 'DORI Puebla',
    ADD CONSTRAINT acquisition_requests_fiscal_period_first_day
        CHECK (fiscal_period = date_trunc('month', fiscal_period)::date),
    ADD CONSTRAINT acquisition_requests_public_price_positive
        CHECK (maximum_unit_price_mxn > 0),
    ADD CONSTRAINT acquisition_requests_public_soh_range
        CHECK (minimum_soh BETWEEN 0 AND 100),
    ADD CONSTRAINT acquisition_requests_soh_age_positive
        CHECK (soh_diagnosis_max_age_days > 0),
    ADD CONSTRAINT acquisition_requests_station_not_blank
        CHECK (btrim(destination_station_name) <> '');

ALTER TABLE public.acquisition_offers
    ADD COLUMN request_fiscal_period date,
    ADD COLUMN delivery_terms_accepted_at timestamptz,
    ADD COLUMN delivery_terms_accepted_by uuid,
    ADD COLUMN evidence_validation jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD CONSTRAINT acquisition_offers_terms_actor_fkey
        FOREIGN KEY (delivery_terms_accepted_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT;

UPDATE public.acquisition_offers offer
SET request_fiscal_period = request.fiscal_period
FROM public.acquisition_requests request
WHERE request.id = offer.request_id AND request.environment_id = offer.environment_id;

ALTER TABLE public.acquisition_offers
    ALTER COLUMN request_fiscal_period SET NOT NULL;

CREATE OR REPLACE FUNCTION app.populate_acquisition_offer_request_context()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
BEGIN
    IF NEW.request_fiscal_period IS NULL THEN
        SELECT request.fiscal_period INTO NEW.request_fiscal_period
        FROM public.acquisition_requests request
        WHERE request.id=NEW.request_id AND request.environment_id=NEW.environment_id;
    END IF;
    RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION app.populate_acquisition_offer_request_context() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.populate_acquisition_offer_request_context() TO postgres,service_role;
CREATE TRIGGER acquisition_offer_request_context
BEFORE INSERT ON public.acquisition_offers
FOR EACH ROW EXECUTE FUNCTION app.populate_acquisition_offer_request_context();

ALTER TABLE public.acquisition_evidence
    DROP CONSTRAINT acquisition_evidence_kind_check,
    ADD CONSTRAINT acquisition_evidence_kind_check CHECK (
        kind IN (
            'vin', 'dashboard', 'front', 'rear', 'left_side', 'right_side',
            'interior', 'charger', 'battery', 'document',
            'exterior_front', 'exterior_driver_side', 'exterior_passenger_side',
            'exterior_rear', 'interior_dashboard', 'steering_wheel', 'odometer',
            'driver_seat', 'passenger_seat', 'rear_seats', 'keys',
            'charger_110v', 'charger_220v', 'origin_invoice', 'soh_report',
            'front_compartment', 'trunk'
        )
    );

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'acquisition-request-documents', 'acquisition-request-documents', false,
    10485760, ARRAY['application/pdf', 'text/plain', 'application/octet-stream']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY acquisition_request_documents_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'acquisition-request-documents'
    AND array_length(storage.foldername(name), 1) = 3
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND (storage.foldername(name))[2] = app.auth_profile_id()::text
    AND app.auth_is_acquisition_admin()
);

CREATE POLICY acquisition_request_documents_select
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'acquisition-request-documents'
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND EXISTS (
        SELECT 1 FROM public.acquisition_requests request
        WHERE request.environment_id = app.current_environment_id()
          AND request.delivery_terms_document_path = name
    )
    AND (app.auth_is_acquisition_admin() OR app.auth_acquisition_supplier_id() IS NOT NULL)
);

DROP POLICY IF EXISTS acquisition_test_evidence_objects_delete ON storage.objects;
CREATE POLICY acquisition_test_evidence_objects_delete
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id IN ('acquisition-evidence', 'acquisition-chat-attachments', 'acquisition-request-documents')
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND app.auth_is_acquisition_admin()
    AND EXISTS (
        SELECT 1 FROM public.environments environment
        WHERE environment.id = app.current_environment_id() AND environment.code = 'test'
    )
);

CREATE OR REPLACE FUNCTION public.publish_acquisition_request_v2(
    p_model text, p_versions text[], p_target_quantity integer,
    p_minimum_year integer, p_maximum_year integer, p_maximum_mileage integer,
    p_maximum_unit_price_mxn numeric, p_delivery_city text,
    p_destination_station_name text, p_fiscal_period date, p_minimum_soh numeric,
    p_soh_diagnosis_max_age_days integer, p_delivery_terms_document_path text,
    p_deadline_at timestamptz, p_target_delivery_date date,
    p_requirements jsonb, p_idempotency_key text
)
RETURNS public.acquisition_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_actor_profile_id uuid := app.auth_profile_id();
    v_now timestamptz := app.env_now(v_environment_id);
    v_payload jsonb;
    v_command public.command_log%ROWTYPE;
    v_result public.acquisition_requests%ROWTYPE;
    v_code text;
    v_item jsonb;
BEGIN
    IF NOT app.auth_is_acquisition_admin() THEN
        RAISE EXCEPTION 'dori_acquisition_admin_required' USING ERRCODE = '42501';
    END IF;
    IF btrim(COALESCE(p_model, '')) = '' OR p_target_quantity <= 0
       OR p_minimum_year NOT BETWEEN 2000 AND 2100 OR p_maximum_year < p_minimum_year
       OR p_maximum_mileage < 0 OR p_maximum_unit_price_mxn <= 0
       OR btrim(COALESCE(p_delivery_city, '')) = ''
       OR btrim(COALESCE(p_destination_station_name, '')) = ''
       OR p_minimum_soh NOT BETWEEN 0 AND 100 OR p_soh_diagnosis_max_age_days <= 0
       OR p_fiscal_period IS NULL
       OR p_fiscal_period <> date_trunc('month', p_fiscal_period)::date THEN
        RAISE EXCEPTION 'invalid_acquisition_request_fields' USING ERRCODE = '22023';
    END IF;
    IF p_deadline_at IS NULL OR p_deadline_at <= v_now THEN
        RAISE EXCEPTION 'acquisition_request_deadline_must_be_future' USING ERRCODE = '22023';
    END IF;
    IF p_target_delivery_date IS NULL OR p_target_delivery_date < p_deadline_at::date THEN
        RAISE EXCEPTION 'acquisition_target_delivery_date_invalid' USING ERRCODE = '22023';
    END IF;
    IF jsonb_typeof(p_requirements) <> 'array' OR jsonb_array_length(p_requirements) = 0 THEN
        RAISE EXCEPTION 'acquisition_request_requirements_required' USING ERRCODE = '22023';
    END IF;
    IF btrim(COALESCE(p_delivery_terms_document_path, '')) = '' OR
       p_delivery_terms_document_path NOT LIKE v_environment_id::text || '/' || v_actor_profile_id::text || '/%' OR
       NOT EXISTS (
           SELECT 1 FROM storage.objects object
           WHERE object.bucket_id = 'acquisition-request-documents'
             AND object.name = p_delivery_terms_document_path
             AND object.owner_id = auth.uid()::text
       ) THEN
        RAISE EXCEPTION 'invalid_or_unowned_delivery_terms_document' USING ERRCODE = '42501';
    END IF;
    FOR v_item IN SELECT value FROM jsonb_array_elements(p_requirements) LOOP
        IF btrim(COALESCE(v_item->>'code', '')) = ''
           OR btrim(COALESCE(v_item->>'title', '')) = ''
           OR btrim(COALESCE(v_item->>'value', '')) = ''
           OR COALESCE(v_item->>'category', '') NOT IN ('specification','documentation','condition','evidence')
           OR COALESCE(v_item->>'response_type', 'confirmation') NOT IN ('confirmation','text','number','date','document','photo') THEN
            RAISE EXCEPTION 'invalid_acquisition_request_requirement' USING ERRCODE = '22023';
        END IF;
    END LOOP;
    v_payload := jsonb_build_object(
        'model', btrim(p_model), 'versions', COALESCE(to_jsonb(p_versions), '[]'::jsonb),
        'target_quantity', p_target_quantity, 'minimum_year', p_minimum_year,
        'maximum_year', p_maximum_year, 'maximum_mileage', p_maximum_mileage,
        'maximum_unit_price_mxn', p_maximum_unit_price_mxn,
        'delivery_city', btrim(p_delivery_city), 'destination_station_name', btrim(p_destination_station_name),
        'fiscal_period', p_fiscal_period, 'minimum_soh', p_minimum_soh,
        'soh_diagnosis_max_age_days', p_soh_diagnosis_max_age_days,
        'delivery_terms_document_path', p_delivery_terms_document_path,
        'deadline_at', p_deadline_at, 'target_delivery_date', p_target_delivery_date,
        'requirements', p_requirements
    );
    v_command := app.begin_acquisition_command('publish_acquisition_request_v2', p_idempotency_key, v_payload);
    IF v_command.result_payload IS NOT NULL THEN
        SELECT * INTO STRICT v_result FROM public.acquisition_requests
        WHERE id = (v_command.result_payload->>'request_id')::uuid;
        RETURN v_result;
    END IF;
    v_code := 'ADQ-' || to_char(v_now, 'YYYYMMDD') || '-' || upper(substr(replace(extensions.gen_random_uuid()::text, '-', ''), 1, 6));
    INSERT INTO public.acquisition_requests(
        environment_id, code, title, target_quantity, model, versions,
        minimum_year, maximum_year, maximum_mileage, maximum_unit_price_mxn,
        delivery_city, destination_station_name, deadline_at, target_delivery_date,
        fiscal_period, minimum_soh, soh_diagnosis_max_age_days,
        delivery_terms_document_path, status, created_by, created_at, updated_at
    ) VALUES (
        v_environment_id, v_code, p_target_quantity::text || ' vehículos requeridos',
        p_target_quantity, btrim(p_model), COALESCE(p_versions, '{}'), p_minimum_year,
        p_maximum_year, p_maximum_mileage, p_maximum_unit_price_mxn,
        btrim(p_delivery_city), btrim(p_destination_station_name), p_deadline_at,
        p_target_delivery_date, p_fiscal_period, p_minimum_soh,
        p_soh_diagnosis_max_age_days, p_delivery_terms_document_path,
        'published', v_actor_profile_id, v_now, v_now
    ) RETURNING * INTO v_result;
    INSERT INTO public.acquisition_request_rules(
        request_id, environment_id, target_soh, minimum_soh, internal_price_limit_mxn, created_at
    ) VALUES (v_result.id, v_environment_id, p_minimum_soh, p_minimum_soh, NULL, v_now);
    INSERT INTO public.acquisition_request_requirements(
        environment_id, request_id, code, category, title, value, required,
        display_order, response_type, requires_dori_verification, metadata, created_at
    ) SELECT v_environment_id, v_result.id, btrim(item->>'code'), item->>'category',
        btrim(item->>'title'), btrim(item->>'value'), COALESCE((item->>'required')::boolean, true),
        COALESCE((item->>'display_order')::integer, ordinal::integer),
        COALESCE(item->>'response_type', 'confirmation'),
        COALESCE((item->>'requires_dori_verification')::boolean, false),
        COALESCE(item->'metadata', '{}'::jsonb), v_now
    FROM jsonb_array_elements(p_requirements) WITH ORDINALITY AS requirement(item, ordinal);
    PERFORM app.finish_acquisition_command(
        v_command.id, jsonb_build_object('request_id', v_result.id),
        'acquisition.request.published', 'acquisition_request', v_result.id,
        jsonb_build_object('fiscal_period', p_fiscal_period, 'target_delivery_date', p_target_delivery_date)
    );
    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.publish_acquisition_request_v2(
    text,text[],integer,integer,integer,integer,numeric,text,text,date,numeric,integer,text,timestamptz,date,jsonb,text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.publish_acquisition_request_v2(
    text,text[],integer,integer,integer,integer,numeric,text,text,date,numeric,integer,text,timestamptz,date,jsonb,text
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.submit_acquisition_offer_v2(
    p_offer_id uuid, p_request_id uuid, p_vin text, p_model text,
    p_version text, p_year integer, p_mileage integer, p_declared_soh numeric,
    p_color text, p_price_mxn numeric, p_transfer_included boolean,
    p_delivery_terms_accepted boolean, p_validation_results jsonb,
    p_evidence jsonb, p_idempotency_key text
)
RETURNS public.acquisition_offers
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_actor_profile_id uuid := app.auth_profile_id();
    v_supplier_id uuid := app.auth_acquisition_supplier_id();
    v_now timestamptz := app.env_now(v_environment_id);
    v_request_row public.acquisition_requests%ROWTYPE;
    v_rules public.acquisition_request_rules%ROWTYPE;
    v_request jsonb; v_command public.command_log%ROWTYPE;
    v_result public.acquisition_offers%ROWTYPE;
    v_item jsonb; v_kind text; v_path text;
    v_recommendation text; v_risk text; v_summary text;
BEGIN
    IF v_supplier_id IS NULL THEN RAISE EXCEPTION 'active_acquisition_provider_required' USING ERRCODE='42501'; END IF;
    IF p_offer_id IS NULL THEN RAISE EXCEPTION 'offer_id_required' USING ERRCODE='22023'; END IF;
    SELECT request.* INTO v_request_row FROM public.acquisition_requests request
    WHERE request.id=p_request_id AND request.environment_id=v_environment_id
      AND request.status IN ('published','evaluating','partially_awarded') FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'active_acquisition_request_not_found' USING ERRCODE='P0002'; END IF;
    IF v_request_row.deadline_at IS NOT NULL AND v_now > v_request_row.deadline_at THEN
        RAISE EXCEPTION 'acquisition_request_offer_deadline_passed' USING ERRCODE='55000';
    END IF;
    IF NOT p_delivery_terms_accepted THEN RAISE EXCEPTION 'delivery_terms_acceptance_required' USING ERRCODE='22023'; END IF;
    IF NOT p_transfer_included THEN RAISE EXCEPTION 'destination_station_delivery_required' USING ERRCODE='22023'; END IF;
    IF p_year < v_request_row.minimum_year OR p_year > v_request_row.maximum_year THEN
        RAISE EXCEPTION 'offered_year_outside_request' USING ERRCODE='23514';
    END IF;
    IF p_mileage > v_request_row.maximum_mileage THEN RAISE EXCEPTION 'offered_mileage_exceeds_request' USING ERRCODE='23514'; END IF;
    IF p_price_mxn > v_request_row.maximum_unit_price_mxn THEN RAISE EXCEPTION 'offered_price_exceeds_request' USING ERRCODE='23514'; END IF;
    IF p_declared_soh IS NULL OR p_declared_soh < v_request_row.minimum_soh THEN RAISE EXCEPTION 'offered_soh_below_request' USING ERRCODE='23514'; END IF;
    IF COALESCE(p_validation_results->>'odometer','pending') NOT IN ('match','manual_review')
       OR COALESCE(p_validation_results->>'vin','pending') NOT IN ('match','manual_review') THEN
        RAISE EXCEPTION 'evidence_automatic_validation_required' USING ERRCODE='23514';
    END IF;
    IF jsonb_typeof(p_evidence)<>'array' OR jsonb_array_length(p_evidence)<3 THEN
        RAISE EXCEPTION 'at_least_three_evidence_items_required' USING ERRCODE='22023';
    END IF;
    SELECT * INTO STRICT v_rules FROM public.acquisition_request_rules
    WHERE request_id=p_request_id AND environment_id=v_environment_id;
    v_request := jsonb_build_object(
        'offer_id',p_offer_id,'request_id',p_request_id,'vin',upper(btrim(p_vin)),
        'model',btrim(p_model),'version',NULLIF(btrim(p_version),''),'year',p_year,
        'mileage',p_mileage,'declared_soh',p_declared_soh,'color',NULLIF(btrim(p_color),''),
        'price_mxn',p_price_mxn,'transfer_included',p_transfer_included,
        'delivery_terms_accepted',p_delivery_terms_accepted,'validation_results',p_validation_results,
        'evidence',p_evidence
    );
    v_command := app.begin_acquisition_command('submit_acquisition_offer_v2',p_idempotency_key,v_request);
    IF v_command.result_payload IS NOT NULL THEN
        SELECT * INTO STRICT v_result FROM public.acquisition_offers
        WHERE id=(v_command.result_payload->>'offer_id')::uuid; RETURN v_result;
    END IF;
    FOR v_item IN SELECT value FROM jsonb_array_elements(p_evidence) LOOP
        v_kind:=v_item->>'kind'; v_path:=v_item->>'path';
        IF v_kind NOT IN (
            'vin','dashboard','front','rear','left_side','right_side','interior','charger','battery','document',
            'exterior_front','exterior_driver_side','exterior_passenger_side','exterior_rear','interior_dashboard',
            'steering_wheel','odometer','driver_seat','passenger_seat','rear_seats','keys','charger_110v',
            'charger_220v','origin_invoice','soh_report','front_compartment','trunk'
        ) OR v_path IS NULL
          OR v_path NOT LIKE v_environment_id::text||'/'||v_supplier_id::text||'/'||p_offer_id::text||'/%'
          OR NOT EXISTS (SELECT 1 FROM storage.objects object WHERE object.bucket_id='acquisition-evidence'
              AND object.name=v_path AND object.owner_id=auth.uid()::text) THEN
            RAISE EXCEPTION 'invalid_or_unowned_acquisition_evidence' USING ERRCODE='42501';
        END IF;
    END LOOP;
    INSERT INTO public.acquisition_offers(
        id,environment_id,request_id,supplier_id,created_by,vin,model,version,year,mileage,
        declared_soh,color,price_mxn,transfer_included,agreed_price_mxn,status,committed_delivery_date,
        request_fiscal_period,delivery_terms_accepted_at,delivery_terms_accepted_by,evidence_validation,
        submitted_at,updated_at
    ) VALUES (
        p_offer_id,v_environment_id,p_request_id,v_supplier_id,v_actor_profile_id,upper(btrim(p_vin)),
        btrim(p_model),NULLIF(btrim(p_version),''),p_year,p_mileage,p_declared_soh,NULLIF(btrim(p_color),''),
        p_price_mxn,p_transfer_included,NULL,'submitted',v_request_row.target_delivery_date,
        v_request_row.fiscal_period,v_now,v_actor_profile_id,p_validation_results,v_now,v_now
    ) RETURNING * INTO v_result;
    INSERT INTO public.acquisition_evidence(environment_id,offer_id,kind,object_path,uploaded_by,created_at)
    SELECT v_environment_id,p_offer_id,item->>'kind',item->>'path',v_actor_profile_id,v_now
    FROM jsonb_array_elements(p_evidence) item;
    IF v_rules.internal_price_limit_mxn IS NULL THEN
        v_recommendation:='wait_for_information'; v_risk:='medium';
        v_summary:='DORI debe completar la valuación interna antes de decidir.';
    ELSIF p_price_mxn<=v_rules.internal_price_limit_mxn THEN
        v_recommendation:='buy'; v_risk:='low'; v_summary:='La unidad cumple los parámetros principales.';
    ELSIF p_price_mxn<=v_rules.internal_price_limit_mxn*1.05 THEN
        v_recommendation:='negotiate'; v_risk:='medium'; v_summary:='La unidad es viable si se ajusta el precio.';
    ELSE v_recommendation:='review'; v_risk:='medium'; v_summary:='El precio requiere revisión adicional.'; END IF;
    INSERT INTO public.acquisition_offer_assessments(
        offer_id,environment_id,estimated_value_mxn,maximum_recommended_mxn,risk,recommendation,
        evidence_status,summary,calculated_at
    ) VALUES (p_offer_id,v_environment_id,v_rules.internal_price_limit_mxn,v_rules.internal_price_limit_mxn,
        v_risk,v_recommendation,'complete',v_summary,v_now);
    UPDATE public.acquisition_requests SET status='evaluating',revision=revision+1,updated_at=v_now
    WHERE id=p_request_id AND status='published';
    PERFORM app.finish_acquisition_command(v_command.id,jsonb_build_object('offer_id',v_result.id),
        'acquisition.offer.submitted','acquisition_offer',v_result.id,
        jsonb_build_object('request_id',p_request_id,'supplier_id',v_supplier_id,'fiscal_period',v_request_row.fiscal_period));
    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_acquisition_offer_v2(
    uuid,uuid,text,text,text,integer,integer,numeric,text,numeric,boolean,boolean,jsonb,jsonb,text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_acquisition_offer_v2(
    uuid,uuid,text,text,text,integer,integer,numeric,text,numeric,boolean,boolean,jsonb,jsonb,text
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.plan_test_acquisition_environment_reset(p_confirmation text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE v_environment_id uuid:=app.current_environment_id(); v_environment_code text; v_objects jsonb; v_counts jsonb;
BEGIN
    IF NOT app.auth_is_acquisition_admin() OR p_confirmation<>'LIMPIAR TEST' THEN
        RAISE EXCEPTION 'test_environment_reset_denied' USING ERRCODE='42501'; END IF;
    SELECT code INTO v_environment_code FROM public.environments WHERE id=v_environment_id;
    IF v_environment_code IS DISTINCT FROM 'test' THEN RAISE EXCEPTION 'test_environment_required' USING ERRCODE='42501'; END IF;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('bucket',object.bucket_id,'path',object.name)
        ORDER BY object.bucket_id,object.name),'[]'::jsonb) INTO v_objects
    FROM storage.objects object
    WHERE object.bucket_id IN ('acquisition-evidence','acquisition-chat-attachments','acquisition-request-documents')
      AND (storage.foldername(object.name))[1]=v_environment_id::text;
    SELECT jsonb_build_object(
        'requests',(SELECT count(*) FROM public.acquisition_requests WHERE environment_id=v_environment_id),
        'request_rules',(SELECT count(*) FROM public.acquisition_request_rules WHERE environment_id=v_environment_id),
        'request_requirements',(SELECT count(*) FROM public.acquisition_request_requirements WHERE environment_id=v_environment_id),
        'offers',(SELECT count(*) FROM public.acquisition_offers WHERE environment_id=v_environment_id),
        'evidence',(SELECT count(*) FROM public.acquisition_evidence WHERE environment_id=v_environment_id),
        'assessments',(SELECT count(*) FROM public.acquisition_offer_assessments WHERE environment_id=v_environment_id),
        'negotiations',(SELECT count(*) FROM public.acquisition_negotiations WHERE environment_id=v_environment_id),
        'orders',(SELECT count(*) FROM public.acquisition_orders WHERE environment_id=v_environment_id),
        'deliveries',(SELECT count(*) FROM public.acquisition_deliveries WHERE environment_id=v_environment_id),
        'receptions',(SELECT count(*) FROM public.acquisition_receptions WHERE environment_id=v_environment_id),
        'holds',(SELECT count(*) FROM public.acquisition_holds WHERE environment_id=v_environment_id),
        'delivery_commitments',(SELECT count(*) FROM public.acquisition_delivery_commitment_history WHERE environment_id=v_environment_id),
        'threads',(SELECT count(*) FROM public.acquisition_chat_threads WHERE environment_id=v_environment_id),
        'messages',(SELECT count(*) FROM public.acquisition_chat_messages WHERE environment_id=v_environment_id),
        'read_receipts',(SELECT count(*) FROM public.acquisition_chat_read_receipts WHERE environment_id=v_environment_id),
        'notifications',(SELECT count(*) FROM public.acquisition_notifications WHERE environment_id=v_environment_id),
        'storage_objects',jsonb_array_length(v_objects)) INTO v_counts;
    RETURN jsonb_build_object('environment_id',v_environment_id,'counts',v_counts,'storage_objects',v_objects);
END;
$function$;

REVOKE ALL ON FUNCTION public.plan_test_acquisition_environment_reset(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.plan_test_acquisition_environment_reset(text) TO authenticated, service_role;



