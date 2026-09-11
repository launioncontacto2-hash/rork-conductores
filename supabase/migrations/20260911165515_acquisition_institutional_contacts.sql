-- Contactos institucionales de DORI Adquisicion.
-- La tabla es de consulta para el cliente. El alta y mantenimiento quedan
-- reservados a procesos administrativos posteriores y nunca se realizan
-- directamente desde SwiftUI.

CREATE TABLE public.acquisition_contacts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    supplier_id uuid,
    organization_name text NOT NULL,
    person_name text NOT NULL,
    job_title text NOT NULL,
    phone text NOT NULL,
    email text NOT NULL,
    business_hours text NOT NULL,
    is_primary boolean NOT NULL DEFAULT false,
    status text NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT acquisition_contacts_environment_fkey
        FOREIGN KEY (environment_id) REFERENCES public.environments(id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_contacts_supplier_environment_fkey
        FOREIGN KEY (supplier_id, environment_id)
        REFERENCES public.acquisition_suppliers(id, environment_id) ON DELETE RESTRICT,
    CONSTRAINT acquisition_contacts_organization_not_blank CHECK (btrim(organization_name) <> ''),
    CONSTRAINT acquisition_contacts_person_not_blank CHECK (btrim(person_name) <> ''),
    CONSTRAINT acquisition_contacts_title_not_blank CHECK (btrim(job_title) <> ''),
    CONSTRAINT acquisition_contacts_phone_not_blank CHECK (btrim(phone) <> ''),
    CONSTRAINT acquisition_contacts_email_not_blank CHECK (btrim(email) <> ''),
    CONSTRAINT acquisition_contacts_hours_not_blank CHECK (btrim(business_hours) <> ''),
    CONSTRAINT acquisition_contacts_email_shape CHECK (position('@' IN email) > 1),
    CONSTRAINT acquisition_contacts_status_check CHECK (status IN ('active', 'inactive')),
    CONSTRAINT acquisition_contacts_id_environment_unique UNIQUE (id, environment_id)
);

CREATE INDEX acquisition_contacts_environment_supplier_status_idx
    ON public.acquisition_contacts(environment_id, supplier_id, status);

CREATE UNIQUE INDEX acquisition_contacts_primary_scope_unique
    ON public.acquisition_contacts(environment_id, supplier_id) NULLS NOT DISTINCT
    WHERE is_primary AND status = 'active';

ALTER TABLE public.acquisition_contacts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.acquisition_contacts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.acquisition_contacts TO authenticated;
GRANT ALL ON TABLE public.acquisition_contacts TO postgres, service_role;

CREATE POLICY acquisition_contacts_read ON public.acquisition_contacts
FOR SELECT TO authenticated USING (
    environment_id = app.current_environment_id()
    AND status = 'active'
    AND (
        app.auth_is_acquisition_admin()
        OR (
            app.auth_acquisition_supplier_id() IS NOT NULL
            AND (
                supplier_id IS NULL
                OR supplier_id = app.auth_acquisition_supplier_id()
            )
        )
    )
);

COMMENT ON TABLE public.acquisition_contacts IS
    'Directorio institucional de DORI y sus proveedores, aislado por entorno y proveedor.';
COMMENT ON COLUMN public.acquisition_contacts.supplier_id IS
    'NULL identifica un contacto institucional DORI; un UUID identifica al proveedor propietario.';
