-- DORI 4B-1: recruitment is the sole operational HR identity.
-- Historical hr memberships remain valid data, but no longer authorize access.

DROP POLICY IF EXISTS candidates_authorized_read ON public.candidates;
CREATE POLICY candidates_authorized_read ON public.candidates
FOR SELECT TO authenticated
USING (
    app.auth_has_role('recruitment', station_id)
    OR app.auth_has_region_role('management', station_id)
    OR app.auth_has_role('direction')
);

DROP POLICY IF EXISTS candidate_documents_authorized_read ON public.candidate_documents;
CREATE POLICY candidate_documents_authorized_read ON public.candidate_documents
FOR SELECT TO authenticated
USING (
    app.auth_has_role('recruitment', station_id)
    OR app.auth_has_region_role('management', station_id)
    OR app.auth_has_role('direction')
    OR EXISTS (
        SELECT 1 FROM public.hirings hiring
        WHERE hiring.candidate_id = candidate_documents.candidate_id
          AND hiring.status = 'completed'
          AND hiring.profile_id = app.auth_profile_id()
    )
);

DROP POLICY IF EXISTS hirings_authorized_read ON public.hirings;
CREATE POLICY hirings_authorized_read ON public.hirings
FOR SELECT TO authenticated
USING (
    app.auth_has_role('recruitment', station_id)
    OR app.auth_has_region_role('management', station_id)
    OR app.auth_has_role('direction')
    OR profile_id = app.auth_profile_id()
);

DROP POLICY IF EXISTS candidate_document_objects_select ON storage.objects;
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
              OR app.auth_has_region_role('management', document.station_id)
              OR app.auth_has_role('direction')
              OR hiring.profile_id = app.auth_profile_id()
          )
    )
);

CREATE OR REPLACE FUNCTION app.dori_station_role_local_part(
    p_role text,
    p_station_code text
)
RETURNS text
LANGUAGE plpgsql
STABLE
STRICT
SET search_path TO 'pg_catalog', 'app', 'pg_temp'
AS $$
DECLARE
    v_prefix text;
    v_code text := lower(btrim(p_station_code));
BEGIN
    v_prefix := CASE p_role
        WHEN 'supervisor' THEN 'supervision'
        WHEN 'recruitment' THEN 'reclutamiento'
        WHEN 'management' THEN 'gerencia'
        WHEN 'direction' THEN 'direccion'
        ELSE NULL
    END;

    IF v_prefix IS NULL THEN
        RAISE EXCEPTION 'dori_station_identity_role_invalid'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app.station_identity_codes catalog
        WHERE catalog.code = v_code AND catalog.status = 'active'
    ) THEN
        RAISE EXCEPTION 'dori_station_identity_code_invalid'
            USING ERRCODE = '22023';
    END IF;

    RETURN v_prefix || '.' || v_code;
END;
$$;

REVOKE ALL ON FUNCTION app.dori_station_role_local_part(text, text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.dori_station_role_local_part(text, text)
TO postgres, service_role;
