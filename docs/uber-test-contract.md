# UBER Test → DORI Copiloto — contrato TEST

Este módulo es exclusivamente de laboratorio TEST. Consola publica tandas de 1 a 10 ofertas UberX o Uber Comfort para un conductor del entorno TEST. La secuencia `sequence_no` es FIFO y cada oferta se presenta una sola vez por `offer_id`.

Con un turno abierto, el receptor autenticado y enlazado por `installation_id` obtiene la oferta presentada. El receptor por defecto sin instalación está revocado; el RPC sin argumento no forma parte del contrato. Terminar el turno detiene el receptor y revoca el vínculo.

Cada oferta presentada se evalúa con el motor canónico DORI mediante `uber-test-copilot-evaluate`. El contexto usa `source=simulated`, conserva la hora operativa simulada dentro del payload y mantiene la identidad `driver.profile_id`. La evaluación se persiste como DecisionEvent enlazado al mismo `offer_id` y se encola una sola notificación. Una repetición conserva el estado existente y una segunda respuesta para la misma oferta con datos distintos devuelve conflicto controlado.

Los resultados `accepted`, `discarded` y `expired` son idempotentes por `offer_id` y `idempotency_key`; cada resultado activa la siguiente oferta o completa la tanda. El push usa una notificación por oferta y no modifica turnos, finanzas, Acquisition ni producción.

La integración no cambia el motor económico, umbrales, OCR ni la tarjeta de conductor. Los workflows y fixtures de este módulo deben apuntar únicamente a TEST y nunca incluir secretos en el repositorio.
## Transporte foreground estabilizado

UBER Test usa Supabase Realtime Postgres Changes sobre `public.uber_test_offer_events` como señal primaria en foreground. El evento sólo despierta al cliente; la recuperación server-authoritative mediante `uber-test-next` decide la oferta no resuelta. El polling de 15 segundos permanece únicamente como fallback de recuperación cuando se pierde Realtime o al volver a foreground. RLS mantiene el aislamiento por conductor.
