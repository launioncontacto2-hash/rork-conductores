# DORI Copiloto — Bloque 2

Simulador reproducible para el motor V0.1. `scripts/copilot-simulator.cjs` importa directamente `ios-turno-ev/TurnoEV/Resources/dori-copilot.js`; no contiene otra fórmula de puntuación o decisión. La suite sustituye temporalmente la función exportada del motor y comprueba que una ejecución individual pasa exactamente por ella.

## Uso

Desde la raíz del repositorio, con Node 24 y sin instalar dependencias:

```text
node scripts/run-copilot-simulator.cjs single A
node scripts/run-copilot-simulator.cjs single C --hour 18 --demand high --battery 30 --remaining 120 --pickup 6 --fare 115 --distance 9 --destination-value 65
node scripts/run-copilot-simulator.cjs hours C
node scripts/run-copilot-simulator.cjs input ruta/a/entrada.json --minimum-net-hourly 150
node scripts/run-copilot-simulator.cjs mass --minimum-net-hourly 120
```

`single` ejecuta uno de los casos A–E y acepta cambios de hora, demanda, batería, tiempo restante, recogida, tarifa, distancia y valor de destino. `hours` conserva la misma oferta y la ejecuta a las 05:00, 07:00, 10:00, 14:00, 18:00, 22:00 y 01:00. Por defecto usa la demanda automática versionada del motor, por lo que una diferencia temporal queda explicada por la demanda y espera resueltas. `input` evalúa un contrato completo en JSON. `mass` recorre siempre la misma matriz cartesiana y emite JSON; no usa azar ni escribe resultados.

## Matriz y búsqueda de anomalías

La matriz predeterminada combina 7 horas, 3 demandas, 3 niveles de batería, 3 tiempos restantes, 2 recogidas, 4 tarifas, 3 distancias y 3 valores de destino: 13,608 escenarios. Para cada escenario ejecuta además 4 comprobaciones metamórficas, mejorando por separado tarifa, batería, tiempo restante y recogida: 54,432 evaluaciones derivadas. En total se invoca 68,040 veces el mismo motor.

El detector revisa valores finitos, puntuación 0–100, suma ponderada, semántica de costo de oportunidad, selección de umbral, coherencia de la regla final, veto operativo y cantidad de razones. También busca que una mejora aislada empeore la puntuación o revierta una recomendación favorable, y que el mismo viaje sea recomendado en alta demanda pero rechazado en normal o baja demanda.

Cada anomalía contiene entrada completa, recomendación, puntuación, umbral, valores esperados de aceptar y rechazar, costo de oportunidad, bloqueos operativos y razones. Las comparaciones entre casos incluyen además el contexto relacionado. Las decisiones cercanas al límite se cuentan por separado y se conservan hasta 20 muestras completas; estar cerca del umbral no se clasifica por sí solo como falla.

## Estrategias base

Cada escenario compara DORI con:

1. aceptar todo;
2. aceptar cuando el beneficio neto por hora conectada alcanza un mínimo configurable.

Para cada política se reportan aceptaciones, rechazos, valor esperado agregado y promedio, y aceptaciones con bloqueo operativo. Estos valores comparan alternativas dentro de los supuestos V0.1; no son backtesting con resultados reales ni prueban ganancias o superioridad. En particular, una estrategia base puede mostrar mayor valor económico teórico mientras acepta viajes operacionalmente inviables.

## Resultado reproducible de validación

Con los parámetros `mxn-lab-0.1.0` y mínimo base de 120 MXN por hora conectada:

- 13,608 escenarios principales;
- 54,432 comprobaciones derivadas;
- 1,519 decisiones cercanas al límite;
- 0 contradicciones o anomalías del motor;
- DORI: 2,716 aceptados y 0 aceptaciones con bloqueo operativo;
- aceptar todo: 13,608 aceptados, 7,560 con bloqueo operativo;
- mínimo horario: 7,938 aceptados, 4,410 con bloqueo operativo.

Durante las pruebas se encontró una falla del simulador al ejecutar una matriz personalizada que omitía demanda normal: el comparador intentaba leer un miembro inexistente del par. Se corrigió exigiendo ambos niveles antes de comparar y se conserva la matriz parcial como prueba de regresión. No se modificaron el motor, sus pesos, umbrales ni reglas.

Quedan fuera de este bloque la interfaz SwiftUI, Supabase, persistencia, Uber, Learning Engine e IA generativa.
