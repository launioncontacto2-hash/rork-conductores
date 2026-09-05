-- =====================================================================
-- TurnoEV · 15F · Ausencias, vacantes y competencia por guardias
--
-- Autoridad:
--   - absences conserva la solicitud y su resolucion supervisora
--   - coverage_vacancies conserva la plaza ofrecida
--   - coverage_claims conserva al ganador de la exclusion global
--   - toda escritura del cliente cruza una RPC autenticada e idempotente
-- =====================================================================

CREATE TABLE public.absences (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    vacancy_id uuid,
    resolved_by uuid,
    folio text NOT NULL DEFAULT (
        'AUS-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
    ),
    operating_date date NOT NULL,
    shift_group text NOT NULL,
    shift_slot text NOT NULL,
    kind text NOT NULL,
    reason text NOT NULL,
    comments text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'searching',
    decision_note text,
    revision bigint NOT NULL DEFAULT 1,
    requested_at timestamptz NOT NULL,
    decided_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT absences_driver_scope_fkey
        FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT absences_resolver_environment_fkey
        FOREIGN KEY (resolved_by, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT absences_id_station_environment_unique
        UNIQUE (id, station_id, environment_id),
    CONSTRAINT absences_environment_folio_unique
        UNIQUE (environment_id, folio),
    CONSTRAINT absences_folio_not_blank CHECK (btrim(folio) <> ''),
    CONSTRAINT absences_group_check
        CHECK (shift_group IN ('weekday', 'weekend')),
    CONSTRAINT absences_slot_check
        CHECK (shift_slot IN ('morning', 'evening')),
    CONSTRAINT absences_kind_check
        CHECK (kind IN ('scheduled', 'emergency', 'leave', 'other')),
    CONSTRAINT absences_reason_length
        CHECK (char_length(btrim(reason)) BETWEEN 3 AND 1000),
    CONSTRAINT absences_comments_length
        CHECK (char_length(comments) <= 2000),
    CONSTRAINT absences_status_check CHECK (
        status IN (
            'searching', 'covered', 'awaiting_authorization',
            'approved', 'rejected', 'cancelled', 'uncovered'
        )
    ),
    CONSTRAINT absences_revision_positive CHECK (revision > 0),
    CONSTRAINT absences_decision_fields_consistent CHECK (
        (
            status IN ('approved', 'rejected')
            AND resolved_by IS NOT NULL
            AND decided_at IS NOT NULL
        )
        OR (
            status NOT IN ('approved', 'rejected')
            AND resolved_by IS NULL
            AND decided_at IS NULL
        )
    )
);

CREATE UNIQUE INDEX absences_open_driver_slot_unique
    ON public.absences(driver_profile_id, operating_date, shift_slot)
    WHERE status IN (
        'searching', 'covered', 'awaiting_authorization', 'approved'
    );
CREATE INDEX absences_station_date_idx
    ON public.absences(station_id, operating_date, requested_at DESC, id);
CREATE INDEX absences_driver_requested_idx
    ON public.absences(driver_profile_id, requested_at DESC, id);
CREATE INDEX absences_resolved_by_idx
    ON public.absences(resolved_by)
    WHERE resolved_by IS NOT NULL;

CREATE TABLE public.coverage_vacancies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    absence_id uuid,
    opened_by uuid NOT NULL,
    titular_driver_profile_id uuid,
    vehicle_id uuid,
    approved_by uuid,
    folio text NOT NULL DEFAULT (
        'VAC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
    ),
    operating_date date NOT NULL,
    shift_group text NOT NULL,
    shift_slot text NOT NULL,
    origin text NOT NULL,
    bonus_mode text NOT NULL DEFAULT 'none',
    bonus_mxn integer NOT NULL DEFAULT 0,
    reason text NOT NULL,
    status text NOT NULL DEFAULT 'searching',
    is_critical boolean NOT NULL DEFAULT false,
    revision bigint NOT NULL DEFAULT 1,
    opened_at timestamptz NOT NULL,
    claimed_at timestamptz,
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT coverage_vacancies_absence_scope_fkey
        FOREIGN KEY (absence_id, station_id, environment_id)
        REFERENCES public.absences(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT coverage_vacancies_opener_environment_fkey
        FOREIGN KEY (opened_by, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT coverage_vacancies_titular_scope_fkey
        FOREIGN KEY (titular_driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT coverage_vacancies_vehicle_scope_fkey
        FOREIGN KEY (vehicle_id, station_id, environment_id)
        REFERENCES public.vehicles(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT coverage_vacancies_approver_environment_fkey
        FOREIGN KEY (approved_by, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT coverage_vacancies_id_station_environment_unique
        UNIQUE (id, station_id, environment_id),
    CONSTRAINT coverage_vacancies_environment_folio_unique
        UNIQUE (environment_id, folio),
    CONSTRAINT coverage_vacancies_absence_unique UNIQUE (absence_id),
    CONSTRAINT coverage_vacancies_folio_not_blank CHECK (btrim(folio) <> ''),
    CONSTRAINT coverage_vacancies_group_check
        CHECK (shift_group IN ('weekday', 'weekend')),
    CONSTRAINT coverage_vacancies_slot_check
        CHECK (shift_slot IN ('morning', 'evening')),
    CONSTRAINT coverage_vacancies_origin_check
        CHECK (origin IN ('absence', 'extraordinary', 'cancellation')),
    CONSTRAINT coverage_vacancies_bonus_mode_check
        CHECK (bonus_mode IN ('fixed', 'variable', 'none')),
    CONSTRAINT coverage_vacancies_bonus_nonnegative CHECK (bonus_mxn >= 0),
    CONSTRAINT coverage_vacancies_bonus_consistent CHECK (
        (bonus_mode = 'none' AND bonus_mxn = 0)
        OR (bonus_mode <> 'none' AND bonus_mxn > 0)
    ),
    CONSTRAINT coverage_vacancies_reason_length
        CHECK (char_length(btrim(reason)) BETWEEN 3 AND 1000),
    CONSTRAINT coverage_vacancies_status_check CHECK (
        status IN (
            'searching', 'reserved', 'confirmed', 'uncovered',
            'cancelled', 'completed', 'no_show'
        )
    ),
    CONSTRAINT coverage_vacancies_revision_positive CHECK (revision > 0),
    CONSTRAINT coverage_vacancies_absence_origin_consistent CHECK (
        (origin = 'absence' AND absence_id IS NOT NULL AND titular_driver_profile_id IS NOT NULL)
        OR (origin <> 'absence' AND absence_id IS NULL)
    ),
    CONSTRAINT coverage_vacancies_claim_fields_consistent CHECK (
        (status = 'searching' AND claimed_at IS NULL)
        OR (status <> 'searching')
    ),
    CONSTRAINT coverage_vacancies_approval_fields_consistent CHECK (
        (
            status IN ('confirmed', 'completed', 'no_show')
            AND approved_by IS NOT NULL
            AND approved_at IS NOT NULL
        )
        OR status NOT IN ('confirmed', 'completed', 'no_show')
    )
);

ALTER TABLE public.absences
    ADD CONSTRAINT absences_vacancy_scope_fkey
    FOREIGN KEY (vacancy_id, station_id, environment_id)
    REFERENCES public.coverage_vacancies(id, station_id, environment_id)
    ON DELETE RESTRICT;

CREATE INDEX coverage_vacancies_station_open_idx
    ON public.coverage_vacancies(station_id, status, operating_date, id);
CREATE INDEX coverage_vacancies_titular_date_idx
    ON public.coverage_vacancies(titular_driver_profile_id, operating_date, id);
CREATE INDEX coverage_vacancies_opened_by_idx
    ON public.coverage_vacancies(opened_by);
CREATE INDEX coverage_vacancies_vehicle_idx
    ON public.coverage_vacancies(vehicle_id)
    WHERE vehicle_id IS NOT NULL;
CREATE INDEX coverage_vacancies_approved_by_idx
    ON public.coverage_vacancies(approved_by)
    WHERE approved_by IS NOT NULL;

CREATE TABLE public.coverage_claims (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    vacancy_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'won',
    operating_date date NOT NULL,
    shift_slot text NOT NULL,
    note text,
    claimed_at timestamptz NOT NULL,
    decided_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT coverage_claims_vacancy_scope_fkey
        FOREIGN KEY (vacancy_id, station_id, environment_id)
        REFERENCES public.coverage_vacancies(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT coverage_claims_driver_scope_fkey
        FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id)
        ON DELETE RESTRICT,
    CONSTRAINT coverage_claims_status_check
        CHECK (status IN ('won', 'approved', 'rejected', 'cancelled', 'expired')),
    CONSTRAINT coverage_claims_slot_check
        CHECK (shift_slot IN ('morning', 'evening')),
    CONSTRAINT coverage_claims_note_length
        CHECK (note IS NULL OR char_length(btrim(note)) BETWEEN 3 AND 1000),
    CONSTRAINT coverage_claims_decision_fields_consistent CHECK (
        (status = 'won' AND decided_at IS NULL)
        OR (status <> 'won' AND decided_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX coverage_claims_winner_unique
    ON public.coverage_claims(vacancy_id)
    WHERE status IN ('won', 'approved');
CREATE UNIQUE INDEX coverage_claims_driver_slot_unique
    ON public.coverage_claims(driver_profile_id, operating_date, shift_slot)
    WHERE status IN ('won', 'approved');
CREATE INDEX coverage_claims_vacancy_claimed_idx
    ON public.coverage_claims(vacancy_id, claimed_at, id);
CREATE INDEX coverage_claims_driver_claimed_idx
    ON public.coverage_claims(driver_profile_id, claimed_at DESC, id);
CREATE INDEX coverage_claims_station_claimed_idx
    ON public.coverage_claims(station_id, claimed_at DESC, id);

ALTER TABLE public.absences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coverage_vacancies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coverage_claims ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.absences, public.coverage_vacancies,
    public.coverage_claims FROM anon, authenticated;
GRANT ALL ON TABLE public.absences, public.coverage_vacancies,
    public.coverage_claims TO postgres, service_role;

CREATE TRIGGER absences_touch
BEFORE UPDATE ON public.absences
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TRIGGER coverage_vacancies_touch
BEFORE UPDATE ON public.coverage_vacancies
FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE POLICY absences_authorized_read
ON public.absences FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.driver_profiles dp
        WHERE dp.id = driver_profile_id
          AND dp.profile_id = (SELECT app.auth_profile_id())
    )
    OR app.auth_has_role('supervisor', station_id)
    OR app.auth_has_role('management', station_id)
);

CREATE POLICY coverage_vacancies_authorized_read
ON public.coverage_vacancies FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.driver_profiles dp
        JOIN public.staff_memberships sm ON sm.id = dp.membership_id
        WHERE dp.profile_id = (SELECT app.auth_profile_id())
          AND dp.station_id = coverage_vacancies.station_id
          AND dp.environment_id = coverage_vacancies.environment_id
          AND dp.status = 'active'
          AND dp.id IS DISTINCT FROM coverage_vacancies.titular_driver_profile_id
          AND NOT (
              sm.shift_group = coverage_vacancies.shift_group
              AND sm.shift_slot = coverage_vacancies.shift_slot
          )
    )
    OR EXISTS (
        SELECT 1
        FROM public.coverage_claims cc
        JOIN public.driver_profiles dp ON dp.id = cc.driver_profile_id
        WHERE cc.vacancy_id = coverage_vacancies.id
          AND dp.profile_id = app.auth_profile_id()
    )
    OR app.auth_has_role('supervisor', station_id)
    OR app.auth_has_role('management', station_id)
);

CREATE POLICY coverage_claims_authorized_read
ON public.coverage_claims FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.driver_profiles dp
        WHERE dp.id = driver_profile_id
          AND dp.profile_id = (SELECT app.auth_profile_id())
    )
    OR app.auth_has_role('supervisor', station_id)
    OR app.auth_has_role('management', station_id)
);

GRANT SELECT ON TABLE public.absences, public.coverage_vacancies,
    public.coverage_claims TO authenticated;

CREATE OR REPLACE FUNCTION public.request_absence(
    p_operating_date date,
    p_shift_slot text,
    p_kind text,
    p_reason text,
    p_comments text,
    p_idempotency_key text,
    p_install_id text
)
RETURNS public.absences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_now timestamptz;
    v_group text;
    v_station_timezone text;
    v_request jsonb;
    v_driver public.driver_profiles%ROWTYPE;
    v_membership public.staff_memberships%ROWTYPE;
    v_command public.command_log%ROWTYPE;
    v_absence public.absences%ROWTYPE;
    v_vacancy public.coverage_vacancies%ROWTYPE;
BEGIN
    PERFORM app.assert_driver_device_session(p_install_id);
    v_actor_profile_id := app.auth_profile_id();
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;
    IF p_operating_date IS NULL THEN
        RAISE EXCEPTION 'operating_date_required' USING ERRCODE = '22023';
    END IF;
    IF p_shift_slot NOT IN ('morning', 'evening') THEN
        RAISE EXCEPTION 'invalid_shift_slot' USING ERRCODE = '22023';
    END IF;
    IF p_kind NOT IN ('scheduled', 'emergency', 'leave', 'other') THEN
        RAISE EXCEPTION 'invalid_absence_kind' USING ERRCODE = '22023';
    END IF;
    IF p_reason IS NULL OR char_length(btrim(p_reason)) NOT BETWEEN 3 AND 1000 THEN
        RAISE EXCEPTION 'invalid_absence_reason' USING ERRCODE = '22023';
    END IF;
    IF char_length(coalesce(p_comments, '')) > 2000 THEN
        RAISE EXCEPTION 'invalid_absence_comments' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_group := CASE
        WHEN extract(isodow FROM p_operating_date) BETWEEN 1 AND 5
        THEN 'weekday' ELSE 'weekend'
    END;
    v_request := jsonb_build_object(
        'operating_date', p_operating_date,
        'shift_slot', p_shift_slot,
        'kind', p_kind,
        'reason', btrim(p_reason),
        'comments', coalesce(btrim(p_comments), ''),
        'install_id', btrim(p_install_id)
    );

    SELECT cl.* INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'request_absence'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'absence_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT a.* INTO STRICT v_absence
        FROM public.absences a
        WHERE a.id = (v_command.result_payload->>'absence_id')::uuid;
        RETURN v_absence;
    END IF;

    SELECT dp.* INTO v_driver
    FROM public.driver_profiles dp
    WHERE dp.profile_id = v_actor_profile_id
      AND dp.environment_id = v_environment_id
      AND dp.status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_driver_profile_required' USING ERRCODE = '42501';
    END IF;
    IF NOT app.auth_has_role('driver', v_driver.station_id) THEN
        RAISE EXCEPTION 'active_driver_membership_required' USING ERRCODE = '42501';
    END IF;
    SELECT sm.* INTO STRICT v_membership
    FROM public.staff_memberships sm
    WHERE sm.id = v_driver.membership_id;
    SELECT s.timezone INTO STRICT v_station_timezone
    FROM public.stations s
    WHERE s.id = v_driver.station_id
      AND s.environment_id = v_environment_id;
    IF p_operating_date < (v_now AT TIME ZONE v_station_timezone)::date
       OR p_operating_date > (v_now AT TIME ZONE v_station_timezone)::date + 90 THEN
        RAISE EXCEPTION 'absence_date_out_of_range' USING ERRCODE = '22023';
    END IF;
    IF v_membership.shift_slot IS NOT NULL
       AND v_membership.shift_slot <> p_shift_slot THEN
        RAISE EXCEPTION 'absence_shift_slot_not_owned' USING ERRCODE = '22023';
    END IF;
    IF v_membership.shift_group IS NOT NULL
       AND v_membership.shift_group <> v_group THEN
        RAISE EXCEPTION 'absence_shift_group_not_owned' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.absences a
        WHERE a.driver_profile_id = v_driver.id
          AND a.operating_date = p_operating_date
          AND a.shift_slot = p_shift_slot
          AND a.status IN ('searching', 'covered', 'awaiting_authorization', 'approved')
    ) THEN
        RAISE EXCEPTION 'absence_already_exists' USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'request_absence',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    INSERT INTO public.absences (
        environment_id, station_id, driver_profile_id, operating_date,
        shift_group, shift_slot, kind, reason, comments, status, requested_at
    ) VALUES (
        v_environment_id, v_driver.station_id, v_driver.id, p_operating_date,
        v_group, p_shift_slot, p_kind, btrim(p_reason),
        coalesce(btrim(p_comments), ''), 'searching', v_now
    ) RETURNING * INTO v_absence;

    INSERT INTO public.coverage_vacancies (
        environment_id, station_id, absence_id, opened_by,
        titular_driver_profile_id, operating_date, shift_group, shift_slot,
        origin, bonus_mode, bonus_mxn, reason, status, is_critical, opened_at
    ) VALUES (
        v_environment_id, v_driver.station_id, v_absence.id, v_actor_profile_id,
        v_driver.id, p_operating_date, v_group, p_shift_slot,
        'absence', 'fixed', 300, 'Cobertura por ausencia', 'searching',
        p_kind = 'emergency', v_now
    ) RETURNING * INTO v_vacancy;

    UPDATE public.absences
    SET vacancy_id = v_vacancy.id
    WHERE id = v_absence.id
    RETURNING * INTO STRICT v_absence;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'absence_id', v_absence.id,
            'vacancy_id', v_vacancy.id,
            'folio', v_absence.folio,
            'revision', v_absence.revision
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_driver.station_id,
        v_command.id, 'absence.requested', 'absence', v_absence.id,
        jsonb_build_object(
            'vacancy_id', v_vacancy.id,
            'operating_date', p_operating_date,
            'shift_slot', p_shift_slot,
            'kind', p_kind
        ), v_now
    );

    RETURN v_absence;
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_guard(
    p_vacancy_id uuid,
    p_idempotency_key text,
    p_install_id text
)
RETURNS public.coverage_claims
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_now timestamptz;
    v_station_timezone text;
    v_request jsonb;
    v_driver public.driver_profiles%ROWTYPE;
    v_membership public.staff_memberships%ROWTYPE;
    v_vacancy public.coverage_vacancies%ROWTYPE;
    v_command public.command_log%ROWTYPE;
    v_claim public.coverage_claims%ROWTYPE;
BEGIN
    PERFORM app.assert_driver_device_session(p_install_id);
    v_actor_profile_id := app.auth_profile_id();
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_request := jsonb_build_object(
        'vacancy_id', p_vacancy_id,
        'install_id', btrim(p_install_id)
    );

    SELECT cl.* INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'claim_guard'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'claim_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT cc.* INTO STRICT v_claim
        FROM public.coverage_claims cc
        WHERE cc.id = (v_command.result_payload->>'claim_id')::uuid;
        RETURN v_claim;
    END IF;

    SELECT dp.* INTO v_driver
    FROM public.driver_profiles dp
    WHERE dp.profile_id = v_actor_profile_id
      AND dp.environment_id = v_environment_id
      AND dp.status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'active_driver_profile_required' USING ERRCODE = '42501';
    END IF;
    IF NOT app.auth_has_role('driver', v_driver.station_id) THEN
        RAISE EXCEPTION 'active_driver_membership_required' USING ERRCODE = '42501';
    END IF;
    SELECT sm.* INTO STRICT v_membership
    FROM public.staff_memberships sm
    WHERE sm.id = v_driver.membership_id;

    -- El bloqueo de la vacante es la autoridad de la carrera entre telefonos.
    SELECT cv.* INTO v_vacancy
    FROM public.coverage_vacancies cv
    WHERE cv.id = p_vacancy_id
      AND cv.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'vacancy_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_vacancy.station_id <> v_driver.station_id THEN
        RAISE EXCEPTION 'vacancy_station_not_allowed' USING ERRCODE = '42501';
    END IF;
    IF v_vacancy.status <> 'searching' THEN
        RAISE EXCEPTION 'vacancy_already_claimed' USING ERRCODE = '23505';
    END IF;
    IF v_vacancy.titular_driver_profile_id = v_driver.id THEN
        RAISE EXCEPTION 'titular_cannot_claim_own_vacancy' USING ERRCODE = '22023';
    END IF;
    SELECT s.timezone INTO STRICT v_station_timezone
    FROM public.stations s
    WHERE s.id = v_vacancy.station_id
      AND s.environment_id = v_environment_id;
    IF v_vacancy.operating_date < (v_now AT TIME ZONE v_station_timezone)::date THEN
        RAISE EXCEPTION 'vacancy_expired' USING ERRCODE = '22023';
    END IF;
    IF v_membership.shift_group = v_vacancy.shift_group
       AND v_membership.shift_slot = v_vacancy.shift_slot THEN
        RAISE EXCEPTION 'driver_has_regular_shift_conflict' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.shifts sh
        WHERE sh.driver_profile_id = v_driver.id
          AND sh.operating_date = v_vacancy.operating_date
          AND sh.shift_slot = v_vacancy.shift_slot
    ) THEN
        RAISE EXCEPTION 'driver_has_shift_conflict' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.coverage_claims cc
        WHERE cc.driver_profile_id = v_driver.id
          AND cc.operating_date = v_vacancy.operating_date
          AND cc.shift_slot = v_vacancy.shift_slot
          AND cc.status IN ('won', 'approved')
    ) THEN
        RAISE EXCEPTION 'driver_has_guard_conflict' USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'claim_guard',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    INSERT INTO public.coverage_claims (
        environment_id, station_id, vacancy_id, driver_profile_id,
        status, operating_date, shift_slot, claimed_at
    ) VALUES (
        v_environment_id, v_vacancy.station_id, v_vacancy.id, v_driver.id,
        'won', v_vacancy.operating_date, v_vacancy.shift_slot, v_now
    ) RETURNING * INTO v_claim;

    UPDATE public.coverage_vacancies
    SET status = 'reserved', claimed_at = v_now, revision = revision + 1
    WHERE id = v_vacancy.id
      AND status = 'searching';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'vacancy_already_claimed' USING ERRCODE = '23505';
    END IF;

    IF v_vacancy.absence_id IS NOT NULL THEN
        UPDATE public.absences
        SET status = 'covered', revision = revision + 1
        WHERE id = v_vacancy.absence_id
          AND status = 'searching';
    END IF;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'claim_id', v_claim.id,
            'vacancy_id', v_vacancy.id,
            'status', v_claim.status
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_vacancy.station_id,
        v_command.id, 'coverage.claim_won', 'coverage_claim', v_claim.id,
        jsonb_build_object(
            'vacancy_id', v_vacancy.id,
            'operating_date', v_vacancy.operating_date,
            'shift_slot', v_vacancy.shift_slot
        ), v_now
    );

    RETURN v_claim;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'vacancy_already_claimed' USING ERRCODE = '23505';
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_guard(
    p_vacancy_id uuid,
    p_expected_revision bigint,
    p_note text,
    p_idempotency_key text
)
RETURNS public.coverage_vacancies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_now timestamptz;
    v_request jsonb;
    v_vacancy public.coverage_vacancies%ROWTYPE;
    v_claim public.coverage_claims%ROWTYPE;
    v_command public.command_log%ROWTYPE;
BEGIN
    v_actor_profile_id := app.auth_profile_id();
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_expected_revision IS NULL OR p_expected_revision < 1 THEN
        RAISE EXCEPTION 'invalid_expected_revision' USING ERRCODE = '22023';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;
    IF p_note IS NOT NULL AND btrim(p_note) = '' THEN
        RAISE EXCEPTION 'invalid_guard_note' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_request := jsonb_build_object(
        'vacancy_id', p_vacancy_id,
        'expected_revision', p_expected_revision,
        'note', nullif(btrim(p_note), '')
    );

    SELECT cl.* INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'approve_guard'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'vacancy_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT cv.* INTO STRICT v_vacancy
        FROM public.coverage_vacancies cv
        WHERE cv.id = (v_command.result_payload->>'vacancy_id')::uuid;
        RETURN v_vacancy;
    END IF;

    SELECT cv.* INTO v_vacancy
    FROM public.coverage_vacancies cv
    WHERE cv.id = p_vacancy_id
      AND cv.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'vacancy_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT app.auth_has_role('supervisor', v_vacancy.station_id) THEN
        RAISE EXCEPTION 'supervisor_role_required_for_station' USING ERRCODE = '42501';
    END IF;
    IF v_vacancy.status <> 'reserved' THEN
        RAISE EXCEPTION 'vacancy_not_reserved' USING ERRCODE = '55000';
    END IF;
    IF v_vacancy.revision <> p_expected_revision THEN
        RAISE EXCEPTION 'vacancy_revision_conflict' USING ERRCODE = '40001';
    END IF;
    SELECT cc.* INTO v_claim
    FROM public.coverage_claims cc
    WHERE cc.vacancy_id = v_vacancy.id
      AND cc.status = 'won'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'vacancy_winner_not_found' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'approve_guard',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    UPDATE public.coverage_claims
    SET status = 'approved', note = nullif(btrim(p_note), ''), decided_at = v_now
    WHERE id = v_claim.id;

    UPDATE public.coverage_vacancies
    SET status = 'confirmed', approved_by = v_actor_profile_id,
        approved_at = v_now, revision = revision + 1
    WHERE id = v_vacancy.id
      AND revision = p_expected_revision
    RETURNING * INTO STRICT v_vacancy;

    IF v_vacancy.absence_id IS NOT NULL THEN
        UPDATE public.absences
        SET status = 'awaiting_authorization', revision = revision + 1
        WHERE id = v_vacancy.absence_id
          AND status = 'covered';
    END IF;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'vacancy_id', v_vacancy.id,
            'claim_id', v_claim.id,
            'status', v_vacancy.status,
            'revision', v_vacancy.revision
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_vacancy.station_id,
        v_command.id, 'coverage.guard_approved', 'coverage_vacancy', v_vacancy.id,
        jsonb_build_object('claim_id', v_claim.id, 'revision', v_vacancy.revision),
        v_now
    );

    RETURN v_vacancy;
END;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_absence(
    p_absence_id uuid,
    p_expected_revision bigint,
    p_decision text,
    p_note text,
    p_idempotency_key text
)
RETURNS public.absences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor_profile_id uuid;
    v_environment_id uuid;
    v_now timestamptz;
    v_request jsonb;
    v_absence public.absences%ROWTYPE;
    v_vacancy public.coverage_vacancies%ROWTYPE;
    v_command public.command_log%ROWTYPE;
BEGIN
    v_actor_profile_id := app.auth_profile_id();
    IF v_actor_profile_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_expected_revision IS NULL OR p_expected_revision < 1 THEN
        RAISE EXCEPTION 'invalid_expected_revision' USING ERRCODE = '22023';
    END IF;
    IF p_decision NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'invalid_absence_decision' USING ERRCODE = '22023';
    END IF;
    IF p_note IS NULL OR char_length(btrim(p_note)) NOT BETWEEN 3 AND 1000 THEN
        RAISE EXCEPTION 'invalid_absence_decision_note' USING ERRCODE = '22023';
    END IF;
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE = '22023';
    END IF;

    v_environment_id := app.current_environment_id();
    v_now := app.env_now(v_environment_id);
    v_request := jsonb_build_object(
        'absence_id', p_absence_id,
        'expected_revision', p_expected_revision,
        'decision', p_decision,
        'note', btrim(p_note)
    );

    SELECT cl.* INTO v_command
    FROM public.command_log cl
    WHERE cl.environment_id = v_environment_id
      AND cl.idempotency_key = btrim(p_idempotency_key)
    FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name <> 'resolve_absence'
           OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status <> 'completed'
           OR v_command.result_payload->>'absence_id' IS NULL THEN
            RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE = '23505';
        END IF;
        SELECT a.* INTO STRICT v_absence
        FROM public.absences a
        WHERE a.id = (v_command.result_payload->>'absence_id')::uuid;
        RETURN v_absence;
    END IF;

    SELECT a.* INTO v_absence
    FROM public.absences a
    WHERE a.id = p_absence_id
      AND a.environment_id = v_environment_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'absence_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT app.auth_has_role('supervisor', v_absence.station_id) THEN
        RAISE EXCEPTION 'supervisor_role_required_for_station' USING ERRCODE = '42501';
    END IF;
    IF v_absence.status IN ('approved', 'rejected', 'cancelled', 'uncovered') THEN
        RAISE EXCEPTION 'absence_not_open' USING ERRCODE = '55000';
    END IF;
    IF v_absence.revision <> p_expected_revision THEN
        RAISE EXCEPTION 'absence_revision_conflict' USING ERRCODE = '40001';
    END IF;

    IF v_absence.vacancy_id IS NOT NULL THEN
        SELECT cv.* INTO STRICT v_vacancy
        FROM public.coverage_vacancies cv
        WHERE cv.id = v_absence.vacancy_id
        FOR UPDATE;
    END IF;
    IF p_decision = 'approved'
       AND (v_vacancy.id IS NULL OR v_vacancy.status <> 'confirmed') THEN
        RAISE EXCEPTION 'absence_requires_confirmed_coverage' USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.command_log (
        environment_id, actor_profile_id, command_name, idempotency_key,
        status, request_payload, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, 'resolve_absence',
        btrim(p_idempotency_key), 'accepted', v_request, v_now
    ) RETURNING * INTO v_command;

    UPDATE public.absences
    SET status = p_decision, resolved_by = v_actor_profile_id,
        decision_note = btrim(p_note), decided_at = v_now,
        revision = revision + 1
    WHERE id = v_absence.id
      AND revision = p_expected_revision
    RETURNING * INTO STRICT v_absence;

    IF p_decision = 'rejected' AND v_vacancy.id IS NOT NULL
       AND v_vacancy.status IN ('searching', 'reserved', 'confirmed') THEN
        UPDATE public.coverage_claims
        SET status = 'rejected', note = btrim(p_note), decided_at = v_now
        WHERE vacancy_id = v_vacancy.id
          AND status IN ('won', 'approved');

        UPDATE public.coverage_vacancies
        SET status = 'cancelled', revision = revision + 1
        WHERE id = v_vacancy.id;
    END IF;

    UPDATE public.command_log
    SET status = 'completed',
        result_payload = jsonb_build_object(
            'absence_id', v_absence.id,
            'status', v_absence.status,
            'revision', v_absence.revision
        )
    WHERE id = v_command.id;

    INSERT INTO public.audit_log (
        environment_id, actor_profile_id, station_id, command_id,
        event_type, entity_type, entity_id, metadata, occurred_at
    ) VALUES (
        v_environment_id, v_actor_profile_id, v_absence.station_id,
        v_command.id, 'absence.resolved', 'absence', v_absence.id,
        jsonb_build_object('decision', p_decision, 'revision', v_absence.revision),
        v_now
    );

    RETURN v_absence;
END;
$function$;

REVOKE ALL ON FUNCTION public.request_absence(date, text, text, text, text, text, text)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.claim_guard(uuid, text, text)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_guard(uuid, bigint, text, text)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resolve_absence(uuid, bigint, text, text, text)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_absence(date, text, text, text, text, text, text)
    TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_guard(uuid, text, text)
    TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.approve_guard(uuid, bigint, text, text)
    TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_absence(uuid, bigint, text, text, text)
    TO authenticated, service_role;

-- Incluye las vacantes abiertas en la proyeccion compacta de consola.
CREATE OR REPLACE FUNCTION app.refresh_station_live(p_station_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, app, pg_temp
AS $function$
DECLARE
    v_environment_id uuid;
BEGIN
    SELECT s.environment_id INTO v_environment_id
    FROM public.stations s WHERE s.id = p_station_id;
    IF NOT FOUND THEN RETURN; END IF;

    INSERT INTO public.station_live (
        station_id, environment_id, active_shifts, present_drivers,
        available_units, units_in_shop, open_incidents, open_vacancies,
        last_event_at, updated_at
    )
    SELECT
        p_station_id,
        v_environment_id,
        (SELECT count(*)::integer FROM public.shifts sh
         WHERE sh.station_id = p_station_id AND sh.status = 'open'),
        (SELECT count(DISTINCT sh.driver_profile_id)::integer FROM public.shifts sh
         WHERE sh.station_id = p_station_id AND sh.status = 'open'),
        (SELECT count(*)::integer FROM public.vehicles v
         WHERE v.station_id = p_station_id AND v.status = 'available'),
        (SELECT count(*)::integer FROM public.vehicles v
         WHERE v.station_id = p_station_id AND v.status = 'maintenance'),
        (SELECT count(*)::integer FROM public.incidents i
         WHERE i.station_id = p_station_id AND i.status <> 'closed'),
        (SELECT count(*)::integer FROM public.coverage_vacancies cv
         WHERE cv.station_id = p_station_id
           AND cv.status IN ('searching', 'reserved')),
        app.env_now(v_environment_id),
        now()
    ON CONFLICT (station_id) DO UPDATE SET
        environment_id = EXCLUDED.environment_id,
        active_shifts = EXCLUDED.active_shifts,
        present_drivers = EXCLUDED.present_drivers,
        available_units = EXCLUDED.available_units,
        units_in_shop = EXCLUDED.units_in_shop,
        open_incidents = EXCLUDED.open_incidents,
        open_vacancies = EXCLUDED.open_vacancies,
        last_event_at = EXCLUDED.last_event_at,
        updated_at = EXCLUDED.updated_at;
END;
$function$;

CREATE TRIGGER station_live_from_coverage_vacancies
AFTER INSERT OR UPDATE OR DELETE ON public.coverage_vacancies
FOR EACH ROW EXECUTE FUNCTION app.refresh_station_live_from_row();

DO $block$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename = 'coverage_vacancies'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.coverage_vacancies;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename = 'coverage_claims'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.coverage_claims;
        END IF;
    END IF;
END;
$block$;

COMMENT ON TABLE public.absences IS
    '15F: solicitudes de ausencia con revision y resolucion supervisora.';
COMMENT ON TABLE public.coverage_vacancies IS
    '15F: plazas ofrecidas; la fila se bloquea al competir por una guardia.';
COMMENT ON TABLE public.coverage_claims IS
    '15F: ganador unico y decisiones de una vacante de cobertura.';
