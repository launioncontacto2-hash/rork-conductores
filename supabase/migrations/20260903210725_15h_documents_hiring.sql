-- =====================================================================
-- TurnoEV · 15H · Expedientes y alta autoritativa
--
-- Los archivos viven en un bucket privado e inmutable. PostgreSQL guarda
-- solamente metadatos y decide quien puede leerlos. La firma del alta
-- reserva el expediente en una transaccion; una Edge Function autenticada
-- crea la identidad de Auth y completa perfil, membresia y driver_profile
-- en una segunda transaccion compensable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Candidatos, documentos e altas
-- ---------------------------------------------------------------------

CREATE TABLE public.candidates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    created_by uuid NOT NULL,
    full_name text NOT NULL,
    phone text NOT NULL,
    email text NOT NULL,
    city text NOT NULL,
    age integer NOT NULL,
    curp text NOT NULL,
    requested_shift_group text NOT NULL,
    requested_shift_slot text NOT NULL,
    stage text NOT NULL DEFAULT 'lead',
    screening_status text,
    interview_score integer,
    interview_decision text,
    notes text,
    revision bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    hired_at timestamptz,
    CONSTRAINT candidates_station_environment_fkey
        FOREIGN KEY (station_id, environment_id)
        REFERENCES public.stations(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT candidates_creator_environment_fkey
        FOREIGN KEY (created_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT candidates_id_station_environment_unique
        UNIQUE (id, station_id, environment_id),
    CONSTRAINT candidates_name_length
        CHECK (char_length(btrim(full_name)) BETWEEN 3 AND 200),
    CONSTRAINT candidates_phone_length
        CHECK (char_length(btrim(phone)) BETWEEN 7 AND 30),
    CONSTRAINT candidates_email_shape
        CHECK (btrim(email) = lower(btrim(email)) AND btrim(email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
    CONSTRAINT candidates_city_length
        CHECK (char_length(btrim(city)) BETWEEN 2 AND 120),
    CONSTRAINT candidates_age_range CHECK (age BETWEEN 18 AND 80),
    CONSTRAINT candidates_curp_shape CHECK (btrim(curp) ~ '^[A-Z0-9]{18}$'),
    CONSTRAINT candidates_shift_group_check CHECK (requested_shift_group IN ('weekday', 'weekend')),
    CONSTRAINT candidates_shift_slot_check CHECK (requested_shift_slot IN ('morning', 'evening')),
    CONSTRAINT candidates_stage_check CHECK (stage IN (
        'lead', 'contacted', 'prequalified', 'interviewed', 'documents',
        'ready_to_hire', 'approved', 'hired', 'lost'
    )),
    CONSTRAINT candidates_screening_check CHECK (screening_status IS NULL OR screening_status IN ('fit', 'review', 'unfit')),
    CONSTRAINT candidates_interview_score_range CHECK (interview_score IS NULL OR interview_score BETWEEN 0 AND 100),
    CONSTRAINT candidates_interview_decision_check CHECK (
        interview_decision IS NULL OR interview_decision IN ('recommended', 'conditional', 'not_recommended')
    ),
    CONSTRAINT candidates_notes_length CHECK (notes IS NULL OR char_length(btrim(notes)) BETWEEN 1 AND 2000),
    CONSTRAINT candidates_revision_positive CHECK (revision > 0),
    CONSTRAINT candidates_hired_consistent CHECK ((stage = 'hired') = (hired_at IS NOT NULL))
);

CREATE UNIQUE INDEX candidates_environment_email_unique
    ON public.candidates(environment_id, lower(btrim(email)));
CREATE UNIQUE INDEX candidates_environment_curp_unique
    ON public.candidates(environment_id, btrim(curp));
CREATE INDEX candidates_station_stage_idx
    ON public.candidates(station_id, stage, created_at DESC, id);
CREATE INDEX candidates_created_by_idx ON public.candidates(created_by);

CREATE TABLE public.candidate_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    candidate_id uuid NOT NULL,
    uploaded_by uuid NOT NULL,
    verified_by uuid NOT NULL,
    kind text NOT NULL,
    status text NOT NULL DEFAULT 'accepted',
    object_path text NOT NULL,
    original_filename text NOT NULL,
    content_type text NOT NULL,
    byte_size bigint NOT NULL,
    checksum_sha256 text,
    issued_at date,
    expires_at date,
    rejection_reason text,
    uploaded_at timestamptz NOT NULL,
    verified_at timestamptz NOT NULL,
    superseded_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT candidate_documents_candidate_scope_fkey
        FOREIGN KEY (candidate_id, station_id, environment_id)
        REFERENCES public.candidates(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT candidate_documents_uploader_environment_fkey
        FOREIGN KEY (uploaded_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT candidate_documents_verifier_environment_fkey
        FOREIGN KEY (verified_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT candidate_documents_kind_check CHECK (kind IN (
        'officialId', 'curp', 'rfc', 'license', 'addressProof', 'photo'
    )),
    CONSTRAINT candidate_documents_status_check CHECK (status IN ('accepted', 'rejected', 'superseded')),
    CONSTRAINT candidate_documents_path_not_blank CHECK (btrim(object_path) <> ''),
    CONSTRAINT candidate_documents_filename_length CHECK (char_length(btrim(original_filename)) BETWEEN 1 AND 255),
    CONSTRAINT candidate_documents_content_type_check CHECK (content_type IN ('application/pdf', 'image/jpeg', 'image/png', 'image/heic')),
    CONSTRAINT candidate_documents_byte_size_check CHECK (byte_size BETWEEN 1 AND 10485760),
    CONSTRAINT candidate_documents_checksum_check CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT candidate_documents_expiry_check CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at),
    CONSTRAINT candidate_documents_rejection_consistent CHECK (
        (status = 'rejected' AND rejection_reason IS NOT NULL)
        OR (status <> 'rejected' AND rejection_reason IS NULL)
    ),
    CONSTRAINT candidate_documents_superseded_consistent CHECK (
        (status = 'superseded' AND superseded_at IS NOT NULL)
        OR (status <> 'superseded' AND superseded_at IS NULL)
    ),
    CONSTRAINT candidate_documents_object_unique UNIQUE (object_path)
);

CREATE UNIQUE INDEX candidate_documents_current_kind_unique
    ON public.candidate_documents(candidate_id, kind)
    WHERE status = 'accepted';
CREATE INDEX candidate_documents_candidate_idx
    ON public.candidate_documents(candidate_id, uploaded_at DESC, id);
CREATE INDEX candidate_documents_station_idx
    ON public.candidate_documents(station_id, status, uploaded_at DESC, id);
CREATE INDEX candidate_documents_uploaded_by_idx ON public.candidate_documents(uploaded_by);
CREATE INDEX candidate_documents_verified_by_idx ON public.candidate_documents(verified_by);

CREATE TABLE public.hirings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    candidate_id uuid NOT NULL,
    signed_by uuid NOT NULL,
    auth_user_id uuid,
    profile_id uuid,
    membership_id uuid,
    driver_profile_id uuid,
    employee_number text NOT NULL,
    shift_group text NOT NULL,
    shift_slot text NOT NULL,
    status text NOT NULL DEFAULT 'identity_pending',
    revision bigint NOT NULL DEFAULT 1,
    failure_code text,
    signed_at timestamptz NOT NULL,
    completed_at timestamptz,
    failed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT hirings_candidate_scope_fkey
        FOREIGN KEY (candidate_id, station_id, environment_id)
        REFERENCES public.candidates(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT hirings_signer_environment_fkey
        FOREIGN KEY (signed_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT hirings_profile_environment_fkey
        FOREIGN KEY (profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT hirings_membership_environment_fkey
        FOREIGN KEY (membership_id, environment_id)
        REFERENCES public.staff_memberships(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT hirings_driver_scope_fkey
        FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT hirings_employee_number_not_blank CHECK (btrim(employee_number) <> ''),
    CONSTRAINT hirings_shift_group_check CHECK (shift_group IN ('weekday', 'weekend')),
    CONSTRAINT hirings_shift_slot_check CHECK (shift_slot IN ('morning', 'evening')),
    CONSTRAINT hirings_status_check CHECK (status IN ('identity_pending', 'completed', 'failed', 'cancelled')),
    CONSTRAINT hirings_revision_positive CHECK (revision > 0),
    CONSTRAINT hirings_failure_code_length CHECK (failure_code IS NULL OR char_length(btrim(failure_code)) BETWEEN 1 AND 100),
    CONSTRAINT hirings_completion_consistent CHECK (
        (status = 'completed' AND auth_user_id IS NOT NULL AND profile_id IS NOT NULL
            AND membership_id IS NOT NULL AND driver_profile_id IS NOT NULL AND completed_at IS NOT NULL)
        OR status <> 'completed'
    ),
    CONSTRAINT hirings_failure_consistent CHECK (
        (status = 'failed' AND failure_code IS NOT NULL AND failed_at IS NOT NULL)
        OR (status <> 'failed' AND failure_code IS NULL AND failed_at IS NULL)
    )
);

CREATE UNIQUE INDEX hirings_active_candidate_unique
    ON public.hirings(candidate_id) WHERE status IN ('identity_pending', 'completed');
CREATE UNIQUE INDEX hirings_environment_employee_unique
    ON public.hirings(environment_id, employee_number) WHERE status IN ('identity_pending', 'completed');
CREATE UNIQUE INDEX hirings_auth_user_unique
    ON public.hirings(auth_user_id) WHERE auth_user_id IS NOT NULL;
CREATE UNIQUE INDEX hirings_profile_unique
    ON public.hirings(profile_id) WHERE profile_id IS NOT NULL;
CREATE INDEX hirings_station_status_idx ON public.hirings(station_id, status, signed_at DESC, id);
CREATE INDEX hirings_signed_by_idx ON public.hirings(signed_by);
CREATE INDEX hirings_membership_idx ON public.hirings(membership_id) WHERE membership_id IS NOT NULL;
CREATE INDEX hirings_driver_profile_idx ON public.hirings(driver_profile_id) WHERE driver_profile_id IS NOT NULL;

ALTER TABLE public.candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hirings ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.candidates, public.candidate_documents, public.hirings
    FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.candidates, public.candidate_documents, public.hirings TO authenticated;
GRANT ALL ON TABLE public.candidates, public.candidate_documents, public.hirings TO postgres, service_role;

-- ---------------------------------------------------------------------
-- 2. Bucket privado e inmutable
-- ---------------------------------------------------------------------

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'candidate-documents', 'candidate-documents', false, 10485760,
    ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/heic']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY candidate_document_objects_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'candidate-documents'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) >= 4
    AND EXISTS (
        SELECT 1
        FROM public.candidates candidate
        WHERE candidate.environment_id::text = (storage.foldername(name))[1]
          AND candidate.station_id::text = (storage.foldername(name))[2]
          AND candidate.id::text = (storage.foldername(name))[3]
          AND candidate.environment_id = app.current_environment_id()
          AND app.auth_has_role('recruitment', candidate.station_id)
    )
);

CREATE POLICY candidate_document_objects_select
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'candidate-documents'
    AND EXISTS (
        SELECT 1
        FROM public.candidate_documents document
        LEFT JOIN public.hirings hiring
          ON hiring.candidate_id = document.candidate_id
         AND hiring.status = 'completed'
        WHERE document.object_path = name
          AND document.status <> 'rejected'
          AND (
              app.auth_has_role('recruitment', document.station_id)
              OR app.auth_has_role('hr', document.station_id)
              OR app.auth_has_region_role('management', document.station_id)
              OR app.auth_has_role('direction')
              OR hiring.profile_id = app.auth_profile_id()
          )
    )
);

-- No UPDATE ni DELETE: cada reemplazo usa una ruta nueva y conserva historia.

-- ---------------------------------------------------------------------
-- 3. Lectura RLS por estacion y por titular
-- ---------------------------------------------------------------------

CREATE POLICY candidates_authorized_read ON public.candidates
FOR SELECT TO authenticated
USING (
    app.auth_has_role('recruitment', station_id)
    OR app.auth_has_role('hr', station_id)
    OR app.auth_has_region_role('management', station_id)
    OR app.auth_has_role('direction')
);

CREATE POLICY candidate_documents_authorized_read ON public.candidate_documents
FOR SELECT TO authenticated
USING (
    app.auth_has_role('recruitment', station_id)
    OR app.auth_has_role('hr', station_id)
    OR app.auth_has_region_role('management', station_id)
    OR app.auth_has_role('direction')
    OR EXISTS (
        SELECT 1 FROM public.hirings hiring
        WHERE hiring.candidate_id = candidate_documents.candidate_id
          AND hiring.status = 'completed'
          AND hiring.profile_id = app.auth_profile_id()
    )
);

CREATE POLICY hirings_authorized_read ON public.hirings
FOR SELECT TO authenticated
USING (
    app.auth_has_role('recruitment', station_id)
    OR app.auth_has_role('hr', station_id)
    OR app.auth_has_region_role('management', station_id)
    OR app.auth_has_role('direction')
    OR profile_id = app.auth_profile_id()
);

-- ---------------------------------------------------------------------
-- 4. Comandos publicos
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.upload_document(
    p_candidate_id uuid,
    p_kind text,
    p_object_path text,
    p_original_filename text,
    p_issued_at date,
    p_expires_at date,
    p_checksum_sha256 text,
    p_idempotency_key text
)
RETURNS public.candidate_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'storage', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor uuid;
    v_environment uuid;
    v_now timestamptz;
    v_candidate public.candidates%ROWTYPE;
    v_document public.candidate_documents%ROWTYPE;
    v_command public.command_log%ROWTYPE;
    v_object storage.objects%ROWTYPE;
    v_request jsonb;
    v_prefix text;
    v_content_type text;
    v_byte_size bigint;
BEGIN
    v_actor := app.auth_profile_id();
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_kind NOT IN ('officialId', 'curp', 'rfc', 'license', 'addressProof', 'photo')
       OR coalesce(btrim(p_object_path), '') = ''
       OR char_length(coalesce(btrim(p_original_filename), '')) NOT BETWEEN 1 AND 255
       OR coalesce(btrim(p_idempotency_key), '') = ''
       OR (p_checksum_sha256 IS NOT NULL AND p_checksum_sha256 !~ '^[0-9a-f]{64}$')
       OR (p_expires_at IS NOT NULL AND p_issued_at IS NOT NULL AND p_expires_at < p_issued_at)
    THEN
        RAISE EXCEPTION 'invalid_document_request' USING ERRCODE = '22023';
    END IF;

    v_environment := app.current_environment_id();
    v_now := app.env_now(v_environment);
    SELECT * INTO v_candidate
    FROM public.candidates
    WHERE id = p_candidate_id AND environment_id = v_environment
    FOR UPDATE;
    IF NOT FOUND OR v_candidate.stage IN ('approved', 'hired', 'lost') THEN
        RAISE EXCEPTION 'open_candidate_required' USING ERRCODE = '22023';
    END IF;
    IF NOT app.auth_has_role('recruitment', v_candidate.station_id) THEN
        RAISE EXCEPTION 'document_upload_forbidden' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object(
        'candidate_id', p_candidate_id,
        'kind', p_kind,
        'object_path', btrim(p_object_path),
        'issued_at', p_issued_at,
        'expires_at', p_expires_at,
        'checksum_sha256', p_checksum_sha256
    );
    SELECT * INTO v_command
    FROM public.command_log
    WHERE environment_id = v_environment
      AND idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'upload_document'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
        THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT * INTO STRICT v_document
        FROM public.candidate_documents
        WHERE id = (v_command.result_payload ->> 'document_id')::uuid;
        RETURN v_document;
    END IF;

    v_prefix := v_environment::text || '/' || v_candidate.station_id::text || '/' || v_candidate.id::text || '/';
    IF left(btrim(p_object_path), char_length(v_prefix)) <> v_prefix
       OR position('/../' IN ('/' || btrim(p_object_path) || '/')) > 0
    THEN
        RAISE EXCEPTION 'document_path_out_of_scope' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_object
    FROM storage.objects
    WHERE bucket_id = 'candidate-documents'
      AND name = btrim(p_object_path)
    FOR UPDATE;
    IF NOT FOUND OR v_object.owner_id IS DISTINCT FROM auth.uid()::text THEN
        RAISE EXCEPTION 'owned_storage_object_required' USING ERRCODE = '22023';
    END IF;
    v_content_type := lower(coalesce(v_object.metadata ->> 'mimetype', ''));
    v_byte_size := coalesce((v_object.metadata ->> 'size')::bigint, 0);
    IF v_content_type NOT IN ('application/pdf', 'image/jpeg', 'image/png', 'image/heic')
       OR v_byte_size NOT BETWEEN 1 AND 10485760
    THEN
        RAISE EXCEPTION 'unsupported_document_object' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.command_log(
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment, v_actor, 'upload_document', btrim(p_idempotency_key),
        'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    UPDATE public.candidate_documents
    SET status = 'superseded', superseded_at = v_now
    WHERE candidate_id = v_candidate.id
      AND kind = p_kind
      AND status = 'accepted';

    INSERT INTO public.candidate_documents(
        environment_id, station_id, candidate_id, uploaded_by, verified_by,
        kind, status, object_path, original_filename, content_type, byte_size,
        checksum_sha256, issued_at, expires_at, uploaded_at, verified_at
    ) VALUES (
        v_environment, v_candidate.station_id, v_candidate.id, v_actor, v_actor,
        p_kind, 'accepted', btrim(p_object_path), btrim(p_original_filename),
        v_content_type, v_byte_size, p_checksum_sha256, p_issued_at, p_expires_at,
        v_now, v_now
    ) RETURNING * INTO v_document;

    UPDATE public.candidates candidate
    SET stage = CASE
            WHEN candidate.screening_status = 'fit'
             AND candidate.interview_decision IN ('recommended', 'conditional')
             AND (
                 SELECT count(DISTINCT document.kind)
                 FROM public.candidate_documents document
                 WHERE document.candidate_id = candidate.id
                   AND document.status = 'accepted'
                   AND (document.expires_at IS NULL OR document.expires_at >= (v_now AT TIME ZONE 'UTC')::date)
             ) = 6
            THEN 'ready_to_hire'
            ELSE 'documents'
        END,
        revision = revision + 1,
        updated_at = now()
    WHERE candidate.id = v_candidate.id;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object('document_id', v_document.id)
    WHERE id = v_command.id;

    INSERT INTO public.audit_log(
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment, v_actor, v_candidate.station_id, v_command.id,
        'candidate_document.uploaded', 'candidate_document', v_document.id,
        jsonb_build_object('candidate_id', v_candidate.id, 'kind', p_kind, 'byte_size', v_byte_size),
        v_now
    );
    RETURN v_document;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sign_hiring(
    p_candidate_id uuid,
    p_employee_number text,
    p_idempotency_key text
)
RETURNS public.hirings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor uuid;
    v_environment uuid;
    v_now timestamptz;
    v_candidate public.candidates%ROWTYPE;
    v_hiring public.hirings%ROWTYPE;
    v_command public.command_log%ROWTYPE;
    v_request jsonb;
    v_employee_number text;
    v_document_count integer;
BEGIN
    v_actor := app.auth_profile_id();
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    v_employee_number := upper(btrim(coalesce(p_employee_number, '')));
    IF char_length(v_employee_number) NOT BETWEEN 3 AND 40
       OR v_employee_number !~ '^[A-Z0-9][A-Z0-9-]*$'
       OR coalesce(btrim(p_idempotency_key), '') = ''
    THEN
        RAISE EXCEPTION 'invalid_hiring_request' USING ERRCODE = '22023';
    END IF;

    v_environment := app.current_environment_id();
    v_now := app.env_now(v_environment);
    SELECT * INTO v_candidate
    FROM public.candidates
    WHERE id = p_candidate_id AND environment_id = v_environment
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'candidate_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT app.auth_has_role('recruitment', v_candidate.station_id) THEN
        RAISE EXCEPTION 'hiring_signature_forbidden' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object('candidate_id', p_candidate_id, 'employee_number', v_employee_number);
    SELECT * INTO v_command
    FROM public.command_log
    WHERE environment_id = v_environment
      AND idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'sign_hiring'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status NOT IN ('accepted', 'completed')
        THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT * INTO STRICT v_hiring
        FROM public.hirings
        WHERE id = (v_command.result_payload ->> 'hiring_id')::uuid;
        RETURN v_hiring;
    END IF;

    IF v_candidate.stage <> 'ready_to_hire'
       OR v_candidate.screening_status <> 'fit'
       OR v_candidate.interview_decision NOT IN ('recommended', 'conditional')
    THEN
        RAISE EXCEPTION 'candidate_not_ready' USING ERRCODE = '22023';
    END IF;
    SELECT count(DISTINCT document.kind)::integer INTO v_document_count
    FROM public.candidate_documents document
    WHERE document.candidate_id = v_candidate.id
      AND document.status = 'accepted'
      AND (document.expires_at IS NULL OR document.expires_at >= (v_now AT TIME ZONE 'UTC')::date);
    IF v_document_count <> 6 THEN
        RAISE EXCEPTION 'candidate_documents_incomplete' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.profiles WHERE employee_number = v_employee_number) THEN
        RAISE EXCEPTION 'employee_number_already_exists' USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.command_log(
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment, v_actor, 'sign_hiring', btrim(p_idempotency_key),
        'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    INSERT INTO public.hirings(
        environment_id, station_id, candidate_id, signed_by, employee_number,
        shift_group, shift_slot, status, signed_at
    ) VALUES (
        v_environment, v_candidate.station_id, v_candidate.id, v_actor,
        v_employee_number, v_candidate.requested_shift_group,
        v_candidate.requested_shift_slot, 'identity_pending', v_now
    ) RETURNING * INTO v_hiring;

    UPDATE public.candidates
    SET stage = 'approved', revision = revision + 1, updated_at = now()
    WHERE id = v_candidate.id;
    UPDATE public.command_log
    SET result_payload = jsonb_build_object('hiring_id', v_hiring.id)
    WHERE id = v_command.id;
    INSERT INTO public.audit_log(
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment, v_actor, v_candidate.station_id, v_command.id,
        'hiring.signed', 'hiring', v_hiring.id,
        jsonb_build_object('candidate_id', v_candidate.id, 'employee_number', v_employee_number),
        v_now
    );
    RETURN v_hiring;
END;
$function$;

-- ---------------------------------------------------------------------
-- 5. Finalizacion privilegiada desde la Edge Function
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.complete_hiring(
    p_hiring_id uuid,
    p_auth_user_id uuid
)
RETURNS public.hirings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_hiring public.hirings%ROWTYPE;
    v_candidate public.candidates%ROWTYPE;
    v_profile_id uuid := gen_random_uuid();
    v_membership_id uuid := gen_random_uuid();
    v_driver_profile_id uuid := gen_random_uuid();
    v_auth_email text;
    v_now timestamptz;
    v_command_id uuid;
BEGIN
    IF current_user NOT IN ('postgres', 'service_role') THEN
        RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_hiring FROM public.hirings WHERE id = p_hiring_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'hiring_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_hiring.status = 'completed' THEN
        IF v_hiring.auth_user_id IS DISTINCT FROM p_auth_user_id THEN
            RAISE EXCEPTION 'hiring_identity_conflict' USING ERRCODE = '23505';
        END IF;
        RETURN v_hiring;
    END IF;
    IF v_hiring.status <> 'identity_pending' THEN
        RAISE EXCEPTION 'pending_hiring_required' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO STRICT v_candidate FROM public.candidates WHERE id = v_hiring.candidate_id FOR UPDATE;
    SELECT lower(email) INTO v_auth_email FROM auth.users WHERE id = p_auth_user_id;
    IF v_auth_email IS NULL OR v_auth_email <> lower(v_candidate.email) THEN
        RAISE EXCEPTION 'matching_auth_identity_required' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.profiles WHERE auth_user_id = p_auth_user_id) THEN
        RAISE EXCEPTION 'auth_identity_already_linked' USING ERRCODE = '23505';
    END IF;
    v_now := app.env_now(v_hiring.environment_id);

    INSERT INTO public.profiles(
        id, environment_id, auth_user_id, employee_number, display_name,
        status
    ) VALUES (
        v_profile_id, v_hiring.environment_id, p_auth_user_id,
        v_hiring.employee_number, v_candidate.full_name,
        'active'
    );
    INSERT INTO public.staff_memberships(
        id, environment_id, profile_id, station_id, role, starts_at,
        shift_group, shift_slot
    ) VALUES (
        v_membership_id, v_hiring.environment_id, v_profile_id,
        v_hiring.station_id, 'driver', v_now,
        v_hiring.shift_group, v_hiring.shift_slot
    );
    INSERT INTO public.driver_profiles(
        id, environment_id, station_id, profile_id, membership_id,
        employee_number, legacy_code, status
    ) VALUES (
        v_driver_profile_id, v_hiring.environment_id, v_hiring.station_id,
        v_profile_id, v_membership_id, v_hiring.employee_number,
        v_hiring.employee_number, 'active'
    );

    UPDATE public.hirings
    SET auth_user_id = p_auth_user_id,
        profile_id = v_profile_id,
        membership_id = v_membership_id,
        driver_profile_id = v_driver_profile_id,
        status = 'completed',
        revision = revision + 1,
        completed_at = v_now,
        updated_at = now()
    WHERE id = v_hiring.id
    RETURNING * INTO v_hiring;
    UPDATE public.candidates
    SET stage = 'hired', hired_at = v_now, revision = revision + 1, updated_at = now()
    WHERE id = v_candidate.id;
    SELECT id INTO v_command_id
    FROM public.command_log
    WHERE environment_id = v_hiring.environment_id
      AND command_name = 'sign_hiring'
      AND result_payload ->> 'hiring_id' = v_hiring.id::text
    FOR UPDATE;
    UPDATE public.command_log
    SET status = 'completed',
        result_payload = result_payload || jsonb_build_object(
            'profile_id', v_profile_id,
            'membership_id', v_membership_id,
            'driver_profile_id', v_driver_profile_id
        )
    WHERE id = v_command_id;
    INSERT INTO public.audit_log(
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_hiring.environment_id, v_hiring.signed_by, v_hiring.station_id, v_command_id,
        'hiring.completed', 'hiring', v_hiring.id,
        jsonb_build_object('profile_id', v_profile_id, 'employee_number', v_hiring.employee_number),
        v_now
    );
    RETURN v_hiring;
END;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_hiring_auth_user(p_hiring_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_auth_user_id uuid;
BEGIN
    IF current_user NOT IN ('postgres', 'service_role') THEN
        RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
    END IF;
    SELECT auth_user.id INTO v_auth_user_id
    FROM public.hirings hiring
    JOIN public.candidates candidate ON candidate.id = hiring.candidate_id
    JOIN auth.users auth_user ON lower(auth_user.email) = lower(candidate.email)
    WHERE hiring.id = p_hiring_id
      AND hiring.status IN ('identity_pending', 'completed');
    IF v_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'hiring_auth_identity_not_found' USING ERRCODE = 'P0002';
    END IF;
    RETURN v_auth_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fail_hiring(
    p_hiring_id uuid,
    p_failure_code text
)
RETURNS public.hirings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
DECLARE
    v_hiring public.hirings%ROWTYPE;
    v_now timestamptz;
    v_command_id uuid;
BEGIN
    IF current_user NOT IN ('postgres', 'service_role') THEN
        RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
    END IF;
    IF char_length(coalesce(btrim(p_failure_code), '')) NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'failure_code_required' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_hiring FROM public.hirings WHERE id = p_hiring_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'hiring_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_hiring.status <> 'identity_pending' THEN
        RAISE EXCEPTION 'pending_hiring_required' USING ERRCODE = '22023';
    END IF;
    v_now := app.env_now(v_hiring.environment_id);
    UPDATE public.hirings
    SET status = 'failed', failure_code = btrim(p_failure_code),
        failed_at = v_now, revision = revision + 1, updated_at = now()
    WHERE id = v_hiring.id
    RETURNING * INTO v_hiring;
    UPDATE public.candidates
    SET stage = 'ready_to_hire', revision = revision + 1, updated_at = now()
    WHERE id = v_hiring.candidate_id;
    UPDATE public.command_log
    SET status = 'rejected',
        result_payload = result_payload || jsonb_build_object('failure_code', btrim(p_failure_code))
    WHERE environment_id = v_hiring.environment_id
      AND command_name = 'sign_hiring'
      AND result_payload ->> 'hiring_id' = v_hiring.id::text
    RETURNING id INTO v_command_id;
    INSERT INTO public.audit_log(
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_hiring.environment_id, v_hiring.signed_by, v_hiring.station_id, v_command_id,
        'hiring.failed', 'hiring', v_hiring.id,
        jsonb_build_object('failure_code', btrim(p_failure_code)), v_now
    );
    RETURN v_hiring;
END;
$function$;

-- ---------------------------------------------------------------------
-- 6. Vistas, mantenimiento y privilegios
-- ---------------------------------------------------------------------

CREATE VIEW public.candidate_document_current
WITH (security_invoker = true)
AS
SELECT * FROM public.candidate_documents WHERE status = 'accepted';

GRANT SELECT ON public.candidate_document_current TO authenticated, service_role;

CREATE TRIGGER candidates_touch
BEFORE UPDATE ON public.candidates
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER hirings_touch
BEFORE UPDATE ON public.hirings
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

REVOKE ALL ON FUNCTION public.upload_document(uuid,text,text,text,date,date,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sign_hiring(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upload_document(uuid,text,text,text,date,date,text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sign_hiring(uuid,text,text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.complete_hiring(uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_hiring_auth_user(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fail_hiring(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_hiring(uuid,uuid) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_hiring_auth_user(uuid) TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.fail_hiring(uuid,text) TO postgres, service_role;

COMMENT ON TABLE public.candidates IS '15H: candidatos del proceso autoritativo, aislados por entorno y estacion.';
COMMENT ON TABLE public.candidate_documents IS '15H: metadatos versionados de archivos privados; los objetos viven en Storage.';
COMMENT ON TABLE public.hirings IS '15H: saga de alta; firma transaccional y enlace posterior con Supabase Auth.';
COMMENT ON FUNCTION public.sign_hiring(uuid,text,text) IS 'Firma el alta y reserva identidad; una Edge Function completa Auth y las filas laborales.';
