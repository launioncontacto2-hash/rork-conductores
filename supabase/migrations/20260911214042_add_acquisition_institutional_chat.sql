-- Fase C: mensajeria institucional aislada por entorno y proveedor.
-- Los mensajes son inmutables; las acciones comerciales siguen en sus RPC.

CREATE TABLE public.acquisition_chat_threads (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    supplier_id uuid NOT NULL,
    offer_id uuid,
    scope text NOT NULL CHECK (scope IN ('general', 'unit')),
    title text NOT NULL CHECK (btrim(title) <> ''),
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT acquisition_chat_threads_scope_offer_check CHECK (
        (scope = 'general' AND offer_id IS NULL)
        OR (scope = 'unit' AND offer_id IS NOT NULL)
    ),
    CONSTRAINT acquisition_chat_threads_supplier_environment_fkey
        FOREIGN KEY (supplier_id, environment_id)
        REFERENCES public.acquisition_suppliers(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT acquisition_chat_threads_offer_environment_fkey
        FOREIGN KEY (offer_id, environment_id)
        REFERENCES public.acquisition_offers(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT acquisition_chat_threads_creator_environment_fkey
        FOREIGN KEY (created_by, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT acquisition_chat_threads_identity_unique
        UNIQUE NULLS NOT DISTINCT (environment_id, supplier_id, scope, offer_id),
    CONSTRAINT acquisition_chat_threads_id_environment_unique
        UNIQUE (id, environment_id)
);

CREATE TABLE public.acquisition_chat_messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
    environment_id uuid NOT NULL,
    thread_id uuid NOT NULL,
    sender_profile_id uuid,
    sender_role text NOT NULL CHECK (sender_role IN ('dori_admin', 'provider', 'system')),
    message_kind text NOT NULL CHECK (message_kind IN ('text', 'attachment', 'system')),
    body text,
    attachment_path text,
    system_event_type text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT acquisition_chat_messages_content_check CHECK (
        NULLIF(btrim(body), '') IS NOT NULL OR attachment_path IS NOT NULL
    ),
    CONSTRAINT acquisition_chat_messages_body_size_check CHECK (
        body IS NULL OR length(body) <= 4000
    ),
    CONSTRAINT acquisition_chat_messages_thread_environment_fkey
        FOREIGN KEY (thread_id, environment_id)
        REFERENCES public.acquisition_chat_threads(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT acquisition_chat_messages_sender_environment_fkey
        FOREIGN KEY (sender_profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT acquisition_chat_messages_sender_check CHECK (
        (sender_role = 'system' AND sender_profile_id IS NULL AND message_kind = 'system')
        OR (sender_role IN ('dori_admin', 'provider') AND sender_profile_id IS NOT NULL)
    )
);

CREATE TABLE public.acquisition_chat_read_receipts (
    environment_id uuid NOT NULL,
    thread_id uuid NOT NULL,
    profile_id uuid NOT NULL,
    last_read_sequence bigint NOT NULL DEFAULT 0 CHECK (last_read_sequence >= 0),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (thread_id, profile_id),
    CONSTRAINT acquisition_chat_receipts_thread_environment_fkey
        FOREIGN KEY (thread_id, environment_id)
        REFERENCES public.acquisition_chat_threads(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT acquisition_chat_receipts_profile_environment_fkey
        FOREIGN KEY (profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT
);

CREATE INDEX acquisition_chat_threads_participant_idx
    ON public.acquisition_chat_threads(environment_id, supplier_id, updated_at DESC);
CREATE INDEX acquisition_chat_messages_thread_idx
    ON public.acquisition_chat_messages(environment_id, thread_id, event_sequence);

ALTER TABLE public.acquisition_chat_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_chat_read_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY acquisition_chat_threads_select
ON public.acquisition_chat_threads FOR SELECT TO authenticated
USING (
    environment_id = app.current_environment_id()
    AND (
        app.auth_is_acquisition_admin()
        OR supplier_id = app.auth_acquisition_supplier_id()
    )
);

CREATE POLICY acquisition_chat_messages_select
ON public.acquisition_chat_messages FOR SELECT TO authenticated
USING (
    environment_id = app.current_environment_id()
    AND EXISTS (
        SELECT 1 FROM public.acquisition_chat_threads thread
        WHERE thread.id = acquisition_chat_messages.thread_id
          AND thread.environment_id = acquisition_chat_messages.environment_id
          AND (
              app.auth_is_acquisition_admin()
              OR thread.supplier_id = app.auth_acquisition_supplier_id()
          )
    )
);

CREATE POLICY acquisition_chat_receipts_select
ON public.acquisition_chat_read_receipts FOR SELECT TO authenticated
USING (
    environment_id = app.current_environment_id()
    AND profile_id = app.auth_profile_id()
    AND EXISTS (
        SELECT 1 FROM public.acquisition_chat_threads thread
        WHERE thread.id = acquisition_chat_read_receipts.thread_id
          AND thread.environment_id = acquisition_chat_read_receipts.environment_id
          AND (
              app.auth_is_acquisition_admin()
              OR thread.supplier_id = app.auth_acquisition_supplier_id()
          )
    )
);

REVOKE ALL ON public.acquisition_chat_threads,
    public.acquisition_chat_messages,
    public.acquisition_chat_read_receipts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.acquisition_chat_threads,
    public.acquisition_chat_messages,
    public.acquisition_chat_read_receipts TO authenticated;
GRANT ALL ON public.acquisition_chat_threads,
    public.acquisition_chat_messages,
    public.acquisition_chat_read_receipts TO service_role;

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'acquisition-chat-attachments',
    'acquisition-chat-attachments',
    false,
    10485760,
    ARRAY['image/jpeg', 'image/png', 'image/heic', 'application/pdf']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY acquisition_chat_attachments_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'acquisition-chat-attachments'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) = 3
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND EXISTS (
        SELECT 1 FROM public.acquisition_chat_threads thread
        WHERE thread.id::text = (storage.foldername(name))[3]
          AND thread.environment_id = app.current_environment_id()
          AND thread.supplier_id::text = (storage.foldername(name))[2]
          AND (
              app.auth_is_acquisition_admin()
              OR thread.supplier_id = app.auth_acquisition_supplier_id()
          )
    )
);

CREATE POLICY acquisition_chat_attachments_select
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'acquisition-chat-attachments'
    AND EXISTS (
        SELECT 1
        FROM public.acquisition_chat_messages message
        JOIN public.acquisition_chat_threads thread
          ON thread.id = message.thread_id
         AND thread.environment_id = message.environment_id
        WHERE message.attachment_path = name
          AND message.environment_id = app.current_environment_id()
          AND (
              app.auth_is_acquisition_admin()
              OR thread.supplier_id = app.auth_acquisition_supplier_id()
          )
    )
);

CREATE OR REPLACE FUNCTION public.ensure_acquisition_chat_thread(
    p_supplier_id uuid,
    p_offer_id uuid DEFAULT NULL
)
RETURNS public.acquisition_chat_threads
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_actor_profile_id uuid := app.auth_profile_id();
    v_role text := app.auth_acquisition_role();
    v_supplier_id uuid := app.auth_acquisition_supplier_id();
    v_offer public.acquisition_offers%ROWTYPE;
    v_scope text := CASE WHEN p_offer_id IS NULL THEN 'general' ELSE 'unit' END;
    v_title text := 'Chat general';
    v_result public.acquisition_chat_threads%ROWTYPE;
BEGIN
    IF v_role = 'provider' THEN
        IF p_supplier_id IS NOT NULL AND p_supplier_id <> v_supplier_id THEN
            RAISE EXCEPTION 'acquisition_chat_access_denied' USING ERRCODE = '42501';
        END IF;
        p_supplier_id := v_supplier_id;
    ELSIF v_role <> 'dori_admin' THEN
        RAISE EXCEPTION 'active_acquisition_membership_required' USING ERRCODE = '42501';
    END IF;

    IF v_role = 'dori_admin' AND p_supplier_id IS NULL AND p_offer_id IS NOT NULL THEN
        SELECT offer.supplier_id INTO p_supplier_id
        FROM public.acquisition_offers offer
        WHERE offer.id = p_offer_id AND offer.environment_id = v_environment_id;
    END IF;

    IF p_supplier_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.acquisition_suppliers supplier
        WHERE supplier.id = p_supplier_id
          AND supplier.environment_id = v_environment_id
          AND supplier.status = 'active'
    ) THEN
        RAISE EXCEPTION 'active_acquisition_supplier_required' USING ERRCODE = '42501';
    END IF;

    IF p_offer_id IS NOT NULL THEN
        SELECT offer.* INTO v_offer
        FROM public.acquisition_offers offer
        WHERE offer.id = p_offer_id
          AND offer.environment_id = v_environment_id
          AND offer.supplier_id = p_supplier_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'acquisition_chat_offer_not_found' USING ERRCODE = 'P0002';
        END IF;
        v_title := 'Unidad ' || right(v_offer.vin, 6);
    END IF;

    INSERT INTO public.acquisition_chat_threads(
        environment_id, supplier_id, offer_id, scope, title,
        created_by, created_at, updated_at
    ) VALUES (
        v_environment_id, p_supplier_id, p_offer_id, v_scope, v_title,
        v_actor_profile_id, app.env_now(v_environment_id), app.env_now(v_environment_id)
    )
    ON CONFLICT (environment_id, supplier_id, scope, offer_id)
    DO UPDATE SET title = EXCLUDED.title
    RETURNING * INTO v_result;

    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.send_acquisition_chat_message(
    p_thread_id uuid,
    p_body text,
    p_attachment_path text,
    p_idempotency_key text
)
RETURNS public.acquisition_chat_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_actor_profile_id uuid := app.auth_profile_id();
    v_role text := app.auth_acquisition_role();
    v_supplier_id uuid := app.auth_acquisition_supplier_id();
    v_thread public.acquisition_chat_threads%ROWTYPE;
    v_request jsonb;
    v_command public.command_log%ROWTYPE;
    v_result public.acquisition_chat_messages%ROWTYPE;
BEGIN
    SELECT thread.* INTO v_thread
    FROM public.acquisition_chat_threads thread
    WHERE thread.id = p_thread_id
      AND thread.environment_id = v_environment_id
      AND (
          v_role = 'dori_admin'
          OR (v_role = 'provider' AND thread.supplier_id = v_supplier_id)
      )
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'acquisition_chat_access_denied' USING ERRCODE = '42501';
    END IF;

    p_body := NULLIF(btrim(p_body), '');
    p_attachment_path := NULLIF(btrim(p_attachment_path), '');
    IF p_body IS NULL AND p_attachment_path IS NULL THEN
        RAISE EXCEPTION 'acquisition_chat_message_required' USING ERRCODE = '22023';
    END IF;
    IF p_body IS NOT NULL AND length(p_body) > 4000 THEN
        RAISE EXCEPTION 'acquisition_chat_message_too_long' USING ERRCODE = '22023';
    END IF;
    IF p_attachment_path IS NOT NULL AND (
        p_attachment_path NOT LIKE
            v_environment_id::text || '/' || v_thread.supplier_id::text || '/' || p_thread_id::text || '/%'
        OR NOT EXISTS (
            SELECT 1 FROM storage.objects object
            WHERE object.bucket_id = 'acquisition-chat-attachments'
              AND object.name = p_attachment_path
              AND object.owner_id = auth.uid()::text
        )
    ) THEN
        RAISE EXCEPTION 'invalid_or_unowned_chat_attachment' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object(
        'thread_id', p_thread_id,
        'body', p_body,
        'attachment_path', p_attachment_path
    );
    v_command := app.begin_acquisition_command(
        'send_acquisition_chat_message', p_idempotency_key, v_request
    );
    IF v_command.result_payload IS NOT NULL THEN
        SELECT * INTO STRICT v_result
        FROM public.acquisition_chat_messages
        WHERE id = (v_command.result_payload->>'message_id')::uuid;
        RETURN v_result;
    END IF;

    INSERT INTO public.acquisition_chat_messages(
        environment_id, thread_id, sender_profile_id, sender_role,
        message_kind, body, attachment_path, created_at
    ) VALUES (
        v_environment_id, p_thread_id, v_actor_profile_id, v_role,
        CASE WHEN p_attachment_path IS NULL THEN 'text' ELSE 'attachment' END,
        p_body, p_attachment_path, app.env_now(v_environment_id)
    ) RETURNING * INTO v_result;

    UPDATE public.acquisition_chat_threads
    SET updated_at = app.env_now(v_environment_id)
    WHERE id = p_thread_id;

    PERFORM app.finish_acquisition_command(
        v_command.id,
        jsonb_build_object('message_id', v_result.id, 'thread_id', p_thread_id),
        'acquisition.chat.message_sent',
        'acquisition_chat_thread',
        p_thread_id,
        jsonb_build_object('message_kind', v_result.message_kind)
    );
    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_acquisition_chat_read(
    p_thread_id uuid,
    p_last_read_sequence bigint
)
RETURNS public.acquisition_chat_read_receipts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid := app.current_environment_id();
    v_profile_id uuid := app.auth_profile_id();
    v_role text := app.auth_acquisition_role();
    v_supplier_id uuid := app.auth_acquisition_supplier_id();
    v_max_sequence bigint;
    v_result public.acquisition_chat_read_receipts%ROWTYPE;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.acquisition_chat_threads thread
        WHERE thread.id = p_thread_id
          AND thread.environment_id = v_environment_id
          AND (
              v_role = 'dori_admin'
              OR (v_role = 'provider' AND thread.supplier_id = v_supplier_id)
          )
    ) THEN
        RAISE EXCEPTION 'acquisition_chat_access_denied' USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(max(event_sequence), 0) INTO v_max_sequence
    FROM public.acquisition_chat_messages
    WHERE thread_id = p_thread_id AND environment_id = v_environment_id;

    INSERT INTO public.acquisition_chat_read_receipts(
        environment_id, thread_id, profile_id, last_read_sequence, updated_at
    ) VALUES (
        v_environment_id, p_thread_id, v_profile_id,
        LEAST(GREATEST(COALESCE(p_last_read_sequence, 0), 0), v_max_sequence),
        app.env_now(v_environment_id)
    )
    ON CONFLICT (thread_id, profile_id) DO UPDATE
    SET last_read_sequence = GREATEST(
            acquisition_chat_read_receipts.last_read_sequence,
            EXCLUDED.last_read_sequence
        ),
        updated_at = EXCLUDED.updated_at
    RETURNING * INTO v_result;

    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_acquisition_chat_threads()
RETURNS TABLE (
    thread_id uuid,
    supplier_id uuid,
    offer_id uuid,
    scope text,
    title text,
    supplier_name text,
    last_message text,
    last_message_kind text,
    last_message_at timestamptz,
    unread_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT thread.id,
           thread.supplier_id,
           thread.offer_id,
           thread.scope,
           thread.title,
           supplier.name,
           latest.body,
           latest.message_kind,
           latest.created_at,
           (
               SELECT count(*)
               FROM public.acquisition_chat_messages unread
               WHERE unread.thread_id = thread.id
                 AND unread.environment_id = thread.environment_id
                 AND unread.event_sequence > COALESCE(receipt.last_read_sequence, 0)
                 AND unread.sender_profile_id IS DISTINCT FROM app.auth_profile_id()
           )
    FROM public.acquisition_chat_threads thread
    JOIN public.acquisition_suppliers supplier
      ON supplier.id = thread.supplier_id
     AND supplier.environment_id = thread.environment_id
    LEFT JOIN public.acquisition_chat_read_receipts receipt
      ON receipt.thread_id = thread.id
     AND receipt.profile_id = app.auth_profile_id()
    LEFT JOIN LATERAL (
        SELECT message.body, message.message_kind, message.created_at
        FROM public.acquisition_chat_messages message
        WHERE message.thread_id = thread.id
          AND message.environment_id = thread.environment_id
        ORDER BY message.event_sequence DESC
        LIMIT 1
    ) latest ON true
    WHERE thread.environment_id = app.current_environment_id()
      AND (
          app.auth_is_acquisition_admin()
          OR thread.supplier_id = app.auth_acquisition_supplier_id()
      )
    ORDER BY latest.created_at DESC NULLS LAST, thread.updated_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.ensure_acquisition_chat_thread(uuid, uuid),
    public.send_acquisition_chat_message(uuid, text, text, text),
    public.mark_acquisition_chat_read(uuid, bigint),
    public.list_acquisition_chat_threads() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_acquisition_chat_thread(uuid, uuid),
    public.send_acquisition_chat_message(uuid, text, text, text),
    public.mark_acquisition_chat_read(uuid, bigint),
    public.list_acquisition_chat_threads() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION app.append_acquisition_chat_system_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_offer_id uuid;
    v_supplier_id uuid;
    v_thread_id uuid;
    v_body text;
BEGIN
    IF NEW.event_type = 'acquisition.chat.message_sent' THEN
        RETURN NEW;
    END IF;

    IF NEW.entity_type = 'acquisition_offer' THEN
        v_offer_id := NEW.entity_id;
        SELECT supplier_id INTO v_supplier_id
        FROM public.acquisition_offers
        WHERE id = v_offer_id AND environment_id = NEW.environment_id;
    ELSIF NEW.entity_type = 'acquisition_order' THEN
        SELECT offer_id, supplier_id INTO v_offer_id, v_supplier_id
        FROM public.acquisition_orders
        WHERE id = NEW.entity_id AND environment_id = NEW.environment_id;
    ELSE
        RETURN NEW;
    END IF;

    IF v_offer_id IS NULL OR v_supplier_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_body := CASE NEW.event_type
        WHEN 'acquisition.offer.submitted' THEN 'El proveedor envió una propuesta.'
        WHEN 'acquisition.offer.counteroffer' THEN
            CASE NEW.metadata->>'actor_role'
                WHEN 'dori_admin' THEN 'DORI envió una oferta.'
                ELSE 'El proveedor envió una contraoferta.'
            END
        WHEN 'acquisition.offer.accept' THEN 'La oferta fue aceptada.'
        WHEN 'acquisition.offer.award' THEN 'DORI confirmó la compra.'
        WHEN 'acquisition.offer.reject' THEN 'DORI decidió no continuar.'
        WHEN 'acquisition.offer.withdraw' THEN 'El proveedor decidió no continuar.'
        WHEN 'acquisition.delivery.ready' THEN 'La unidad está lista para entregar.'
        WHEN 'acquisition.delivery.receive' THEN 'DORI registró la recepción.'
        WHEN 'acquisition.delivery.resolve_condition' THEN 'El proveedor informó que resolvió la condición.'
        WHEN 'acquisition.delivery.close_condition' THEN 'DORI confirmó la resolución y cerró la operación.'
        ELSE NULL
    END;
    IF v_body IS NULL THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.acquisition_chat_threads(
        environment_id, supplier_id, offer_id, scope, title,
        created_by, created_at, updated_at
    )
    SELECT NEW.environment_id, v_supplier_id, v_offer_id, 'unit',
           'Unidad ' || right(offer.vin, 6), NEW.actor_profile_id,
           NEW.occurred_at, NEW.occurred_at
    FROM public.acquisition_offers offer
    WHERE offer.id = v_offer_id AND offer.environment_id = NEW.environment_id
    ON CONFLICT (environment_id, supplier_id, scope, offer_id)
    DO UPDATE SET updated_at = EXCLUDED.updated_at
    RETURNING id INTO v_thread_id;

    INSERT INTO public.acquisition_chat_messages(
        environment_id, thread_id, sender_profile_id, sender_role,
        message_kind, body, system_event_type, created_at
    ) VALUES (
        NEW.environment_id, v_thread_id, NULL, 'system',
        'system', v_body, NEW.event_type, NEW.occurred_at
    );
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION app.append_acquisition_chat_system_event()
FROM PUBLIC, anon, authenticated;

CREATE TRIGGER acquisition_audit_chat_system_event
AFTER INSERT ON public.audit_log
FOR EACH ROW
WHEN (NEW.event_type LIKE 'acquisition.%')
EXECUTE FUNCTION app.append_acquisition_chat_system_event();

-- Todo proveedor activo parte con un chat institucional general compartido.
INSERT INTO public.acquisition_chat_threads(
    environment_id, supplier_id, offer_id, scope, title,
    created_by, created_at, updated_at
)
SELECT supplier.environment_id, supplier.id, NULL, 'general', 'Chat general',
       NULL, app.env_now(supplier.environment_id), app.env_now(supplier.environment_id)
FROM public.acquisition_suppliers supplier
WHERE supplier.status = 'active'
ON CONFLICT (environment_id, supplier_id, scope, offer_id) DO NOTHING;

DO $realtime$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'acquisition_chat_messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.acquisition_chat_messages;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'acquisition_chat_read_receipts'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.acquisition_chat_read_receipts;
    END IF;
END;
$realtime$;

COMMENT ON TABLE public.acquisition_chat_messages IS
    'Mensajes institucionales inmutables; texto, adjunto privado o evento automatico.';
