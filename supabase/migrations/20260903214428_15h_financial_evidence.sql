-- =====================================================================
-- TurnoEV · 15H · Evidencia financiera privada
--
-- Los comprobantes se suben primero a Storage. El registro financiero
-- solo acepta una ruta propia, dentro del entorno/estacion/conductor que
-- el RPC ya autorizo. No existen UPDATE ni DELETE para clientes.
-- =====================================================================

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'financial-evidence', 'financial-evidence', false, 10485760,
    ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/heic']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY financial_evidence_objects_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'financial-evidence'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) >= 4
    AND EXISTS (
        SELECT 1
        FROM public.driver_profiles driver
        WHERE driver.environment_id::text = (storage.foldername(name))[1]
          AND driver.station_id::text = (storage.foldername(name))[2]
          AND driver.id::text = (storage.foldername(name))[3]
          AND driver.environment_id = app.current_environment_id()
          AND driver.profile_id = app.auth_profile_id()
          AND driver.status = 'active'
          AND app.auth_has_role('driver', driver.station_id)
    )
);

CREATE POLICY financial_evidence_objects_select
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'financial-evidence'
    AND EXISTS (
        SELECT 1
        FROM public.driver_profiles driver
        WHERE driver.environment_id::text = (storage.foldername(name))[1]
          AND driver.station_id::text = (storage.foldername(name))[2]
          AND driver.id::text = (storage.foldername(name))[3]
          AND driver.environment_id = app.current_environment_id()
          AND (
              driver.profile_id = app.auth_profile_id()
              OR app.auth_has_role('supervisor', driver.station_id)
              OR app.auth_has_region_role('management', driver.station_id)
              OR app.auth_has_role('direction')
          )
    )
);

-- No UPDATE ni DELETE: una correccion financiera emite un asiento nuevo y
-- conserva la evidencia original.

CREATE OR REPLACE FUNCTION app.validate_financial_evidence_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'storage', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_object storage.objects%ROWTYPE;
    v_prefix text;
    v_content_type text;
    v_byte_size bigint;
BEGIN
    IF NEW.evidence_path IS NULL AND TG_TABLE_NAME = 'incomes' THEN
        RETURN NEW;
    END IF;
    IF coalesce(btrim(NEW.evidence_path), '') = '' THEN
        RAISE EXCEPTION 'financial_evidence_required' USING ERRCODE = '22023';
    END IF;

    v_prefix := NEW.environment_id::text || '/' || NEW.station_id::text || '/' ||
        NEW.driver_profile_id::text || '/';
    IF left(btrim(NEW.evidence_path), char_length(v_prefix)) <> v_prefix
       OR position('/../' IN ('/' || btrim(NEW.evidence_path) || '/')) > 0
    THEN
        RAISE EXCEPTION 'financial_evidence_path_out_of_scope' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_object
    FROM storage.objects
    WHERE bucket_id = 'financial-evidence'
      AND name = btrim(NEW.evidence_path);
    IF NOT FOUND OR v_object.owner_id IS DISTINCT FROM auth.uid()::text THEN
        RAISE EXCEPTION 'owned_financial_evidence_required' USING ERRCODE = '22023';
    END IF;

    v_content_type := lower(coalesce(v_object.metadata ->> 'mimetype', ''));
    v_byte_size := coalesce((v_object.metadata ->> 'size')::bigint, 0);
    IF v_content_type NOT IN ('application/pdf', 'image/jpeg', 'image/png', 'image/heic')
       OR v_byte_size NOT BETWEEN 1 AND 10485760
    THEN
        RAISE EXCEPTION 'unsupported_financial_evidence' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION app.validate_financial_evidence_insert() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app.validate_financial_evidence_insert() TO postgres, service_role;

CREATE TRIGGER incomes_validate_financial_evidence
BEFORE INSERT ON public.incomes
FOR EACH ROW EXECUTE FUNCTION app.validate_financial_evidence_insert();

CREATE TRIGGER cash_deposits_validate_financial_evidence
BEFORE INSERT ON public.cash_deposits
FOR EACH ROW EXECUTE FUNCTION app.validate_financial_evidence_insert();

COMMENT ON FUNCTION app.validate_financial_evidence_insert() IS
    '15H: exige que la evidencia financiera del cliente exista, sea propia y permanezca dentro de su alcance.';
