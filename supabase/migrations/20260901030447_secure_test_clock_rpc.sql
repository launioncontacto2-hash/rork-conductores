-- =====================================================================
-- TurnoEV · 15D · Reloj TEST autenticado
--
-- La linea base 20260829185653 revoco EXECUTE a authenticated sobre
-- update_test_clock. La app podia leer el reloj, pero cada cambio era
-- rechazado y el refresh posterior restauraba el valor anterior.
--
-- El RPC publico queda como SECURITY INVOKER. La escritura privilegiada
-- vive en app (esquema no expuesto) y vuelve a comprobar identidad, rol y
-- entorno antes de tocar la fila protegida.
-- =====================================================================

CREATE OR REPLACE FUNCTION app.update_test_clock_authorized(
    p_environment_id uuid,
    p_anchor_simulated_at timestamptz,
    p_anchor_real_at timestamptz,
    p_speed double precision,
    p_is_paused boolean,
    p_expected_revision bigint DEFAULT NULL
)
RETURNS public.test_clock
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_environment_id uuid;
    v_environment_code text;
    v_current_revision bigint;
    v_row public.test_clock%ROWTYPE;
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication_required'
            USING ERRCODE = '42501';
    END IF;

    v_environment_id := app.current_environment_id();

    IF p_environment_id IS DISTINCT FROM v_environment_id THEN
        RAISE EXCEPTION 'clock_environment_outside_session'
            USING ERRCODE = '42501';
    END IF;

    SELECT e.code
      INTO v_environment_code
      FROM public.environments e
     WHERE e.id = p_environment_id;

    IF v_environment_code IS NULL THEN
        RAISE EXCEPTION 'environment_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_environment_code <> 'test' THEN
        RAISE EXCEPTION 'environment_not_test'
            USING ERRCODE = '42501';
    END IF;

    IF NOT app.auth_has_role('supervisor') THEN
        RAISE EXCEPTION 'supervisor_role_required_for_test_clock'
            USING ERRCODE = '42501';
    END IF;

    IF p_speed IS NULL OR p_speed <= 0 THEN
        RAISE EXCEPTION 'speed_must_be_positive'
            USING ERRCODE = '22023';
    END IF;

    IF p_anchor_simulated_at IS NULL
       OR p_anchor_real_at IS NULL
       OR p_is_paused IS NULL THEN
        RAISE EXCEPTION 'anchor_incomplete'
            USING ERRCODE = '22023';
    END IF;

    SELECT c.revision
      INTO v_current_revision
      FROM public.test_clock c
     WHERE c.environment_id = p_environment_id
     FOR UPDATE;

    IF v_current_revision IS NULL THEN
        RAISE EXCEPTION 'clock_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF p_expected_revision IS NOT NULL
       AND p_expected_revision <> v_current_revision THEN
        RAISE EXCEPTION 'revision_conflict expected=% current=%',
            p_expected_revision, v_current_revision
            USING ERRCODE = '40001';
    END IF;

    UPDATE public.test_clock c
       SET anchor_simulated_at = p_anchor_simulated_at,
           anchor_real_at = p_anchor_real_at,
           speed = p_speed,
           is_paused = p_is_paused,
           revision = c.revision + 1
     WHERE c.environment_id = p_environment_id
    RETURNING c.* INTO v_row;

    RETURN v_row;
END;
$function$;

REVOKE ALL ON FUNCTION app.update_test_clock_authorized(
    uuid, timestamptz, timestamptz, double precision, boolean, bigint
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION app.update_test_clock_authorized(
    uuid, timestamptz, timestamptz, double precision, boolean, bigint
) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_test_clock(
    p_environment_id uuid,
    p_anchor_simulated_at timestamptz,
    p_anchor_real_at timestamptz,
    p_speed double precision,
    p_is_paused boolean,
    p_expected_revision bigint DEFAULT NULL
)
RETURNS public.test_clock
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
    SELECT app.update_test_clock_authorized(
        p_environment_id,
        p_anchor_simulated_at,
        p_anchor_real_at,
        p_speed,
        p_is_paused,
        p_expected_revision
    );
$function$;

COMMENT ON FUNCTION public.update_test_clock(
    uuid, timestamptz, timestamptz, double precision, boolean, bigint
) IS
    'Actualiza el reloj TEST con revision optimista. Exige una sesion autenticada y una membresia vigente de supervisor en el entorno actual.';

REVOKE ALL ON FUNCTION public.update_test_clock(
    uuid, timestamptz, timestamptz, double precision, boolean, bigint
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.update_test_clock(
    uuid, timestamptz, timestamptz, double precision, boolean, bigint
) TO authenticated;
