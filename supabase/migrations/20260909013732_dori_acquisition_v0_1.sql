-- =====================================================================
-- DORI Adquisicion v0.1
--
-- Contrato incremental para el prototipo de dos telefonos. Reutiliza
-- auth.users, profiles, environments, command_log y audit_log. Los
-- proveedores externos viven en una membresia propia y nunca se agregan
-- artificialmente a staff_memberships.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Organizaciones, identidad de adquisicion y datos del flujo
-- ---------------------------------------------------------------------

CREATE TABLE public.acquisition_suppliers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    city text NOT NULL,
    status text NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT acquisition_suppliers_environment_fkey
        FOREIGN KEY (environment_id) REFERENCES public.environments(id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_suppliers_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT acquisition_suppliers_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT acquisition_suppliers_city_not_blank CHECK (btrim(city) <> ''),
    CONSTRAINT acquisition_suppliers_status_check
        CHECK (status IN ('active', 'restricted', 'suspended')),
    CONSTRAINT acquisition_suppliers_environment_code_unique UNIQUE (environment_id, code),
    CONSTRAINT acquisition_suppliers_id_environment_unique UNIQUE (id, environment_id)
);

CREATE TABLE public.acquisition_memberships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    profile_id uuid NOT NULL,
    supplier_id uuid,
    role text NOT NULL,
    status text NOT NULL DEFAULT 'active',
    starts_at timestamptz NOT NULL DEFAULT now(),
    ends_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT acquisition_memberships_profile_environment_fkey
        FOREIGN KEY (profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_memberships_supplier_environment_fkey
        FOREIGN KEY (supplier_id, environment_id)
        REFERENCES public.acquisition_suppliers(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_memberships_role_check
        CHECK (role IN ('dori_admin', 'provider')),
    CONSTRAINT acquisition_memberships_status_check
        CHECK (status IN ('active', 'suspended')),
    CONSTRAINT acquisition_memberships_scope_check CHECK (
        (role = 'dori_admin' AND supplier_id IS NULL)
        OR (role = 'provider' AND supplier_id IS NOT NULL)
    ),
    CONSTRAINT acquisition_memberships_interval_check
        CHECK (ends_at IS NULL OR ends_at > starts_at)
);

CREATE UNIQUE INDEX acquisition_memberships_active_profile_unique
    ON public.acquisition_memberships(environment_id, profile_id)
    WHERE ends_at IS NULL;
CREATE INDEX acquisition_memberships_supplier_idx
    ON public.acquisition_memberships(environment_id, supplier_id);

CREATE TABLE public.acquisition_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    code text NOT NULL,
    title text NOT NULL,
    target_quantity integer NOT NULL,
    model text NOT NULL,
    versions text[] NOT NULL DEFAULT '{}',
    minimum_year integer NOT NULL,
    maximum_year integer NOT NULL,
    maximum_mileage integer NOT NULL,
    delivery_city text NOT NULL DEFAULT 'Puebla',
    deadline_at timestamptz,
    status text NOT NULL DEFAULT 'published',
    created_by uuid NOT NULL,
    revision bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT acquisition_requests_environment_fkey
        FOREIGN KEY (environment_id) REFERENCES public.environments(id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_requests_creator_environment_fkey
        FOREIGN KEY (created_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_requests_code_not_blank CHECK (btrim(code) <> ''),
    CONSTRAINT acquisition_requests_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT acquisition_requests_model_not_blank CHECK (btrim(model) <> ''),
    CONSTRAINT acquisition_requests_quantity_positive CHECK (target_quantity > 0),
    CONSTRAINT acquisition_requests_years_check CHECK (minimum_year BETWEEN 2000 AND 2100 AND maximum_year >= minimum_year),
    CONSTRAINT acquisition_requests_mileage_check CHECK (maximum_mileage >= 0),
    CONSTRAINT acquisition_requests_status_check CHECK (
        status IN ('published', 'evaluating', 'partially_awarded', 'awarded', 'closed', 'cancelled')
    ),
    CONSTRAINT acquisition_requests_environment_code_unique UNIQUE (environment_id, code),
    CONSTRAINT acquisition_requests_id_environment_unique UNIQUE (id, environment_id)
);

CREATE TABLE public.acquisition_request_rules (
    request_id uuid NOT NULL,
    environment_id uuid NOT NULL,
    target_soh numeric(5,2),
    minimum_soh numeric(5,2),
    internal_price_limit_mxn numeric(12,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (request_id, environment_id),
    CONSTRAINT acquisition_request_rules_request_fkey
        FOREIGN KEY (request_id, environment_id)
        REFERENCES public.acquisition_requests(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_request_rules_soh_check CHECK (
        (target_soh IS NULL OR target_soh BETWEEN 0 AND 100)
        AND (minimum_soh IS NULL OR minimum_soh BETWEEN 0 AND 100)
        AND (target_soh IS NULL OR minimum_soh IS NULL OR target_soh >= minimum_soh)
    ),
    CONSTRAINT acquisition_request_rules_price_positive CHECK (internal_price_limit_mxn > 0)
);

CREATE TABLE public.acquisition_offers (
    id uuid PRIMARY KEY,
    environment_id uuid NOT NULL,
    request_id uuid NOT NULL,
    supplier_id uuid NOT NULL,
    created_by uuid NOT NULL,
    vin text NOT NULL,
    model text NOT NULL,
    version text,
    year integer NOT NULL,
    mileage integer NOT NULL,
    declared_soh numeric(5,2),
    color text,
    price_mxn numeric(12,2) NOT NULL,
    transfer_included boolean NOT NULL DEFAULT false,
    agreed_price_mxn numeric(12,2),
    status text NOT NULL DEFAULT 'submitted',
    revision bigint NOT NULL DEFAULT 1,
    submitted_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT acquisition_offers_request_environment_fkey
        FOREIGN KEY (request_id, environment_id)
        REFERENCES public.acquisition_requests(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_offers_supplier_environment_fkey
        FOREIGN KEY (supplier_id, environment_id)
        REFERENCES public.acquisition_suppliers(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_offers_creator_environment_fkey
        FOREIGN KEY (created_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_offers_vin_check CHECK (vin ~ '^[A-HJ-NPR-Z0-9]{17}$'),
    CONSTRAINT acquisition_offers_model_not_blank CHECK (btrim(model) <> ''),
    CONSTRAINT acquisition_offers_year_check CHECK (year BETWEEN 2000 AND 2100),
    CONSTRAINT acquisition_offers_mileage_check CHECK (mileage >= 0),
    CONSTRAINT acquisition_offers_soh_check CHECK (declared_soh IS NULL OR declared_soh BETWEEN 0 AND 100),
    CONSTRAINT acquisition_offers_price_check CHECK (price_mxn > 0 AND (agreed_price_mxn IS NULL OR agreed_price_mxn > 0)),
    CONSTRAINT acquisition_offers_status_check CHECK (
        status IN (
            'submitted', 'negotiating', 'price_agreed', 'awarded',
            'ready_for_delivery', 'received', 'accepted',
            'accepted_with_observations', 'accepted_with_condition',
            'rejected', 'withdrawn'
        )
    ),
    CONSTRAINT acquisition_offers_request_vin_unique UNIQUE (environment_id, request_id, vin),
    CONSTRAINT acquisition_offers_id_environment_unique UNIQUE (id, environment_id)
);

CREATE INDEX acquisition_offers_request_idx
    ON public.acquisition_offers(environment_id, request_id, status);
CREATE INDEX acquisition_offers_supplier_idx
    ON public.acquisition_offers(environment_id, supplier_id, status);

CREATE TABLE public.acquisition_evidence (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    offer_id uuid NOT NULL,
    kind text NOT NULL,
    object_path text NOT NULL,
    uploaded_by uuid NOT NULL,
    verified boolean NOT NULL DEFAULT false,
    notes text,
    created_at timestamptz NOT NULL,
    CONSTRAINT acquisition_evidence_offer_environment_fkey
        FOREIGN KEY (offer_id, environment_id)
        REFERENCES public.acquisition_offers(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_evidence_uploader_environment_fkey
        FOREIGN KEY (uploaded_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_evidence_kind_check CHECK (
        kind IN ('vin', 'dashboard', 'front', 'rear', 'left_side', 'right_side', 'interior', 'charger', 'battery', 'document')
    ),
    CONSTRAINT acquisition_evidence_path_not_blank CHECK (btrim(object_path) <> ''),
    CONSTRAINT acquisition_evidence_path_unique UNIQUE (object_path)
);

CREATE TABLE public.acquisition_offer_assessments (
    offer_id uuid NOT NULL,
    environment_id uuid NOT NULL,
    estimated_value_mxn numeric(12,2),
    maximum_recommended_mxn numeric(12,2),
    risk text NOT NULL,
    recommendation text NOT NULL,
    evidence_status text NOT NULL,
    summary text NOT NULL,
    calculated_at timestamptz NOT NULL,
    PRIMARY KEY (offer_id, environment_id),
    CONSTRAINT acquisition_assessments_offer_fkey
        FOREIGN KEY (offer_id, environment_id)
        REFERENCES public.acquisition_offers(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_assessments_risk_check CHECK (risk IN ('low', 'medium', 'high')),
    CONSTRAINT acquisition_assessments_recommendation_check CHECK (
        recommendation IN ('buy', 'negotiate', 'review', 'wait_for_information', 'do_not_buy')
    ),
    CONSTRAINT acquisition_assessments_evidence_check CHECK (evidence_status IN ('complete', 'incomplete'))
);

CREATE TABLE public.acquisition_negotiations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    offer_id uuid NOT NULL,
    actor_profile_id uuid NOT NULL,
    actor_role text NOT NULL,
    action text NOT NULL,
    amount_mxn numeric(12,2),
    message text,
    created_at timestamptz NOT NULL,
    CONSTRAINT acquisition_negotiations_offer_environment_fkey
        FOREIGN KEY (offer_id, environment_id)
        REFERENCES public.acquisition_offers(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_negotiations_actor_environment_fkey
        FOREIGN KEY (actor_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_negotiations_actor_role_check CHECK (actor_role IN ('dori_admin', 'provider')),
    CONSTRAINT acquisition_negotiations_action_check CHECK (action IN ('counteroffer', 'accepted')),
    CONSTRAINT acquisition_negotiations_amount_check CHECK (amount_mxn IS NULL OR amount_mxn > 0)
);

CREATE INDEX acquisition_negotiations_offer_idx
    ON public.acquisition_negotiations(environment_id, offer_id, created_at);

CREATE TABLE public.acquisition_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    code text NOT NULL,
    offer_id uuid NOT NULL,
    supplier_id uuid NOT NULL,
    final_price_mxn numeric(12,2) NOT NULL,
    payment_status text NOT NULL DEFAULT 'simulated',
    status text NOT NULL DEFAULT 'awarded',
    awarded_by uuid NOT NULL,
    awarded_at timestamptz NOT NULL,
    closed_at timestamptz,
    revision bigint NOT NULL DEFAULT 1,
    CONSTRAINT acquisition_orders_offer_environment_fkey
        FOREIGN KEY (offer_id, environment_id)
        REFERENCES public.acquisition_offers(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_orders_supplier_environment_fkey
        FOREIGN KEY (supplier_id, environment_id)
        REFERENCES public.acquisition_suppliers(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_orders_awarder_environment_fkey
        FOREIGN KEY (awarded_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_orders_price_positive CHECK (final_price_mxn > 0),
    CONSTRAINT acquisition_orders_payment_status_check CHECK (payment_status IN ('simulated', 'held', 'cancelled')),
    CONSTRAINT acquisition_orders_status_check CHECK (
        status IN ('awarded', 'ready_for_delivery', 'received', 'accepted', 'accepted_with_observations', 'accepted_with_condition', 'rejected', 'closed')
    ),
    CONSTRAINT acquisition_orders_environment_code_unique UNIQUE (environment_id, code),
    CONSTRAINT acquisition_orders_offer_unique UNIQUE (offer_id, environment_id),
    CONSTRAINT acquisition_orders_id_environment_unique UNIQUE (id, environment_id)
);

CREATE TABLE public.acquisition_deliveries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    order_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'preparing',
    ready_at timestamptz,
    received_at timestamptz,
    notes text,
    revision bigint NOT NULL DEFAULT 1,
    CONSTRAINT acquisition_deliveries_order_environment_fkey
        FOREIGN KEY (order_id, environment_id)
        REFERENCES public.acquisition_orders(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_deliveries_status_check CHECK (status IN ('preparing', 'ready', 'received')),
    CONSTRAINT acquisition_deliveries_order_unique UNIQUE (order_id, environment_id),
    CONSTRAINT acquisition_deliveries_id_environment_unique UNIQUE (id, environment_id)
);

CREATE TABLE public.acquisition_receptions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    order_id uuid NOT NULL,
    vin_correct boolean NOT NULL,
    mileage_correct boolean NOT NULL,
    chargers_complete boolean NOT NULL,
    keys_complete boolean NOT NULL,
    new_damage boolean NOT NULL,
    recommended_result text NOT NULL,
    result text NOT NULL,
    issue_summary text,
    hold_amount_mxn numeric(12,2) NOT NULL DEFAULT 0,
    received_by uuid NOT NULL,
    received_at timestamptz NOT NULL,
    CONSTRAINT acquisition_receptions_order_environment_fkey
        FOREIGN KEY (order_id, environment_id)
        REFERENCES public.acquisition_orders(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_receptions_receiver_environment_fkey
        FOREIGN KEY (received_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_receptions_recommendation_check CHECK (
        recommended_result IN ('accepted', 'accepted_with_observations', 'accepted_with_condition', 'rejected')
    ),
    CONSTRAINT acquisition_receptions_result_check CHECK (
        result IN ('accepted', 'accepted_with_observations', 'accepted_with_condition', 'rejected')
    ),
    CONSTRAINT acquisition_receptions_hold_check CHECK (hold_amount_mxn >= 0),
    CONSTRAINT acquisition_receptions_order_unique UNIQUE (order_id, environment_id)
);

CREATE TABLE public.acquisition_holds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    order_id uuid NOT NULL,
    amount_mxn numeric(12,2) NOT NULL,
    reason text NOT NULL,
    status text NOT NULL DEFAULT 'pending_supplier',
    supplier_resolution_note text,
    resolved_by uuid,
    created_at timestamptz NOT NULL,
    ready_for_review_at timestamptz,
    resolved_at timestamptz,
    CONSTRAINT acquisition_holds_order_environment_fkey
        FOREIGN KEY (order_id, environment_id)
        REFERENCES public.acquisition_orders(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_holds_resolver_environment_fkey
        FOREIGN KEY (resolved_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_holds_amount_positive CHECK (amount_mxn > 0),
    CONSTRAINT acquisition_holds_reason_not_blank CHECK (btrim(reason) <> ''),
    CONSTRAINT acquisition_holds_status_check CHECK (status IN ('pending_supplier', 'ready_for_review', 'resolved')),
    CONSTRAINT acquisition_holds_order_unique UNIQUE (order_id, environment_id)
);

-- ---------------------------------------------------------------------
-- 2. RLS y privilegios: clientes autenticados solo leen; escriben por RPC
-- ---------------------------------------------------------------------

ALTER TABLE public.acquisition_suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_request_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_offer_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_negotiations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_receptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_holds ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
    public.acquisition_suppliers,
    public.acquisition_memberships,
    public.acquisition_requests,
    public.acquisition_request_rules,
    public.acquisition_offers,
    public.acquisition_evidence,
    public.acquisition_offer_assessments,
    public.acquisition_negotiations,
    public.acquisition_orders,
    public.acquisition_deliveries,
    public.acquisition_receptions,
    public.acquisition_holds
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE
    public.acquisition_suppliers,
    public.acquisition_memberships,
    public.acquisition_requests,
    public.acquisition_request_rules,
    public.acquisition_offers,
    public.acquisition_evidence,
    public.acquisition_offer_assessments,
    public.acquisition_negotiations,
    public.acquisition_orders,
    public.acquisition_deliveries,
    public.acquisition_receptions,
    public.acquisition_holds
TO authenticated;

GRANT ALL ON TABLE
    public.acquisition_suppliers,
    public.acquisition_memberships,
    public.acquisition_requests,
    public.acquisition_request_rules,
    public.acquisition_offers,
    public.acquisition_evidence,
    public.acquisition_offer_assessments,
    public.acquisition_negotiations,
    public.acquisition_orders,
    public.acquisition_deliveries,
    public.acquisition_receptions,
    public.acquisition_holds
TO postgres, service_role;

CREATE OR REPLACE FUNCTION app.auth_acquisition_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT membership.role
    FROM public.acquisition_memberships membership
    WHERE membership.profile_id = app.auth_profile_id()
      AND membership.environment_id = app.current_environment_id()
      AND membership.status = 'active'
      AND membership.starts_at <= app.env_now(membership.environment_id)
      AND (membership.ends_at IS NULL OR membership.ends_at > app.env_now(membership.environment_id))
    LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION app.auth_acquisition_supplier_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT membership.supplier_id
    FROM public.acquisition_memberships membership
    JOIN public.acquisition_suppliers supplier
      ON supplier.id = membership.supplier_id
     AND supplier.environment_id = membership.environment_id
    WHERE membership.profile_id = app.auth_profile_id()
      AND membership.environment_id = app.current_environment_id()
      AND membership.role = 'provider'
      AND membership.status = 'active'
      AND supplier.status = 'active'
      AND membership.starts_at <= app.env_now(membership.environment_id)
      AND (membership.ends_at IS NULL OR membership.ends_at > app.env_now(membership.environment_id))
    LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION app.auth_is_acquisition_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT COALESCE(app.auth_acquisition_role() = 'dori_admin', false)
$function$;

REVOKE ALL ON FUNCTION app.auth_acquisition_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION app.auth_acquisition_supplier_id() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION app.auth_is_acquisition_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION app.auth_acquisition_role() TO authenticated, service_role, postgres;
GRANT EXECUTE ON FUNCTION app.auth_acquisition_supplier_id() TO authenticated, service_role, postgres;
GRANT EXECUTE ON FUNCTION app.auth_is_acquisition_admin() TO authenticated, service_role, postgres;

CREATE POLICY acquisition_memberships_read ON public.acquisition_memberships
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND (profile_id = app.auth_profile_id() OR app.auth_is_acquisition_admin())
);

CREATE POLICY acquisition_suppliers_read ON public.acquisition_suppliers
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND (app.auth_is_acquisition_admin() OR id = app.auth_acquisition_supplier_id())
);

CREATE POLICY acquisition_requests_read ON public.acquisition_requests
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND (
        app.auth_is_acquisition_admin()
        OR (
            app.auth_acquisition_supplier_id() IS NOT NULL
            AND status IN ('published', 'evaluating', 'partially_awarded', 'awarded')
        )
    )
);

CREATE POLICY acquisition_request_rules_admin_read ON public.acquisition_request_rules
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id() AND app.auth_is_acquisition_admin()
);

CREATE POLICY acquisition_offers_read ON public.acquisition_offers
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND (app.auth_is_acquisition_admin() OR supplier_id = app.auth_acquisition_supplier_id())
);

CREATE POLICY acquisition_evidence_read ON public.acquisition_evidence
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND EXISTS (
        SELECT 1 FROM public.acquisition_offers offer
        WHERE offer.id = acquisition_evidence.offer_id
          AND offer.environment_id = acquisition_evidence.environment_id
          AND (app.auth_is_acquisition_admin() OR offer.supplier_id = app.auth_acquisition_supplier_id())
    )
);

CREATE POLICY acquisition_assessments_admin_read ON public.acquisition_offer_assessments
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id() AND app.auth_is_acquisition_admin()
);

CREATE POLICY acquisition_negotiations_read ON public.acquisition_negotiations
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND EXISTS (
        SELECT 1 FROM public.acquisition_offers offer
        WHERE offer.id = acquisition_negotiations.offer_id
          AND offer.environment_id = acquisition_negotiations.environment_id
          AND (app.auth_is_acquisition_admin() OR offer.supplier_id = app.auth_acquisition_supplier_id())
    )
);

CREATE POLICY acquisition_orders_read ON public.acquisition_orders
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND (app.auth_is_acquisition_admin() OR supplier_id = app.auth_acquisition_supplier_id())
);

CREATE POLICY acquisition_deliveries_read ON public.acquisition_deliveries
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND EXISTS (
        SELECT 1 FROM public.acquisition_orders acquisition_order
        WHERE acquisition_order.id = acquisition_deliveries.order_id
          AND acquisition_order.environment_id = acquisition_deliveries.environment_id
          AND (app.auth_is_acquisition_admin() OR acquisition_order.supplier_id = app.auth_acquisition_supplier_id())
    )
);

CREATE POLICY acquisition_receptions_read ON public.acquisition_receptions
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND EXISTS (
        SELECT 1 FROM public.acquisition_orders acquisition_order
        WHERE acquisition_order.id = acquisition_receptions.order_id
          AND acquisition_order.environment_id = acquisition_receptions.environment_id
          AND (app.auth_is_acquisition_admin() OR acquisition_order.supplier_id = app.auth_acquisition_supplier_id())
    )
);

CREATE POLICY acquisition_holds_read ON public.acquisition_holds
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND EXISTS (
        SELECT 1 FROM public.acquisition_orders acquisition_order
        WHERE acquisition_order.id = acquisition_holds.order_id
          AND acquisition_order.environment_id = acquisition_holds.environment_id
          AND (app.auth_is_acquisition_admin() OR acquisition_order.supplier_id = app.auth_acquisition_supplier_id())
    )
);

-- ---------------------------------------------------------------------
-- 3. Storage privado. Las rutas son:
--    <environment>/<supplier>/<offer>/<uuid>.<extension>
-- ---------------------------------------------------------------------

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'acquisition-evidence', 'acquisition-evidence', false, 10485760,
    ARRAY['image/jpeg', 'image/png', 'image/heic']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY acquisition_evidence_objects_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'acquisition-evidence'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) = 4
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND (storage.foldername(name))[2] = app.auth_acquisition_supplier_id()::text
    AND (storage.foldername(name))[3] ~ '^[0-9a-f-]{36}$'
);

CREATE POLICY acquisition_evidence_objects_select
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'acquisition-evidence'
    AND EXISTS (
        SELECT 1
        FROM public.acquisition_evidence evidence
        JOIN public.acquisition_offers offer
          ON offer.id = evidence.offer_id
         AND offer.environment_id = evidence.environment_id
        WHERE evidence.object_path = name
          AND evidence.environment_id = app.current_environment_id()
          AND (app.auth_is_acquisition_admin() OR offer.supplier_id = app.auth_acquisition_supplier_id())
    )
);

-- Los objetos son inmutables: un reemplazo usa una ruta nueva. No UPDATE ni DELETE.

-- ---------------------------------------------------------------------
-- 4. Infraestructura interna de comandos idempotentes y auditoria
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.begin_acquisition_command(
    p_command_name text,
    p_idempotency_key text,
    p_request jsonb
)
RETURNS public.command_log
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_command public.command_log%ROWTYPE;
    v_environment_id uuid := app.current_environment_id();
    v_actor_profile_id uuid := app.auth_profile_id();
BEGIN
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;

    SELECT command.* INTO v_command
    FROM public.command_log command
    WHERE command.environment_id = v_environment_id
      AND command.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;

    IF FOUND THEN
        IF v_command.command_name <> p_command_name
           OR v_command.request_payload IS DISTINCT FROM p_request
           OR v_command.status <> 'completed' THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        RETURN v_command;
    END IF;

    INSERT INTO public.command_log(
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, p_command_name,
        btrim(p_idempotency_key), 'accepted', p_request,
        app.env_now(v_environment_id)
    ) RETURNING * INTO v_command;

    RETURN v_command;
END;
$function$;

CREATE OR REPLACE FUNCTION app.finish_acquisition_command(
    p_command_id uuid,
    p_result jsonb,
    p_event_type text,
    p_entity_type text,
    p_entity_id uuid,
    p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_command public.command_log%ROWTYPE;
BEGIN
    UPDATE public.command_log
    SET status = 'completed', result_payload = p_result
    WHERE id = p_command_id
    RETURNING * INTO STRICT v_command;

    INSERT INTO public.audit_log(
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_command.environment_id, v_command.actor_profile_id, NULL, v_command.id,
        p_event_type, p_entity_type, p_entity_id, p_metadata,
        app.env_now(v_command.environment_id)
    );
END;
$function$;

REVOKE ALL ON FUNCTION app.begin_acquisition_command(text, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION app.finish_acquisition_command(uuid, jsonb, text, text, uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.begin_acquisition_command(text, text, jsonb) TO service_role, postgres;
GRANT EXECUTE ON FUNCTION app.finish_acquisition_command(uuid, jsonb, text, text, uuid, jsonb) TO service_role, postgres;

-- ---------------------------------------------------------------------
-- 5. RPC 1: publicar una solicitud y sus reglas internas
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.publish_acquisition_request(
    p_code text,
    p_title text,
    p_target_quantity integer,
    p_model text,
    p_versions text[],
    p_minimum_year integer,
    p_maximum_year integer,
    p_maximum_mileage integer,
    p_delivery_city text,
    p_deadline_at timestamptz,
    p_target_soh numeric,
    p_minimum_soh numeric,
    p_internal_price_limit_mxn numeric,
    p_idempotency_key text
)
RETURNS public.acquisition_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_actor_profile_id uuid := app.auth_profile_id();
    v_now timestamptz := app.env_now(v_environment_id);
    v_request jsonb;
    v_command public.command_log%ROWTYPE;
    v_result public.acquisition_requests%ROWTYPE;
BEGIN
    IF NOT app.auth_is_acquisition_admin() THEN
        RAISE EXCEPTION 'dori_acquisition_admin_required' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object(
        'code', btrim(p_code), 'title', btrim(p_title),
        'target_quantity', p_target_quantity, 'model', btrim(p_model),
        'versions', COALESCE(to_jsonb(p_versions), '[]'::jsonb),
        'minimum_year', p_minimum_year, 'maximum_year', p_maximum_year,
        'maximum_mileage', p_maximum_mileage, 'delivery_city', btrim(p_delivery_city),
        'deadline_at', p_deadline_at, 'target_soh', p_target_soh,
        'minimum_soh', p_minimum_soh, 'internal_price_limit_mxn', p_internal_price_limit_mxn
    );
    v_command := app.begin_acquisition_command('publish_acquisition_request', p_idempotency_key, v_request);

    IF v_command.result_payload IS NOT NULL THEN
        SELECT * INTO STRICT v_result FROM public.acquisition_requests
        WHERE id = (v_command.result_payload->>'request_id')::uuid;
        RETURN v_result;
    END IF;

    INSERT INTO public.acquisition_requests(
        environment_id, code, title, target_quantity, model, versions,
        minimum_year, maximum_year, maximum_mileage, delivery_city,
        deadline_at, status, created_by, created_at, updated_at
    ) VALUES (
        v_environment_id, btrim(p_code), btrim(p_title), p_target_quantity,
        btrim(p_model), COALESCE(p_versions, '{}'), p_minimum_year,
        p_maximum_year, p_maximum_mileage, btrim(p_delivery_city),
        p_deadline_at, 'published', v_actor_profile_id, v_now, v_now
    ) RETURNING * INTO v_result;

    INSERT INTO public.acquisition_request_rules(
        request_id, environment_id, target_soh, minimum_soh,
        internal_price_limit_mxn, created_at
    ) VALUES (
        v_result.id, v_environment_id, p_target_soh, p_minimum_soh,
        p_internal_price_limit_mxn, v_now
    );

    PERFORM app.finish_acquisition_command(
        v_command.id, jsonb_build_object('request_id', v_result.id),
        'acquisition.request.published', 'acquisition_request', v_result.id,
        jsonb_build_object('code', v_result.code, 'target_quantity', v_result.target_quantity)
    );
    RETURN v_result;
END;
$function$;

-- ---------------------------------------------------------------------
-- 6. RPC 2: enviar una unidad con evidencia y recomendacion del servidor
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.submit_acquisition_offer(
    p_offer_id uuid,
    p_request_id uuid,
    p_vin text,
    p_model text,
    p_version text,
    p_year integer,
    p_mileage integer,
    p_declared_soh numeric,
    p_color text,
    p_price_mxn numeric,
    p_transfer_included boolean,
    p_evidence jsonb,
    p_idempotency_key text
)
RETURNS public.acquisition_offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_actor_profile_id uuid := app.auth_profile_id();
    v_supplier_id uuid := app.auth_acquisition_supplier_id();
    v_now timestamptz := app.env_now(v_environment_id);
    v_request_row public.acquisition_requests%ROWTYPE;
    v_rules public.acquisition_request_rules%ROWTYPE;
    v_request jsonb;
    v_command public.command_log%ROWTYPE;
    v_result public.acquisition_offers%ROWTYPE;
    v_item jsonb;
    v_kind text;
    v_path text;
    v_recommendation text;
    v_risk text;
    v_summary text;
BEGIN
    IF v_supplier_id IS NULL THEN
        RAISE EXCEPTION 'active_acquisition_provider_required' USING ERRCODE = '42501';
    END IF;
    IF p_offer_id IS NULL THEN
        RAISE EXCEPTION 'offer_id_required' USING ERRCODE = '22023';
    END IF;
    IF jsonb_typeof(p_evidence) <> 'array' OR jsonb_array_length(p_evidence) < 3 THEN
        RAISE EXCEPTION 'at_least_three_evidence_items_required' USING ERRCODE = '22023';
    END IF;

    SELECT request.* INTO v_request_row
    FROM public.acquisition_requests request
    WHERE request.id = p_request_id
      AND request.environment_id = v_environment_id
      AND request.status IN ('published', 'evaluating')
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_acquisition_request_not_found' USING ERRCODE = 'P0002';
    END IF;

    SELECT * INTO STRICT v_rules
    FROM public.acquisition_request_rules
    WHERE request_id = p_request_id AND environment_id = v_environment_id;

    v_request := jsonb_build_object(
        'offer_id', p_offer_id, 'request_id', p_request_id,
        'vin', upper(btrim(p_vin)), 'model', btrim(p_model),
        'version', NULLIF(btrim(p_version), ''), 'year', p_year,
        'mileage', p_mileage, 'declared_soh', p_declared_soh,
        'color', NULLIF(btrim(p_color), ''), 'price_mxn', p_price_mxn,
        'transfer_included', p_transfer_included, 'evidence', p_evidence
    );
    v_command := app.begin_acquisition_command('submit_acquisition_offer', p_idempotency_key, v_request);
    IF v_command.result_payload IS NOT NULL THEN
        SELECT * INTO STRICT v_result FROM public.acquisition_offers
        WHERE id = (v_command.result_payload->>'offer_id')::uuid;
        RETURN v_result;
    END IF;

    FOR v_item IN SELECT value FROM jsonb_array_elements(p_evidence)
    LOOP
        v_kind := v_item->>'kind';
        v_path := v_item->>'path';
        IF v_kind NOT IN ('vin', 'dashboard', 'front', 'rear', 'left_side', 'right_side', 'interior', 'charger', 'battery', 'document')
           OR v_path IS NULL
           OR v_path NOT LIKE v_environment_id::text || '/' || v_supplier_id::text || '/' || p_offer_id::text || '/%'
           OR NOT EXISTS (
                SELECT 1 FROM storage.objects object
                WHERE object.bucket_id = 'acquisition-evidence'
                  AND object.name = v_path
                  AND object.owner_id = auth.uid()::text
           ) THEN
            RAISE EXCEPTION 'invalid_or_unowned_acquisition_evidence' USING ERRCODE = '42501';
        END IF;
    END LOOP;

    INSERT INTO public.acquisition_offers(
        id, environment_id, request_id, supplier_id, created_by, vin,
        model, version, year, mileage, declared_soh, color, price_mxn,
        transfer_included, status, submitted_at, updated_at
    ) VALUES (
        p_offer_id, v_environment_id, p_request_id, v_supplier_id,
        v_actor_profile_id, upper(btrim(p_vin)), btrim(p_model),
        NULLIF(btrim(p_version), ''), p_year, p_mileage, p_declared_soh,
        NULLIF(btrim(p_color), ''), p_price_mxn, p_transfer_included,
        'submitted', v_now, v_now
    ) RETURNING * INTO v_result;

    INSERT INTO public.acquisition_evidence(
        environment_id, offer_id, kind, object_path, uploaded_by, created_at
    )
    SELECT v_environment_id, p_offer_id, item->>'kind', item->>'path', v_actor_profile_id, v_now
    FROM jsonb_array_elements(p_evidence) item;

    IF p_declared_soh IS NULL THEN
        v_recommendation := 'wait_for_information'; v_risk := 'medium';
        v_summary := 'Falta confirmar el estado de salud de la bateria.';
    ELSIF v_rules.minimum_soh IS NOT NULL AND p_declared_soh < v_rules.minimum_soh THEN
        v_recommendation := 'do_not_buy'; v_risk := 'high';
        v_summary := 'El estado de salud declarado esta por debajo del minimo.';
    ELSIF p_year < v_request_row.minimum_year OR p_year > v_request_row.maximum_year
          OR p_mileage > v_request_row.maximum_mileage THEN
        v_recommendation := 'do_not_buy'; v_risk := 'high';
        v_summary := 'La unidad no cumple ano o kilometraje de la solicitud.';
    ELSIF p_price_mxn <= v_rules.internal_price_limit_mxn THEN
        v_recommendation := 'buy'; v_risk := 'low';
        v_summary := 'La unidad cumple los parametros principales de la solicitud.';
    ELSIF p_price_mxn <= v_rules.internal_price_limit_mxn * 1.05 THEN
        v_recommendation := 'negotiate'; v_risk := 'medium';
        v_summary := 'La unidad es viable si se ajusta el precio.';
    ELSIF p_price_mxn <= v_rules.internal_price_limit_mxn * 1.15 THEN
        v_recommendation := 'review'; v_risk := 'medium';
        v_summary := 'El precio requiere una revision adicional.';
    ELSE
        v_recommendation := 'do_not_buy'; v_risk := 'high';
        v_summary := 'El precio supera ampliamente el limite interno.';
    END IF;

    INSERT INTO public.acquisition_offer_assessments(
        offer_id, environment_id, estimated_value_mxn, maximum_recommended_mxn,
        risk, recommendation, evidence_status, summary, calculated_at
    ) VALUES (
        p_offer_id, v_environment_id, v_rules.internal_price_limit_mxn,
        v_rules.internal_price_limit_mxn, v_risk, v_recommendation,
        'complete', v_summary, v_now
    );

    UPDATE public.acquisition_requests
    SET status = 'evaluating', revision = revision + 1, updated_at = v_now
    WHERE id = p_request_id AND status = 'published';

    PERFORM app.finish_acquisition_command(
        v_command.id, jsonb_build_object('offer_id', v_result.id),
        'acquisition.offer.submitted', 'acquisition_offer', v_result.id,
        jsonb_build_object('request_id', p_request_id, 'supplier_id', v_supplier_id)
    );
    RETURN v_result;
END;
$function$;

-- ---------------------------------------------------------------------
-- 7. RPC 3: contraofertar, aceptar precio o adjudicar
-- ---------------------------------------------------------------------

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
    IF p_action NOT IN ('counteroffer', 'accept', 'award') THEN
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

-- ---------------------------------------------------------------------
-- 8. RPC 4: preparar, recibir, resolver condicion y cerrar
-- ---------------------------------------------------------------------

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
        IF p_result NOT IN ('accepted', 'accepted_with_observations', 'accepted_with_condition', 'rejected') THEN
            RAISE EXCEPTION 'valid_reception_result_required' USING ERRCODE = '22023';
        END IF;
        IF p_result IN ('accepted_with_condition', 'rejected') AND NULLIF(btrim(p_note), '') IS NULL THEN
            RAISE EXCEPTION 'reception_issue_summary_required' USING ERRCODE = '22023';
        END IF;
        IF p_result = 'accepted_with_condition' AND COALESCE(p_hold_amount_mxn, 0) <= 0 THEN
            RAISE EXCEPTION 'positive_hold_required_for_condition' USING ERRCODE = '22023';
        END IF;
        IF p_result <> 'accepted_with_condition' AND COALESCE(p_hold_amount_mxn, 0) <> 0 THEN
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
            v_recommended, p_result, NULLIF(btrim(p_note), ''),
            COALESCE(p_hold_amount_mxn, 0), v_actor_profile_id, v_now
        );
        UPDATE public.acquisition_deliveries
        SET status = 'received', received_at = v_now, revision = revision + 1
        WHERE id = v_delivery.id;
        UPDATE public.acquisition_orders
        SET status = p_result,
            payment_status = CASE WHEN p_result = 'accepted_with_condition' THEN 'held'
                                  WHEN p_result = 'rejected' THEN 'cancelled' ELSE 'simulated' END,
            closed_at = CASE WHEN p_result = 'accepted_with_condition' THEN NULL ELSE v_now END,
            revision = revision + 1
        WHERE id = p_order_id;
        UPDATE public.acquisition_offers SET status = p_result, revision = revision + 1, updated_at = v_now WHERE id = v_offer.id;
        IF p_result = 'accepted_with_condition' THEN
            INSERT INTO public.acquisition_holds(
                environment_id, order_id, amount_mxn, reason, status, created_at
            ) VALUES (
                v_environment_id, p_order_id, p_hold_amount_mxn, btrim(p_note), 'pending_supplier', v_now
            );
        END IF;
        v_result := jsonb_build_object(
            'order_id', p_order_id, 'status', p_result,
            'recommended_result', v_recommended, 'hold_amount_mxn', COALESCE(p_hold_amount_mxn, 0)
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
        jsonb_build_object('actor_role', v_role, 'result', p_result, 'hold_amount_mxn', p_hold_amount_mxn)
    );
    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.publish_acquisition_request(
    text, text, integer, text, text[], integer, integer, integer,
    text, timestamptz, numeric, numeric, numeric, text
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_acquisition_offer(
    uuid, uuid, text, text, text, integer, integer, numeric,
    text, numeric, boolean, jsonb, text
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.respond_acquisition_offer(uuid, text, numeric, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_acquisition_delivery(uuid, text, jsonb, text, text, numeric, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.publish_acquisition_request(
    text, text, integer, text, text[], integer, integer, integer,
    text, timestamptz, numeric, numeric, numeric, text
) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.submit_acquisition_offer(
    uuid, uuid, text, text, text, integer, integer, numeric,
    text, numeric, boolean, jsonb, text
) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.respond_acquisition_offer(uuid, text, numeric, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_acquisition_delivery(uuid, text, jsonb, text, text, numeric, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- 9. Realtime solo para el tablero compartido entre los dos telefonos
-- ---------------------------------------------------------------------

DO $block$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'acquisition_requests', 'acquisition_offers', 'acquisition_negotiations',
        'acquisition_orders', 'acquisition_deliveries', 'acquisition_receptions',
        'acquisition_holds'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_publication_tables
            WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = v_table
        ) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
        END IF;
    END LOOP;
END
$block$;

-- ---------------------------------------------------------------------
-- 10. Datos funcionales simulados exclusivamente en TEST
-- ---------------------------------------------------------------------

INSERT INTO public.acquisition_suppliers(environment_id, code, name, city, status)
SELECT environment.id, seed.code, seed.name, seed.city, 'active'
FROM public.environments environment
CROSS JOIN (VALUES
    ('PROV-PUE-A', 'Agencia Puebla Centro', 'Puebla'),
    ('PROV-PUE-B', 'Agencia Puebla Norte', 'Puebla')
) AS seed(code, name, city)
WHERE environment.code = 'test'
ON CONFLICT (environment_id, code) DO NOTHING;

-- La solicitud simulada necesita una identidad DORI para created_by. Se crea
-- al ejecutar scripts/provision-test-acquisition.sql despues de confirmar las
-- dos cuentas TEST; nunca se inventa un profile ni un auth.users en la migracion.

COMMENT ON TABLE public.acquisition_memberships IS
    'Membresia exclusiva de DORI Adquisicion. Proveedores externos no pertenecen a staff_memberships.';
COMMENT ON TABLE public.acquisition_request_rules IS
    'Parametros internos DORI separados de la solicitud visible para proveedores.';
COMMENT ON FUNCTION public.submit_acquisition_offer(
    uuid, uuid, text, text, text, integer, integer, numeric,
    text, numeric, boolean, jsonb, text
) IS 'Envia una unidad con evidencia inmutable y calcula la recomendacion inicial en el servidor.';
