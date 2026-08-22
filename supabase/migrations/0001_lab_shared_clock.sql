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
--    · concede al cliente anónimo lo mínimo: LEER entorno y reloj
--    · expone update_test_clock() como ÚNICA vía de escritura del reloj:
--      la revisión se asigna en el servidor, bajo bloqueo de fila
--    · publica test_clock en Realtime
--
--  Lo que esta migración NO hace, a propósito:
--    · no toca asistencia, vehículos, cobertura, usuarios ni pagos
--    · no abre test_events al cliente (queda cerrada hasta su fase)
--    · no concede INSERT, UPDATE ni DELETE directos sobre ninguna tabla
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
    'Contador monótono asignado SIEMPRE por update_test_clock(), nunca por el cliente. Un cliente jamás debe aceptar una revisión menor o igual a la que ya posee.';

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

-- NO hay política de UPDATE, INSERT ni DELETE sobre test_clock.
-- El cliente no escribe la tabla: llama a update_test_clock() (sección 6),
-- que es quien decide la revisión. Si un día alguien concediera UPDATE por
-- error, la ausencia de política seguiría bloqueando la escritura directa.
drop policy if exists test_clock_update on public.test_clock;

-- test_events: RLS activo y SIN política. Queda denegada por defecto
-- para anon y authenticated hasta que su fase lo justifique.

-- ---------------------------------------------------------------------
-- 6. Privilegios explícitos (mínimos)
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

revoke all on public.test_environment from anon, authenticated;
revoke all on public.test_clock       from anon, authenticated;
revoke all on public.test_events      from anon, authenticated;

-- Sólo lectura. La escritura ocurre exclusivamente dentro de
-- update_test_clock(), que se ejecuta con los privilegios de su dueño.
grant select on public.test_environment to anon, authenticated;
grant select on public.test_clock       to anon, authenticated;

-- ---------------------------------------------------------------------
-- 7. Escritura atómica del reloj
--
--    Única vía de escritura. Resuelve la carrera entre dos dispositivos
--    que parten de la misma revisión N:
--
--      · SELECT ... FOR UPDATE serializa a los dos llamantes sobre la
--        única fila del entorno. El segundo espera al primero.
--      · La revisión final la calcula el servidor (revision + 1) ya con
--        el bloqueo tomado, así que jamás se emiten dos N+1.
--      · En READ COMMITTED, cuando el segundo obtiene el bloqueo su
--        SELECT vuelve a evaluar la fila y ve YA la revisión del primero.
--        Si venía anunciando la revisión N sobre la que se paró
--        (p_expected_revision), la comparación falla y se levanta un
--        conflicto explícito en vez de pisar el cambio ajeno.
--
--    SECURITY DEFINER: el cliente no tiene UPDATE sobre la tabla, de modo
--    que no puede escribir la revisión ni por accidente ni a propósito.
--    Al saltarse RLS, la función reproduce aquí la misma condición que
--    exigen las políticas de lectura: el entorno debe ser de prueba.
-- ---------------------------------------------------------------------
drop function if exists public.update_test_clock(
    uuid, timestamptz, timestamptz, double precision, boolean, bigint
);

create function public.update_test_clock(
    p_environment_id      uuid,
    p_anchor_simulated_at timestamptz,
    p_anchor_real_at      timestamptz,
    p_speed               double precision,
    p_is_paused           boolean,
    p_expected_revision   bigint default null
)
returns public.test_clock
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_status           text;
    v_current_revision bigint;
    v_row              public.test_clock;
begin
    -- La velocidad se conserva al pausar; 0 no es un ritmo válido.
    if p_speed is null or p_speed <= 0 then
        raise exception 'speed_must_be_positive' using errcode = '22023';
    end if;

    if p_anchor_simulated_at is null or p_anchor_real_at is null or p_is_paused is null then
        raise exception 'anchor_incomplete' using errcode = '22023';
    end if;

    -- Producción nunca se toca desde un dispositivo.
    select e.status into v_status
    from public.test_environment e
    where e.id = p_environment_id;

    if v_status is null then
        raise exception 'environment_not_found' using errcode = 'P0002';
    end if;

    if v_status <> 'test' then
        raise exception 'environment_not_test' using errcode = '42501';
    end if;

    -- Bloqueo de la única fila del entorno: a partir de aquí, un solo
    -- llamante a la vez. El resto espera.
    select c.revision into v_current_revision
    from public.test_clock c
    where c.environment_id = p_environment_id
    for update;

    if v_current_revision is null then
        raise exception 'clock_not_found' using errcode = 'P0002';
    end if;

    -- Concurrencia optimista declarada por el cliente: dice sobre qué
    -- revisión estaba parado. Si la fila avanzó mientras tanto, esto NO
    -- se resuelve pisando: se devuelve el conflicto y el cliente recarga.
    if p_expected_revision is not null and p_expected_revision <> v_current_revision then
        raise exception 'revision_conflict expected=% current=%',
            p_expected_revision, v_current_revision
            using errcode = '40001';
    end if;

    update public.test_clock c
       set anchor_simulated_at = p_anchor_simulated_at,
           anchor_real_at      = p_anchor_real_at,
           speed               = p_speed,
           is_paused           = p_is_paused,
           revision            = c.revision + 1
     where c.environment_id = p_environment_id
    returning c.* into v_row;

    return v_row;
end;
$$;

comment on function public.update_test_clock is
    'Única vía de escritura del reloj de laboratorio. Bloquea la fila del entorno, asigna revision = revision + 1 en el servidor y actualiza anclas, velocidad y pausa en una sola sentencia. Devuelve la fila final.';

-- El dueño de la función es quien ejecuta esta migración (rol privilegiado):
-- es lo que permite que la función escriba una tabla que el cliente no puede.
revoke all on function public.update_test_clock(
    uuid, timestamptz, timestamptz, double precision, boolean, bigint
) from public;

grant execute on function public.update_test_clock(
    uuid, timestamptz, timestamptz, double precision, boolean, bigint
) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 8. Realtime: se publica ÚNICAMENTE test_clock
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
