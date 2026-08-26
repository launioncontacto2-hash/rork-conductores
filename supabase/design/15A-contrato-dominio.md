# FASE 15A · Contrato, identidad y frontera de datos

Documento de diseño. **No ejecuta migraciones.** Ninguna tabla productiva se crea
hasta cerrar las decisiones abiertas del §13.

Decisiones vinculantes recibidas:

1. PROD y PRUEBA en **proyectos Supabase físicamente separados**. `environment_id`
   se conserva como defensa en profundidad, no como frontera primaria.
2. **Android congelado** durante 15A–15H. iOS es cliente de referencia; Web es el
   segundo cliente real.
3. **Migración de IDs internos ahora.** Los códigos legibles dejan de ser PK.
4. **El servidor es la única autoridad de reglas.** El cliente valida de forma
   *predictiva*, nunca suficiente.

---

## 0 · Regla de autoridad (principio rector del contrato)

Toda regla de negocio existe, como mucho, en dos lugares, y con rangos distintos:

| | Servidor (SQL / RPC) | Cliente (Swift / TS) |
|---|---|---|
| Naturaleza | **Autoritativa** | **Predictiva** |
| Propósito | Aceptar o rechazar la operación | Anticipar el resultado para la UX |
| Si discrepan | **Gana el servidor, siempre** | Se corrige y se muestra el motivo |
| Puede faltar | No | Sí (degrada la UX, no la corrección) |
| Puede estar mal | Es un defecto crítico | Es un defecto de UX |

**Convención de nombres obligatoria.** Todo validador de cliente se nombra
`canX`, `isXAllowed` o `xPredicate`. Ninguno se llama `validateX` ni `assertX`:
esos nombres quedan reservados al servidor. Un revisor debe poder distinguir el
rango leyendo sólo el identificador.

Ejemplo canónico:

```
Swift (predictivo)                    Servidor (autoritativo)
─────────────────────────────────     ─────────────────────────────────────
ShiftRules.canStartShift(now:)        start_shift(p_assignment_id, …)
  → habilita/deshabilita el botón       → re-verifica TODO:
  → explica al conductor por qué           usuario autenticado
     todavía no puede                      membresía vigente y su rol
                                           estación de la membresía
                                           ventana horaria del turno
                                           asignación vigente y propia
                                           vehículo disponible y sin turno
                                           ningún turno abierto del conductor
                                           entorno coincidente
                                           revisión esperada
                                           exclusiones (índices únicos)
```

El cliente **nunca** manda un estado calculado (p. ej. "el turno vale 8 h", "la
meta es $18,240"). Manda **hechos e intención**; el servidor deriva.

---

## 1 · ERD textual

```
                              ┌──────────────┐
                              │ environments │  (TEST: N filas · PROD: 1 fila 'prod')
                              └──────┬───────┘
                                     │ environment_id (defensa en profundidad)
        ┌────────────────────────────┼────────────────────────────┐
        │                            │                            │
   ┌────▼────┐                 ┌─────▼─────┐               ┌──────▼──────┐
   │ regions │◄────────────────┤ stations  │◄──────────────┤ station_    │
   └─────────┘   region_id     └─────┬─────┘  station_id   │ capacity_   │
                                     │                     │ grants      │ (append-only, fechado)
                                     │                     └─────────────┘
   auth.users (Supabase Auth)        │
        │ 1:1                        │
   ┌────▼─────┐                      │
   │ profiles │  identidad de la persona · NO cambia nunca
   └────┬─────┘
        │ 1:N
   ┌────▼──────────────┐   station_id   ┌───────────┐
   │ staff_memberships ├───────────────►│ stations  │
   │  role · vigencia  │                └───────────┘
   └────┬──────────────┘
        │ 0..1  (sólo si role = 'driver')
   ┌────▼───────────┐
   │ driver_profiles│  datos laborales del conductor
   └────┬───────────┘
        │
        │            ┌──────────┐        ┌──────────────────────────┐
        │            │ vehicles ├───────►│ vehicle_state_transitions│ (append-only)
        │            └────┬─────┘        └──────────────────────────┘
        │                 │
        │   ┌─────────────▼──────────────┐
        └──►│        assignments         │  UNIQUE parcial: 1 vehículo activo, 1 conductor activo
            └─────────────┬──────────────┘
                          │
                    ┌─────▼─────┐
                    │  shifts   │  revision · máquina de estados
                    └─┬───┬───┬─┘
      ┌───────────────┘   │   └───────────────┐
┌─────▼──────────┐  ┌─────▼────┐      ┌───────▼────────┐
│ shift_readings │  │ incomes  │      │   incidents    │
│  (append-only) │  │(append+  │      │ (revision)     │
└────────────────┘  │ reversa) │      └───────┬────────┘
                    └────┬─────┘              │
                         │                ┌───▼──────────┐    ┌────────────────────┐
                         │                │ work_orders  ├───►│ work_order_updates │ (append-only)
                         │                └──────────────┘    └────────────────────┘
                         │
              ┌──────────▼───────────┐   ┌───────────────┐   ┌────────────────┐
              │  cash_deposits (AO)  │   │ cash_charges  │   │   settlements  │
              └──────────────────────┘   └───────────────┘   └───────┬────────┘
                                                                     │
                        ┌────────────────┐                   ┌───────▼────────┐
                        │ bank_accounts  │◄──────────────────┤   transfers    │ (state machine + idempotencia)
                        │  (versionado)  │                   └────────────────┘
                        └────────────────┘
              ┌─────────┐        ┌────────────────┐
              │ credits ├───────►│ credit_payments│ (append-only)
              └─────────┘        └────────────────┘

   COBERTURA
   ┌───────────┐      ┌────────────────────┐      ┌──────────────────┐
   │ absences  ├─────►│ coverage_vacancies ├─────►│ coverage_claims  │
   └───────────┘      └────────────────────┘      └──────────────────┘
                       UNIQUE parcial: 1 claim ganador por vacante

   RR. HH. / RECLUTAMIENTO
   ┌────────────┐   ┌──────────────────┐   ┌──────────┐   ┌───────────┐
   │ candidates ├──►│ candidate_events │   │ hirings  ├──►│ documents │
   └────────────┘   │  (append-only)   │   └──────────┘   └───────────┘
                    └──────────────────┘

   TRANSVERSAL
   ┌──────────┐  ┌──────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │ policies │  │  alerts  │  │  audit_log   │  │ command_log  │  │ station_live │
   │(versionada)│ │(manuales)│  │(append-only) │  │(idempotencia)│  │ (proyección) │
   └──────────┘  └──────────┘  └──────────────┘  └──────────────┘  └──────────────┘
   ┌──────────┐
   │ devices  │  enrolamiento + última actividad (Consola 0.1)
   └──────────┘

   SÓLO EN EL PROYECTO TEST
   ┌──────────────────┐  ┌────────────┐  ┌─────────────┐
   │ test_environment │  │ test_clock │  │ test_events │
   └──────────────────┘  └────────────┘  └─────────────┘
```

---

## 2 · Catálogo de entidades

### 2.1 Entidades que NO se crean, y por qué

Se te entregó una lista mínima. Tres de sus miembros **no deben ser tablas**:

| Pedida | Decisión | Motivo |
|---|---|---|
| `station_capacity` | **No es tabla propia** → `station_capacity_grants` (append-only, fechada) + vista `station_capacity_current` | La capacidad la autoriza Gerencia y cambia en el tiempo. Un `int` mutable en `stations` borra la historia de quién autorizó qué y desde cuándo. |
| facturación diaria de estación (`StationGoalLedger`) | **Vista**, no tabla | Es `sum(incomes)` agrupado. Materializar una suma derivable es exactamente el origen de la divergencia `goalBoard`/`goalProgress` detectada en Fase 14. Si el `EXPLAIN` lo exige, se materializa **después**, con medición. |
| alertas derivadas (tolerancia, aging, `dueAt`) | **No se persisten** | Son funciones puras de datos que ya viven en tablas. Persistirlas crea un segundo estado que puede contradecir al primero. Sólo las alertas **manuales** son filas. |

Y una que sí se añade y no estaba en la lista:

| Añadida | Motivo |
|---|---|
| `command_log` | Sin ella no hay idempotencia real. Es el prerrequisito de `transfers`, de la cola offline y de cualquier reintento seguro. Debe existir antes de la primera escritura productiva, no después. |
| `devices` | La Consola 0.1 pide "estado de conexión / última actividad". Ese dato no existe hoy en ninguna parte. |
| `station_live` | Proyección compacta que evita que Dirección y la consola se suscriban a cada fila operativa del país (§7). |

### 2.2 Catálogo

Leyenda: **Rev** = `revision` para concurrencia optimista · **Soft** = borrado lógico ·
**Env** = lleva `environment_id` · **Est** = alcance por estación.

| # | Tabla | PK | Claves humanas | FK principales | Est | Env | Rev | Timestamps | Soft |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `environments` | `id uuid` | `code` | — | — | — | no | `created_at` | no |
| 2 | `regions` | `id uuid` | `code`, `legacy_code` | `environment_id` | — | ✅ | no | c/u | ✅ |
| 3 | `stations` | `id uuid` | `code`, `legacy_code` | `region_id` | propia | ✅ | no | c/u | ✅ |
| 4 | `profiles` | `id uuid` = `auth.users.id` | `employee_number`, `legacy_code` | — | ❌ | ✅ | no | c/u | ✅ |
| 5 | `staff_memberships` | `id uuid` | — | `profile_id`, `station_id` | ✅ | ✅ | no | c/u | **no** (se cierra con `valid_to`) |
| 6 | `driver_profiles` | `id uuid` | `employee_number` | `profile_id`, `station_id` | ✅ | ✅ | sí | c/u | ✅ |
| 7 | `vehicles` | `id uuid` | `internal_number`, `plate`, `vin`, `qr_code`, `legacy_code` | `station_id` | ✅ | ✅ | sí | c/u | ✅ |
| 8 | `vehicle_state_transitions` | `id uuid` | — | `vehicle_id`, `actor_id` | ✅ | ✅ | **AO** | `created_at` | no |
| 9 | `assignments` | `id uuid` | — | `driver_profile_id`, `vehicle_id`, `station_id`, `assigned_by` | ✅ | ✅ | no¹ | c/u | no (se cierra con `ended_at`) |
| 10 | `shifts` | `id uuid` | `folio` | `driver_profile_id`, `vehicle_id`, `assignment_id`, `station_id` | ✅ | ✅ | **sí** | c/u | no |
| 11 | `shift_readings` | `id uuid` | — | `shift_id`, `vehicle_id` | ✅ | ✅ | **AO** | `captured_at`, `created_at` | no |
| 12 | `incomes` | `id uuid` | `folio` | `shift_id`, `driver_profile_id` | ✅ | ✅ | **AO²** | `created_at` | no |
| 13 | `cash_deposits` | `id uuid` | `reference` | `driver_profile_id`, `shift_id` | ✅ | ✅ | **AO** | `created_at` | no |
| 14 | `cash_charges` | `id uuid` | — | `driver_profile_id` | ✅ | ✅ | **AO** | `created_at` | no |
| 15 | `incidents` | `id uuid` | `folio`, `legacy_code` | `shift_id`, `vehicle_id`, `reported_by`, `station_id` | ✅ | ✅ | **sí** | c/u | no |
| 16 | `work_orders` | `id uuid` | `folio`, `legacy_code` | `vehicle_id`, `incident_id?`, `station_id`, `opened_by` | ✅ | ✅ | **sí** | c/u | no |
| 17 | `work_order_updates` | `id uuid` | — | `work_order_id`, `actor_id` | ✅ | ✅ | **AO** | `created_at` | no |
| 18 | `absences` | `id uuid` | `folio` | `driver_profile_id`, `station_id`, `resolved_by?` | ✅ | ✅ | sí | c/u | no |
| 19 | `coverage_vacancies` | `id uuid` | `folio` | `absence_id?`, `station_id`, `opened_by` | ✅ | ✅ | no¹ | c/u | no |
| 20 | `coverage_claims` | `id uuid` | — | `vacancy_id`, `driver_profile_id` | ✅ | ✅ | no¹ | c/u | no |
| 21 | `settlements` | `id uuid` | `folio` | `driver_profile_id`, `station_id` | ✅ | ✅ | **sí** | c/u | no |
| 22 | `transfers` | `id uuid` | `folio` | `settlement_id`, `bank_account_id`, `authorized_by?` | ✅ | ✅ | **SM³** | c/u | no |
| 23 | `bank_accounts` | `id uuid` | `clabe_last4` | `driver_profile_id` | ✅ | ✅ | **versión⁴** | c/u | no |
| 24 | `credits` | `id uuid` | `folio` | `driver_profile_id` | ✅ | ✅ | sí | c/u | no |
| 25 | `credit_payments` | `id uuid` | — | `credit_id` | ✅ | ✅ | **AO** | `created_at` | no |
| 26 | `documents` | `id uuid` | — | `subject_type`+`subject_id`, `station_id`, `uploaded_by` | ✅ | ✅ | sí | c/u | ✅ |
| 27 | `candidates` | `id uuid` | `folio`, `legacy_code` | `station_id`, `owner_id` | ✅ | ✅ | **sí** | c/u | ✅ |
| 28 | `candidate_events` | `id uuid` | — | `candidate_id`, `actor_id` | ✅ | ✅ | **AO** | `created_at` | no |
| 29 | `hirings` | `id uuid` | `folio` | `candidate_id`, `profile_id?`, `station_id`, `signed_by` | ✅ | ✅ | sí | c/u | no |
| 30 | `station_capacity_grants` | `id uuid` | — | `station_id`, `granted_by` | ✅ | ✅ | **AO** | `effective_from`, `created_at` | no |
| 31 | `policies` | `id uuid` | `key` | `station_id?`, `set_by` | opc. | ✅ | **versión⁴** | c/u | no |
| 32 | `alerts` | `id uuid` | — | `station_id?`, `created_by`, `resolved_by?` | opc. | ✅ | sí | c/u | no |
| 33 | `audit_log` | `id uuid` | — | `actor_id`, `station_id?` | opc. | ✅ | **AO** | `at` (servidor) | **nunca** |
| 34 | `command_log` | `id uuid` | `idempotency_key` | `actor_id` | opc. | ✅ | **AO** | `created_at` | no |
| 35 | `devices` | `id uuid` | `install_id` | `profile_id` | ❌ | ✅ | no | c/u, `last_seen_at` | ✅ |
| 36 | `station_live` | `station_id uuid` | — | `station_id` | propia | ✅ | no | `updated_at` | no |

**AO** = append-only.
¹ Exclusividad por índice único parcial, no por revisión (§6).
² `incomes` es append-only con **asiento de reversa**: un registro erróneo no se
   edita ni se borra, se compensa con una fila `reversal_of`.
³ Máquina de estados + idempotencia, no revisión (§6).
⁴ Versionado por filas: una nueva versión cierra la anterior (`superseded_by`).

### 2.3 Vistas (no tablas)

| Vista | Deriva de | Sustituye a |
|---|---|---|
| `station_capacity_current` | `station_capacity_grants` | `turnoev.station.capacity.<id>` |
| `station_daily_billing` | `incomes` × `shifts` × fecha | `StationGoalLedger` |
| `assignment_current` | `assignments where ended_at is null` | `AssignmentBook` |
| `bank_account_current` | `bank_accounts where superseded_by is null` | `CashAccount` |
| `policy_current` | `policies where superseded_by is null` | `AbsencePolicy` |

---

## 3 · Identidad: legacy → UUID

### 3.1 Estrategia de generación — decisión y su cláusula de salida

**Hallazgo de infraestructura.** UUIDv7 **no está disponible limpiamente en
Supabase hoy**:

- La extensión `pg_uuidv7` no existe en la plataforma
  (`ERROR: extension "pg_uuidv7" is not available (SQLSTATE 0A000)`).
- `uuidv7()` nativo aparece en **Postgres 18**; Supabase no lo sirve por defecto
  todavía.
- El *version pinning* de extensiones quedó deprecado en 2026-08, así que
  instalar una variante propia tampoco es una vía limpia.

Aplicando la regla que fijaste, la decisión es **UUID estándar generado
server-side**, con una indirección de una línea que evita repetir esta discusión:

```sql
-- Única fuente de identificadores del dominio.
-- Hoy delega en gen_random_uuid() (v4).
-- Cuando el proyecto corra Postgres 18, se sustituye SÓLO el cuerpo por
-- uuidv7(). Ni una definición de tabla cambia: siguen siendo `uuid`.
create or replace function public.new_id() returns uuid
language sql volatile parallel safe as $$
  select gen_random_uuid()
$$;

-- Uso uniforme, sin excepciones:
--   id uuid primary key default public.new_id()
```

**Una sola estrategia. Sin ULID. Sin mezcla.** El requisito de orden temporal que
habría motivado v7 se cubre con índices explícitos `(station_id, created_at desc, id)`
en las tablas append-only de volumen — que es lo que las consultas usan de todos
modos, y no depende de la versión de UUID.

**El cliente nunca genera un ID de dominio.** Excepción única y acotada: la cola
offline (§ Fase 15, punto 7) genera un `client_ref uuid` que **no es** la PK; el
servidor asigna la PK real y devuelve el mapeo.

### 3.2 Tabla de migración de fixtures

Los códigos actuales pasan a **campos humanos** y a `legacy_code`. Ninguna FK los
referencia jamás.

| Entidad actual | Ejemplo hoy | PK nueva | Clave humana | `legacy_code` | Ocurrencias en código |
|---|---|---|---|---|---|
| Conductor | `drv-1042` | `driver_profiles.id uuid` | `employee_number = "1042"` | `"drv-1042"` | 9 |
| Vehículo | `veh-014` | `vehicles.id uuid` | `internal_number = "TEV-014"`, `plate`, `vin`, `qr_code` | `"veh-014"` | 16 |
| Cuenta | `acc-sup`, `acc-mto` | `profiles.id uuid` (= `auth.users.id`) | `employee_number` | `"acc-sup"` | 27 |
| Estación | `est-*` | `stations.id uuid` | `code = "EST-CDMX-01"` | `"est-*"` | 27 |
| Región | (dentro de `Region`) | `regions.id uuid` | `code` | legacy | — |
| Incidencia | `inc-*` | `incidents.id uuid` | `folio` generado | `"inc-*"` | 6 |
| Orden taller | `wo-validate` | `work_orders.id uuid` | `folio` generado | `"wo-validate"` | 4 |

> Nota: las cifras son **ocurrencias de literal en el código**, no entidades
> distintas. El censo exacto de entidades se hace con el script de siembra, que
> es idempotente y reporta el conteo real antes de escribir.

Reglas de la columna `legacy_code`:

```sql
legacy_code text,
constraint <t>_legacy_code_unique unique (environment_id, legacy_code)
```

- **Nullable.** Toda entidad nacida después de 15A la deja en `NULL`.
- **Única por entorno.** Impide sembrar dos veces el mismo fixture.
- **Sin índice de búsqueda operativa.** Existe para la migración y la
  trazabilidad, no para consultar en caliente.
- **Fecha de retiro explícita:** al cerrar 15H se verifica que ningún código de
  cliente la lea; a partir de ahí sólo es histórico.

### 3.3 Frontera de compatibilidad durante la transición

15A **no reemplaza los IDs Swift**. Define la frontera y nada más:

```
┌─ Dominio remoto ────────────┐   ┌─ Frontera ─────┐   ┌─ App actual ────────────┐
│ vehicles.id      uuid       │   │  RemoteRef     │   │ Vehicle.id  String      │
│ vehicles.legacy_code text   │◄──┤  uuid ↔ legacy ├──►│ "veh-014"               │
│ vehicles.internal_number    │   │  (tabla mapa)  │   │ (intacto en 15A)        │
└─────────────────────────────┘   └────────────────┘   └─────────────────────────┘
```

Mecanismo de mapeo, en tres pasos y por fase:

1. **15A** — El servidor guarda `legacy_code`. El cliente no cambia. Existe un
   endpoint de resolución `resolve_legacy(entity, code) → uuid` usado sólo por
   los scripts de siembra y verificación.
2. **15B–15H** — Cada fase que servidoriza una entidad introduce en Swift un
   `RemoteId` opaco **junto** al `String` existente. El tipo Swift gana un campo
   `remoteId: UUID?` nullable; nada se rompe mientras sea `nil`.
3. **Cierre de cada fase** — Cuando el servidor es autoridad de esa entidad, el
   `String` legible pasa a ser presentación (`internalNumber`, `employeeNumber`) y
   `remoteId` deja de ser opcional. La clave `UserDefaults` se borra.

**Prohibido en 15A:** cambiar el tipo de un `id` en Swift, renombrar campos de
`Domain.swift`/`Organization.swift`, o tocar `MockData`.

---

## 4 · Usuarios, perfiles y roles

### 4.1 Decisión: `driver ≠ user`, y `role` es una tabla

La pregunta que planteaste tiene una respuesta con consecuencias fuertes, así que
va explícita.

**Hoy** `StaffAccount` mezcla cinco cosas en una fila: identidad (`name`, `email`),
credencial (`password` en claro), rol (`role`), adscripción (`stationId`,
`regionId`, `slot`) y vínculo laboral (`driverId`). Cuando un supervisor cambia de
estación, **hay que editar la identidad de la persona**. Cuando alguien asciende de
conductor a supervisor, se rompe `driverId`. Eso no escala a red nacional.

**Modelo adoptado — cuatro capas:**

```
auth.users            Supabase Auth. Credencial. Nunca la tocamos a mano.
    │ 1:1 (id compartido)
profiles              La PERSONA. Nombre, foto, teléfono, employee_number.
    │                 Inmutable frente a cambios de puesto. Nunca se borra.
    │ 1:N
staff_memberships     El PUESTO. (profile_id, station_id, role, valid_from, valid_to)
    │                 Cambiar de estación = cerrar una membresía y abrir otra.
    │                 La historia laboral queda escrita, no sobrescrita.
    │ 0..1  sólo cuando role='driver'
driver_profiles       Los DATOS LABORALES del conductor: grupo, bloque, antigüedad,
                      unidad titular. No existen para un supervisor.
```

### 4.2 ¿Rol único, tabla, o múltiples roles?

| Opción | Veredicto |
|---|---|
| Campo único en `profiles` | **Rechazado.** Reproduce el defecto actual: un ascenso reescribe la identidad y borra la historia. |
| Tabla de membresías, **una activa** | **Rechazado por insuficiente.** El gerente que cubre dos estaciones o el reclutador regional no caben, y ese caso ya existe en la red descrita. |
| **Tabla de membresías, múltiples activas** | **Adoptado.** |

Con dos restricciones que impiden que "múltiple" degenere en ambigüedad:

```sql
-- Una persona no puede tener dos veces el MISMO rol en la MISMA estación a la vez.
create unique index staff_memberships_active_unique
  on staff_memberships (profile_id, station_id, role)
  where valid_to is null;

-- Un conductor sólo puede estar activo en UNA estación. Su turno, su unidad y su
-- cartera pertenecen a una sola operación.
create unique index staff_memberships_single_active_driver
  on staff_memberships (profile_id)
  where valid_to is null and role = 'driver';
```

**Rol activo de la sesión.** Una persona con varias membresías elige una al entrar
(igual que hoy elige interfaz). El rol elegido **no viaja en el JWT** (§5.2); se
guarda en `devices.active_membership_id` y el servidor lo verifica contra
`staff_memberships` en cada operación. Si la membresía se cerró, la siguiente
operación falla con `membership_revoked` y la app vuelve al selector.

### 4.3 El JWT no es la base de datos

El token lleva **lo mínimo que no puede cambiar durante su vigencia**:

| Claim | Contenido | Por qué ahí |
|---|---|---|
| `sub` | `profiles.id` | Identidad. No cambia nunca. |
| `environment` | `'prod'` \| `'test'` | Coherencia con el proyecto. No cambia sin cerrar sesión. |
| `role` (Supabase) | `authenticated` | Requisito de la plataforma. |

**No lleva:** `station_id`, `region_ids`, rol de negocio, capacidad, permisos.
Todo eso se resuelve server-side contra `staff_memberships` (§5.2), que es
exactamente lo que hace que una revocación surta efecto **en la siguiente
consulta** y no cuando expire el token.

---

## 5 · RLS

### 5.1 Forma de las políticas

Tres funciones auxiliares, `stable security definer`, resuelven todo el alcance:

```sql
-- Estaciones donde el sujeto tiene HOY una membresía viva con alguno de los roles dados.
create or replace function public.auth_stations(p_roles text[])
returns setof uuid language sql stable security definer set search_path = public as $$
  select m.station_id
  from public.staff_memberships m
  where m.profile_id = auth.uid()
    and m.valid_to is null
    and m.role = any(p_roles)
$$;

create or replace function public.auth_has_role(p_roles text[]) returns boolean …
create or replace function public.auth_driver_profile() returns uuid …
```

Política tipo (supervisión sobre turnos de su estación):

```sql
create policy shifts_read_supervisor on public.shifts
  for select to authenticated
  using (station_id in (select public.auth_stations(array['supervisor','manager'])));
```

**Coste y mitigación.** Son funciones `stable`: Postgres las evalúa una vez por
sentencia, no por fila. `staff_memberships` lleva
`index (profile_id) where valid_to is null` — el conjunto vivo de una persona es
de 1 a 3 filas. Es una lectura de índice por consulta, no un join por fila.

### 5.2 Revocación sin esperar a que caduque el token

Esta es la razón de fondo para sacar `station_id` del JWT. Comparación explícita:

| | `station_id` en el JWT | Alcance resuelto en cada consulta |
|---|---|---|
| Mover a alguien de estación | Sigue viendo la anterior **hasta que expire el token** (típicamente 1 h) | Efecto **inmediato**, en la siguiente consulta |
| Suspender una cuenta | Sigue operando hasta el refresh | Efecto inmediato |
| Degradar un rol | Ídem | Efecto inmediato |
| Forzar el corte antes | Sólo revocando *todas* las sesiones | Innecesario |
| Coste | 0 lecturas | 1 lectura de índice por sentencia |

Se paga una lectura de índice para eliminar una ventana de una hora en la que
alguien opera con autoridad que ya le fue retirada. En un sistema que autoriza
transferencias de dinero, esa ventana no es aceptable.

**Además**, `staff_memberships` es realtime para el propio sujeto: al cerrarse su
membresía, su dispositivo recibe el cambio y la app cambia de pantalla sola, sin
esperar al primer rechazo.

### 5.3 Matriz RLS

Leyenda: **S**=select · **I**=insert · **U**=update · **D**=delete ·
**RPC**=sólo vía función `security definer` · **—**=sin acceso ·
*(p)*=filas propias · *(e)*=su estación · *(r)*=su región · *(el)*=elegibles.

| Tabla | Conductor | Supervisor | Taller | Gerencia | Dirección | Reclutamiento | Lab |
|---|---|---|---|---|---|---|---|
| `environments` | S | S | S | S | S | S | S |
| `regions` | S | S | S | S | S | S | S |
| `stations` | S*(e)* | S*(e)* | S*(e)* | S*(r)* | S | S*(e)* | S+RPC |
| `profiles` | S*(p)* | S*(e)* | S*(e)* | S*(r)* | S | S*(e)* | S+RPC |
| `staff_memberships` | S*(p)* | S*(e)* | S*(e)* | S*(r)* | S+RPC | S*(e)* | S+RPC |
| `driver_profiles` | S*(p)*, U*(p)*ᵃ | S*(e)* | S*(e)* | S*(r)* | S | S*(e)*+RPC | S+RPC |
| `vehicles` | S*(asignado)* | S*(e)* | S*(e)*+RPC | S*(r)* | S | — | S+RPC |
| `vehicle_state_transitions` | — | S*(e)*+RPC | S*(e)*+RPC | S*(r)* | S | — | S+RPC |
| `assignments` | S*(p)* | S*(e)*+**RPC** | S*(e)* | S*(r)* | S | — | RPC |
| `shifts` | S*(p)*+**RPC** | S*(e)*+RPC | S*(e)* | S*(r)* | S | — | RPC |
| `shift_readings` | S*(p)*+**RPC** | S*(e)* | S*(e)* | S*(r)* | S | — | RPC |
| `incomes` | S*(p)*+**RPC** | S*(e)* | — | S*(r)* | S | — | RPC |
| `cash_deposits` | S*(p)*+**RPC** | S*(e)* | — | S*(r)* | S | — | RPC |
| `cash_charges` | S*(p)* | S*(e)*+RPC | — | S*(r)*+RPC | S | — | RPC |
| `incidents` | S*(p)*+**RPC** | S*(e)*+RPC | S*(e)*+RPC | S*(r)* | S | — | RPC |
| `work_orders` | S*(su unidad)* | S*(e)* | S*(e)*+**RPC** | S*(r)* | S | — | RPC |
| `work_order_updates` | — | S*(e)* | S*(e)*+RPC | S*(r)* | S | — | RPC |
| `absences` | S*(p)*+**RPC** | S*(e)*+RPC | — | S*(r)* | S | — | RPC |
| `coverage_vacancies` | S*(el)* | S*(e)*+RPC | — | S*(r)* | S | — | RPC |
| `coverage_claims` | S*(p)*+**RPC** | S*(e)*+RPC | — | S*(r)* | S | — | RPC |
| `settlements` | S*(p)* | — | — | S*(r)* | S | — | RPC |
| `transfers` | S*(p)* | — | — | S*(r)*+**RPC** | S | — | RPC |
| `bank_accounts` | S*(p)*ᵇ+**RPC** | — | — | S*(r)*ᵇ+RPC | Sᵇ | — | RPC |
| `credits` | S*(p)*+RPC | — | — | S*(r)* | S | — | RPC |
| `credit_payments` | S*(p)* | — | — | S*(r)* | S | — | RPC |
| `documents` | S*(p)*+RPC | S*(e)* | S*(e)*+RPC | S*(r)* | S | S*(e)*+RPC | RPC |
| `candidates` | — | — | — | S*(r)* | S | S*(e)*+**RPC** | RPC |
| `candidate_events` | — | — | — | S*(r)* | S | S*(e)*+RPC | RPC |
| `hirings` | S*(p)* | S*(e)* | — | S*(r)* | S | S*(e)*+**RPC** | RPC |
| `station_capacity_grants` | — | S*(e)* | — | S*(r)*+**RPC** | S+RPC | S*(e)* | RPC |
| `policies` | S | S*(e)* | S*(e)* | S*(r)*+RPC | S+RPC | S*(e)* | RPC |
| `alerts` | S*(audiencia)* | S*(e)*+RPC | S*(e)*+RPC | S*(r)*+RPC | S+RPC | S*(e)* | RPC |
| `audit_log` | — | — | — | S*(r)* | S | — | S*(test)* |
| `command_log` | S*(p)* | S*(p)* | S*(p)* | S*(p)* | S*(p)* | S*(p)* | S*(p)* |
| `devices` | S*(p)*+RPC | S*(p)* | S*(p)* | S*(p)* | S | S*(p)* | S |
| `station_live` | — | S*(e)* | S*(e)* | S*(r)* | S | — | S |

ᵃ Sólo campos de preferencia personal, jamás grupo/bloque/estación.
ᵇ **Nunca la CLABE completa.** La política expone `clabe_last4` y `bank_name`; el
número íntegro sólo es legible por la RPC de dispersión (§8).

**Regla transversal:** `DELETE` no está concedido a **ningún** rol en **ninguna**
tabla. Lo que deja de valer se cierra (`valid_to`, `ended_at`, `superseded_by`) o
se marca (`deleted_at`). El borrado físico es una operación de mantenimiento con
credencial de servicio, fuera de la app.

---

## 6 · Concurrencia

No se añade `revision` mecánicamente. Cada entidad recibe **el mecanismo más
barato que sea suficiente**.

### 6.1 Matriz

| Entidad | Mecanismo | Justificación |
|---|---|---|
| `assignments` | **Índice único parcial + transacción** | El invariante es de *exclusión*, no de *edición concurrente*. Dos supervisores no editan la misma fila: crean filas que compiten. La base lo resuelve mejor que cualquier revisión. |
| `coverage_claims` | **`SELECT … FOR UPDATE` en RPC + único parcial** | Réplica exacta de `update_test_clock`. Serializa a los reclamantes sobre la vacante; el segundo obtiene `vacancy_already_claimed`, no un error genérico. |
| `shifts` | **`revision` (optimistic)** | Única entidad que conductor y supervisor editan **de verdad a la vez** (el conductor cierra, el supervisor corrige). Campos disjuntos por rol reducen el conflicto, no lo eliminan. |
| `incidents`, `work_orders` | **`revision`** | Edición colaborativa real entre supervisor y taller. |
| `absences`, `credits`, `settlements`, `documents`, `candidates`, `hirings`, `alerts`, `driver_profiles`, `vehicles` | **`revision`** | Editables por más de un actor, con ventanas de solape plausibles. |
| `transfers` | **Máquina de estados + `idempotency_key`** | El riesgo no es sobrescribir: es **pagar dos veces**. Una revisión no lo impide; un único parcial sobre `status='authorized'` más una clave de idempotencia, sí. |
| `bank_accounts`, `policies` | **Versionado por filas** | Nunca se edita: se emite versión nueva y se cierra la anterior. Auditable por construcción. |
| `shift_readings`, `incomes`, `cash_deposits`, `cash_charges`, `credit_payments`, `work_order_updates`, `candidate_events`, `vehicle_state_transitions`, `station_capacity_grants` | **Append-only** | Un hecho registrado no se edita. La corrección es un asiento nuevo (`reversal_of`). Sin concurrencia posible. |
| `audit_log`, `command_log` | **Append-only, sin `UPDATE`/`DELETE` para nadie** | Si se pueden alterar, no son auditoría. |
| `staff_memberships` | **Cierre por `valid_to` + único parcial** | Nunca se edita una membresía: se cierra y se abre otra. |
| `station_live` | **Last-write-wins deliberado** | Es una proyección reconstruible desde las tablas fuente. Perder una escritura sólo retrasa un dashboard. Es el **único** LWW del sistema y está declarado como tal. |

### 6.2 Contrato de `revision`

```
El cliente envía   : p_expected_revision (la que tenía en pantalla)
El servidor asigna : revision = revision + 1, bajo bloqueo, siempre
Si difieren        : excepción 40001 'revision_conflict expected=% current=%'
El cliente         : recarga, MUESTRA qué cambió y quién lo cambió, y
                     pide confirmación explícita. Nunca reintenta en silencio.
```

Idéntico a `update_test_clock`. Es el patrón ya probado en producción del
laboratorio y no se reinventa.

---

## 7 · Realtime

### 7.1 Análisis por entidad, antes de nombrar canales

| Entidad | Quién necesita enterarse | Latencia aceptable | Filtro natural | Volumen esperado (100 estaciones) |
|---|---|---|---|---|
| `assignments` | conductor afectado, supervisor, taller | **segundos** | `station_id` | ~2 400 cambios/día (2/conductor) |
| `shifts` (apertura/cierre) | supervisor, gerencia | **segundos** | `station_id` | ~4 800/día |
| `shifts` (en curso) | nadie | — | — | 0 — el cronómetro es local |
| `vehicles.state` | supervisor, taller | segundos | `station_id` | ~1 000/día |
| `incidents` | supervisor, taller | **segundos** | `station_id` | ~200/día |
| `coverage_vacancies` | supervisor + conductores **elegibles** | **segundos** (compiten) | `station_id` + elegibilidad | ~300/día |
| `coverage_claims` | supervisor, reclamantes | segundos | `vacancy_id` | ~600/día |
| `alerts` críticas | audiencia declarada | segundos | `station_id`, `audience` | ~100/día |
| `staff_memberships` | **el propio sujeto** | segundos | `profile_id` | raro, pero crítico (§5.2) |
| `transfers` | conductor, gerencia | minutos | `driver_profile_id` | ~1 200/semana |
| `work_orders` | supervisor, taller | minutos | `station_id` | ~150/día |
| `incomes` | nadie en vivo | minutos (refresh) | — | ~15 000/día ⚠️ |
| `shift_readings` | nadie | — | — | ~9 600/día ⚠️ |
| `settlements` | conductor | al abrir pantalla | — | semanal |
| histórico, métricas, expedientes, candidatos, auditoría | nadie | bajo demanda | — | — |

Las dos filas ⚠️ son precisamente las que un diseño ingenuo publicaría "por
consistencia" y las que harían inviable el plan de Supabase.

### 7.2 El problema de Dirección y la consola, resuelto

Dirección y la consola necesitan **saber que algo pasa**, no *cada cosa que pasa*.
Suscribirlas a `shifts` nacional serían ~4 800 eventos/día sobre 100 estaciones,
la mayoría irrelevantes para un tablero agregado.

**Solución: `station_live`, una proyección de una fila por estación.**

```sql
create table public.station_live (
  station_id        uuid primary key references public.stations(id),
  environment_id    uuid not null,
  active_shifts     int  not null default 0,
  present_drivers   int  not null default 0,
  available_units   int  not null default 0,
  units_in_shop     int  not null default 0,
  open_incidents    int  not null default 0,
  critical_alerts   int  not null default 0,
  open_vacancies    int  not null default 0,
  billed_today_mxn  int  not null default 0,
  last_event_at     timestamptz,
  updated_at        timestamptz not null default now()
);
```

Mantenida por triggers `after insert/update` sobre `shifts`, `incidents`,
`vehicles`, `coverage_vacancies` e `incomes`. Consecuencias:

- Dirección se suscribe a **100 filas**, no a decenas de miles.
- La consola pinta el mapa nacional en vivo con **un** canal.
- Si necesita el detalle de una estación, **entonces** abre el canal de esa
  estación — y lo cierra al salir.
- Es reconstruible: un `refresh_station_live(station_id)` la recalcula desde las
  fuentes. Por eso puede ser LWW sin riesgo (§6.1).

### 7.3 Implementación concreta en Supabase

`postgres_changes` filtra por **igualdad sobre una sola columna**. El diseño se
somete a esa limitación en lugar de pelearla:

| Canal | Tabla | Filtro | Suscriptor |
|---|---|---|---|
| `station:{uuid}:ops` | `station_live` | `station_id=eq.{uuid}` | supervisor, taller, gerencia |
| `station:{uuid}:assignments` | `assignments` | `station_id=eq.{uuid}` | supervisor, taller |
| `station:{uuid}:shifts` | `shifts` | `station_id=eq.{uuid}` | supervisor |
| `station:{uuid}:incidents` | `incidents` | `station_id=eq.{uuid}` | supervisor, taller |
| `station:{uuid}:vacancies` | `coverage_vacancies` | `station_id=eq.{uuid}` | supervisor |
| `driver:{uuid}` | `assignments` | `driver_profile_id=eq.{uuid}` | ese conductor |
| `driver:{uuid}:vacancies` | `coverage_vacancies` | `station_id=eq.{uuid}` + **filtro RLS de elegibilidad** | conductores elegibles |
| `me:{uuid}:membership` | `staff_memberships` | `profile_id=eq.{uuid}` | el sujeto |
| `national:live` | `station_live` | *(sin filtro, acotado por RLS)* | dirección, consola |
| `env:{uuid}:clock` | `test_clock` | ya existe | todos en PRUEBA |

Reglas de publicación:

- **Sólo se añaden a `supabase_realtime`** las tablas de la lista. `incomes`,
  `shift_readings`, `audit_log`, `command_log` y todo el histórico **no se
  publican jamás**.
- **RLS aplica también a Realtime.** Un conductor no recibe filas que no podría
  leer, aunque el filtro del canal sea más ancho.
- **Presupuesto por dispositivo, verificable:** conductor **≤ 3** canales;
  supervisor/taller **≤ 5**; gerencia **1** (`national:live` acotado por región);
  consola **1** + como máximo **1** de detalle. Si una fase futura supera ese
  presupuesto, es un defecto de diseño, no un ajuste de configuración.

---

## 8 · Contrato de comandos

### 8.1 Forma canónica

```sql
create function public.<comando>(
    p_idempotency_key uuid,          -- obligatorio en TODO comando
    p_expected_revision bigint,      -- sólo si la entidad usa revisión
    …parámetros de intención…
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp;
```

Todo comando, sin excepción:

1. Resuelve el actor con `auth.uid()`. **Nunca** acepta un `actor_id` del cliente.
2. Verifica membresía viva y rol contra `staff_memberships`.
3. Verifica que el `environment_id` de los operandos coincide con el del token.
4. Consulta `command_log` por `idempotency_key`; si existe, **devuelve el
   resultado original** sin reejecutar.
5. Re-verifica **todas** las precondiciones, incluidas las que el cliente ya
   comprobó de forma predictiva.
6. Escribe dentro de una transacción.
7. Escribe `audit_log` (por trigger, no a mano).
8. Registra en `command_log`.
9. Devuelve `{ok, entity, id, revision, …}` o levanta un error tipificado.

### 8.2 Taxonomía de errores

Cerrada. El cliente los mapea a mensajes en español; un error fuera de esta lista
es un defecto.

| Código | `errcode` | Significado | Qué hace el cliente |
|---|---|---|---|
| `not_authenticated` | 42501 | sin sesión válida | vuelve al acceso |
| `membership_revoked` | 42501 | la membresía se cerró | vuelve al selector de rol |
| `not_authorized` | 42501 | rol o estación insuficientes | explica el alcance |
| `environment_mismatch` | 42501 | operando de otro entorno | **bloquea y reporta** |
| `not_found` | P0002 | operando inexistente | recarga |
| `precondition_failed` | 22023 | regla de negocio incumplida | muestra el motivo exacto |
| `revision_conflict` | 40001 | la fila avanzó | recarga, muestra el diff, pide confirmación |
| `exclusive_conflict` | 23505 | otro ganó la exclusión | dice **quién** y **cuándo** |
| `idempotent_replay` | — (200) | reintento reconocido | trata como éxito |
| `stale_command` | 22023 | comando offline caducado | pasa la cola a `conflicto` |

### 8.3 Los tres comandos ancla (detallados)

**`assign_vehicle`** — exclusión pura, sin revisión.

```
actor        supervisor (membresía viva en la estación del vehículo)
params       p_idempotency_key, p_driver_profile_id, p_vehicle_id, p_kind, p_note
valida       vehículo existe · misma estación que la membresía · no en taller
             conductor existe · misma estación · sin turno abierto
             entorno coincide
escribe      TXN: cierra assignment previo del conductor (ended_at)
                  cierra assignment previo del vehículo (ended_at)
                  inserta assignment nuevo
exclusión    unique (vehicle_id) where ended_at is null
             unique (driver_profile_id) where ended_at is null
evento       assignments → station:{id}:assignments, driver:{id}
errores      exclusive_conflict (con nombre del supervisor y hora), precondition_failed
```

**`start_shift`** — el ejemplo que pediste explícito.

```
actor        conductor
params       p_idempotency_key, p_assignment_id, p_odometer_km, p_battery_pct
valida       (TODO se re-verifica, aunque el botón ya estuviera habilitado)
             1. auth.uid() resuelve a un profile
             2. membresía viva con role='driver'
             3. la asignación es SUYA y sigue abierta
             4. la estación de la asignación = la de su membresía
             5. ventana horaria del bloque, calculada EN SERVIDOR
             6. vehículo disponible, no en taller, sin turno abierto
             7. el conductor no tiene ningún turno abierto
             8. odómetro >= último shift_reading del vehículo
             9. batería 0..100
            10. documentos del conductor vigentes
            11. entorno coincide
escribe      TXN: shifts (revision=1) + shift_readings(kind='start')
                  + vehicle_state_transitions(→ 'assigned')
exclusión    unique (driver_profile_id) where status='open'
             unique (vehicle_id)        where status='open'
evento       shifts, station_live → station:{id}:shifts
nota         El servidor NO acepta la hora del cliente. `started_at = now()`
             (o la hora lógica del entorno TEST, leída de test_clock).
```

**`claim_guard`** — exclusión global bajo bloqueo.

```
actor        conductor elegible
params       p_idempotency_key, p_vacancy_id
valida       vacante existe y status='open'
             elegibilidad (estación, bloque, sin choque con turno propio, sin sanción)
escribe      TXN: SELECT … FROM coverage_vacancies WHERE id=… FOR UPDATE
                  re-verifica status='open' YA CON EL BLOQUEO
                  inserta coverage_claims(status='won')
                  actualiza vacancy.status='claimed'
exclusión    unique (vacancy_id) where status='won'
evento       coverage_vacancies, coverage_claims → station:{id}:vacancies
errores      exclusive_conflict → "Otro conductor tomó esta guardia a las HH:MM."
prohibido    offline. Requiere exclusión global.
```

### 8.4 Catálogo completo (22 comandos)

| Comando | Actor | Mecanismo | Offline | Fase |
|---|---|---|---|---|
| `sign_in` | cualquiera | Supabase Auth | ❌ | 15B |
| `select_membership` | cualquiera | escritura en `devices` | ❌ | 15B |
| `assign_vehicle` | supervisor | único parcial + TXN | ❌ | 15C |
| `end_assignment` | supervisor | TXN | ❌ | 15C |
| `set_vehicle_state` | taller/supervisor | máquina de estados | ❌ | 15C |
| `start_shift` | conductor | único parcial + TXN | ❌ | 15D |
| `finish_shift` | conductor | revisión + TXN | ❌ | 15D |
| `submit_reading` | conductor | append-only | ✅ cola | 15D |
| `report_incident` | conductor | TXN | ✅ borrador | 15E |
| `update_incident` | supervisor | revisión | ❌ | 15E |
| `open_work_order` | taller | TXN | ❌ | 15E |
| `close_work_order` | taller | revisión + TXN | ❌ | 15E |
| `request_absence` | conductor | TXN | ❌ | 15F |
| `resolve_absence` | supervisor | revisión + TXN | ❌ | 15F |
| `claim_guard` | conductor | `FOR UPDATE` + único | ❌ | 15F |
| `approve_guard` | supervisor | revisión + TXN | ❌ | 15F |
| `register_income` | conductor | append-only + TXN | ✅ evidencia | 15G |
| `close_settlement` | sistema/gerencia | TXN programada | ❌ | 15G |
| `authorize_transfer` | gerencia | idempotencia + SM | ❌ | 15G |
| `set_bank_account` | conductor/gerencia | versionado + doble control | ❌ | 15G |
| `upload_document` | varios | Storage + TXN | ✅ archivo | 15H |
| `sign_hiring` | reclutamiento | TXN multi-tabla | ❌ | 15H |

---

## 9 · Auditoría

### 9.1 Esquema

```sql
create table public.audit_log (
  id               uuid primary key default public.new_id(),
  at               timestamptz not null default now(),   -- SERVIDOR. Nunca el cliente.
  actor_id         uuid references public.profiles(id),  -- null = proceso del sistema
  actor_role       text,                                 -- rol EFECTIVO al ejecutar
  action           text not null,                        -- nombre del comando
  entity           text not null,
  entity_id        uuid not null,
  station_id       uuid references public.stations(id),
  environment_id   uuid not null references public.environments(id),
  before           jsonb,
  after            jsonb,
  idempotency_key  uuid,
  device_id        uuid references public.devices(id),
  app_version      text,
  platform         text,                                 -- 'ios' | 'web'
  ip_hash          text,                                 -- SHA-256, nunca la IP
  reason           text                                  -- obligatorio en comandos de consola
);

create index audit_log_entity_idx  on public.audit_log (entity, entity_id, at desc);
create index audit_log_actor_idx   on public.audit_log (actor_id, at desc);
create index audit_log_station_idx on public.audit_log (station_id, at desc);
```

### 9.2 El cliente no puede escribir su propia auditoría

Tres barreras independientes:

1. **Sin `GRANT INSERT`** a `anon` ni a `authenticated`. Ni con RLS abierta podría.
2. **RLS activo sin política de escritura.** Denegado por defecto.
3. **Producida por trigger**, no por el comando. El trigger
   `audit_row_change()` se dispara `after insert or update` sobre cada tabla
   auditada y toma `actor_id` de `auth.uid()` y `at` de `now()` — **valores que el
   cliente no puede falsificar**.

Además: `UPDATE` y `DELETE` revocados para **todos** los roles, incluida la
consola y Dirección. La auditoría se lee y se exporta; no se corrige.

### 9.3 Datos sensibles en `before`/`after`

Regla: **el trigger redacta antes de escribir**, no después.

| Dato | Tratamiento |
|---|---|
| CLABE completa | **Nunca.** Sólo `clabe_last4` + `sha256(clabe)` para probar el cambio sin exponer el número. |
| Contraseñas / tokens | Nunca llegan a Postgres (viven en Auth). Si apareciera un campo así, el trigger lo elimina. |
| Fotos y evidencia | Sólo la ruta de Storage y el hash. Jamás el binario. |
| CURP / RFC / domicilio | Enmascarados: `"CURP": "MEXX****"`. |
| Teléfono / correo | Últimos 4 dígitos / dominio. |
| Montos y odómetro | Íntegros. Son el objeto de la auditoría. |

Implementación: lista blanca por tabla (`audit_fields`), no lista negra. Un campo
nuevo **no se audita hasta declararlo** — falla del lado seguro.

**Retención:** 24 meses en caliente; después, exportación mensual firmada a
almacenamiento frío y purga con credencial de servicio. Se define ahora para que
la tabla no crezca sin límite y para que la purga sea un procedimiento, no una
urgencia.

---

## 10 · Estrategia PROD / TEST

### 10.1 Los dos proyectos

| | **PROD** | **TEST** |
|---|---|---|
| Proyecto Supabase | `turno-ev-prod` (nuevo) | `turno-ev-laboratorio` (`yyxzuiantrmoyozetswv`, existente) |
| Migraciones de dominio | `0100_*` … idénticas | `0100_*` … idénticas |
| Simulación temporal | **ausente** | `0001_lab_shared_clock.sql` |
| `test_clock`, `test_events`, `update_test_clock` | **no existen** | existen |
| Auth | usuarios reales | usuarios de prueba |
| Datos | operación real | mundo del laboratorio |
| Credenciales | `EXPO_PUBLIC_SUPABASE_PROD_*` | `EXPO_PUBLIC_SUPABASE_TEST_*` |
| `environments` | 1 fila: `'prod'` | N filas |

Estructura de migraciones:

```
supabase/
  migrations/
    domain/     0100_identity.sql … 0190_projections.sql   → ambos proyectos
    lab/        0001_lab_shared_clock.sql                   → SÓLO test
```

**Guardia contra el accidente:** cada migración de `lab/` empieza con

```sql
do $$ begin
  if exists (select 1 from public.environments where code = 'prod') then
    raise exception 'Migración de laboratorio ejecutada contra PRODUCCIÓN. Abortada.';
  end if;
end $$;
```

Y cada migración de `domain/` es idempotente (`if not exists`), reproducible en
ambos.

### 10.2 Cómo elige iOS el backend

**Descartado explícitamente:** que `LabRuntime.isTest` reconfigure el cliente. Hoy
ese booleano cambia en caliente desde una hoja modal; si además reapuntara la base
de datos, una sesión autenticada quedaría hablando con otro proyecto y otro Auth.

**Mecanismo adoptado — el entorno es una propiedad de la sesión, no de la UI:**

```swift
enum BackendEnvironment: String, Codable, Sendable {
    case production
    case test

    var credentials: SupabaseConfig.Credentials { /* del par PROD_* o TEST_* */ }
}
```

Ciclo de vida, explícito:

```
1. Arranque sin sesión
   → pantalla de acceso, con selector de entorno visible
     (en build de App Store: sólo Producción; ver 10.3)

2. sign_in
   → se fija BackendEnvironment
   → el cliente Supabase se construye UNA VEZ con ese par de credenciales
   → se guarda en Keychain junto al refresh token

3. Sesión viva
   → el entorno es INMUTABLE. La hoja de entorno no puede cambiarlo.
   → SupabaseBridge.client es de sólo lectura para el resto de la app.

4. Cambio de entorno  (acción deliberada, con confirmación)
   → signOut()               cierra sesión en Auth
   → cancela suscripciones Realtime
   → vacía TODA la caché local del entorno anterior
   → destruye el SupabaseClient
   → vuelve al paso 1
   NO existe una vía que salte del 3 al 3.

5. LabRuntime.isTest
   → deja de seleccionar backend
   → pasa a ser DERIVADO: session.environment == .test
   → sigue gobernando el reloj simulado y la UI del laboratorio, nada más
```

### 10.3 Secretos de PROD fuera del build de TEST

- Las credenciales viven en variables públicas separadas
  (`EXPO_PUBLIC_SUPABASE_PROD_URL` / `_PUBLISHABLE_KEY` y `..._TEST_...`). Son
  claves *publishable*: no son secretos, pero sí **superficie**.
- **Build de laboratorio** (interno): compila ambos pares; el selector de entorno
  es visible.
- **Build de App Store**: compila **sólo** el par PROD. El par TEST queda vacío y
  `BackendEnvironment.test` no resuelve credenciales → el selector no se muestra.
  Un usuario final no tiene forma de alcanzar el laboratorio.
- Ninguna clave de `service_role` entra jamás en un binario. La siembra y la
  purga se ejecutan desde fuera de la app.
- `Config.swift` se autogenera en build: las variables nuevas se declaran con
  `requestEnvs` **al empezar 15B**, no ahora.

---

## 11 · Compatibilidad con la app actual

**15A no cambia una sola línea de Swift.** Lo que queda intacto, nombre por nombre:

| Componente | Estado tras 15A |
|---|---|
| `FleetStore` | **Intacto.** Sigue siendo autoridad del turno. |
| `SupervisionStore`, `CoverageStore`, `StationOfficeStore`, `RegionalStore`, `NationalStore`, `RecruitmentStore`, `WalletStore`, `AbsenceResolutionStore`, `LabStore`, `VisualEditorStore` | **Intactos.** Siguen siendo autoridad. |
| Todas las claves `UserDefaults` (`turnoev.*`) | **Intactas.** Ninguna se borra en 15A. |
| `MockData`, `SupervisionMockData`, `RegionalMockData`, `NationalMockData`, `RecruitmentMockData`, `StationOfficeMockData` | **Intactos.** |
| `AssignmentBook`, `DossierBook`, `StationGoalLedger`, `CashAccount`, `CashDepositLedger`, `CashChargeLedger`, `CoverageEarningLedger`, `AbsencePolicy`, `ReserveFleet`, `BonusSchedule`, `RecruitHandoff` | **Intactos.** |
| `ClockBeat`, `TimeScope`, `ClockAnchor`, `ClockSignal`, `AppClock`, `SimulationClock` | **Intactos.** Fase 15 no los toca (regresión concreta aparte). |
| `SharedClockSync`, `SupabaseService` | **Intactos.** Siguen apuntando al proyecto de laboratorio. |
| Navegación, vistas, `Palette`, `Fmt`, `ShiftRules` y demás reglas puras | **Intactos.** |

**Lo único que 15A produce:**

1. Migraciones SQL en `supabase/migrations/domain/`, **ejecutadas contra el
   proyecto TEST y contra un PROD vacío**. Ningún cliente las consume.
2. Un script de siembra idempotente que traduce fixtures a filas con
   `legacy_code`. Se ejecuta sólo en TEST.
3. Este documento.

El backend existe **en paralelo y sin autoridad**. La primera vez que un cliente
lee del servidor es 15B; la primera vez que escribe es 15B también, y con
fallback local.

**Criterio de aceptación de 15A:** desinstalar el backend recién creado no debe
producir ningún cambio observable en el iPhone. Si lo produce, 15A se excedió.

---

## 12 · Roadmap revisado

| Fase | Alcance | Entregable verificable |
|---|---|---|
| **15A** | Contrato, esquema base, identidad, RLS, auditoría, `command_log`, dos proyectos | Esquema desplegado en TEST y PROD vacío. App sin cambios. |
| **15B** | Auth real, `profiles`, `staff_memberships`, `stations`, `regions`. Contraseñas fuera del binario | Iniciar sesión contra el servidor, con fallback local |
| **15C** | `vehicles`, `assignments`, exclusividad, estados | Asignar desde un iPhone y verlo en otro |
| **15D** | `shifts`, `shift_readings` | Turno abierto en un iPhone, visible para el supervisor en otro |
| **🖥 Consola 0.1** | **Observabilidad de sólo lectura** | **Primera validación de la arquitectura completa** |
| **15E** | `incidents`, `work_orders`, transiciones de vehículo | Incidencia del conductor abre OT en el taller |
| **15F** | `absences`, `coverage_vacancies`, `coverage_claims` | Dos teléfonos compiten por una guardia; uno pierde limpiamente |
| **15G** | `incomes`, depósitos, `settlements`, `transfers`, `bank_accounts` | Liquidación calculada en servidor; transferencia no duplicable |
| **15H** | `documents`, `candidates`, `hirings` | Alta firmada crea usuario real |
| **15I** | Consola completa; Web deja de tener estado propio | Segundo cliente real |
| **15J** | Android: reincorporar o congelar formalmente | Decisión documentada |

### Consola 0.1 — definición

Se adelanta a **después de 15D**, como pediste. Propósito único: **probar por
primera vez la cadena `iPhone → backend autoritativo → consola PC`**.

**Sólo lectura. Cero comandos. Cero escrituras.**

| Lee | Fuente |
|---|---|
| Estaciones con capacidad vigente | `stations` + `station_capacity_current` |
| Conductores por estación | `driver_profiles` + `staff_memberships` |
| Vehículos y estado | `vehicles` |
| Asignaciones vigentes | `assignment_current` |
| Turnos activos | `shifts where status='open'` |
| Última actividad y conexión | `devices.last_seen_at` |
| Pulso por estación | `station_live` (1 canal) |

Condiciones de aceptación, medibles:

1. Se autentica con el **mismo Auth** que los teléfonos. Sin credencial propia.
2. Su alcance sale de **su membresía**, no de configuración de la consola.
3. **Sin `localStorage` autoritativo.** Caché de React Query y nada más.
4. Un turno iniciado en el iPhone aparece en la consola en **≤ 5 s**, sin recargar.
5. Cerrar la membresía del operador de consola la deja sin datos **en la siguiente
   consulta**, sin esperar a que caduque el token. *(Valida el §5.2.)*
6. Exactamente **2 canales Realtime** abiertos. Verificable en el diagnóstico.

`devices.last_seen_at` se alimenta con un heartbeat de la app (`touch_device()`,
como mucho 1/min). Se introduce en 15B para que el dato exista cuando la consola
lo necesite.

---

## 13 · Riesgos no contemplados hasta ahora

Los de Fase 15 siguen vigentes. Estos son **nuevos** o afinados por este diseño.

| # | Riesgo | Gravedad | Mitigación |
|---|---|---|---|
| 1 | **La hora del servidor y la hora lógica del laboratorio son distintas.** `start_shift` en TEST no puede usar `now()`: usaría la hora real y contradiría el reloj simulado que 12 fases construyeron. | **crítico** | En TEST, cada RPC deriva la hora de `test_clock` con una función `env_now(environment_id)`. En PROD, `env_now()` **es** `now()`. Debe entrar en 15A, no descubrirse en 15D. |
| 2 | **Auth de conductores sin correo corporativo.** OTP por SMS tiene coste por mensaje y depende de un proveedor externo; en México además hay latencia de entrega variable. | alto | Decidir en 15B: SMS OTP, correo personal, o credencial emitida por reclutamiento con cambio obligatorio. Afecta al coste operativo mensual. |
| 3 | **PROD arranca vacío: no hay usuarios.** El primer administrador no puede crearse desde la app, porque la app exige membresía. | alto | Procedimiento de *bootstrap* documentado con `service_role`, ejecutado una vez y auditado. Definir en 15A, ejecutar en 15B. |
| 4 | **La UI actual asume datos completos y síncronos.** Todo `UserDefaults` responde en microsegundos. Ninguna vista tiene estado de carga, error o reintento. | alto | Cada fase añade los tres estados a las vistas que toca. Presupuesto de trabajo de UI **no contabilizado** en el plan original. |
| 5 | **Storage no está diseñado.** Fotos de odómetro, evidencia y documentos van hoy como `Data` dentro de `UserDefaults`. Sin buckets, sin políticas, sin límites, sin caducidad de URLs. | alto | Diseñar buckets y RLS de Storage en 15A junto al esquema; se usa desde 15D. |
| 6 | **Cambio de horario y zona.** El país no aplica horario de verano desde 2022, pero hay estados fronterizos que sí. `timestamptz` lo resuelve en almacenamiento; **no** resuelve "el bloque de las 06:00 en la zona de la estación". | medio | `stations.timezone` desde 15A. Toda ventana horaria se calcula en la zona de la estación, nunca en la del dispositivo. |
| 7 | **Cuota de Realtime.** El plan tiene techo de conexiones concurrentes y de mensajes. 100 estaciones × ~15 dispositivos ≈ 1 500 conexiones, más la consola. | medio | El presupuesto por dispositivo (§7.3) y `station_live` lo acotan. Verificar el techo del plan **antes** de 15C. |
| 8 | **`security definer` salta RLS por diseño.** Un `search_path` mal fijado o un parámetro no validado en un solo RPC abre toda la base. | medio | `set search_path = public, pg_temp` obligatorio; plantilla única de comando; revisión específica de cada RPC nuevo; ningún RPC acepta `actor_id`. |
| 9 | **La siembra de fixtures puede correrse contra PROD.** El script existe y es idempotente; nada impide apuntarlo mal. | medio | El script aborta si `environments` contiene `code='prod'`. Misma guardia que las migraciones de laboratorio. |
| 10 | **Divergencia de reglas al duplicarlas en SQL.** `ShiftRules` en Swift y su equivalente en Postgres pueden separarse en silencio. | alto | Batería de paridad: casos de frontera (cambio de bloque, fin de semana, medianoche) ejecutados contra ambas implementaciones y comparados en CI de cada fase. |
| 11 | **Migración de datos ya existentes en teléfonos.** Si alguien tiene un turno abierto en `UserDefaults` cuando llegue 15D, ese turno no existe en el servidor. | medio | Cada fase migratoria detecta estado local huérfano, lo sube como registro histórico marcado `migrated=true`, y sólo entonces borra la clave. |
| 12 | **`environment_id` redundante en proyectos separados** puede inducir a relajar la separación física ("total, ya está el campo"). | bajo | Documentado aquí: la frontera primaria son los dos proyectos. `environment_id` es trazabilidad y defensa en profundidad, **nunca** justificación para unificar. |

---

## 14 · Decisiones abiertas — bloquean la ejecución de 15A

No se crea ninguna tabla productiva hasta cerrar estas cuatro.

1. **¿Existe ya el proyecto Supabase de PRODUCCIÓN?** Si no, hay que crearlo y
   obtener su URL y su clave publishable antes de la primera migración.
2. **¿Autenticación de conductores?** SMS OTP (coste por mensaje), correo
   personal, o credencial emitida por reclutamiento. Condiciona `profiles` y el
   flujo de 15B.
3. **¿Versión de Postgres de los proyectos objetivo?** Si alguno ya corre PG18,
   `new_id()` puede delegar en `uuidv7()` desde el día uno. Es una comprobación de
   un minuto que evita una migración futura.
4. **¿Retención de auditoría?** Propuesta: 24 meses en caliente + exportación
   mensual. Si hay una obligación fiscal o laboral distinta, cambia el diseño de
   particionado.

Cerradas esas cuatro, 15A se ejecuta en un solo paso reversible: migraciones de
dominio contra TEST, verificación, y contra PROD vacío. Sin tocar el iPhone.
