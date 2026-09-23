# UBER Test - contrato TEST aislado

Consola compone una tanda de 1 a 10 ofertas y la publica en `uber_test_offer_batches` y `uber_test_offers` con `environment = TEST`. `sequence_no` define el orden FIFO. UBER Test solo lee la tanda de su conductor TEST y publica resultados `accepted`, `discarded` o `expired` en `uber_test_offer_results` con una `idempotency_key` unica.

Cada tanda tambien deja un evento fuente generico `uber_test_offer_events` (`offer_batch_ready`) para una integracion futura. En esta fase no existe consumidor DORI: UBER Test no importa ni ejecuta `dori-copiloto.js`, no calcula recomendaciones, no activa Copiloto y no modifica turnos, finanzas ni produccion.

El boton visible en Consola se denomina **MANDAR TANDA DE VIAJES** y debe permanecer deshabilitado si no hay ofertas, hay mas de 10, faltan datos obligatorios o el conductor no esta en TEST.
