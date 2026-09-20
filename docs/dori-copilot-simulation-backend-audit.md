# DORI Copiloto — auditoría de persistencia y transporte de simulaciones

## Base auditada

- `integration/dori-test`: `f4c5f2e428a0696fe1c1037307d8a68cb22112ae`.
- Rama de contrato de referencia: `feat/copilot-console-simulation-contract` en `df3a09d112253b6e7e1948da6ff52c49ec66848f`.
- No se mezcló ninguna rama y no se modificó backend existente.

## Piezas reutilizables

`dori-copilot.js` y `dori-copilot-runtime.ts` son el motor y adaptador canónicos. `dori-copilot-events` ya autentica el Bearer token, recalcula la decisión en servidor, no acepta una recomendación del cliente, usa idempotencia y llama RPC con `service_role` sólo en la Edge Function. `dori_decision_events` y `dori_outcome_events` conservan el contexto, resultado, versiones, razones, puntuaciones, valores esperados, costo de oportunidad, bloqueos, estación, entorno, conductor y actor. Sus triggers los hacen append-only.

`SessionPrincipal` es la identidad probada por servidor: `profileId` es `public.profiles.id`, y contiene `environmentId`, `stationId` y `role`. Para un conductor, el backend resuelve el `driver_profile_id` mediante `auth_user_id → profiles → driver_profiles → staff_memberships`; el cliente no puede elegir una identidad distinta.

La Consola ya tiene `console_identity`, `console_drivers`, autorización por estación y canales Realtime para `station_live`, incidencias, órdenes y vacantes. iOS mantiene un heartbeat operativo y refresca el estado del conductor cada 20 segundos. Existe Realtime reutilizable, pero no hay canal ni tabla de Copiloto.

## Gaps reales

1. Los eventos actuales mezclan conceptualmente `source = simulated` con eventos de decisión operativos. No tienen `is_simulation`, `test_case_id`, expectativa ni clasificación expected/actual.
2. Los RPC actuales sólo resuelven una identidad de conductor activa; una identidad `console` no puede crear una decisión mediante ellos.
3. La Edge Function actual sólo acepta `decision` y `outcome`; no existe transporte de caso pendiente hacia un conductor.
4. No existe persistencia de expectativa de Consola ni una evaluación comparativa.
5. No existe expiración de casos de laboratorio en tablas o RLS.
6. La RLS actual permite a `supervisor` leer eventos DORI normales de su estación. Eso debe documentarse como alcance existente, pero no reutilizarse para datos de laboratorio.
7. La función compartida `auth_can_operate_station` autoriza `console` y `supervisor` para operaciones generales. No debe utilizarse para el contrato de simulación porque incluiría al Supervisor.
8. No existe un mecanismo de notificación Copiloto; el polling del conductor y un canal Realtime dedicado son las piezas disponibles.

## Gobierno y permisos

| Acción | Administración | Consola | Copiloto/backend | Conductor | Supervisor |
|---|---:|---:|---:|---:|---:|
| Crear caso | no | sí, estación propia | valida | no | no |
| Crear expectativa | no | sí, mismo actor/caso | conserva | no | no |
| Cambiar parámetros | futuro | no | consume versión activa | no | no |
| Ejecutar motor | no | solicita | sí, servidor | puede solicitar sólo su caso | no |
| Leer expected | no | sí, casos propios/estación | interno | no | no |
| Leer actual | no | sí, evaluación de laboratorio autorizada | sí | sí, sólo su caso | no |
| Validar laboratorio | no | sí | calcula | no | no |

La exclusión del Supervisor debe ser explícita en cada policy y RPC, sin reutilizar `auth_can_operate_station`.

## Propuesta mínima

Crear tres tablas separadas de los eventos live:

### `copilot_simulation_cases`

Campos mínimos: `id`, `environment_id`, `station_id`, `test_case_id` único por entorno/estación, `driver_profile_id`, `created_by_profile_id`, `input_payload`, `contract_version`, `created_at`, `expires_at`, `status`, `is_simulation` con `CHECK (is_simulation = true)`. El payload debe conservar `source = simulated`; el sobre externo usa `source = console_simulation`.

FK compuestas deben exigir que entorno, estación y conductor pertenezcan al mismo alcance. `expires_at > created_at`. No debe existir FK ni escritura hacia `shifts`, `assignments`, `vehicles` operativos ni finanzas.

### `copilot_simulation_expectations`

Una fila por caso: `case_id`, `expected_recommendation`, `expected_reason_code` opcional, `actor_profile_id`, `criterion_version`, `created_at`. Debe ser append-only y sólo visible para Consola/backend. El expected nunca entra en `input_payload` ni en la llamada al motor.

### `copilot_simulation_evaluations`

Una evaluación por caso y versión de ejecución: `case_id`, `actual_result_payload`, `decision_event_id` opcional sólo como referencia audit trail, `actual_recommendation`, `classification`, `has_operational_block`, `model_version`, `rules_version`, `parameter_version`, `evaluated_by_profile_id`, `evaluated_at`, `idempotency_key`, `command_id`. `classification` debe tener CHECK con `correct_recommend`, `correct_reject`, `false_positive`, `false_negative`. Append-only y UNIQUE `(case_id, idempotency_key)`.

No reutilizar `dori_decision_events` como tabla principal del caso: sus policies actuales incluyen Supervisor y no distinguen laboratorio de operación normal. Si se conserva una referencia a un evento, debe ser sólo audit trail y nunca abrir lectura del evento live.

## RPC y Edge Function futuros

Crear una Edge Function separada, por ejemplo `dori-copilot-simulation`, con tres operaciones estrictas:

1. `create_case`: autentica `console`, deriva `profile_id`, entorno y estación desde `console_identity`, valida `driver_profile_id` dentro de la estación y crea caso + expectativa en una transacción.
2. `evaluate_case`: autentica el conductor dueño del caso o un proceso backend autorizado; vuelve a comprobar vigencia, identidad y estación; llama al motor canónico con `input_payload` únicamente; inserta evaluación y auditoría.
3. `get_pending`: autentica conductor y devuelve sólo casos pendientes propios, sin `expected` ni configuración administrativa.

Los RPC subyacentes deben ser `SECURITY DEFINER` sólo cuando sea necesario, con `search_path` fijo, `auth_user_id` comprobado en el cuerpo, grants revocados para `anon`/`authenticated` y ejecución sólo desde la Edge Function. El cliente no debe recibir `service_role` ni ejecutar RPC internos directamente.

La idempotencia debe usar `command_log` y una clave por operación. Repetir `create_case` con el mismo payload devuelve el mismo caso; cambiar el payload con la misma clave falla. Repetir `evaluate_case` devuelve la evaluación existente.

## RLS y separación live/simulation

- RLS activo en las tres tablas.
- Consola: SELECT/INSERT de casos y expectativas sólo en `environment_id` y `station_id` de `console_identity`.
- Conductor: SELECT de casos pendientes/evaluaciones sólo cuando `driver_profile_id` se resuelve desde su `auth_user_id`; nunca SELECT de expectativas.
- Backend: acceso mediante RPC/Edge Function.
- `anon`: sin acceso.
- Supervisor: sin SELECT, INSERT, UPDATE, DELETE ni EXECUTE de RPC de laboratorio.
- Nadie actualiza o borra filas; el estado se expresa con nuevas filas o una transición protegida por RPC.

## Conductor y turno

El turno activo canónico es `shifts.status = 'open'`, limitado por `shifts_open_driver_unique`, y se obtiene desde la asignación activa. El caso simulado debe vincularse al `driver_profile_id` y estación, pero no a un `shift_id` operativo. Si se requiere contexto temporal, se captura como snapshot dentro del payload; nunca se escribe en `shifts`.

El conductor puede consultar casos pendientes por polling dentro del heartbeat existente o por un canal Realtime dedicado a `copilot_simulation_cases` filtrado por `driver_profile_id`. La primera fase debe preferir polling protegido, porque no depende de una nueva notificación ni de APNs. La evaluación sólo genera un resultado de laboratorio; no inicia, cierra ni modifica el turno, ingresos, batería, vehículo, asignación o aceptación de Uber.

## Acquisition y routing

No se necesita tocar Acquisition, `ContentView`, `ShiftView`, Auth, tabs, navegación raíz, Supervisor ni `SupabaseService.swift` para este contrato backend. La única integración iOS futura sería un lector/servicio de casos pendientes dentro del flujo existente de Turno, usando `SessionPrincipal` y el `driver_profile_id` resuelto por backend.

## Pruebas requeridas para implementación

- aislamiento por `environment_id` y `station_id`;
- Consola autorizada frente a Consola de otra estación;
- Supervisor rechazado en crear, leer expected, leer actual y ejecutar;
- conductor sólo ve sus casos y nunca expected;
- conductor sin turno abierto no puede ejecutar un caso que requiera turno;
- caso expirado rechazado;
- payload simulado no crea ni modifica `shifts`;
- expected no llega al motor;
- idempotencia y payload mismatch;
- append-only y rechazo de UPDATE/DELETE;
- clasificación de las cuatro combinaciones expected/actual;
- preservación de versiones y resultado canónico;
- separación de eventos live y simulados;
- Realtime/polling no filtra casos de otra identidad;
- auditoría de actor, estación, entorno y comando.

## Archivos que habría que tocar en una implementación posterior

- nueva migración en `supabase/migrations/`;
- nueva Edge Function y contrato compartido bajo `supabase/functions/`;
- pruebas pgTAP en `supabase/tests/`;
- servicio iOS de consulta de casos, sin tocar routing ni vistas protegidas;
- posiblemente un canal Realtime dedicado o polling dentro del store existente.

No se deben modificar las migraciones actuales de eventos, RLS live, Auth, Acquisition, TestFlight ni módulos de Supervisor.

## Control de Apego

1. Administración configura: preservado como frontera futura.
2. Consola prueba: única creadora propuesta.
3. Copiloto evalúa: motor canónico en servidor.
4. Conductor observa: sólo su caso y resultado.
5. Supervisor fuera del circuito: policies y RPC propuestos lo excluyen.
6. Live y simulation separados: tablas y permisos separados.
7. Turno real protegido: no se escribe `shifts`.
8. Acquisition Golden, routing global, Auth, producción y bundle ID intactos.

**APEGO AL DISEÑO RAÍZ — PASS**
