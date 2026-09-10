-- Keep the existing RPC signature while making the server-calculated reception
-- result authoritative. Clients pass NULL for p_result; legacy callers may send
-- the same value, but a conflicting value is rejected.
CREATE OR REPLACE FUNCTION public.complete_acquisition_delivery(
    p_order_id uuid,
    p_action text,
    p_checklist jsonb,
    p_result text,
    p_note text,
    p_hold_amount_mxn numeric,
    p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_actor_profile_id uuid := app.auth_profile_id();
    v_role text := app.auth_acquisition_role();
    v_supplier_id uuid := app.auth_acquisition_supplier_id();
    v_now timestamptz := app.env_now(v_environment_id);
    v_order public.acquisition_orders%ROWTYPE;
    v_delivery public.acquisition_deliveries%ROWTYPE;
    v_offer public.acquisition_offers%ROWTYPE;
    v_hold public.acquisition_holds%ROWTYPE;
    v_recommended text;
    v_effective_result text;
    v_effective_hold_amount_mxn numeric;
    v_request jsonb;
    v_result jsonb;
    v_command public.command_log%ROWTYPE;
BEGIN
    IF p_action NOT IN ('ready', 'receive', 'resolve_condition', 'close_condition') THEN
        RAISE EXCEPTION 'invalid_acquisition_delivery_action' USING ERRCODE = '22023';
    END IF;

    SELECT acquisition_order.* INTO v_order
    FROM public.acquisition_orders acquisition_order
    WHERE acquisition_order.id = p_order_id
      AND acquisition_order.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'acquisition_order_not_found' USING ERRCODE = 'P0002'; END IF;
    IF NOT (v_role = 'dori_admin' OR (v_role = 'provider' AND v_order.supplier_id = v_supplier_id)) THEN
        RAISE EXCEPTION 'acquisition_order_access_denied' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO STRICT v_delivery FROM public.acquisition_deliveries
    WHERE order_id = p_order_id AND environment_id = v_environment_id FOR UPDATE;
    SELECT * INTO STRICT v_offer FROM public.acquisition_offers
    WHERE id = v_order.offer_id AND environment_id = v_environment_id FOR UPDATE;

    v_request := jsonb_build_object(
        'order_id', p_order_id, 'action', p_action,
        'checklist', p_checklist, 'result', p_result,
        'note', NULLIF(btrim(p_note), ''), 'hold_amount_mxn', p_hold_amount_mxn
    );
    v_command := app.begin_acquisition_command('complete_acquisition_delivery.' || p_action, p_idempotency_key, v_request);
    IF v_command.result_payload IS NOT NULL THEN RETURN v_command.result_payload; END IF;

    IF p_action = 'ready' THEN
        IF v_role <> 'provider' OR v_order.status <> 'awarded' THEN
            RAISE EXCEPTION 'provider_ready_not_allowed' USING ERRCODE = '42501';
        END IF;
        UPDATE public.acquisition_deliveries
        SET status = 'ready', ready_at = v_now, notes = NULLIF(btrim(p_note), ''), revision = revision + 1
        WHERE id = v_delivery.id;
        UPDATE public.acquisition_orders SET status = 'ready_for_delivery', revision = revision + 1 WHERE id = p_order_id;
        UPDATE public.acquisition_offers SET status = 'ready_for_delivery', revision = revision + 1, updated_at = v_now WHERE id = v_offer.id;
        v_result := jsonb_build_object('order_id', p_order_id, 'status', 'ready_for_delivery');

    ELSIF p_action = 'receive' THEN
        IF v_role <> 'dori_admin' OR v_order.status <> 'ready_for_delivery' THEN
            RAISE EXCEPTION 'dori_reception_not_allowed' USING ERRCODE = '42501';
        END IF;
        IF p_checklist IS NULL OR NOT (p_checklist ?& ARRAY['vin_correct','mileage_correct','chargers_complete','keys_complete','new_damage']) THEN
            RAISE EXCEPTION 'complete_reception_checklist_required' USING ERRCODE = '22023';
        END IF;
        IF NOT COALESCE((p_checklist->>'vin_correct')::boolean, false) THEN
            v_recommended := 'rejected';
        ELSIF NOT COALESCE((p_checklist->>'keys_complete')::boolean, false)
              OR NOT COALESCE((p_checklist->>'chargers_complete')::boolean, false) THEN
            v_recommended := 'accepted_with_condition';
        ELSIF NOT COALESCE((p_checklist->>'mileage_correct')::boolean, false)
              OR COALESCE((p_checklist->>'new_damage')::boolean, false) THEN
            v_recommended := 'accepted_with_observations';
        ELSE
            v_recommended := 'accepted';
        END IF;

        v_effective_result := COALESCE(NULLIF(btrim(p_result), ''), v_recommended);
        IF v_effective_result <> v_recommended THEN
            RAISE EXCEPTION 'reception_result_must_match_server_recommendation' USING ERRCODE = '22023';
        END IF;
        v_effective_hold_amount_mxn := CASE
            WHEN v_effective_result = 'accepted_with_condition'
                THEN COALESCE(NULLIF(p_hold_amount_mxn, 0), 6000)
            ELSE COALESCE(p_hold_amount_mxn, 0)
        END;
        IF v_effective_result IN ('accepted_with_condition', 'rejected')
           AND NULLIF(btrim(p_note), '') IS NULL THEN
            RAISE EXCEPTION 'reception_issue_summary_required' USING ERRCODE = '22023';
        END IF;
        IF v_effective_result = 'accepted_with_condition' AND v_effective_hold_amount_mxn <= 0 THEN
            RAISE EXCEPTION 'positive_hold_required_for_condition' USING ERRCODE = '22023';
        END IF;
        IF v_effective_result <> 'accepted_with_condition' AND v_effective_hold_amount_mxn <> 0 THEN
            RAISE EXCEPTION 'hold_only_allowed_for_condition' USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.acquisition_receptions(
            environment_id, order_id, vin_correct, mileage_correct,
            chargers_complete, keys_complete, new_damage, recommended_result,
            result, issue_summary, hold_amount_mxn, received_by, received_at
        ) VALUES (
            v_environment_id, p_order_id,
            (p_checklist->>'vin_correct')::boolean,
            (p_checklist->>'mileage_correct')::boolean,
            (p_checklist->>'chargers_complete')::boolean,
            (p_checklist->>'keys_complete')::boolean,
            (p_checklist->>'new_damage')::boolean,
            v_recommended, v_effective_result, NULLIF(btrim(p_note), ''),
            v_effective_hold_amount_mxn, v_actor_profile_id, v_now
        );
        UPDATE public.acquisition_deliveries
        SET status = 'received', received_at = v_now, revision = revision + 1
        WHERE id = v_delivery.id;
        UPDATE public.acquisition_orders
        SET status = v_effective_result,
            payment_status = CASE WHEN v_effective_result = 'accepted_with_condition' THEN 'held'
                                  WHEN v_effective_result = 'rejected' THEN 'cancelled' ELSE 'simulated' END,
            closed_at = CASE WHEN v_effective_result = 'accepted_with_condition' THEN NULL ELSE v_now END,
            revision = revision + 1
        WHERE id = p_order_id;
        UPDATE public.acquisition_offers
        SET status = v_effective_result, revision = revision + 1, updated_at = v_now
        WHERE id = v_offer.id;
        IF v_effective_result = 'accepted_with_condition' THEN
            INSERT INTO public.acquisition_holds(
                environment_id, order_id, amount_mxn, reason, status, created_at
            ) VALUES (
                v_environment_id, p_order_id, v_effective_hold_amount_mxn, btrim(p_note), 'pending_supplier', v_now
            );
        END IF;
        v_result := jsonb_build_object(
            'order_id', p_order_id, 'status', v_effective_result,
            'recommended_result', v_recommended, 'hold_amount_mxn', v_effective_hold_amount_mxn
        );

    ELSIF p_action = 'resolve_condition' THEN
        IF v_role <> 'provider' OR v_order.status <> 'accepted_with_condition' OR NULLIF(btrim(p_note), '') IS NULL THEN
            RAISE EXCEPTION 'provider_condition_resolution_not_allowed' USING ERRCODE = '42501';
        END IF;
        SELECT * INTO v_hold FROM public.acquisition_holds
        WHERE order_id = p_order_id AND environment_id = v_environment_id FOR UPDATE;
        IF NOT FOUND OR v_hold.status <> 'pending_supplier' THEN
            RAISE EXCEPTION 'pending_acquisition_hold_not_found' USING ERRCODE = 'P0002';
        END IF;
        UPDATE public.acquisition_holds
        SET status = 'ready_for_review', supplier_resolution_note = btrim(p_note), ready_for_review_at = v_now
        WHERE id = v_hold.id;
        v_result := jsonb_build_object('order_id', p_order_id, 'status', 'condition_ready_for_review');

    ELSE
        IF v_role <> 'dori_admin' OR v_order.status <> 'accepted_with_condition' THEN
            RAISE EXCEPTION 'dori_condition_close_not_allowed' USING ERRCODE = '42501';
        END IF;
        SELECT * INTO v_hold FROM public.acquisition_holds
        WHERE order_id = p_order_id AND environment_id = v_environment_id FOR UPDATE;
        IF NOT FOUND OR v_hold.status <> 'ready_for_review' THEN
            RAISE EXCEPTION 'resolved_evidence_not_ready' USING ERRCODE = '55000';
        END IF;
        UPDATE public.acquisition_holds
        SET status = 'resolved', resolved_by = v_actor_profile_id, resolved_at = v_now
        WHERE id = v_hold.id;
        UPDATE public.acquisition_orders
        SET status = 'closed', payment_status = 'simulated', closed_at = v_now, revision = revision + 1
        WHERE id = p_order_id;
        v_result := jsonb_build_object('order_id', p_order_id, 'status', 'closed');
    END IF;

    PERFORM app.finish_acquisition_command(
        v_command.id, v_result, 'acquisition.delivery.' || p_action,
        'acquisition_order', p_order_id,
        jsonb_build_object(
            'actor_role', v_role,
            'result', COALESCE(v_effective_result, p_result),
            'hold_amount_mxn', COALESCE(v_effective_hold_amount_mxn, p_hold_amount_mxn)
        )
    );
    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.complete_acquisition_delivery(uuid, text, jsonb, text, text, numeric, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_acquisition_delivery(uuid, text, jsonb, text, text, numeric, text)
TO authenticated, service_role;
