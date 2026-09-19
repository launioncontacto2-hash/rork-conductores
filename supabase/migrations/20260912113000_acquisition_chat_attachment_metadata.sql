-- Attachment metadata for institutional acquisition chat.
-- Threads already bind every message to environment, supplier and optional offer/VIN.

ALTER TABLE public.acquisition_chat_messages
    ADD COLUMN attachment_mime_type text,
    ADD COLUMN attachment_filename text,
    ADD COLUMN attachment_size_bytes bigint;

ALTER TABLE public.acquisition_chat_messages
    ADD CONSTRAINT acquisition_chat_attachment_metadata_check CHECK (
        (
            attachment_path IS NULL
            AND attachment_mime_type IS NULL
            AND attachment_filename IS NULL
            AND attachment_size_bytes IS NULL
        ) OR (
            attachment_path IS NOT NULL
            AND NULLIF(btrim(attachment_mime_type), '') IS NOT NULL
            AND NULLIF(btrim(attachment_filename), '') IS NOT NULL
            AND length(attachment_filename) <= 255
            AND attachment_size_bytes BETWEEN 1 AND 10485760
        )
    ) NOT VALID;

-- Existing image-only messages predate explicit metadata. Backfill without
-- changing their immutable content or storage path.
UPDATE public.acquisition_chat_messages
SET attachment_mime_type = 'image/jpeg',
    attachment_filename = 'Evidencia.jpg',
    attachment_size_bytes = 1
WHERE attachment_path IS NOT NULL
  AND attachment_mime_type IS NULL;

ALTER TABLE public.acquisition_chat_messages
    VALIDATE CONSTRAINT acquisition_chat_attachment_metadata_check;

UPDATE storage.buckets
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY[
        'image/jpeg', 'image/png', 'image/heic',
        'video/mp4', 'video/quicktime',
        'audio/mp4', 'audio/x-m4a', 'audio/mpeg', 'audio/wav',
        'application/pdf', 'application/octet-stream',
        'text/plain',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ]::text[]
WHERE id = 'acquisition-chat-attachments';

CREATE OR REPLACE FUNCTION public.send_acquisition_chat_message(
    p_thread_id uuid,
    p_body text,
    p_attachment_path text,
    p_attachment_mime_type text,
    p_attachment_filename text,
    p_attachment_size_bytes bigint,
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
    p_attachment_mime_type := NULLIF(btrim(p_attachment_mime_type), '');
    p_attachment_filename := NULLIF(btrim(p_attachment_filename), '');
    IF p_body IS NULL AND p_attachment_path IS NULL THEN
        RAISE EXCEPTION 'acquisition_chat_message_required' USING ERRCODE = '22023';
    END IF;
    IF p_body IS NOT NULL AND length(p_body) > 4000 THEN
        RAISE EXCEPTION 'acquisition_chat_message_too_long' USING ERRCODE = '22023';
    END IF;
    IF p_attachment_path IS NULL AND (
        p_attachment_mime_type IS NOT NULL
        OR p_attachment_filename IS NOT NULL
        OR p_attachment_size_bytes IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'acquisition_chat_attachment_path_required' USING ERRCODE = '22023';
    END IF;
    IF p_attachment_path IS NOT NULL AND (
        p_attachment_mime_type IS NULL
        OR p_attachment_filename IS NULL
        OR length(p_attachment_filename) > 255
        OR p_attachment_size_bytes NOT BETWEEN 1 AND 10485760
        OR p_attachment_path NOT LIKE
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
        'attachment_path', p_attachment_path,
        'attachment_mime_type', p_attachment_mime_type,
        'attachment_filename', p_attachment_filename,
        'attachment_size_bytes', p_attachment_size_bytes
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
        message_kind, body, attachment_path, attachment_mime_type,
        attachment_filename, attachment_size_bytes, created_at
    ) VALUES (
        v_environment_id, p_thread_id, v_actor_profile_id, v_role,
        CASE WHEN p_attachment_path IS NULL THEN 'text' ELSE 'attachment' END,
        p_body, p_attachment_path, p_attachment_mime_type,
        p_attachment_filename, p_attachment_size_bytes,
        app.env_now(v_environment_id)
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

REVOKE ALL ON FUNCTION public.send_acquisition_chat_message(
    uuid, text, text, text, text, bigint, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_acquisition_chat_message(
    uuid, text, text, text, text, bigint, text
) TO authenticated, service_role;

COMMENT ON FUNCTION public.send_acquisition_chat_message(
    uuid, text, text, text, text, bigint, text
) IS 'Sends immutable institutional text/private attachment messages; commercial transitions remain separate RPCs.';

-- Compatibility for build 1030 and earlier image-only clients. Metadata is
-- derived server-side so a rolling TestFlight update never breaks chat.
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
    v_mime text;
    v_filename text;
    v_size bigint;
BEGIN
    IF NULLIF(btrim(p_attachment_path), '') IS NOT NULL THEN
        SELECT COALESCE(object.metadata->>'mimetype', 'image/jpeg'),
               regexp_replace(p_attachment_path, '^.*/', ''),
               COALESCE((object.metadata->>'size')::bigint, 1)
        INTO v_mime, v_filename, v_size
        FROM storage.objects object
        WHERE object.bucket_id = 'acquisition-chat-attachments'
          AND object.name = p_attachment_path;
    END IF;

    RETURN public.send_acquisition_chat_message(
        p_thread_id,
        p_body,
        p_attachment_path,
        v_mime,
        v_filename,
        v_size,
        p_idempotency_key
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.send_acquisition_chat_message(
    uuid, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_acquisition_chat_message(
    uuid, text, text, text
) TO authenticated, service_role;
