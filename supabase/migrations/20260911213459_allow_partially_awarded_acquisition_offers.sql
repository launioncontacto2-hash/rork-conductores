-- Una solicitud sigue aceptando unidades mientras no alcance su cantidad
-- objetivo. La adjudicacion de la primera unidad cambia el estado a
-- partially_awarded; ese estado debe conservar el mismo contrato de captura
-- que published/evaluating.
DO $migration$
DECLARE
    v_signature regprocedure :=
        'public.submit_acquisition_offer(uuid,uuid,text,text,text,integer,integer,numeric,text,numeric,boolean,jsonb,text)'::regprocedure;
    v_definition text;
    v_updated_definition text;
    v_old_filter constant text :=
        'request.status IN (''published'', ''evaluating'')';
    v_new_filter constant text :=
        'request.status IN (''published'', ''evaluating'', ''partially_awarded'')';
BEGIN
    SELECT pg_get_functiondef(v_signature) INTO STRICT v_definition;
    v_updated_definition := replace(v_definition, v_old_filter, v_new_filter);

    IF v_updated_definition = v_definition THEN
        RAISE EXCEPTION 'submit_acquisition_offer_status_filter_not_found';
    END IF;

    EXECUTE v_updated_definition;
END;
$migration$;

COMMENT ON FUNCTION public.submit_acquisition_offer(
    uuid, uuid, text, text, text, integer, integer, numeric,
    text, numeric, boolean, jsonb, text
) IS
    'Envia una unidad con evidencia privada mientras la solicitud siga abierta o parcialmente adjudicada.';
