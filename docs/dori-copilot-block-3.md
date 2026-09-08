# DORI Copiloto · Bloque 3

## Flujo de persistencia

`dori-copilot-events` es la unica entrada remota. Requiere un JWT de usuario y
acepta uno de estos comandos:

- `decision`: `kind`, `idempotencyKey` e `input` (`DecisionInput`).
- `outcome`: `kind`, `idempotencyKey`, `decisionId` y `observation`
  (`OutcomeObservation`).

La funcion valida al usuario con Supabase Auth. Para una decision ejecuta
`supabase/functions/_shared/dori-copilot.js`, construye el `DecisionEvent` y
llama al RPC interno. Para un resultado recupera la decision almacenada,
construye el `OutcomeEvent` con ese mismo motor y llama al segundo RPC. El
cliente no puede aportar `recommendation`, `scores`, valores esperados,
versiones ni errores de prediccion.

La clave `SUPABASE_SERVICE_ROLE_KEY` existe solo en el entorno de la Edge
Function. No forma parte del contrato del cliente.

## Procedencia de campos

| Procedencia | Campos |
| --- | --- |
| Cliente | oferta y contexto completos en `DecisionInput`; `source`; accion y observaciones reales en `OutcomeObservation`; clave de idempotencia |
| Motor V0.1 | recomendacion, razones, puntuaciones, umbral, versiones, parametros, valores esperados, costo de oportunidad, bloqueos, demanda resuelta y supuestos |
| Backend | identidad y alcance del conductor, ids y fechas de creacion, ids de comando, entorno, estacion y marcas de registro |
| Observado despues | accion tomada, tarifa, duracion, distancia, espera y tarifa siguiente; `null` significa desconocido |
| Reservado para aprendizaje futuro | contexto `traffic`, `events` y `weather`, eventos completos, observaciones y errores de prediccion; este bloque no entrena ni modifica el motor |

## Almacenamiento y seguridad

- `dori_decision_events` conserva el evento completo y columnas consultables de
  cada calculo.
- `dori_outcome_events` conserva una observacion por decision y sus errores
  calculados.
- Ambas tablas son append-only: `UPDATE` y `DELETE` fallan mediante trigger.
- `anon` no tiene acceso. `authenticated` solo puede hacer `SELECT`, filtrado
  por RLS a su propio perfil de conductor o a supervisores de la estacion.
- Ningun cliente tiene permiso de escritura directa ni `EXECUTE` sobre los RPC.
  `service_role` puede ejecutar los RPC, pero tampoco escribir directamente las
  tablas.
- Los RPC resuelven la identidad desde `auth.users`, verifican conductor activo,
  propiedad, coherencia de versiones y calculos, registran `command_log` para
  idempotencia y generan `audit_log`.

La reproducibilidad se apoya en `event_schema_version`, `model_version`,
`rules_version`, `parameter_version`, el objeto completo `parameters`, la
entrada completa y el resultado inmutable. `replayDecisionEvent` puede volver a
evaluar la decision con esa evidencia.

## Alcance

No se agrego interfaz SwiftUI, integracion con Uber, Learning Engine ni cambios
de reglas o pesos. La migracion y la funcion quedan listas para despliegue
posterior; este bloque solo las valida localmente.
