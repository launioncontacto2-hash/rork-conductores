-- =====================================================================
-- TurnoEV · 15G · Ciclo financiero autoritativo
--
-- Ingresos, depositos y cargos son hechos append-only. Las liquidaciones
-- se calculan en servidor y una liquidacion solo puede tener una
-- transferencia activa. La CLABE completa vive fuera del esquema expuesto.
-- =====================================================================

CREATE TABLE public.incomes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    shift_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    reversal_of uuid,
    folio text NOT NULL DEFAULT ('ING-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
    source text NOT NULL,
    amount_mxn integer NOT NULL,
    trips integer NOT NULL DEFAULT 0,
    external_reference text,
    evidence_path text,
    note text,
    reported_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT incomes_shift_scope_fkey FOREIGN KEY (shift_id, station_id, environment_id)
        REFERENCES public.shifts(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT incomes_driver_scope_fkey FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT incomes_reversal_fkey FOREIGN KEY (reversal_of) REFERENCES public.incomes(id) ON DELETE RESTRICT,
    CONSTRAINT incomes_environment_folio_unique UNIQUE (environment_id, folio),
    CONSTRAINT incomes_source_check CHECK (source IN ('uber', 'didi', 'cash', 'other')),
    CONSTRAINT incomes_amount_nonzero CHECK (amount_mxn <> 0),
    CONSTRAINT incomes_reversal_sign_check CHECK ((reversal_of IS NULL AND amount_mxn > 0) OR (reversal_of IS NOT NULL AND amount_mxn < 0)),
    CONSTRAINT incomes_trips_nonnegative CHECK (trips >= 0),
    CONSTRAINT incomes_reference_length CHECK (external_reference IS NULL OR char_length(btrim(external_reference)) BETWEEN 1 AND 200),
    CONSTRAINT incomes_note_length CHECK (note IS NULL OR char_length(btrim(note)) BETWEEN 1 AND 1000)
);

CREATE UNIQUE INDEX incomes_single_reversal_unique ON public.incomes(reversal_of) WHERE reversal_of IS NOT NULL;
CREATE INDEX incomes_driver_reported_idx ON public.incomes(driver_profile_id, reported_at DESC, id);
CREATE INDEX incomes_station_reported_idx ON public.incomes(station_id, reported_at DESC, id);
CREATE INDEX incomes_shift_idx ON public.incomes(shift_id);

CREATE TABLE public.cash_deposits (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    shift_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    folio text NOT NULL DEFAULT ('DEP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
    amount_mxn integer NOT NULL,
    bank text NOT NULL,
    receipt_reference text NOT NULL,
    evidence_path text NOT NULL,
    deposited_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_deposits_shift_scope_fkey FOREIGN KEY (shift_id, station_id, environment_id)
        REFERENCES public.shifts(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT cash_deposits_driver_scope_fkey FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT cash_deposits_environment_folio_unique UNIQUE (environment_id, folio),
    CONSTRAINT cash_deposits_amount_positive CHECK (amount_mxn > 0),
    CONSTRAINT cash_deposits_bank_not_blank CHECK (btrim(bank) <> ''),
    CONSTRAINT cash_deposits_reference_not_blank CHECK (btrim(receipt_reference) <> ''),
    CONSTRAINT cash_deposits_evidence_not_blank CHECK (btrim(evidence_path) <> '')
);

CREATE INDEX cash_deposits_driver_date_idx ON public.cash_deposits(driver_profile_id, deposited_at DESC, id);
CREATE INDEX cash_deposits_station_date_idx ON public.cash_deposits(station_id, deposited_at DESC, id);
CREATE INDEX cash_deposits_shift_idx ON public.cash_deposits(shift_id);

CREATE TABLE public.cash_charges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    created_by uuid NOT NULL,
    reversal_of uuid,
    folio text NOT NULL DEFAULT ('CAR-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
    concept text NOT NULL,
    amount_mxn integer NOT NULL,
    charged_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cash_charges_driver_scope_fkey FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT cash_charges_creator_environment_fkey FOREIGN KEY (created_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT cash_charges_reversal_fkey FOREIGN KEY (reversal_of) REFERENCES public.cash_charges(id) ON DELETE RESTRICT,
    CONSTRAINT cash_charges_environment_folio_unique UNIQUE (environment_id, folio),
    CONSTRAINT cash_charges_amount_nonzero CHECK (amount_mxn <> 0),
    CONSTRAINT cash_charges_reversal_sign_check CHECK ((reversal_of IS NULL AND amount_mxn > 0) OR (reversal_of IS NOT NULL AND amount_mxn < 0)),
    CONSTRAINT cash_charges_concept_length CHECK (char_length(btrim(concept)) BETWEEN 3 AND 500)
);

CREATE UNIQUE INDEX cash_charges_single_reversal_unique ON public.cash_charges(reversal_of) WHERE reversal_of IS NOT NULL;
CREATE INDEX cash_charges_driver_date_idx ON public.cash_charges(driver_profile_id, charged_at DESC, id);
CREATE INDEX cash_charges_station_date_idx ON public.cash_charges(station_id, charged_at DESC, id);
CREATE INDEX cash_charges_created_by_idx ON public.cash_charges(created_by);

CREATE TABLE public.bank_accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    created_by uuid NOT NULL,
    approved_by uuid,
    superseded_by uuid,
    bank_name text NOT NULL,
    clabe_last4 text NOT NULL,
    version integer NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL,
    approved_at timestamptz,
    superseded_at timestamptz,
    CONSTRAINT bank_accounts_driver_scope_fkey FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT bank_accounts_creator_environment_fkey FOREIGN KEY (created_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT bank_accounts_approver_environment_fkey FOREIGN KEY (approved_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT bank_accounts_superseded_fkey FOREIGN KEY (superseded_by) REFERENCES public.bank_accounts(id) ON DELETE RESTRICT,
    CONSTRAINT bank_accounts_bank_not_blank CHECK (btrim(bank_name) <> ''),
    CONSTRAINT bank_accounts_clabe_last4_check CHECK (clabe_last4 ~ '^[0-9]{4}$'),
    CONSTRAINT bank_accounts_version_positive CHECK (version > 0),
    CONSTRAINT bank_accounts_status_check CHECK (status IN ('pending', 'active', 'rejected', 'superseded')),
    CONSTRAINT bank_accounts_approval_consistent CHECK (
        (status = 'active' AND approved_by IS NOT NULL AND approved_at IS NOT NULL)
        OR (status <> 'active')
    ),
    CONSTRAINT bank_accounts_superseded_consistent CHECK ((superseded_by IS NULL AND superseded_at IS NULL) OR (superseded_by IS NOT NULL AND superseded_at IS NOT NULL)),
    CONSTRAINT bank_accounts_driver_version_unique UNIQUE (driver_profile_id, version),
    CONSTRAINT bank_accounts_id_station_environment_unique UNIQUE (id, station_id, environment_id)
);

CREATE UNIQUE INDEX bank_accounts_active_driver_unique ON public.bank_accounts(driver_profile_id) WHERE status = 'active';
CREATE UNIQUE INDEX bank_accounts_pending_driver_unique ON public.bank_accounts(driver_profile_id) WHERE status = 'pending';
CREATE INDEX bank_accounts_station_current_idx ON public.bank_accounts(station_id, driver_profile_id) WHERE status = 'active';
CREATE INDEX bank_accounts_created_by_idx ON public.bank_accounts(created_by);
CREATE INDEX bank_accounts_approved_by_idx ON public.bank_accounts(approved_by) WHERE approved_by IS NOT NULL;
CREATE INDEX bank_accounts_superseded_by_idx ON public.bank_accounts(superseded_by) WHERE superseded_by IS NOT NULL;

CREATE TABLE app.bank_account_secrets (
    bank_account_id uuid PRIMARY KEY REFERENCES public.bank_accounts(id) ON DELETE RESTRICT,
    clabe text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT bank_account_secrets_clabe_check CHECK (clabe ~ '^[0-9]{18}$')
);

ALTER TABLE app.bank_account_secrets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE app.bank_account_secrets FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE app.bank_account_secrets TO postgres, service_role;

CREATE TABLE public.settlements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    driver_profile_id uuid NOT NULL,
    closed_by uuid NOT NULL,
    folio text NOT NULL DEFAULT ('LIQ-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
    period_start date NOT NULL,
    period_end date NOT NULL,
    gross_income_mxn integer NOT NULL,
    cash_charges_mxn integer NOT NULL,
    net_mxn integer NOT NULL,
    status text NOT NULL DEFAULT 'available',
    revision bigint NOT NULL DEFAULT 1,
    closed_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT settlements_driver_scope_fkey FOREIGN KEY (driver_profile_id, station_id, environment_id)
        REFERENCES public.driver_profiles(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT settlements_closer_environment_fkey FOREIGN KEY (closed_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT settlements_environment_folio_unique UNIQUE (environment_id, folio),
    CONSTRAINT settlements_driver_period_unique UNIQUE (driver_profile_id, period_start, period_end),
    CONSTRAINT settlements_id_station_environment_unique UNIQUE (id, station_id, environment_id),
    CONSTRAINT settlements_period_check CHECK (period_end >= period_start AND period_end - period_start <= 31),
    CONSTRAINT settlements_amounts_check CHECK (gross_income_mxn >= 0 AND cash_charges_mxn >= 0 AND net_mxn = gross_income_mxn - cash_charges_mxn),
    CONSTRAINT settlements_status_check CHECK (status IN ('available', 'authorized', 'processing', 'transferred', 'completed', 'cancelled')),
    CONSTRAINT settlements_revision_positive CHECK (revision > 0)
);

CREATE INDEX settlements_driver_period_idx ON public.settlements(driver_profile_id, period_start DESC, id);
CREATE INDEX settlements_station_status_idx ON public.settlements(station_id, status, period_start DESC, id);
CREATE INDEX settlements_closed_by_idx ON public.settlements(closed_by);

CREATE TABLE public.transfers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    station_id uuid NOT NULL,
    settlement_id uuid NOT NULL,
    bank_account_id uuid NOT NULL,
    authorized_by uuid NOT NULL,
    folio text NOT NULL DEFAULT ('TR-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
    amount_mxn integer NOT NULL,
    status text NOT NULL DEFAULT 'authorized',
    revision bigint NOT NULL DEFAULT 1,
    authorized_at timestamptz NOT NULL,
    processed_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT transfers_settlement_scope_fkey FOREIGN KEY (settlement_id, station_id, environment_id)
        REFERENCES public.settlements(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT transfers_bank_account_scope_fkey FOREIGN KEY (bank_account_id, station_id, environment_id)
        REFERENCES public.bank_accounts(id, station_id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT transfers_authorizer_environment_fkey FOREIGN KEY (authorized_by, environment_id)
        REFERENCES public.profiles(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT transfers_environment_folio_unique UNIQUE (environment_id, folio),
    CONSTRAINT transfers_amount_positive CHECK (amount_mxn > 0),
    CONSTRAINT transfers_status_check CHECK (status IN ('authorized', 'processing', 'transferred', 'completed', 'failed', 'cancelled')),
    CONSTRAINT transfers_revision_positive CHECK (revision > 0)
);

CREATE UNIQUE INDEX transfers_active_settlement_unique ON public.transfers(settlement_id)
    WHERE status IN ('authorized', 'processing', 'transferred', 'completed');
CREATE INDEX transfers_station_status_idx ON public.transfers(station_id, status, authorized_at DESC, id);
CREATE INDEX transfers_bank_account_idx ON public.transfers(bank_account_id);
CREATE INDEX transfers_authorized_by_idx ON public.transfers(authorized_by);

ALTER TABLE public.incomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_deposits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transfers ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.incomes, public.cash_deposits, public.cash_charges,
    public.bank_accounts, public.settlements, public.transfers FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.incomes, public.cash_deposits, public.cash_charges,
    public.bank_accounts, public.settlements, public.transfers TO postgres, service_role;

CREATE OR REPLACE FUNCTION app.guard_financial_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'pg_temp'
AS $function$
BEGIN
    RAISE EXCEPTION 'financial_record_append_only' USING ERRCODE = '42501';
END;
$function$;

CREATE OR REPLACE FUNCTION app.refresh_station_live(p_station_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, app, pg_temp
AS $function$
DECLARE v_environment_id uuid; v_timezone text; v_today date;
BEGIN
    SELECT s.environment_id,s.timezone INTO v_environment_id,v_timezone FROM public.stations s WHERE s.id=p_station_id;
    IF NOT FOUND THEN RETURN; END IF;
    v_today := (app.env_now(v_environment_id) AT TIME ZONE v_timezone)::date;
    INSERT INTO public.station_live(station_id,environment_id,active_shifts,present_drivers,available_units,units_in_shop,
        open_incidents,open_vacancies,billed_today_mxn,last_event_at,updated_at)
    SELECT p_station_id,v_environment_id,
      (SELECT count(*)::integer FROM public.shifts sh WHERE sh.station_id=p_station_id AND sh.status='open'),
      (SELECT count(DISTINCT sh.driver_profile_id)::integer FROM public.shifts sh WHERE sh.station_id=p_station_id AND sh.status='open'),
      (SELECT count(*)::integer FROM public.vehicles v WHERE v.station_id=p_station_id AND v.status='available'),
      (SELECT count(*)::integer FROM public.vehicles v WHERE v.station_id=p_station_id AND v.status='maintenance'),
      (SELECT count(*)::integer FROM public.incidents i WHERE i.station_id=p_station_id AND i.status<>'closed'),
      (SELECT count(*)::integer FROM public.coverage_vacancies cv WHERE cv.station_id=p_station_id AND cv.status IN ('searching','reserved')),
      (SELECT coalesce(sum(i.amount_mxn),0)::integer FROM public.incomes i
        WHERE i.station_id=p_station_id AND (i.reported_at AT TIME ZONE v_timezone)::date=v_today),
      app.env_now(v_environment_id),now()
    ON CONFLICT(station_id) DO UPDATE SET environment_id=EXCLUDED.environment_id,active_shifts=EXCLUDED.active_shifts,
      present_drivers=EXCLUDED.present_drivers,available_units=EXCLUDED.available_units,units_in_shop=EXCLUDED.units_in_shop,
      open_incidents=EXCLUDED.open_incidents,open_vacancies=EXCLUDED.open_vacancies,billed_today_mxn=EXCLUDED.billed_today_mxn,
      last_event_at=EXCLUDED.last_event_at,updated_at=EXCLUDED.updated_at;
END;
$function$;

DO $block$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime')
     AND NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='transfers')
  THEN ALTER PUBLICATION supabase_realtime ADD TABLE public.transfers; END IF;
END;
$block$;

COMMENT ON TABLE public.incomes IS '15G: ingresos y reversiones append-only registrados por turno.';
COMMENT ON TABLE public.cash_deposits IS '15G: evidencia append-only de depositos de efectivo.';
COMMENT ON TABLE public.cash_charges IS '15G: cargos y reversiones append-only aplicables a liquidaciones.';
COMMENT ON TABLE public.bank_accounts IS '15G: versiones de cuenta; solo banco y ultimos cuatro digitos expuestos.';
COMMENT ON TABLE app.bank_account_secrets IS '15G: CLABE completa no expuesta, disponible solo para dispersion privilegiada.';
COMMENT ON TABLE public.settlements IS '15G: calculo financiero congelado y autoritativo por periodo.';
COMMENT ON TABLE public.transfers IS '15G: autorizaciones de dispersion idempotentes y no duplicables.';

REVOKE ALL ON FUNCTION app.guard_financial_append_only() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.guard_financial_append_only() TO postgres;

CREATE TRIGGER incomes_block_update BEFORE UPDATE ON public.incomes FOR EACH ROW EXECUTE FUNCTION app.guard_financial_append_only();
CREATE TRIGGER incomes_block_delete BEFORE DELETE ON public.incomes FOR EACH ROW EXECUTE FUNCTION app.guard_financial_append_only();
CREATE TRIGGER cash_deposits_block_update BEFORE UPDATE ON public.cash_deposits FOR EACH ROW EXECUTE FUNCTION app.guard_financial_append_only();
CREATE TRIGGER cash_deposits_block_delete BEFORE DELETE ON public.cash_deposits FOR EACH ROW EXECUTE FUNCTION app.guard_financial_append_only();
CREATE TRIGGER cash_charges_block_update BEFORE UPDATE ON public.cash_charges FOR EACH ROW EXECUTE FUNCTION app.guard_financial_append_only();
CREATE TRIGGER cash_charges_block_delete BEFORE DELETE ON public.cash_charges FOR EACH ROW EXECUTE FUNCTION app.guard_financial_append_only();

CREATE TRIGGER settlements_touch BEFORE UPDATE ON public.settlements FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER transfers_touch BEFORE UPDATE ON public.transfers FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE POLICY incomes_authorized_read ON public.incomes FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.driver_profiles dp WHERE dp.id = driver_profile_id AND dp.profile_id = (SELECT app.auth_profile_id()))
    OR app.auth_has_role('supervisor', station_id) OR app.auth_has_role('management', station_id) OR app.auth_has_role('direction')
);
CREATE POLICY cash_deposits_authorized_read ON public.cash_deposits FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.driver_profiles dp WHERE dp.id = driver_profile_id AND dp.profile_id = (SELECT app.auth_profile_id()))
    OR app.auth_has_role('supervisor', station_id) OR app.auth_has_role('management', station_id) OR app.auth_has_role('direction')
);
CREATE POLICY cash_charges_authorized_read ON public.cash_charges FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.driver_profiles dp WHERE dp.id = driver_profile_id AND dp.profile_id = (SELECT app.auth_profile_id()))
    OR app.auth_has_role('supervisor', station_id) OR app.auth_has_role('management', station_id) OR app.auth_has_role('direction')
);
CREATE POLICY bank_accounts_authorized_read ON public.bank_accounts FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.driver_profiles dp WHERE dp.id = driver_profile_id AND dp.profile_id = (SELECT app.auth_profile_id()))
    OR app.auth_has_role('management', station_id) OR app.auth_has_role('direction')
);
CREATE POLICY settlements_authorized_read ON public.settlements FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.driver_profiles dp WHERE dp.id = driver_profile_id AND dp.profile_id = (SELECT app.auth_profile_id()))
    OR app.auth_has_role('management', station_id) OR app.auth_has_role('direction')
);
CREATE POLICY transfers_authorized_read ON public.transfers FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.settlements st JOIN public.driver_profiles dp ON dp.id = st.driver_profile_id
            WHERE st.id = settlement_id AND dp.profile_id = (SELECT app.auth_profile_id()))
    OR app.auth_has_role('management', station_id) OR app.auth_has_role('direction')
);

GRANT SELECT ON TABLE public.incomes, public.cash_deposits, public.cash_charges,
    public.bank_accounts, public.settlements, public.transfers TO authenticated;

CREATE VIEW public.bank_account_current WITH (security_invoker = true) AS
SELECT id, environment_id, station_id, driver_profile_id, bank_name, clabe_last4,
       version, status, created_at, approved_at
FROM public.bank_accounts WHERE status = 'active';
REVOKE ALL ON TABLE public.bank_account_current FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.bank_account_current TO authenticated, service_role;

CREATE VIEW public.station_daily_billing WITH (security_invoker = true) AS
SELECT i.environment_id, i.station_id, (i.reported_at AT TIME ZONE s.timezone)::date AS operating_date,
       sum(i.amount_mxn)::bigint AS billed_mxn, count(*)::bigint AS entry_count
FROM public.incomes i JOIN public.stations s ON s.id = i.station_id
GROUP BY i.environment_id, i.station_id, (i.reported_at AT TIME ZONE s.timezone)::date;
REVOKE ALL ON TABLE public.station_daily_billing FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.station_daily_billing TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.register_income(
    p_shift_id uuid, p_source text, p_amount_mxn integer, p_trips integer,
    p_external_reference text, p_evidence_path text, p_note text,
    p_reversal_of uuid, p_idempotency_key text, p_install_id text
)
RETURNS public.incomes LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app', 'auth', 'pg_temp'
AS $function$
DECLARE
    v_actor uuid; v_env uuid; v_now timestamptz; v_driver public.driver_profiles%ROWTYPE;
    v_shift public.shifts%ROWTYPE; v_original public.incomes%ROWTYPE;
    v_command public.command_log%ROWTYPE; v_income public.incomes%ROWTYPE; v_request jsonb; v_amount integer;
BEGIN
    PERFORM app.assert_driver_device_session(p_install_id);
    v_actor := app.auth_profile_id();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
    IF coalesce(btrim(p_idempotency_key),'')='' THEN RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE='22023'; END IF;
    IF p_source NOT IN ('uber','didi','cash','other') OR p_amount_mxn IS NULL OR p_amount_mxn <= 0
       OR coalesce(p_trips,0) < 0 THEN RAISE EXCEPTION 'invalid_income' USING ERRCODE='22023'; END IF;
    IF char_length(coalesce(p_note,'')) > 1000 OR char_length(coalesce(p_external_reference,'')) > 200
       OR char_length(coalesce(p_evidence_path,'')) > 1000 THEN RAISE EXCEPTION 'income_text_too_long' USING ERRCODE='22023'; END IF;
    v_env := app.current_environment_id(); v_now := app.env_now(v_env);
    v_request := jsonb_build_object('shift_id',p_shift_id,'source',p_source,'amount_mxn',p_amount_mxn,
        'trips',coalesce(p_trips,0),'external_reference',nullif(btrim(p_external_reference),''),
        'evidence_path',nullif(btrim(p_evidence_path),''),'note',nullif(btrim(p_note),''),
        'reversal_of',p_reversal_of,'install_id',btrim(p_install_id));
    SELECT * INTO v_command FROM public.command_log WHERE environment_id=v_env AND idempotency_key=btrim(p_idempotency_key) FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name<>'register_income' OR v_command.request_payload IS DISTINCT FROM v_request
           OR v_command.status<>'completed' THEN RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE='23505'; END IF;
        SELECT * INTO STRICT v_income FROM public.incomes WHERE id=(v_command.result_payload->>'income_id')::uuid;
        RETURN v_income;
    END IF;
    SELECT * INTO v_driver FROM public.driver_profiles WHERE profile_id=v_actor AND environment_id=v_env AND status='active';
    IF NOT FOUND OR NOT app.auth_has_role('driver',v_driver.station_id) THEN RAISE EXCEPTION 'active_driver_required' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_shift FROM public.shifts WHERE id=p_shift_id AND driver_profile_id=v_driver.id
        AND station_id=v_driver.station_id AND environment_id=v_env;
    IF NOT FOUND THEN RAISE EXCEPTION 'owned_shift_required' USING ERRCODE='42501'; END IF;
    v_amount := p_amount_mxn;
    IF p_reversal_of IS NOT NULL THEN
        SELECT * INTO v_original FROM public.incomes WHERE id=p_reversal_of AND driver_profile_id=v_driver.id
            AND shift_id=p_shift_id AND reversal_of IS NULL FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'reversible_income_required' USING ERRCODE='22023'; END IF;
        IF p_amount_mxn<>v_original.amount_mxn THEN RAISE EXCEPTION 'reversal_amount_mismatch' USING ERRCODE='22023'; END IF;
        v_amount := -p_amount_mxn;
    END IF;
    INSERT INTO public.command_log(environment_id,actor_profile_id,command_name,idempotency_key,status,request_payload,occurred_at)
    VALUES(v_env,v_actor,'register_income',btrim(p_idempotency_key),'accepted',v_request,v_now) RETURNING * INTO v_command;
    INSERT INTO public.incomes(environment_id,station_id,shift_id,driver_profile_id,reversal_of,source,amount_mxn,
        trips,external_reference,evidence_path,note,reported_at)
    VALUES(v_env,v_driver.station_id,p_shift_id,v_driver.id,p_reversal_of,p_source,v_amount,coalesce(p_trips,0),
        nullif(btrim(p_external_reference),''),nullif(btrim(p_evidence_path),''),nullif(btrim(p_note),''),v_now)
    RETURNING * INTO v_income;
    UPDATE public.command_log SET status='completed',result_payload=jsonb_build_object('income_id',v_income.id,'folio',v_income.folio)
        WHERE id=v_command.id;
    INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,command_id,event_type,entity_type,entity_id,metadata,occurred_at)
    VALUES(v_env,v_actor,v_driver.station_id,v_command.id,'income.registered','income',v_income.id,
        jsonb_build_object('shift_id',p_shift_id,'amount_mxn',v_amount,'source',p_source,'reversal_of',p_reversal_of),v_now);
    PERFORM app.refresh_station_live(v_driver.station_id);
    RETURN v_income;
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_cash_deposit(
    p_shift_id uuid, p_amount_mxn integer, p_bank text, p_receipt_reference text,
    p_evidence_path text, p_idempotency_key text, p_install_id text
)
RETURNS public.cash_deposits LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp'
AS $function$
DECLARE
    v_actor uuid; v_env uuid; v_now timestamptz; v_driver public.driver_profiles%ROWTYPE;
    v_shift public.shifts%ROWTYPE; v_command public.command_log%ROWTYPE; v_deposit public.cash_deposits%ROWTYPE; v_request jsonb;
BEGIN
    PERFORM app.assert_driver_device_session(p_install_id); v_actor:=app.auth_profile_id();
    IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
    IF coalesce(btrim(p_idempotency_key),'')='' OR coalesce(p_amount_mxn,0)<=0 OR coalesce(btrim(p_bank),'')=''
       OR coalesce(btrim(p_receipt_reference),'')='' OR coalesce(btrim(p_evidence_path),'')=''
       THEN RAISE EXCEPTION 'invalid_cash_deposit' USING ERRCODE='22023'; END IF;
    v_env:=app.current_environment_id(); v_now:=app.env_now(v_env);
    v_request:=jsonb_build_object('shift_id',p_shift_id,'amount_mxn',p_amount_mxn,'bank',btrim(p_bank),
        'receipt_reference',btrim(p_receipt_reference),'evidence_path',btrim(p_evidence_path),'install_id',btrim(p_install_id));
    SELECT * INTO v_command FROM public.command_log WHERE environment_id=v_env AND idempotency_key=btrim(p_idempotency_key) FOR UPDATE;
    IF FOUND THEN
        IF v_command.command_name<>'register_cash_deposit' OR v_command.request_payload IS DISTINCT FROM v_request OR v_command.status<>'completed'
          THEN RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE='23505'; END IF;
        SELECT * INTO STRICT v_deposit FROM public.cash_deposits WHERE id=(v_command.result_payload->>'deposit_id')::uuid; RETURN v_deposit;
    END IF;
    SELECT * INTO v_driver FROM public.driver_profiles WHERE profile_id=v_actor AND environment_id=v_env AND status='active';
    IF NOT FOUND OR NOT app.auth_has_role('driver',v_driver.station_id) THEN RAISE EXCEPTION 'active_driver_required' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_shift FROM public.shifts WHERE id=p_shift_id AND driver_profile_id=v_driver.id AND station_id=v_driver.station_id AND environment_id=v_env;
    IF NOT FOUND THEN RAISE EXCEPTION 'owned_shift_required' USING ERRCODE='42501'; END IF;
    INSERT INTO public.command_log(environment_id,actor_profile_id,command_name,idempotency_key,status,request_payload,occurred_at)
      VALUES(v_env,v_actor,'register_cash_deposit',btrim(p_idempotency_key),'accepted',v_request,v_now) RETURNING * INTO v_command;
    INSERT INTO public.cash_deposits(environment_id,station_id,shift_id,driver_profile_id,amount_mxn,bank,receipt_reference,evidence_path,deposited_at)
      VALUES(v_env,v_driver.station_id,p_shift_id,v_driver.id,p_amount_mxn,btrim(p_bank),btrim(p_receipt_reference),btrim(p_evidence_path),v_now)
      RETURNING * INTO v_deposit;
    UPDATE public.command_log SET status='completed',result_payload=jsonb_build_object('deposit_id',v_deposit.id,'folio',v_deposit.folio) WHERE id=v_command.id;
    INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,command_id,event_type,entity_type,entity_id,metadata,occurred_at)
      VALUES(v_env,v_actor,v_driver.station_id,v_command.id,'cash_deposit.registered','cash_deposit',v_deposit.id,
        jsonb_build_object('shift_id',p_shift_id,'amount_mxn',p_amount_mxn),v_now);
    RETURN v_deposit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_bank_account(
    p_driver_profile_id uuid, p_bank_name text, p_clabe text,
    p_idempotency_key text, p_install_id text DEFAULT NULL
)
RETURNS public.bank_accounts LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp'
AS $function$
DECLARE
    v_actor uuid; v_env uuid; v_now timestamptz; v_driver public.driver_profiles%ROWTYPE;
    v_is_owner boolean; v_is_manager boolean; v_version integer; v_status text;
    v_command public.command_log%ROWTYPE; v_account public.bank_accounts%ROWTYPE; v_request jsonb;
BEGIN
    v_actor:=app.auth_profile_id(); IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
    IF coalesce(btrim(p_idempotency_key),'')='' OR coalesce(btrim(p_bank_name),'')='' OR coalesce(btrim(p_clabe),'') !~ '^[0-9]{18}$'
      THEN RAISE EXCEPTION 'invalid_bank_account' USING ERRCODE='22023'; END IF;
    v_env:=app.current_environment_id(); v_now:=app.env_now(v_env);
    SELECT * INTO v_driver FROM public.driver_profiles WHERE id=p_driver_profile_id AND environment_id=v_env AND status='active';
    IF NOT FOUND THEN RAISE EXCEPTION 'active_driver_required' USING ERRCODE='22023'; END IF;
    v_is_owner := v_driver.profile_id=v_actor AND app.auth_has_role('driver',v_driver.station_id);
    v_is_manager := app.auth_has_role('management',v_driver.station_id) OR app.auth_has_role('direction');
    IF NOT v_is_owner AND NOT v_is_manager THEN RAISE EXCEPTION 'bank_account_forbidden' USING ERRCODE='42501'; END IF;
    IF v_is_owner THEN PERFORM app.assert_driver_device_session(p_install_id); END IF;
    v_request:=jsonb_build_object('driver_profile_id',p_driver_profile_id,'bank_name',btrim(p_bank_name),
       'clabe_last4',right(btrim(p_clabe),4),'install_id',CASE WHEN v_is_owner THEN btrim(p_install_id) ELSE NULL END);
    SELECT * INTO v_command FROM public.command_log WHERE environment_id=v_env AND idempotency_key=btrim(p_idempotency_key) FOR UPDATE;
    IF FOUND THEN
      IF v_command.command_name<>'set_bank_account' OR v_command.request_payload IS DISTINCT FROM v_request OR v_command.status<>'completed'
        THEN RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE='23505'; END IF;
      SELECT * INTO STRICT v_account FROM public.bank_accounts WHERE id=(v_command.result_payload->>'bank_account_id')::uuid; RETURN v_account;
    END IF;
    IF EXISTS(SELECT 1 FROM public.bank_accounts WHERE driver_profile_id=p_driver_profile_id AND status='pending')
      THEN RAISE EXCEPTION 'bank_account_pending_review' USING ERRCODE='23505'; END IF;
    SELECT coalesce(max(version),0)+1 INTO v_version FROM public.bank_accounts WHERE driver_profile_id=p_driver_profile_id;
    v_status:=CASE WHEN v_is_manager THEN 'active' ELSE 'pending' END;
    INSERT INTO public.command_log(environment_id,actor_profile_id,command_name,idempotency_key,status,request_payload,occurred_at)
      VALUES(v_env,v_actor,'set_bank_account',btrim(p_idempotency_key),'accepted',v_request,v_now) RETURNING * INTO v_command;
    INSERT INTO public.bank_accounts(environment_id,station_id,driver_profile_id,created_by,approved_by,bank_name,clabe_last4,version,status,created_at,approved_at)
      VALUES(v_env,v_driver.station_id,p_driver_profile_id,v_actor,NULL,btrim(p_bank_name),right(btrim(p_clabe),4),
        v_version,'pending',v_now,NULL) RETURNING * INTO v_account;
    INSERT INTO app.bank_account_secrets(bank_account_id,clabe) VALUES(v_account.id,btrim(p_clabe));
    IF v_status='active' THEN
      UPDATE public.bank_accounts SET status='superseded',superseded_by=v_account.id,superseded_at=v_now
        WHERE driver_profile_id=p_driver_profile_id AND status='active';
      UPDATE public.bank_accounts SET status='active',approved_by=v_actor,approved_at=v_now WHERE id=v_account.id RETURNING * INTO v_account;
    END IF;
    UPDATE public.command_log SET status='completed',result_payload=jsonb_build_object('bank_account_id',v_account.id,'version',v_account.version,'status',v_account.status) WHERE id=v_command.id;
    INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,command_id,event_type,entity_type,entity_id,metadata,occurred_at)
      VALUES(v_env,v_actor,v_driver.station_id,v_command.id,'bank_account.set','bank_account',v_account.id,
        jsonb_build_object('driver_profile_id',p_driver_profile_id,'version',v_version,'status',v_status,'clabe_last4',v_account.clabe_last4),v_now);
    RETURN v_account;
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_bank_account(
    p_bank_account_id uuid, p_approve boolean, p_idempotency_key text
)
RETURNS public.bank_accounts LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp'
AS $function$
DECLARE
    v_actor uuid; v_env uuid; v_now timestamptz; v_account public.bank_accounts%ROWTYPE;
    v_command public.command_log%ROWTYPE; v_request jsonb;
BEGIN
    v_actor:=app.auth_profile_id(); IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
    IF coalesce(btrim(p_idempotency_key),'')='' THEN RAISE EXCEPTION 'idempotency_key_required' USING ERRCODE='22023'; END IF;
    v_env:=app.current_environment_id(); v_now:=app.env_now(v_env);
    v_request:=jsonb_build_object('bank_account_id',p_bank_account_id,'approve',p_approve);
    SELECT * INTO v_command FROM public.command_log WHERE environment_id=v_env AND idempotency_key=btrim(p_idempotency_key) FOR UPDATE;
    IF FOUND THEN
      IF v_command.command_name<>'approve_bank_account' OR v_command.request_payload IS DISTINCT FROM v_request OR v_command.status<>'completed'
        THEN RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE='23505'; END IF;
      SELECT * INTO STRICT v_account FROM public.bank_accounts WHERE id=(v_command.result_payload->>'bank_account_id')::uuid; RETURN v_account;
    END IF;
    SELECT * INTO v_account FROM public.bank_accounts WHERE id=p_bank_account_id AND environment_id=v_env FOR UPDATE;
    IF NOT FOUND OR v_account.status<>'pending' THEN RAISE EXCEPTION 'pending_bank_account_required' USING ERRCODE='22023'; END IF;
    IF NOT (app.auth_has_role('management',v_account.station_id) OR app.auth_has_role('direction'))
      THEN RAISE EXCEPTION 'bank_account_approval_forbidden' USING ERRCODE='42501'; END IF;
    IF v_account.created_by=v_actor THEN RAISE EXCEPTION 'bank_account_dual_control_required' USING ERRCODE='42501'; END IF;
    INSERT INTO public.command_log(environment_id,actor_profile_id,command_name,idempotency_key,status,request_payload,occurred_at)
      VALUES(v_env,v_actor,'approve_bank_account',btrim(p_idempotency_key),'accepted',v_request,v_now) RETURNING * INTO v_command;
    IF p_approve THEN
      UPDATE public.bank_accounts SET status='superseded',superseded_by=v_account.id,superseded_at=v_now
        WHERE driver_profile_id=v_account.driver_profile_id AND status='active';
      UPDATE public.bank_accounts SET status='active',approved_by=v_actor,approved_at=v_now WHERE id=v_account.id RETURNING * INTO v_account;
    ELSE
      UPDATE public.bank_accounts SET status='rejected',approved_by=v_actor,approved_at=v_now WHERE id=v_account.id RETURNING * INTO v_account;
    END IF;
    UPDATE public.command_log SET status='completed',result_payload=jsonb_build_object('bank_account_id',v_account.id,'status',v_account.status) WHERE id=v_command.id;
    INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,command_id,event_type,entity_type,entity_id,metadata,occurred_at)
      VALUES(v_env,v_actor,v_account.station_id,v_command.id,'bank_account.reviewed','bank_account',v_account.id,
        jsonb_build_object('driver_profile_id',v_account.driver_profile_id,'status',v_account.status,'version',v_account.version),v_now);
    RETURN v_account;
END;
$function$;

CREATE OR REPLACE FUNCTION public.close_settlement(
    p_driver_profile_id uuid, p_period_start date, p_period_end date, p_idempotency_key text
)
RETURNS public.settlements LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp'
AS $function$
DECLARE
    v_actor uuid; v_env uuid; v_now timestamptz; v_driver public.driver_profiles%ROWTYPE; v_tz text;
    v_command public.command_log%ROWTYPE; v_settlement public.settlements%ROWTYPE; v_request jsonb;
    v_gross integer; v_charges integer;
BEGIN
    v_actor:=app.auth_profile_id(); IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
    IF coalesce(btrim(p_idempotency_key),'')='' OR p_period_start IS NULL OR p_period_end IS NULL
       OR p_period_end<p_period_start OR p_period_end-p_period_start>31 THEN RAISE EXCEPTION 'invalid_settlement_period' USING ERRCODE='22023'; END IF;
    v_env:=app.current_environment_id(); v_now:=app.env_now(v_env);
    SELECT * INTO v_driver FROM public.driver_profiles WHERE id=p_driver_profile_id AND environment_id=v_env AND status='active';
    IF NOT FOUND THEN RAISE EXCEPTION 'active_driver_required' USING ERRCODE='22023'; END IF;
    IF NOT (app.auth_has_role('management',v_driver.station_id) OR app.auth_has_role('direction'))
      THEN RAISE EXCEPTION 'settlement_close_forbidden' USING ERRCODE='42501'; END IF;
    SELECT timezone INTO STRICT v_tz FROM public.stations WHERE id=v_driver.station_id;
    IF p_period_end >= (v_now AT TIME ZONE v_tz)::date THEN RAISE EXCEPTION 'settlement_period_not_closed' USING ERRCODE='22023'; END IF;
    v_request:=jsonb_build_object('driver_profile_id',p_driver_profile_id,'period_start',p_period_start,'period_end',p_period_end);
    SELECT * INTO v_command FROM public.command_log WHERE environment_id=v_env AND idempotency_key=btrim(p_idempotency_key) FOR UPDATE;
    IF FOUND THEN
      IF v_command.command_name<>'close_settlement' OR v_command.request_payload IS DISTINCT FROM v_request OR v_command.status<>'completed'
        THEN RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE='23505'; END IF;
      SELECT * INTO STRICT v_settlement FROM public.settlements WHERE id=(v_command.result_payload->>'settlement_id')::uuid; RETURN v_settlement;
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(p_driver_profile_id::text||':'||p_period_start::text||':'||p_period_end::text,0));
    IF EXISTS(SELECT 1 FROM public.settlements WHERE driver_profile_id=p_driver_profile_id AND period_start=p_period_start AND period_end=p_period_end)
      THEN RAISE EXCEPTION 'settlement_already_closed' USING ERRCODE='23505'; END IF;
    SELECT coalesce(sum(i.amount_mxn),0)::integer INTO v_gross FROM public.incomes i JOIN public.stations s ON s.id=i.station_id
      WHERE i.driver_profile_id=p_driver_profile_id AND (i.reported_at AT TIME ZONE s.timezone)::date BETWEEN p_period_start AND p_period_end;
    SELECT coalesce(sum(c.amount_mxn),0)::integer INTO v_charges FROM public.cash_charges c JOIN public.stations s ON s.id=c.station_id
      WHERE c.driver_profile_id=p_driver_profile_id AND (c.charged_at AT TIME ZONE s.timezone)::date BETWEEN p_period_start AND p_period_end;
    IF v_gross-v_charges<0 THEN RAISE EXCEPTION 'negative_settlement_forbidden' USING ERRCODE='22023'; END IF;
    INSERT INTO public.command_log(environment_id,actor_profile_id,command_name,idempotency_key,status,request_payload,occurred_at)
      VALUES(v_env,v_actor,'close_settlement',btrim(p_idempotency_key),'accepted',v_request,v_now) RETURNING * INTO v_command;
    INSERT INTO public.settlements(environment_id,station_id,driver_profile_id,closed_by,period_start,period_end,gross_income_mxn,cash_charges_mxn,net_mxn,closed_at)
      VALUES(v_env,v_driver.station_id,p_driver_profile_id,v_actor,p_period_start,p_period_end,v_gross,v_charges,v_gross-v_charges,v_now) RETURNING * INTO v_settlement;
    UPDATE public.command_log SET status='completed',result_payload=jsonb_build_object('settlement_id',v_settlement.id,'folio',v_settlement.folio,'net_mxn',v_settlement.net_mxn) WHERE id=v_command.id;
    INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,command_id,event_type,entity_type,entity_id,metadata,occurred_at)
      VALUES(v_env,v_actor,v_driver.station_id,v_command.id,'settlement.closed','settlement',v_settlement.id,
       jsonb_build_object('driver_profile_id',p_driver_profile_id,'period_start',p_period_start,'period_end',p_period_end,'gross_income_mxn',v_gross,'cash_charges_mxn',v_charges,'net_mxn',v_gross-v_charges),v_now);
    RETURN v_settlement;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_cash_charge(
    p_driver_profile_id uuid, p_concept text, p_amount_mxn integer,
    p_reversal_of uuid, p_idempotency_key text
)
RETURNS public.cash_charges LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp'
AS $function$
DECLARE
    v_actor uuid; v_env uuid; v_now timestamptz; v_driver public.driver_profiles%ROWTYPE;
    v_original public.cash_charges%ROWTYPE; v_command public.command_log%ROWTYPE;
    v_charge public.cash_charges%ROWTYPE; v_request jsonb; v_amount integer;
BEGIN
    v_actor:=app.auth_profile_id(); IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
    IF coalesce(btrim(p_idempotency_key),'')='' OR char_length(coalesce(btrim(p_concept),'')) NOT BETWEEN 3 AND 500
       OR coalesce(p_amount_mxn,0)<=0 THEN RAISE EXCEPTION 'invalid_cash_charge' USING ERRCODE='22023'; END IF;
    v_env:=app.current_environment_id(); v_now:=app.env_now(v_env);
    SELECT * INTO v_driver FROM public.driver_profiles WHERE id=p_driver_profile_id AND environment_id=v_env AND status='active';
    IF NOT FOUND THEN RAISE EXCEPTION 'active_driver_required' USING ERRCODE='22023'; END IF;
    IF NOT (app.auth_has_role('management',v_driver.station_id) OR app.auth_has_role('direction'))
      THEN RAISE EXCEPTION 'cash_charge_forbidden' USING ERRCODE='42501'; END IF;
    v_request:=jsonb_build_object('driver_profile_id',p_driver_profile_id,'concept',btrim(p_concept),
      'amount_mxn',p_amount_mxn,'reversal_of',p_reversal_of);
    SELECT * INTO v_command FROM public.command_log WHERE environment_id=v_env AND idempotency_key=btrim(p_idempotency_key) FOR UPDATE;
    IF FOUND THEN
      IF v_command.command_name<>'record_cash_charge' OR v_command.request_payload IS DISTINCT FROM v_request OR v_command.status<>'completed'
        THEN RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE='23505'; END IF;
      SELECT * INTO STRICT v_charge FROM public.cash_charges WHERE id=(v_command.result_payload->>'cash_charge_id')::uuid; RETURN v_charge;
    END IF;
    v_amount:=p_amount_mxn;
    IF p_reversal_of IS NOT NULL THEN
      SELECT * INTO v_original FROM public.cash_charges WHERE id=p_reversal_of AND driver_profile_id=p_driver_profile_id AND reversal_of IS NULL FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'reversible_cash_charge_required' USING ERRCODE='22023'; END IF;
      IF p_amount_mxn<>v_original.amount_mxn THEN RAISE EXCEPTION 'reversal_amount_mismatch' USING ERRCODE='22023'; END IF;
      v_amount:=-p_amount_mxn;
    END IF;
    INSERT INTO public.command_log(environment_id,actor_profile_id,command_name,idempotency_key,status,request_payload,occurred_at)
      VALUES(v_env,v_actor,'record_cash_charge',btrim(p_idempotency_key),'accepted',v_request,v_now) RETURNING * INTO v_command;
    INSERT INTO public.cash_charges(environment_id,station_id,driver_profile_id,created_by,reversal_of,concept,amount_mxn,charged_at)
      VALUES(v_env,v_driver.station_id,p_driver_profile_id,v_actor,p_reversal_of,btrim(p_concept),v_amount,v_now) RETURNING * INTO v_charge;
    UPDATE public.command_log SET status='completed',result_payload=jsonb_build_object('cash_charge_id',v_charge.id,'folio',v_charge.folio) WHERE id=v_command.id;
    INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,command_id,event_type,entity_type,entity_id,metadata,occurred_at)
      VALUES(v_env,v_actor,v_driver.station_id,v_command.id,'cash_charge.recorded','cash_charge',v_charge.id,
        jsonb_build_object('driver_profile_id',p_driver_profile_id,'amount_mxn',v_amount,'reversal_of',p_reversal_of),v_now);
    RETURN v_charge;
END;
$function$;

CREATE OR REPLACE FUNCTION public.authorize_transfer(
    p_settlement_id uuid, p_expected_revision bigint, p_idempotency_key text
)
RETURNS public.transfers LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','app','auth','pg_temp'
AS $function$
DECLARE
    v_actor uuid; v_env uuid; v_now timestamptz; v_settlement public.settlements%ROWTYPE;
    v_account public.bank_accounts%ROWTYPE; v_command public.command_log%ROWTYPE; v_transfer public.transfers%ROWTYPE; v_request jsonb;
BEGIN
    v_actor:=app.auth_profile_id(); IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
    IF coalesce(btrim(p_idempotency_key),'')='' OR coalesce(p_expected_revision,0)<=0 THEN RAISE EXCEPTION 'invalid_transfer_request' USING ERRCODE='22023'; END IF;
    v_env:=app.current_environment_id(); v_now:=app.env_now(v_env);
    v_request:=jsonb_build_object('settlement_id',p_settlement_id,'expected_revision',p_expected_revision);
    SELECT * INTO v_command FROM public.command_log WHERE environment_id=v_env AND idempotency_key=btrim(p_idempotency_key) FOR UPDATE;
    IF FOUND THEN
      IF v_command.command_name<>'authorize_transfer' OR v_command.request_payload IS DISTINCT FROM v_request OR v_command.status<>'completed'
        THEN RAISE EXCEPTION 'idempotency_key_conflict' USING ERRCODE='23505'; END IF;
      SELECT * INTO STRICT v_transfer FROM public.transfers WHERE id=(v_command.result_payload->>'transfer_id')::uuid; RETURN v_transfer;
    END IF;
    SELECT * INTO v_settlement FROM public.settlements WHERE id=p_settlement_id AND environment_id=v_env FOR UPDATE;
    IF NOT FOUND OR v_settlement.status<>'available' THEN RAISE EXCEPTION 'available_settlement_required' USING ERRCODE='22023'; END IF;
    IF v_settlement.revision<>p_expected_revision THEN RAISE EXCEPTION 'stale_settlement_revision' USING ERRCODE='40001'; END IF;
    IF NOT (app.auth_has_role('management',v_settlement.station_id) OR app.auth_has_role('direction'))
      THEN RAISE EXCEPTION 'transfer_authorization_forbidden' USING ERRCODE='42501'; END IF;
    IF v_settlement.net_mxn<=0 THEN RAISE EXCEPTION 'positive_settlement_required' USING ERRCODE='22023'; END IF;
    SELECT * INTO v_account FROM public.bank_accounts WHERE driver_profile_id=v_settlement.driver_profile_id AND status='active' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'active_bank_account_required' USING ERRCODE='22023'; END IF;
    INSERT INTO public.command_log(environment_id,actor_profile_id,command_name,idempotency_key,status,request_payload,occurred_at)
      VALUES(v_env,v_actor,'authorize_transfer',btrim(p_idempotency_key),'accepted',v_request,v_now) RETURNING * INTO v_command;
    INSERT INTO public.transfers(environment_id,station_id,settlement_id,bank_account_id,authorized_by,amount_mxn,authorized_at)
      VALUES(v_env,v_settlement.station_id,v_settlement.id,v_account.id,v_actor,v_settlement.net_mxn,v_now) RETURNING * INTO v_transfer;
    UPDATE public.settlements SET status='authorized',revision=revision+1 WHERE id=v_settlement.id;
    UPDATE public.command_log SET status='completed',result_payload=jsonb_build_object('transfer_id',v_transfer.id,'folio',v_transfer.folio,'amount_mxn',v_transfer.amount_mxn) WHERE id=v_command.id;
    INSERT INTO public.audit_log(environment_id,actor_profile_id,station_id,command_id,event_type,entity_type,entity_id,metadata,occurred_at)
      VALUES(v_env,v_actor,v_settlement.station_id,v_command.id,'transfer.authorized','transfer',v_transfer.id,
       jsonb_build_object('settlement_id',v_settlement.id,'bank_account_id',v_account.id,'clabe_last4',v_account.clabe_last4,'amount_mxn',v_transfer.amount_mxn),v_now);
    RETURN v_transfer;
END;
$function$;

REVOKE ALL ON FUNCTION public.register_income(uuid,text,integer,integer,text,text,text,uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.register_cash_deposit(uuid,integer,text,text,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_bank_account(uuid,text,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_bank_account(uuid,boolean,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.close_settlement(uuid,date,date,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_cash_charge(uuid,text,integer,uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.authorize_transfer(uuid,bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_income(uuid,text,integer,integer,text,text,text,uuid,text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_cash_deposit(uuid,integer,text,text,text,text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_bank_account(uuid,text,text,text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.approve_bank_account(uuid,boolean,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.close_settlement(uuid,date,date,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_cash_charge(uuid,text,integer,uuid,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_transfer(uuid,bigint,text) TO authenticated, service_role;
