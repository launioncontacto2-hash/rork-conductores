CREATE TABLE public.acquisition_arrival_inspections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    order_id uuid NOT NULL,
    inspected_by uuid NOT NULL,
    checks jsonb NOT NULL,
    evidence_paths jsonb NOT NULL,
    status text NOT NULL DEFAULT 'completed',
    completed_at timestamptz NOT NULL,
    CONSTRAINT acquisition_arrival_order_environment_fkey
        FOREIGN KEY (order_id, environment_id)
        REFERENCES public.acquisition_orders(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_arrival_inspector_environment_fkey
        FOREIGN KEY (inspected_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_arrival_order_unique UNIQUE (order_id, environment_id),
    CONSTRAINT acquisition_arrival_status_check CHECK (status = 'completed'),
    CONSTRAINT acquisition_arrival_checks_object CHECK (jsonb_typeof(checks) = 'object'),
    CONSTRAINT acquisition_arrival_evidence_object CHECK (jsonb_typeof(evidence_paths) = 'object')
);

ALTER TABLE public.acquisition_arrival_inspections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.acquisition_arrival_inspections FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.acquisition_arrival_inspections TO authenticated;
GRANT ALL ON TABLE public.acquisition_arrival_inspections TO postgres, service_role;

CREATE POLICY acquisition_arrival_inspections_read
ON public.acquisition_arrival_inspections
FOR SELECT TO authenticated
USING (
    environment_id = app.current_environment_id()
    AND EXISTS (
        SELECT 1
        FROM public.acquisition_orders acquisition_order
        WHERE acquisition_order.id = acquisition_arrival_inspections.order_id
          AND acquisition_order.environment_id = acquisition_arrival_inspections.environment_id
          AND (
              app.auth_is_acquisition_admin()
              OR acquisition_order.supplier_id = app.auth_acquisition_supplier_id()
          )
    )
);

CREATE POLICY acquisition_arrival_evidence_admin_insert
ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'acquisition-evidence'
    AND app.auth_is_acquisition_admin()
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND (storage.foldername(name))[4] = 'arrivals'
);

CREATE OR REPLACE FUNCTION public.complete_acquisition_arrival(
    p_order_id uuid,
    p_checks jsonb,
    p_evidence_paths jsonb,
    p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_profile_id uuid := app.auth_profile_id();
    v_order public.acquisition_orders%ROWTYPE;
    v_required text[] := ARRAY[
        'vin','origin_invoice','reinvoice','soh','keys','charger_110v',
        'charger_220v','plates','registration','manufacturer_warranty','used_warranty'
    ];
    v_key text;
    v_path text;
    v_result jsonb;
BEGIN
    IF NOT app.auth_is_acquisition_admin() THEN
        RAISE EXCEPTION 'dori_arrival_admin_required' USING ERRCODE = '42501';
    END IF;
    SELECT acquisition_order.* INTO v_order
    FROM public.acquisition_orders acquisition_order
    WHERE acquisition_order.id = p_order_id
      AND acquisition_order.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'acquisition_order_not_found' USING ERRCODE = 'P0002'; END IF;
    IF v_order.status <> 'ready_for_delivery' THEN
        RAISE EXCEPTION 'arrival_order_not_ready' USING ERRCODE = '55000';
    END IF;
    IF jsonb_typeof(p_checks) <> 'object' OR jsonb_typeof(p_evidence_paths) <> 'object' THEN
        RAISE EXCEPTION 'arrival_payload_invalid' USING ERRCODE = '22023';
    END IF;
    FOREACH v_key IN ARRAY v_required LOOP
        IF COALESCE((p_checks->>v_key)::boolean, false) IS NOT TRUE THEN
            RAISE EXCEPTION 'arrival_check_required:%', v_key USING ERRCODE = '22023';
        END IF;
        v_path := p_evidence_paths->>v_key;
        IF v_path IS NULL OR v_path NOT LIKE v_environment_id::text || '/' || v_order.supplier_id::text || '/' || v_order.offer_id::text || '/arrivals/%' THEN
            RAISE EXCEPTION 'arrival_evidence_path_invalid:%', v_key USING ERRCODE = '42501';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM storage.objects object
            WHERE object.bucket_id = 'acquisition-evidence' AND object.name = v_path
        ) THEN
            RAISE EXCEPTION 'arrival_evidence_missing:%', v_key USING ERRCODE = 'P0002';
        END IF;
    END LOOP;

    INSERT INTO public.acquisition_arrival_inspections(
        environment_id, order_id, inspected_by, checks, evidence_paths, completed_at
    ) VALUES (
        v_environment_id, p_order_id, v_profile_id, p_checks, p_evidence_paths,
        app.env_now(v_environment_id)
    );

    v_result := public.complete_acquisition_delivery(
        p_order_id,
        'receive',
        jsonb_build_object(
            'vin_correct', true, 'mileage_correct', true,
            'chargers_complete', true, 'keys_complete', true, 'new_damage', false
        ),
        NULL,
        'Inspección de 11 requisitos completada',
        0,
        p_idempotency_key || '.receive'
    );
    RETURN v_result || jsonb_build_object('inspection_status', 'completed');
END;
$function$;

REVOKE ALL ON FUNCTION public.complete_acquisition_arrival(uuid, jsonb, jsonb, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_acquisition_arrival(uuid, jsonb, jsonb, text)
TO authenticated, service_role;

COMMENT ON TABLE public.acquisition_arrival_inspections IS
'Snapshot autoritativo de los 11 requisitos revisados durante la llegada física de una unidad.';
