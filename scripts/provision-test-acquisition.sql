-- Provisiona las dos identidades y la solicitud simulada de DORI Adquisicion.
--
-- Requisitos previos, exclusivamente en el proyecto TEST:
--   1. Crear y confirmar adquisiciones.pue@dori.mx en Supabase Auth.
--   2. Crear y confirmar byd.iztacalco@dori.mx en Supabase Auth.
--
-- Las contrasenas nunca deben copiarse a este archivo ni al repositorio.
-- Este script no se ejecuta automaticamente desde una migracion y se niega a
-- operar si el entorno actual no es TEST.

BEGIN;

DO $block$
DECLARE
    v_environment_id uuid;
    v_supplier_id uuid;
    v_admin_auth_user_id uuid;
    v_provider_auth_user_id uuid;
    v_admin_profile_id constant uuid := 'ad300000-0000-4000-8000-000000000001';
    v_provider_profile_id constant uuid := 'ad300000-0000-4000-8000-000000000002';
    v_admin_membership_id constant uuid := 'ad310000-0000-4000-8000-000000000001';
    v_provider_membership_id constant uuid := 'ad310000-0000-4000-8000-000000000002';
    v_request_id constant uuid := 'ad320000-0000-4000-8000-000000000001';
    v_dori_contact_id constant uuid := 'ad330000-0000-4000-8000-000000000001';
    v_provider_contact_id constant uuid := 'ad330000-0000-4000-8000-000000000002';
BEGIN
    SELECT environment.id INTO STRICT v_environment_id
    FROM public.environments environment
    WHERE environment.code = 'test';

    IF app.current_environment_id() <> v_environment_id THEN
        RAISE EXCEPTION 'acquisition_provision_test_environment_required'
            USING ERRCODE = '42501';
    END IF;

    SELECT auth_user.id INTO v_admin_auth_user_id
    FROM auth.users auth_user
    WHERE lower(auth_user.email) = 'adquisiciones.pue@dori.mx';

    SELECT auth_user.id INTO v_provider_auth_user_id
    FROM auth.users auth_user
    WHERE lower(auth_user.email) = 'byd.iztacalco@dori.mx';

    IF v_admin_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'auth_user_test_acquisition_admin_required'
            USING ERRCODE = 'P0002';
    END IF;
    IF v_provider_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'auth_user_test_acquisition_provider_required'
            USING ERRCODE = 'P0002';
    END IF;
    IF EXISTS (
        SELECT 1 FROM auth.users auth_user
        WHERE auth_user.id IN (v_admin_auth_user_id, v_provider_auth_user_id)
          AND auth_user.email_confirmed_at IS NULL
    ) THEN
        RAISE EXCEPTION 'acquisition_test_auth_users_must_be_confirmed'
            USING ERRCODE = '22023';
    END IF;

    SELECT supplier.id INTO STRICT v_supplier_id
    FROM public.acquisition_suppliers supplier
    WHERE supplier.environment_id = v_environment_id
      AND supplier.code = 'PROV-PUE-A'
      AND supplier.status = 'active';

    IF EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.auth_user_id IN (v_admin_auth_user_id, v_provider_auth_user_id)
          AND profile.id NOT IN (v_admin_profile_id, v_provider_profile_id)
    ) THEN
        RAISE EXCEPTION 'acquisition_test_auth_profile_conflict'
            USING ERRCODE = '23505';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id IN (v_admin_profile_id, v_provider_profile_id)
          AND profile.environment_id <> v_environment_id
    ) OR EXISTS (
        SELECT 1 FROM public.acquisition_memberships membership
        WHERE membership.id IN (v_admin_membership_id, v_provider_membership_id)
          AND membership.environment_id <> v_environment_id
    ) OR EXISTS (
        SELECT 1 FROM public.acquisition_requests request
        WHERE request.id = v_request_id
          AND request.environment_id <> v_environment_id
    ) THEN
        RAISE EXCEPTION 'acquisition_test_fixture_cross_environment_conflict'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.profiles(
        id, environment_id, auth_user_id, employee_number, display_name, status
    ) VALUES
        (
            v_admin_profile_id, v_environment_id, v_admin_auth_user_id,
            'ADQ-TEST-ADMIN', 'Administrador DORI Adquisicion', 'active'
        ),
        (
            v_provider_profile_id, v_environment_id, v_provider_auth_user_id,
            'ADQ-TEST-PROV-001', 'Agencia Puebla Centro', 'active'
        )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        auth_user_id = EXCLUDED.auth_user_id,
        employee_number = EXCLUDED.employee_number,
        display_name = EXCLUDED.display_name,
        status = 'active';

    INSERT INTO public.acquisition_memberships(
        id, environment_id, profile_id, supplier_id, role, status,
        starts_at, ends_at
    ) VALUES
        (
            v_admin_membership_id, v_environment_id, v_admin_profile_id,
            NULL, 'dori_admin', 'active', '2000-01-01 00:00:00+00', NULL
        ),
        (
            v_provider_membership_id, v_environment_id, v_provider_profile_id,
            v_supplier_id, 'provider', 'active', '2000-01-01 00:00:00+00', NULL
        )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        profile_id = EXCLUDED.profile_id,
        supplier_id = EXCLUDED.supplier_id,
        role = EXCLUDED.role,
        status = 'active',
        starts_at = EXCLUDED.starts_at,
        ends_at = NULL;

    INSERT INTO public.acquisition_requests(
        id, environment_id, code, title, target_quantity, model, versions,
        minimum_year, maximum_year, maximum_mileage, delivery_city,
        deadline_at, status, created_by, created_at, updated_at
    ) VALUES (
        v_request_id, v_environment_id, 'ADQ-TEST-001',
        '15 autos requeridos', 15, 'Dolphin Mini', ARRAY['Plus'],
        2025, 2026, 20000, 'Puebla',
        app.env_now(v_environment_id) + interval '30 days', 'published',
        v_admin_profile_id, app.env_now(v_environment_id), app.env_now(v_environment_id)
    )
    ON CONFLICT (id) DO UPDATE
    SET title = EXCLUDED.title,
        target_quantity = EXCLUDED.target_quantity,
        model = EXCLUDED.model,
        versions = EXCLUDED.versions,
        minimum_year = EXCLUDED.minimum_year,
        maximum_year = EXCLUDED.maximum_year,
        maximum_mileage = EXCLUDED.maximum_mileage,
        delivery_city = EXCLUDED.delivery_city,
        deadline_at = EXCLUDED.deadline_at,
        status = CASE
            WHEN public.acquisition_requests.status IN ('closed', 'cancelled')
            THEN public.acquisition_requests.status
            ELSE 'published'
        END,
        updated_at = app.env_now(v_environment_id);

    INSERT INTO public.acquisition_request_rules(
        request_id, environment_id, target_soh, minimum_soh,
        internal_price_limit_mxn, created_at
    ) VALUES (
        v_request_id, v_environment_id, 95, 85, 280000,
        app.env_now(v_environment_id)
    )
    ON CONFLICT (request_id, environment_id) DO UPDATE
    SET target_soh = EXCLUDED.target_soh,
        minimum_soh = EXCLUDED.minimum_soh,
        internal_price_limit_mxn = EXCLUDED.internal_price_limit_mxn;

    INSERT INTO public.acquisition_contacts(
        id, environment_id, supplier_id, organization_name, person_name,
        job_title, phone, email, business_hours, is_primary, status,
        created_at, updated_at
    ) VALUES
        (
            v_dori_contact_id, v_environment_id, NULL, 'DORI Puebla',
            'Jorge Ramos', 'Supervisor de adquisiciones', '222 000 0000',
            'adquisiciones.pue@dori.mx', '09:00 a 18:00', true, 'active',
            app.env_now(v_environment_id), app.env_now(v_environment_id)
        ),
        (
            v_provider_contact_id, v_environment_id, v_supplier_id,
            'Agencia Puebla Centro', 'Laura Méndez',
            'Gerente de seminuevos', '222 000 0000',
            'byd.iztacalco@dori.mx', '09:00 a 18:00', true, 'active',
            app.env_now(v_environment_id), app.env_now(v_environment_id)
        )
    ON CONFLICT (id) DO UPDATE
    SET environment_id = EXCLUDED.environment_id,
        supplier_id = EXCLUDED.supplier_id,
        organization_name = EXCLUDED.organization_name,
        person_name = EXCLUDED.person_name,
        job_title = EXCLUDED.job_title,
        phone = EXCLUDED.phone,
        email = EXCLUDED.email,
        business_hours = EXCLUDED.business_hours,
        is_primary = EXCLUDED.is_primary,
        status = 'active',
        updated_at = app.env_now(v_environment_id);

    IF NOT EXISTS (
        SELECT 1
        FROM public.acquisition_memberships admin_membership
        JOIN public.acquisition_memberships provider_membership
          ON provider_membership.environment_id = admin_membership.environment_id
        JOIN public.acquisition_requests request
          ON request.environment_id = admin_membership.environment_id
        WHERE admin_membership.id = v_admin_membership_id
          AND admin_membership.role = 'dori_admin'
          AND provider_membership.id = v_provider_membership_id
          AND provider_membership.role = 'provider'
          AND provider_membership.supplier_id = v_supplier_id
          AND request.id = v_request_id
          AND request.status = 'published'
          AND EXISTS (
              SELECT 1 FROM public.acquisition_contacts contact
              WHERE contact.id IN (v_dori_contact_id, v_provider_contact_id)
                AND contact.environment_id = v_environment_id
                AND contact.status = 'active'
          )
    ) THEN
        RAISE EXCEPTION 'acquisition_test_provision_verification_failed'
            USING ERRCODE = 'P0001';
    END IF;
END;
$block$;

COMMIT;

SELECT
    profile.employee_number,
    lower(auth_user.email) AS auth_email,
    membership.role,
    supplier.name AS supplier_name,
    request.code AS active_request
FROM public.profiles profile
JOIN auth.users auth_user ON auth_user.id = profile.auth_user_id
JOIN public.acquisition_memberships membership
  ON membership.profile_id = profile.id
 AND membership.ends_at IS NULL
LEFT JOIN public.acquisition_suppliers supplier
  ON supplier.id = membership.supplier_id
CROSS JOIN public.acquisition_requests request
WHERE membership.environment_id = request.environment_id
  AND request.code = 'ADQ-TEST-001'
  AND profile.employee_number IN ('ADQ-TEST-ADMIN', 'ADQ-TEST-PROV-001')
ORDER BY profile.employee_number;
