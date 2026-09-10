-- Completa el contrato comercial: el estado rejected ya existia, pero no habia
-- una transicion RPC autorizada para que DORI cerrara una propuesta.
CREATE OR REPLACE FUNCTION public.respond_acquisition_offer(
    p_offer_id uuid,
    p_action text,
    p_amount_mxn numeric,
    p_message text,
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
    v_offer public.acquisition_offers%ROWTYPE;
    v_last public.acquisition_negotiations%ROWTYPE;
    v_order public.acquisition_orders%ROWTYPE;
    v_request jsonb;
    v_result jsonb;
    v_command public.command_log%ROWTYPE;
BEGIN
    IF p_action NOT IN ('counteroffer', 'accept', 'award', 'reject') THEN
        RAISE EXCEPTION 'invalid_acquisition_offer_action' USING ERRCODE = '22023';
    END IF;

    SELECT offer.* INTO v_offer FROM public.acquisition_offers offer
    WHERE offer.id = p_offer_id AND offer.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'acquisition_offer_not_found' USING ERRCODE = 'P0002'; END IF;
    IF NOT (v_role = 'dori_admin' OR (v_role = 'provider' AND v_offer.supplier_id = v_supplier_id)) THEN
        RAISE EXCEPTION 'acquisition_offer_access_denied' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object(
        'offer_id', p_offer_id, 'action', p_action,
        'amount_mxn', p_amount_mxn, 'message', NULLIF(btrim(p_message), '')
    );
    v_command := app.begin_acquisition_command('respond_acquisition_offer.' || p_action, p_idempotency_key, v_request);
    IF v_command.result_payload IS NOT NULL THEN RETURN v_command.result_payload; END IF;

    IF p_action = 'counteroffer' THEN
        IF p_amount_mxn IS NULL OR p_amount_mxn <= 0 OR v_offer.status NOT IN ('submitted', 'negotiating') THEN
            RAISE EXCEPTION 'invalid_acquisition_counteroffer' USING ERRCODE = '22023';
        END IF;
        INSERT INTO public.acquisition_negotiations(
            environment_id, offer_id, actor_profile_id, actor_role,
            action, amount_mxn, message, created_at
        ) VALUES (
            v_environment_id, p_offer_id, v_actor_profile_id, v_role,
            'counteroffer', p_amount_mxn, NULLIF(btrim(p_message), ''), v_now
        );
        UPDATE public.acquisition_offers
        SET status = 'negotiating', revision = revision + 1, updated_at = v_now
        WHERE id = p_offer_id;
        v_result := jsonb_build_object('offer_id', p_offer_id, 'status', 'negotiating');

    ELSIF p_action = 'accept' THEN
        SELECT negotiation.* INTO v_last
        FROM public.acquisition_negotiations negotiation
        WHERE negotiation.offer_id = p_offer_id
          AND negotiation.environment_id = v_environment_id
          AND negotiation.action = 'counteroffer'
        ORDER BY negotiation.created_at DESC, negotiation.id DESC LIMIT 1;
        IF NOT FOUND OR v_last.actor_profile_id = v_actor_profile_id OR v_offer.status <> 'negotiating' THEN
            RAISE EXCEPTION 'no_counteroffer_from_other_party' USING ERRCODE = '55000';
        END IF;
        INSERT INTO public.acquisition_negotiations(
            environment_id, offer_id, actor_profile_id, actor_role,
            action, amount_mxn, message, created_at
        ) VALUES (
            v_environment_id, p_offer_id, v_actor_profile_id, v_role,
            'accepted', v_last.amount_mxn, NULLIF(btrim(p_message), ''), v_now
        );
        UPDATE public.acquisition_offers
        SET status = 'price_agreed', agreed_price_mxn = v_last.amount_mxn,
            revision = revision + 1, updated_at = v_now
        WHERE id = p_offer_id;
        v_result := jsonb_build_object('offer_id', p_offer_id, 'status', 'price_agreed', 'agreed_price_mxn', v_last.amount_mxn);

    ELSIF p_action = 'reject' THEN
        IF v_role <> 'dori_admin' OR v_offer.status NOT IN ('submitted', 'negotiating', 'price_agreed') THEN
            RAISE EXCEPTION 'dori_reject_not_allowed' USING ERRCODE = '42501';
        END IF;
        UPDATE public.acquisition_offers
        SET status = 'rejected', revision = revision + 1, updated_at = v_now
        WHERE id = p_offer_id;
        v_result := jsonb_build_object('offer_id', p_offer_id, 'status', 'rejected');

    ELSE
        IF v_role <> 'dori_admin' OR v_offer.status NOT IN ('submitted', 'negotiating', 'price_agreed') THEN
            RAISE EXCEPTION 'dori_award_not_allowed' USING ERRCODE = '42501';
        END IF;
        IF COALESCE(p_amount_mxn, v_offer.agreed_price_mxn, v_offer.price_mxn) <= 0 THEN
            RAISE EXCEPTION 'final_price_required' USING ERRCODE = '22023';
        END IF;
        INSERT INTO public.acquisition_orders(
            environment_id, code, offer_id, supplier_id, final_price_mxn,
            payment_status, status, awarded_by, awarded_at
        ) VALUES (
            v_environment_id, 'OC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
            p_offer_id, v_offer.supplier_id,
            COALESCE(p_amount_mxn, v_offer.agreed_price_mxn, v_offer.price_mxn),
            'simulated', 'awarded', v_actor_profile_id, v_now
        ) RETURNING * INTO v_order;
        INSERT INTO public.acquisition_deliveries(environment_id, order_id, status)
        VALUES (v_environment_id, v_order.id, 'preparing');
        UPDATE public.acquisition_offers
        SET status = 'awarded', agreed_price_mxn = v_order.final_price_mxn,
            revision = revision + 1, updated_at = v_now
        WHERE id = p_offer_id;
        UPDATE public.acquisition_requests
        SET status = CASE
                WHEN (SELECT count(*) FROM public.acquisition_orders acquisition_order
                      JOIN public.acquisition_offers awarded_offer ON awarded_offer.id = acquisition_order.offer_id
                      WHERE awarded_offer.request_id = v_offer.request_id
                        AND acquisition_order.environment_id = v_environment_id)
                     >= target_quantity THEN 'awarded'
                ELSE 'partially_awarded'
            END,
            revision = revision + 1, updated_at = v_now
        WHERE id = v_offer.request_id;
        v_result := jsonb_build_object('offer_id', p_offer_id, 'order_id', v_order.id, 'status', 'awarded');
    END IF;

    PERFORM app.finish_acquisition_command(
        v_command.id, v_result, 'acquisition.offer.' || p_action,
        'acquisition_offer', p_offer_id,
        jsonb_build_object('actor_role', v_role, 'amount_mxn', p_amount_mxn)
    );
    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.respond_acquisition_offer(uuid, text, numeric, text, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_acquisition_offer(uuid, text, numeric, text, text)
TO authenticated, service_role;
