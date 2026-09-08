# DORI Copiloto — Bloque 1

Motor V0.1 determinista, sin red ni LLM. Una única implementación JavaScript pura queda como recurso del proyecto iOS, preparada para un adaptador JavaScriptCore en un bloque posterior. Los contratos tipados se declaran junto al recurso y se validan en ejecución. No se cambian navegación, autenticación, infraestructura ni tablas existentes.

## Archivos y ejecución

- `ios-turno-ev/TurnoEV/Resources/dori-copilot.js`: motor, configuración, validadores y fábricas de eventos.
- `ios-turno-ev/TurnoEV/Resources/dori-copilot.d.ts`: contratos `TripCandidate`, `MarketContext`, `VehicleContext`, `DriverContext`, parámetros, resultados y eventos.
- `scripts/copilot-fixtures.cjs`: cinco ofertas controladas para pruebas unitarias.
- `scripts/copilot.test.cjs`: ejecutar desde la raíz con `node --test scripts/copilot.test.cjs` (Node 24, sin instalar dependencias).

## Cálculo auditable

Pesos iniciales: tiempo 35%, distancia 20%, recogida 15%, destino 20%, operación 10%. Umbrales: baja demanda 58, normal 65, alta 70. Cada bloque se limita a 0–100.

La tarifa es el importe estimado para el conductor **después de la comisión de plataforma**, antes de costos del vehículo. Beneficio neto del ciclo = tarifa − (km de recogida + viaje + reposicionamiento) × (energía/km + desgaste/km). Hora conectada incluye recogida, viaje, reposicionamiento y espera prevista al siguiente viaje. El valor de rechazar usa una referencia neta por hora conectada para la demanda actual multiplicada por **ese mismo horizonte temporal**. El costo de oportunidad es ese valor alternativo; no se vuelve a restar del beneficio de aceptar.

Se recomienda sólo si supera o iguala el umbral, su valor de aceptar supera o iguala el de rechazar y no existe bloqueo operativo. Autonomía restante debe cubrir recogida + viaje + retorno desde destino + la mayor reserva entre kilómetros mínimos y carga mínima. El regreso incluye un margen temporal configurable; se aplica el menor de tiempo restante declarado, fin absoluto del turno y regreso requerido. Se bloquea también un turno que no ha comenzado. La hora utiliza el desplazamiento UTC explícito; el día sigue ISO lunes=1.

Las referencias económicas, calificación del destino y tabla horaria son **supuestos provisionales de laboratorio**, no predicciones aprendidas ni evidencia de superioridad económica. `automatic` selecciona un supuesto por hora; en contexto manual, cambiar solamente la hora no cambia el resultado si el resto del contexto y los márgenes siguen iguales. Demanda histórica/prevista, tráfico, eventos, clima, odómetro e histórico personal se conservan en el contrato pero no ajustan la política V0.1. El horizonte económico es un ciclo, no un optimizador del turno completo; la vuelta a estación se comprueba como restricción y no como reposicionamiento económico salvo que el contexto la incluya allí.

## Versiones y eventos

Modelo `deterministic-0.1`, reglas `0.1.0`, parámetros iniciales `mxn-lab-0.1.0`, esquema de eventos `1.0.0`. Se puede entregar una configuración completa a `evaluate` o `createDecisionEvent`. Alterar los valores iniciales exige otro identificador de parámetros; cada evento conserva todos los valores para reconstruirlo. Un cambio futuro de fórmula requiere otro modelo/reglas. No hay promoción automática de configuración.

`createDecisionEvent` recibe la entrada y metadatos (UUID y fecha de registro) y ejecuta el motor; no acepta una recomendación fabricada. Conserva copias inmutables y serializables de oferta, contexto, procedencia, configuración, puntuaciones, valores alternativos, razones y banderas de frontera. `replayDecisionEvent` vuelve a ejecutar la versión soportada y detecta discrepancias incluso tras serializar/deserializar o reordenar claves JSON. Es un control de consistencia, no una firma contra manipulación maliciosa.

`createOutcomeEvent` enlaza una decisión verificada con lo observado y la acción del conductor. Importes, duración y distancia reales se refieren al viaje aceptado; datos desconocidos permanecen `null`. Los errores son observado menos previsto. Una espera después de rechazar no se compara con la espera prevista desde el destino de un viaje que nunca se realizó. Ambos eventos conservan la procedencia para separar datos simulados, históricos y manuales.

La persistencia duradera y autorización del servidor, adaptador Swift, interfaz, simulador masivo, proveedor Uber y aprendizaje quedan para bloques posteriores. Las funciones de este bloque construyen eventos serializables; no afirman haberlos guardado en Supabase. La verificación ejecutada es del motor y contratos en Node, incluida su entrada global sin dependencias Node; no es una compilación ni ejecución de iOS.
