# UBER Test — contrato TEST aislado

Consola compone una tanda de 1 a 10 ofertas y la publica en `uber_test_offer_batches` y `uber_test_offers` con `environment = TEST`. `sequence_no` define el orden FIFO. UBER Test sólo lee la tanda de su conductor TEST y publica resultados `accepted`, `discarded` o `expired` en `uber_test_offer_results` con una `idempotency_key` única.

El resultado es un evento operativo para DORI Copiloto; UBER Test no importa ni ejecuta `dori-copilot.js`, no calcula recomendaciones y no modifica turnos, finanzas ni producción. Copiloto sólo debe evaluar cuando el turno del conductor esté abierto; al cerrar el turno, no se crean nuevos análisis.

El botón visible en Consola se denomina **MANDAR TANDA DE VIAJES** y debe permanecer deshabilitado si no hay ofertas, hay más de 10, faltan datos obligatorios o el conductor no está en TEST.
