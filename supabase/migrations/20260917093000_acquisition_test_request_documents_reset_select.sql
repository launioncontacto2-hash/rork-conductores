-- Storage exige SELECT ademas de DELETE para retirar objetos. La politica de
-- limpieza TEST original antecede al bucket de documentos de solicitudes y no
-- lo incluia, por lo que un PDF huérfano no podia eliminarse con la API.

DROP POLICY IF EXISTS acquisition_test_objects_reset_select
ON storage.objects;

CREATE POLICY acquisition_test_objects_reset_select
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id IN (
        'acquisition-evidence',
        'acquisition-chat-attachments',
        'acquisition-request-documents'
    )
    AND (storage.foldername(name))[1] = (SELECT app.current_environment_id())::text
    AND (SELECT app.auth_is_acquisition_admin())
    AND EXISTS (
        SELECT 1
        FROM public.environments environment
        WHERE environment.id = (SELECT app.current_environment_id())
          AND environment.code = 'test'
    )
);



