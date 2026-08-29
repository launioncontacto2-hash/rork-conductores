-- =====================================================================
-- TurnoEV · 15B bridge antes de 15C
-- Alineacion aditiva de identidad, entorno y region.
--
-- Objetivo:
--   - crear regions
--   - anadir environment_id a profiles y staff_memberships
--   - anadir region_id y legacy_code a stations
--   - anadir legacy_code a profiles
--   - conservar IDs y auth_user_id actuales
--
-- Esta migracion NO cambia profiles.id ni remapea auth.users.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Regiones
-- ---------------------------------------------------------------------

CREATE TABLE public.regions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    environment_id uuid NOT NULL,
    code text NOT NULL,
    legacy_code text,
    name text NOT NULL,
    status text NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT regions_environment_id_fkey
        FOREIGN KEY (environment_id)
        REFERENCES public.environments(id)
        ON DELETE RESTRICT,

    CONSTRAINT regions_code_not_blank
        CHECK (btrim(code) <> ''),

    CONSTRAINT regions_name_not_blank
        CHECK (btrim(name) <> ''),

    CONSTRAINT regions_status_check
        CHECK (status IN ('active', 'inactive')),

    CONSTRAINT regions_environment_code_unique
        UNIQUE (environment_id, code)
);

CREATE INDEX regions_environment_idx
    ON public.regions(environment_id);

ALTER TABLE public.regions
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.regions FROM anon, authenticated;
GRANT SELECT ON TABLE public.regions TO authenticated;
GRANT ALL ON TABLE public.regions TO postgres, service_role;

-- ---------------------------------------------------------------------
-- 2. Columnas nuevas, primero nullable
-- ---------------------------------------------------------------------

ALTER TABLE public.profiles
    ADD COLUMN environment_id uuid,
    ADD COLUMN legacy_code text;

ALTER TABLE public.staff_memberships
    ADD COLUMN environment_id uuid;

ALTER TABLE public.stations
    ADD COLUMN region_id uuid,
    ADD COLUMN legacy_code text;

-- ---------------------------------------------------------------------
-- 3. Backfill del entorno
-- ---------------------------------------------------------------------

-- La membresia hereda el entorno de su estacion.
UPDATE public.staff_memberships m
SET environment_id = s.environment_id
FROM public.stations s
WHERE s.id = m.station_id
  AND m.environment_id IS NULL;

-- El perfil hereda el entorno de su membresia.
UPDATE public.profiles p
SET environment_id = m.environment_id
FROM public.staff_memberships m
WHERE m.profile_id = p.id
  AND p.environment_id IS NULL;

-- Defensa adicional para instalaciones reproducibles con un unico
-- entorno fisico disponible.
UPDATE public.profiles p
SET environment_id = app.current_environment_id()
WHERE p.environment_id IS NULL;

-- ---------------------------------------------------------------------
-- 4. Region bootstrap por entorno
-- ---------------------------------------------------------------------

INSERT INTO public.regions (
    environment_id,
    code,
    legacy_code,
    name,
    status
)
SELECT
    e.id,
    'default',
    NULL,
    CASE
        WHEN e.code = 'test' THEN 'Region laboratorio'
        WHEN e.code = 'prod' THEN 'Region inicial'
        ELSE 'Region inicial'
    END,
    'active'
FROM public.environments e
ON CONFLICT (environment_id, code) DO NOTHING;

UPDATE public.stations s
SET region_id = r.id
FROM public.regions r
WHERE r.environment_id = s.environment_id
  AND r.code = 'default'
  AND s.region_id IS NULL;

-- ---------------------------------------------------------------------
-- 5. Endurecer nulabilidad y referencias
-- ---------------------------------------------------------------------

ALTER TABLE public.profiles
    ALTER COLUMN environment_id SET NOT NULL;

ALTER TABLE public.staff_memberships
    ALTER COLUMN environment_id SET NOT NULL;

ALTER TABLE public.stations
    ALTER COLUMN region_id SET NOT NULL;

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_environment_id_fkey
        FOREIGN KEY (environment_id)
        REFERENCES public.environments(id)
        ON DELETE RESTRICT;

ALTER TABLE public.staff_memberships
    ADD CONSTRAINT staff_memberships_environment_id_fkey
        FOREIGN KEY (environment_id)
        REFERENCES public.environments(id)
        ON DELETE RESTRICT;

ALTER TABLE public.stations
    ADD CONSTRAINT stations_region_id_fkey
        FOREIGN KEY (region_id)
        REFERENCES public.regions(id)
        ON DELETE RESTRICT;

-- ---------------------------------------------------------------------
-- 6. Defensa contra referencias cruzadas de entorno
-- ---------------------------------------------------------------------

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_id_environment_unique
        UNIQUE (id, environment_id);

ALTER TABLE public.stations
    ADD CONSTRAINT stations_id_environment_unique
        UNIQUE (id, environment_id);

ALTER TABLE public.staff_memberships
    DROP CONSTRAINT staff_memberships_profile_id_fkey;

ALTER TABLE public.staff_memberships
    DROP CONSTRAINT staff_memberships_station_id_fkey;

ALTER TABLE public.staff_memberships
    ADD CONSTRAINT staff_memberships_profile_environment_fkey
        FOREIGN KEY (profile_id, environment_id)
        REFERENCES public.profiles(id, environment_id)
        ON DELETE RESTRICT;

ALTER TABLE public.staff_memberships
    ADD CONSTRAINT staff_memberships_station_environment_fkey
        FOREIGN KEY (station_id, environment_id)
        REFERENCES public.stations(id, environment_id)
        ON DELETE RESTRICT;

ALTER TABLE public.regions
    ADD CONSTRAINT regions_id_environment_unique
        UNIQUE (id, environment_id);

ALTER TABLE public.stations
    DROP CONSTRAINT stations_region_id_fkey;

ALTER TABLE public.stations
    ADD CONSTRAINT stations_region_environment_fkey
        FOREIGN KEY (region_id, environment_id)
        REFERENCES public.regions(id, environment_id)
        ON DELETE RESTRICT;

-- ---------------------------------------------------------------------
-- 7. Indices
-- ---------------------------------------------------------------------

CREATE INDEX profiles_environment_idx
    ON public.profiles(environment_id);

CREATE INDEX staff_memberships_environment_idx
    ON public.staff_memberships(environment_id);

CREATE INDEX stations_region_idx
    ON public.stations(region_id);

CREATE INDEX regions_status_idx
    ON public.regions(environment_id, status);

-- ---------------------------------------------------------------------
-- 7.1 RLS de regiones una vez disponible profiles.environment_id
-- ---------------------------------------------------------------------

CREATE POLICY regions_authenticated_read
ON public.regions
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = app.auth_profile_id()
          AND p.environment_id = regions.environment_id
    )
);

-- ---------------------------------------------------------------------
-- 8. Comprobaciones finales
-- ---------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.staff_memberships m
        JOIN public.profiles p
          ON p.id = m.profile_id
        JOIN public.stations s
          ON s.id = m.station_id
        WHERE m.environment_id <> p.environment_id
           OR m.environment_id <> s.environment_id
    ) THEN
        RAISE EXCEPTION 'membership_environment_mismatch'
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.stations s
        JOIN public.regions r
          ON r.id = s.region_id
        WHERE s.environment_id <> r.environment_id
    ) THEN
        RAISE EXCEPTION 'station_region_environment_mismatch'
            USING ERRCODE = '23514';
    END IF;
END;
$$;
