-- =====================================================================
--  TurnoEV · Laboratorio · Fase 2
--  Reloj lógico compartido del entorno de PRUEBA
--
--  Proyecto: turno-ev-laboratorio (yyxzuiantrmoyozetswv)
--  Este esquema pertenece EXCLUSIVAMENTE al proyecto de laboratorio.
--  No debe ejecutarse en un proyecto de Producción.
--
--  Alcance deliberado de esta migración:
--    · crea test_environment, test_clock y test_events
--    · siembra UN entorno de prueba y SU reloj
--    · activa RLS en las tres tablas
--    · concede al cliente anónimo lo mínimo: leer entorno, leer reloj,
--      actualizar el reloj de un entorno marcado como 'test'
--    · publica test_clock en Realtime
--
--  Lo que esta migración NO hace, a propósito:
--    · no toca asistencia, vehículos, cobertura, usuarios ni pagos
--    · no abre test_events al cliente (queda cerrada hasta su fase)
--    · no concede INSERT ni DELETE sobre ninguna tabla
--  Reproducible: puede ejecutarse varias veces sin efectos adicionales.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Entorno de prueba
-- ---------------------------------------------------------------------
create table if not exists public.test_environment (
    id         uuid primary key default gen_random_uuid(),
    name       text        not null,
    status     text        not null default 'test',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.test_environment is
    'Entornos de simulación del laboratorio. status = ''test'' habilita la escritura del reloj desde los clientes.';

-- ---------------------------------------------------------------------
-- 2. Reloj lógico (modelo de anclas, NO segundo a segundo)
--
--    Ningún cliente escribe la hora que corre. Se guarda un ancla:
--    un instante simulado clavado a un instante real, más la velocidad.
--    Cada dispositivo deriva la hora localmente:
--       pausado  -> anchor_simulated_at
--       corriendo-> anchor_simulated_at
--                   + (real_now - anchor_real_at) * speed
-- ---------------------------------------------------------------------
create table if not exists public.test_clock (
    environment_id      uuid primary key
                        references public.test_environment (id) on delete cascade,
    anchor_simulated_at timestamptz      not null,
    anchor_real_at      timestamptz      not null,
    speed               double precision not null default 1,
    is_paused           boolean          not null default true,
    revision            bigint           not null default 1,
    updated_at          timestamptz      not null default now(),

    -- La velocidad se conserva al pausar: is_paused es el interruptor,
    -- speed es el ritmo al que se reanuda. Por eso nunca es 0.
    constraint test_clock_speed_positive check (speed > 0),
    constraint test_clock_revision_positive check (revision > 0)
);

comment on column public.test_clock.revision is
    'Contador monótono. Un cliente jamás debe aceptar una revisión menor o igual a la que ya posee.';

-- El servidor sella la hora de escritura: el cliente no la envía.
create or replace function public.test_clock_touch()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists test_clock_touch on public.test_clock;
create trigger test_clock_touch
    before update on public.test_clock
    for each row execute function public.test_clock_touch();

-- ---------------------------------------------------------------------
-- 3. Bitácora de eventos del entorno
--    Se crea ahora para fijar la forma; permanece CERRADA al cliente
--    en esta fase (RLS activo, sin política permisiva).
-- ---------------------------------------------------------------------
create table if not exists public.test_events (
    id             uuid primary key default gen_random_uuid(),
    environment_id uuid        not null
                   references public.test_environment (id) on delete cascade,
    event_type     text        not null,
    payload        jsonb       not null default '{}'::jsonb,
    created_at     timestamptz not null default now()
);

create index if not exists test_events_environment_created_idx
    on public.test_events (environment_id, created_at desc);

-- ---------------------------------------------------------------------
-- 4. Semilla: un entorno de laboratorio y su reloj
--    El id es fijo y conocido por la app (LabEnvironment.sharedTestId).
-- ---------------------------------------------------------------------
insert into public.test_environment (id, name, status)
values ('9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10', 'Laboratorio TurnoEV', 'test')
on conflict (id) do nothing;

insert into public.test_clock (
    environment_id, anchor_simulated_at, anchor_real_at, speed, is_paused, revision
)
values (
    '9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10', now(), now(), 1, true, 1
)
on conflict (environment_id) do nothing;

-- ---------------------------------------------------------------------
-- 5. Row Level Security
--    Se activa en las TRES tablas. Nunca se desactiva.
-- ---------------------------------------------------------------------
alter table public.test_environment enable row level security;
alter table public.test_clock       enable row level security;
alter table public.test_events      enable row level security;

-- Leer el entorno: sólo los marcados como 'test'.
drop policy if exists test_environment_read on public.test_environment;
create policy test_environment_read
    on public.test_environment
    for select
    to anon, authenticated
    using (status = 'test');

-- Leer el reloj: sólo el de un entorno de prueba.
drop policy if exists test_clock_read on public.test_clock;
create policy test_clock_read
    on public.test_clock
    for select
    to anon, authenticated
    using (
        exists (
            select 1 from public.test_environment e
            where e.id = test_clock.environment_id
              and e.status = 'test'
        )
    );

-- Actualizar el reloj: SÓLO el de un entorno de prueba.
-- No hay política de INSERT ni de DELETE: la fila la crea esta migración
-- y ningún cliente puede añadir ni borrar relojes.
drop policy if exists test_clock_update on public.test_clock;
create policy test_clock_update
    on public.test_clock
    for update
    to anon, authenticated
    using (
        exists (
            select 1 from public.test_environment e
            where e.id = test_clock.environment_id
              and e.status = 'test'
        )
    )
    with check (
        exists (
            select 1 from public.test_environment e
            where e.id = test_clock.environment_id
              and e.status = 'test'
        )
    );

-- test_events: RLS activo y SIN política. Queda denegada por defecto
-- para anon y authenticated hasta que su fase lo justifique.

-- ---------------------------------------------------------------------
-- 6. Privilegios explícitos (mínimos)
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

revoke all on public.test_environment from anon, authenticated;
revoke all on public.test_clock       from anon, authenticated;
revoke all on public.test_events      from anon, authenticated;

grant select                       on public.test_environment to anon, authenticated;
grant select                       on public.test_clock       to anon, authenticated;
grant update (
    anchor_simulated_at,
    anchor_real_at,
    speed,
    is_paused,
    revision
)                                  on public.test_clock       to anon, authenticated;

-- ---------------------------------------------------------------------
-- 7. Realtime: se publica ÚNICAMENTE test_clock
-- ---------------------------------------------------------------------
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename  = 'test_clock'
    ) then
        alter publication supabase_realtime add table public.test_clock;
    end if;
end $$;
