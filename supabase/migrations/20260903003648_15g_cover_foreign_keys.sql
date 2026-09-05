-- 15G follow-up: cover every composite foreign key in the financial lifecycle.
-- These indexes keep referential checks and scoped joins predictable as TEST grows.

CREATE INDEX IF NOT EXISTS incomes_shift_scope_fkey_idx
    ON public.incomes (shift_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS incomes_driver_scope_fkey_idx
    ON public.incomes (driver_profile_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS cash_deposits_shift_scope_fkey_idx
    ON public.cash_deposits (shift_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS cash_deposits_driver_scope_fkey_idx
    ON public.cash_deposits (driver_profile_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS cash_charges_driver_scope_fkey_idx
    ON public.cash_charges (driver_profile_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS cash_charges_creator_environment_fkey_idx
    ON public.cash_charges (created_by, environment_id);

CREATE INDEX IF NOT EXISTS bank_accounts_driver_scope_fkey_idx
    ON public.bank_accounts (driver_profile_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS bank_accounts_creator_environment_fkey_idx
    ON public.bank_accounts (created_by, environment_id);

CREATE INDEX IF NOT EXISTS bank_accounts_approver_environment_fkey_idx
    ON public.bank_accounts (approved_by, environment_id)
    WHERE approved_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS settlements_driver_scope_fkey_idx
    ON public.settlements (driver_profile_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS settlements_closer_environment_fkey_idx
    ON public.settlements (closed_by, environment_id);

CREATE INDEX IF NOT EXISTS transfers_settlement_scope_fkey_idx
    ON public.transfers (settlement_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS transfers_bank_account_scope_fkey_idx
    ON public.transfers (bank_account_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS transfers_authorizer_environment_fkey_idx
    ON public.transfers (authorized_by, environment_id);
