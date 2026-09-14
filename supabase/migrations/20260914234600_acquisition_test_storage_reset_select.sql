-- La API de Storage exige SELECT ademas de DELETE para retirar objetos.
-- Esta politica permite que un administrador DORI vea exclusivamente los
-- objetos de Adquisicion del mismo environment TEST, incluidos los que hayan
-- quedado sin fila relacional tras una prueba interrumpida.

DROP POLICY IF EXISTS acquisition_test_objects_reset_select
ON storage.objects;

CREATE POLICY acquisition_test_objects_reset_select
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id IN ('acquisition-evidence', 'acquisition-chat-attachments')
    AND (storage.foldername(name))[1] = app.current_environment_id()::text
    AND app.auth_is_acquisition_admin()
    AND EXISTS (
        SELECT 1
        FROM public.environments environment
        WHERE environment.id = app.current_environment_id()
          AND environment.code = 'test'
    )
);
