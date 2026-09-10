-- El reloj de negocio puede estar congelado en TEST, por lo que created_at no
-- determina por sí solo cuál contraoferta fue registrada al final.
ALTER TABLE public.acquisition_negotiations
    ADD COLUMN event_sequence bigint GENERATED ALWAYS AS IDENTITY;

CREATE UNIQUE INDEX acquisition_negotiations_event_sequence_unique
    ON public.acquisition_negotiations(event_sequence);

DROP INDEX public.acquisition_negotiations_offer_idx;
CREATE INDEX acquisition_negotiations_offer_idx
    ON public.acquisition_negotiations(environment_id, offer_id, event_sequence);

DO $migration$
DECLARE
    v_signature regprocedure :=
        'public.respond_acquisition_offer(uuid,text,numeric,text,text)'::regprocedure;
    v_definition text;
    v_updated_definition text;
    v_old_order constant text :=
        'ORDER BY negotiation.created_at DESC, negotiation.id DESC LIMIT 1;';
    v_new_order constant text :=
        'ORDER BY negotiation.event_sequence DESC LIMIT 1;';
BEGIN
    SELECT pg_get_functiondef(v_signature) INTO STRICT v_definition;
    v_updated_definition := replace(v_definition, v_old_order, v_new_order);

    IF v_updated_definition = v_definition THEN
        RAISE EXCEPTION 'respond_acquisition_offer_order_clause_not_found';
    END IF;

    EXECUTE v_updated_definition;
END;
$migration$;

COMMENT ON COLUMN public.acquisition_negotiations.event_sequence IS
    'Orden transaccional estable; evita desempatar contraofertas por UUID cuando el reloj TEST esta congelado.';
