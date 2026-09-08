# DORI Copiloto · Bloque 4

## Motor compartido con iOS

La fuente unica del algoritmo sigue siendo
`supabase/functions/_shared/dori-copilot.js`. El comando:

```text
node scripts/sync-copilot-ios-resource.cjs
```

copia sus bytes a `ios-turno-ev/TurnoEV/Resources/dori-copilot.js`. No existe
una segunda implementacion editable: el archivo iOS es un artefacto generado.
El modo `--check` falla si falta el recurso o si difiere un solo byte, y
`copilot-ios-resource.test.cjs` tambien comprueba que arranca sin `require` ni
`module.exports` disponibles, como ocurre en JavaScriptCore.

El motor canonico publica `globalThis.DoriCopilot`; su bloque CommonJS esta
protegido por `typeof module !== 'undefined'`, por lo que JavaScriptCore no lo
ejecuta. `DORILocalCopilotService` carga el recurso del bundle, llama
`evaluateJSON` y decodifica el mismo contrato versionado que usan Node y la Edge
Function.

Cada cambio futuro al motor debe ejecutar primero el comando de sincronizacion
y despues:

```text
node scripts/sync-copilot-ios-resource.cjs --check
node --test scripts/copilot.test.cjs scripts/copilot-simulator.test.cjs scripts/copilot-ios-resource.test.cjs
```

## Arquitectura iOS

- `Models/DORICopilot.swift`: contratos Codable para oferta, mercado, vehiculo,
  conductor, entrada, puntuaciones, resultado, recomendacion y evento.
- `Services/DORICopilotService.swift`: evaluador JavaScriptCore local y cliente
  autenticado de `dori-copilot-events`.
- `ViewModels/DORICopilotStore.swift`: datos editables, modo de ejecucion y
  estado de resultado/persistencia.
- `Views/DORICopilotView.swift`: laboratorio funcional accesible desde la
  pestana `Copiloto` del conductor.

La solicitud remota contiene solamente `kind`, `idempotencyKey` e `input`. No
acepta una recomendacion calculada por el telefono. La Edge Function vuelve a
evaluar y devuelve el `DecisionEvent` persistido. El cliente usa la publishable
key y la sesion de usuario ya administradas por `SupabaseBridge`; no contiene
`service_role`.

## Modos visibles

- **Prueba local:** ejecuta el motor incluido y declara `Resultado local · no
  guardado`.
- **Guardar en Supabase:** invoca la Edge Function y solo declara `Decision
  guardada` cuando recibe el evento. Mientras la funcion no este desplegada, el
  error permanece visible y no se simula persistencia.

La pantalla permite editar tarifa, recogida, viaje, hora, demanda, bateria,
autonomia, tiempo restante, distancia de retorno y valor de destino. El area
principal muestra solo `RECOMENDADO` o `NO RECOMENDADO` y hasta tres razones. Las
metricas internas viven dentro de un panel cerrado llamado `Datos internos ·
solo pruebas`.

Los accesos rapidos 05:00, 07:00, 10:00, 14:00, 18:00, 22:00 y 01:00 cambian
unicamente la hora. Con demanda fija las pruebas exigen resultados invariantes;
con demanda automatica comprueban la prioridad horaria versionada del motor.

No se agregaron Uber, aceptacion automatica, Learning Engine, entrenamiento,
fuentes externas ni despliegue remoto de Supabase.
