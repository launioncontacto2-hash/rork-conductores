-- DORI Adquisicion: authoritative iOS push notification outbox.
-- APNs credentials never live in SQL. The dispatcher reads them only from
-- protected Edge Function secrets; this migration merely persists recipients.

CREATE TABLE public.acquisition_push_devices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL REFERENCES public.environments(id) ON DELETE CASCADE,
    profile_id uuid NOT NULL,
    device_token text NOT NULL,
    platform text NOT NULL DEFAULT 'ios' CHECK (platform = 'ios'),
    app_environment text NOT NULL CHECK (app_environment IN ('test', 'prod')),
    bundle_id text NOT NULL,
    registered_at timestamptz NOT NULL,
    last_seen_at timestamptz NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
    revoked_at timestamptz,
    CONSTRAINT acquisition_push_devices_profile_environment_fkey
        FOREIGN KEY (profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_push_devices_token_format
        CHECK (device_token ~ '^[0-9a-f]{64,200}$'),
    CONSTRAINT acquisition_push_devices_revocation_consistent CHECK (
        (status = 'active' AND revoked_at IS NULL)
        OR (status = 'revoked' AND revoked_at IS NOT NULL)
    ),
    CONSTRAINT acquisition_push_devices_bundle_not_blank CHECK (btrim(bundle_id) <> ''),
    CONSTRAINT acquisition_push_devices_unique_token
        UNIQUE (environment_id, app_environment, bundle_id, device_token)
);

CREATE INDEX acquisition_push_devices_recipient_idx
    ON public.acquisition_push_devices(environment_id, profile_id, status);
ALTER TABLE public.acquisition_push_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.acquisition_push_devices FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.acquisition_push_devices TO service_role;

CREATE TABLE public.acquisition_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL REFERENCES public.environments(id) ON DELETE CASCADE,
    audit_event_id uuid NOT NULL REFERENCES public.audit_log(id) ON DELETE RESTRICT,
    recipient_profile_id uuid NOT NULL,
    source_profile_id uuid,
    supplier_id uuid REFERENCES public.acquisition_suppliers(id) ON DELETE CASCADE,
    offer_id uuid REFERENCES public.acquisition_offers(id) ON DELETE CASCADE,
    request_id uuid REFERENCES public.acquisition_requests(id) ON DELETE CASCADE,
    thread_id uuid REFERENCES public.acquisition_chat_threads(id) ON DELETE CASCADE,
    category text NOT NULL CHECK (category IN ('negotiation', 'chat', 'operation', 'request')),
    title text NOT NULL CHECK (btrim(title) <> ''),
    subtitle text,
    body text NOT NULL CHECK (btrim(body) <> ''),
    deep_link jsonb NOT NULL CHECK (jsonb_typeof(deep_link) = 'object'),
    collapse_id text NOT NULL CHECK (btrim(collapse_id) <> ''),
    created_at timestamptz NOT NULL,
    read_at timestamptz,
    push_status text NOT NULL DEFAULT 'pending'
        CHECK (push_status IN ('pending', 'sending', 'sent', 'failed', 'skipped')),
    push_attempts integer NOT NULL DEFAULT 0 CHECK (push_attempts >= 0),
    last_attempt_at timestamptz,
    pushed_at timestamptz,
    last_push_error text,
    CONSTRAINT acquisition_notifications_recipient_environment_fkey
        FOREIGN KEY (recipient_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_notifications_source_environment_fkey
        FOREIGN KEY (source_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE CASCADE,
    CONSTRAINT acquisition_notifications_context_required CHECK (
        (category = 'chat' AND thread_id IS NOT NULL)
        OR (category = 'request' AND request_id IS NOT NULL)
        OR (category IN ('negotiation', 'operation') AND offer_id IS NOT NULL)
    ),
    CONSTRAINT acquisition_notifications_event_recipient_unique
        UNIQUE (audit_event_id, recipient_profile_id)
);

CREATE INDEX acquisition_notifications_recipient_unread_idx
    ON public.acquisition_notifications(environment_id, recipient_profile_id, created_at DESC)
    WHERE read_at IS NULL;
CREATE INDEX acquisition_notifications_dispatch_idx
    ON public.acquisition_notifications(push_status, created_at);
ALTER TABLE public.acquisition_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY acquisition_notifications_select_own
ON public.acquisition_notifications FOR SELECT TO authenticated
USING (
    environment_id = app.current_environment_id()
    AND recipient_profile_id = app.auth_profile_id()
);

REVOKE ALL ON TABLE public.acquisition_notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.acquisition_notifications TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.acquisition_notifications TO service_role;

CREATE OR REPLACE FUNCTION public.register_acquisition_push_device(
    p_device_token text,
    p_platform text,
    p_app_environment text,
    p_bundle_id text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_profile_id uuid := app.auth_profile_id();
    v_environment_code text;
    v_now timestamptz;
    v_id uuid;
BEGIN
    IF v_environment_id IS NULL OR v_profile_id IS NULL
       OR COALESCE(app.auth_acquisition_role() NOT IN ('dori_admin', 'provider'), true) THEN
        RAISE EXCEPTION 'acquisition_push_membership_required' USING ERRCODE = '42501';
    END IF;
    SELECT code INTO STRICT v_environment_code
    FROM public.environments WHERE id = v_environment_id;
    IF p_platform <> 'ios' OR p_app_environment <> v_environment_code
       OR btrim(p_bundle_id) <> 'com.turnoev.mobility'
       OR lower(btrim(p_device_token)) !~ '^[0-9a-f]{64,200}$' THEN
        RAISE EXCEPTION 'invalid_acquisition_push_device' USING ERRCODE = '22023';
    END IF;
    v_now := app.env_now(v_environment_id);

    INSERT INTO public.acquisition_push_devices(
        environment_id, profile_id, device_token, platform,
        app_environment, bundle_id, registered_at, last_seen_at, status
    ) VALUES (
        v_environment_id, v_profile_id, lower(btrim(p_device_token)), 'ios',
        p_app_environment, btrim(p_bundle_id), v_now, v_now, 'active'
    )
    ON CONFLICT (environment_id, app_environment, bundle_id, device_token)
    DO UPDATE SET profile_id = EXCLUDED.profile_id, last_seen_at = EXCLUDED.last_seen_at,
                  status = 'active', revoked_at = NULL
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.revoke_acquisition_push_device(p_device_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_profile_id uuid := app.auth_profile_id();
BEGIN
    UPDATE public.acquisition_push_devices
    SET status = 'revoked', revoked_at = app.env_now(v_environment_id)
    WHERE environment_id = v_environment_id
      AND profile_id = v_profile_id
      AND device_token = lower(btrim(p_device_token));
END;
$function$;

CREATE OR REPLACE FUNCTION public.acquisition_notification_badge_count()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT count(*)
    FROM public.acquisition_notifications notification
    WHERE notification.environment_id = app.current_environment_id()
      AND notification.recipient_profile_id = app.auth_profile_id()
      AND notification.read_at IS NULL;
$function$;

CREATE OR REPLACE FUNCTION public.acquisition_unread_offer_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT DISTINCT notification.offer_id
    FROM public.acquisition_notifications notification
    WHERE notification.environment_id = app.current_environment_id()
      AND notification.recipient_profile_id = app.auth_profile_id()
      AND notification.read_at IS NULL
      AND notification.category <> 'chat'
      AND notification.offer_id IS NOT NULL;
$function$;

CREATE OR REPLACE FUNCTION public.mark_acquisition_notification_context_read(
    p_context_type text,
    p_context_id uuid
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_profile_id uuid := app.auth_profile_id();
    v_count bigint;
BEGIN
    IF p_context_type NOT IN ('offer', 'thread', 'request') THEN
        RAISE EXCEPTION 'invalid_notification_context' USING ERRCODE = '22023';
    END IF;
    UPDATE public.acquisition_notifications notification
    SET read_at = app.env_now(v_environment_id)
    WHERE notification.environment_id = v_environment_id
      AND notification.recipient_profile_id = v_profile_id
      AND notification.read_at IS NULL
      AND CASE p_context_type
          WHEN 'offer' THEN notification.category <> 'chat'
              AND notification.offer_id = p_context_id
          WHEN 'thread' THEN notification.category = 'chat'
              AND notification.thread_id = p_context_id
          WHEN 'request' THEN notification.category = 'request'
              AND notification.request_id = p_context_id
      END;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.register_acquisition_push_device(text, text, text, text),
    public.revoke_acquisition_push_device(text),
    public.acquisition_notification_badge_count(),
    public.acquisition_unread_offer_ids(),
    public.mark_acquisition_notification_context_read(text, uuid)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_acquisition_push_device(text, text, text, text),
    public.revoke_acquisition_push_device(text),
    public.acquisition_notification_badge_count(),
    public.acquisition_unread_offer_ids(),
    public.mark_acquisition_notification_context_read(text, uuid)
TO authenticated, service_role;

CREATE OR REPLACE FUNCTION app.enqueue_acquisition_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_offer public.acquisition_offers%ROWTYPE;
    v_supplier public.acquisition_suppliers%ROWTYPE;
    v_thread public.acquisition_chat_threads%ROWTYPE;
    v_message public.acquisition_chat_messages%ROWTYPE;
    v_request_id uuid;
    v_offer_id uuid;
    v_supplier_id uuid;
    v_thread_id uuid;
    v_actor_role text := NEW.metadata->>'actor_role';
    v_amount numeric;
    v_title text;
    v_subtitle text;
    v_body text;
    v_category text;
    v_deep_link jsonb;
    v_collapse_id text;
    v_message_id uuid;
BEGIN
    IF NEW.event_type NOT LIKE 'acquisition.%' THEN RETURN NEW; END IF;
    IF v_actor_role IS NULL AND NEW.actor_profile_id IS NOT NULL THEN
        SELECT role INTO v_actor_role
        FROM public.acquisition_memberships
        WHERE environment_id = NEW.environment_id
          AND profile_id = NEW.actor_profile_id
          AND status = 'active'
        ORDER BY starts_at DESC
        LIMIT 1;
    END IF;

    IF NEW.event_type = 'acquisition.chat.message_sent' THEN
        v_thread_id := NEW.entity_id;
        SELECT * INTO v_thread FROM public.acquisition_chat_threads
        WHERE id = v_thread_id AND environment_id = NEW.environment_id;
        IF NOT FOUND THEN RETURN NEW; END IF;
        SELECT (result_payload->>'message_id')::uuid INTO v_message_id
        FROM public.command_log WHERE id = NEW.command_id;
        SELECT * INTO v_message FROM public.acquisition_chat_messages
        WHERE id = v_message_id AND environment_id = NEW.environment_id;
        v_offer_id := v_thread.offer_id;
        v_supplier_id := v_thread.supplier_id;
        v_category := 'chat';
        v_deep_link := jsonb_build_object(
            'kind', CASE WHEN v_thread.scope = 'general' THEN 'chat_general' ELSE 'chat_unit' END,
            'thread_id', v_thread.id, 'offer_id', v_thread.offer_id
        );
        v_collapse_id := 'chat-' || v_thread.id::text;
        SELECT * INTO v_supplier FROM public.acquisition_suppliers WHERE id = v_supplier_id;
        IF v_actor_role IS NULL THEN
            SELECT role INTO v_actor_role FROM public.acquisition_memberships
            WHERE environment_id = NEW.environment_id AND profile_id = NEW.actor_profile_id
              AND status = 'active' LIMIT 1;
        END IF;
        v_title := CASE WHEN v_actor_role = 'dori_admin' THEN 'DORI Puebla' ELSE v_supplier.name END;
        IF v_message.attachment_path IS NOT NULL THEN
            v_body := CASE
                WHEN v_message.attachment_mime_type LIKE 'image/%' THEN 'Envió una foto'
                WHEN v_message.attachment_mime_type LIKE 'video/%' THEN 'Envió un video'
                WHEN v_message.attachment_mime_type LIKE 'audio/%' THEN 'Envió una nota de voz'
                ELSE 'Envió un documento'
            END;
        ELSE
            v_body := left(COALESCE(NULLIF(v_message.body, ''), 'Envió un mensaje'), 180);
        END IF;
        IF v_offer_id IS NOT NULL THEN
            SELECT * INTO v_offer FROM public.acquisition_offers WHERE id = v_offer_id;
            v_subtitle := 'Conversación de ' || v_offer.model || COALESCE(' ' || v_offer.version, '')
                || ' ' || v_offer.year || ' · VIN …' || right(v_offer.vin, 6);
        ELSE
            v_subtitle := 'Chat general con ' || v_supplier.name;
        END IF;
    ELSIF NEW.entity_type = 'acquisition_offer' THEN
        v_offer_id := NEW.entity_id;
        SELECT * INTO v_offer FROM public.acquisition_offers
        WHERE id = v_offer_id AND environment_id = NEW.environment_id;
        IF NOT FOUND THEN RETURN NEW; END IF;
        v_supplier_id := v_offer.supplier_id;
        v_request_id := v_offer.request_id;
        SELECT * INTO v_supplier FROM public.acquisition_suppliers WHERE id = v_supplier_id;
        v_amount := COALESCE((NEW.metadata->>'amount_mxn')::numeric,
            v_offer.agreed_price_mxn, v_offer.price_mxn);
        v_category := 'negotiation';
        v_deep_link := jsonb_build_object('kind', 'offer', 'offer_id', v_offer_id);
        v_collapse_id := 'offer-' || v_offer_id::text;
        v_subtitle := v_offer.model || COALESCE(' ' || v_offer.version, '') || ' '
            || v_offer.year || ' · VIN …' || right(v_offer.vin, 6);
        v_title := CASE NEW.event_type
            WHEN 'acquisition.offer.submitted' THEN 'Nueva propuesta de ' || v_supplier.name
            WHEN 'acquisition.offer.counteroffer' THEN
                CASE WHEN v_actor_role = 'dori_admin' THEN 'DORI Puebla hizo una nueva oferta'
                     ELSE 'Nueva contraoferta de ' || v_supplier.name END
            WHEN 'acquisition.offer.accept' THEN 'Precio aceptado'
            WHEN 'acquisition.offer.award' THEN 'DORI confirmó la compra'
            WHEN 'acquisition.offer.reject' THEN 'DORI decidió no continuar'
            WHEN 'acquisition.offer.withdraw' THEN v_supplier.name || ' decidió no continuar'
            ELSE NULL END;
        v_body := CASE NEW.event_type
            WHEN 'acquisition.offer.submitted' THEN 'Precio propuesto: ' || to_char(v_offer.price_mxn, 'FM$999,999,990')
            WHEN 'acquisition.offer.counteroffer' THEN 'Nuevo precio: ' || to_char(v_amount, 'FM$999,999,990')
            WHEN 'acquisition.offer.accept' THEN 'Precio acordado: ' || to_char(v_offer.agreed_price_mxn, 'FM$999,999,990') || ' · Compra pendiente de confirmación'
            WHEN 'acquisition.offer.award' THEN 'Precio final: ' || to_char(v_offer.agreed_price_mxn, 'FM$999,999,990')
            ELSE 'La negociación de esta unidad terminó.' END;
    ELSIF NEW.entity_type = 'acquisition_order' THEN
        SELECT offer_id, supplier_id INTO v_offer_id, v_supplier_id
        FROM public.acquisition_orders WHERE id = NEW.entity_id AND environment_id = NEW.environment_id;
        SELECT * INTO v_offer FROM public.acquisition_offers WHERE id = v_offer_id;
        SELECT * INTO v_supplier FROM public.acquisition_suppliers WHERE id = v_supplier_id;
        v_request_id := v_offer.request_id;
        v_category := 'operation';
        v_deep_link := jsonb_build_object('kind', 'offer', 'offer_id', v_offer_id);
        v_collapse_id := 'offer-' || v_offer_id::text;
        v_subtitle := v_offer.model || COALESCE(' ' || v_offer.version, '') || ' '
            || v_offer.year || ' · VIN …' || right(v_offer.vin, 6);
        v_title := CASE NEW.event_type
            WHEN 'acquisition.delivery.ready' THEN 'Unidad lista para entregar'
            WHEN 'acquisition.delivery.receive' THEN
                CASE WHEN NEW.metadata->>'result' = 'accepted_with_condition'
                     THEN 'Condición detectada en recepción' ELSE 'Recepción registrada' END
            WHEN 'acquisition.delivery.resolve_condition' THEN 'Condición resuelta por ' || v_supplier.name
            WHEN 'acquisition.delivery.close_condition' THEN 'Operación cerrada'
            ELSE NULL END;
        v_body := CASE NEW.event_type
            WHEN 'acquisition.delivery.ready' THEN v_supplier.name || ' marcó la unidad como lista.'
            WHEN 'acquisition.delivery.receive' THEN 'DORI registró la recepción de la unidad.'
            WHEN 'acquisition.delivery.resolve_condition' THEN 'La condición está lista para revisión de DORI.'
            WHEN 'acquisition.delivery.close_condition' THEN 'DORI confirmó la resolución y cerró la operación.'
            ELSE 'La operación cambió.' END;
    ELSIF NEW.event_type = 'acquisition.request.published' THEN
        v_request_id := NEW.entity_id;
        v_category := 'request';
        v_title := 'Nueva solicitud de DORI Puebla';
        SELECT title INTO v_body FROM public.acquisition_requests WHERE id = v_request_id;
        v_subtitle := 'Solicitud disponible';
        v_deep_link := jsonb_build_object('kind', 'request', 'request_id', v_request_id);
        v_collapse_id := 'request-' || v_request_id::text;
    ELSE
        RETURN NEW;
    END IF;
    IF v_title IS NULL THEN RETURN NEW; END IF;

    INSERT INTO public.acquisition_notifications(
        environment_id, audit_event_id, recipient_profile_id, source_profile_id,
        supplier_id, offer_id, request_id, thread_id, category, title, subtitle,
        body, deep_link, collapse_id, created_at
    )
    SELECT NEW.environment_id, NEW.id, membership.profile_id, NEW.actor_profile_id,
           v_supplier_id, v_offer_id, v_request_id, v_thread_id, v_category,
           v_title, v_subtitle, v_body, v_deep_link, v_collapse_id, NEW.occurred_at
    FROM public.acquisition_memberships membership
    WHERE membership.environment_id = NEW.environment_id
      AND membership.status = 'active'
      AND membership.starts_at <= app.env_now(NEW.environment_id)
      AND (membership.ends_at IS NULL OR membership.ends_at > app.env_now(NEW.environment_id))
      AND membership.profile_id IS DISTINCT FROM NEW.actor_profile_id
      AND (
          (NEW.event_type = 'acquisition.request.published' AND membership.role = 'provider')
          OR (v_actor_role = 'dori_admin' AND membership.role = 'provider' AND membership.supplier_id = v_supplier_id)
          OR (v_actor_role = 'provider' AND membership.role = 'dori_admin')
      )
    ON CONFLICT (audit_event_id, recipient_profile_id) DO NOTHING;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION app.enqueue_acquisition_notification() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER acquisition_audit_push_notification
AFTER INSERT ON public.audit_log
FOR EACH ROW
WHEN (NEW.event_type LIKE 'acquisition.%')
EXECUTE FUNCTION app.enqueue_acquisition_notification();

COMMENT ON TABLE public.acquisition_notifications IS
'Immutable recipient outbox derived from authoritative acquisition audit events; no DORI internal valuation fields are stored.';

CREATE OR REPLACE FUNCTION public.claim_acquisition_push_notifications(p_limit integer DEFAULT 25)
RETURNS SETOF public.acquisition_notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF current_user NOT IN ('postgres', 'service_role') THEN
        RAISE EXCEPTION 'push_dispatch_service_role_required' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    WITH claimable AS (
        SELECT notification.id
        FROM public.acquisition_notifications notification
        WHERE notification.push_status = 'pending'
           OR (notification.push_status = 'sending'
               AND notification.last_attempt_at < now() - interval '5 minutes')
        ORDER BY notification.created_at
        FOR UPDATE SKIP LOCKED
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100)
    )
    UPDATE public.acquisition_notifications notification
    SET push_status = 'sending',
        push_attempts = notification.push_attempts + 1,
        last_attempt_at = now(),
        last_push_error = NULL
    FROM claimable
    WHERE notification.id = claimable.id
    RETURNING notification.*;
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_acquisition_push_notifications(integer)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_acquisition_push_notifications(integer)
TO service_role;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION app.request_acquisition_push_dispatch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_url text;
    v_secret text;
BEGIN
    -- Local resets and unconfigured projects remain inert. TEST activation
    -- stores these two values in Supabase Vault, never in migrations or logs.
    IF to_regclass('vault.decrypted_secrets') IS NULL THEN RETURN NEW; END IF;
    EXECUTE $sql$
        SELECT
            max(decrypted_secret) FILTER (WHERE name = 'acquisition_push_dispatch_url'),
            max(decrypted_secret) FILTER (WHERE name = 'acquisition_push_dispatch_secret')
        FROM vault.decrypted_secrets
    $sql$ INTO v_url, v_secret;
    IF v_url IS NULL OR v_secret IS NULL THEN RETURN NEW; END IF;

    PERFORM net.http_post(
        url := v_url,
        headers := jsonb_build_object(
            'content-type', 'application/json',
            'x-push-dispatch-secret', v_secret
        ),
        body := jsonb_build_object('notification_id', NEW.id),
        timeout_milliseconds := 5000
    );
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION app.request_acquisition_push_dispatch()
FROM PUBLIC, anon, authenticated;
CREATE TRIGGER acquisition_notification_dispatch
AFTER INSERT ON public.acquisition_notifications
FOR EACH ROW EXECUTE FUNCTION app.request_acquisition_push_dispatch();

-- Realtime never carries the notification contents to another user: RLS keeps
-- each recipient isolated. It is only a wake-up signal so badges on a user's
-- other devices can be rebuilt from the authoritative unread rows.
DO $publication$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
       AND NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_publication_tables
           WHERE pubname = 'supabase_realtime'
             AND schemaname = 'public'
             AND tablename = 'acquisition_notifications'
       ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.acquisition_notifications;
    END IF;
END;
$publication$;



