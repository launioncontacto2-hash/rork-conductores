-- 15F follow-up: cover every composite foreign key in the coverage lifecycle.
-- These indexes preserve referential-action performance as TEST data grows.

CREATE INDEX IF NOT EXISTS absences_driver_scope_idx
    ON public.absences (driver_profile_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS absences_resolver_environment_idx
    ON public.absences (resolved_by, environment_id)
    WHERE resolved_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS absences_vacancy_scope_idx
    ON public.absences (vacancy_id, station_id, environment_id)
    WHERE vacancy_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS coverage_vacancies_absence_scope_idx
    ON public.coverage_vacancies (absence_id, station_id, environment_id)
    WHERE absence_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS coverage_vacancies_approver_environment_idx
    ON public.coverage_vacancies (approved_by, environment_id)
    WHERE approved_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS coverage_vacancies_opener_environment_idx
    ON public.coverage_vacancies (opened_by, environment_id);

CREATE INDEX IF NOT EXISTS coverage_vacancies_titular_scope_idx
    ON public.coverage_vacancies (titular_driver_profile_id, station_id, environment_id)
    WHERE titular_driver_profile_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS coverage_vacancies_vehicle_scope_idx
    ON public.coverage_vacancies (vehicle_id, station_id, environment_id)
    WHERE vehicle_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS coverage_claims_driver_scope_idx
    ON public.coverage_claims (driver_profile_id, station_id, environment_id);

CREATE INDEX IF NOT EXISTS coverage_claims_vacancy_scope_idx
    ON public.coverage_claims (vacancy_id, station_id, environment_id);
