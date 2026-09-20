# Contrato de Oferta Simulada DORI v1.0.0

Este contrato envuelve el motor canónico sin copiar su lógica. `input` es exactamente un `DORIDecisionInput` con `source: simulated`; el sobre de laboratorio usa `source: console_simulation` e `isSimulation: true`. La expectativa de Consola vive en `expected` y nunca se entrega al motor.

`createSimulationCase` exige `testCaseId`, vigencia, `driverProfileId` (el `public.driver_profiles.id`), contexto completo y una expectativa separada. Dentro de `input`, `driver.driverId` conserva el contrato canónico y representa `public.profiles.id`; el backend valida la relación entre ambos IDs, estación, entorno y estado activo. `evaluateSimulation` llama a `DoriCopilot.evaluate`, conserva el resultado completo y produce `correct_recommend`, `correct_reject`, `false_positive` o `false_negative`.

Una simulación no inicia ni modifica turnos, ingresos, ofertas reales, batería, vehículos o estado operativo. No es un evento live y no contiene ningún papel de Supervisor. La persistencia, la UI, las notificaciones y el gobierno de parámetros quedan fuera de este contrato.
