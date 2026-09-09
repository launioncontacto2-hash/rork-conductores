-- storage.foldername() returns only the directory components, excluding the file.
-- The documented acquisition path has three folders:
-- <environment>/<supplier>/<offer>/<file>.
DROP POLICY IF EXISTS acquisition_evidence_objects_insert ON storage.objects;

CREATE POLICY acquisition_evidence_objects_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'acquisition-evidence'
    AND owner_id = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) = 3
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND (storage.foldername(name))[2] = app.auth_acquisition_supplier_id()::text
    AND (storage.foldername(name))[3] ~ '^[0-9a-f-]{36}$'
);
