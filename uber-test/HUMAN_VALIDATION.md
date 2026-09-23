# UBER Test — validación humana TEST

Estado requerido: `ESPERANDO VALIDACIÓN HUMANA — MISIÓN ABIERTA` cuando sólo falte dispositivo físico.

1. Abrir Consola TEST con un conductor TEST habilitado; esta prueba no requiere Copiloto ni un turno abierto.
2. Crear 10 ofertas y confirmar el orden `#1` a `#10`.
3. Pulsar `MANDAR TANDA DE VIAJES` y confirmar que UBER Test recibe una sola oferta, reproduce la alerta TEST y muestra la barra.
4. En las ofertas 1 y 2 pulsar `ACEPTAR` y `DESCARTAR`; confirmar que avanza automáticamente.
5. Dejar expirar la oferta 3; confirmar que se registra `expired` y continúa la cola.
6. Completar las 10 ofertas con una combinación de aceptar, descartar y expirar.
7. Confirmar FIFO, un solo viaje visible, sin duplicados ni pérdidas, alerta sonora/háptica y temporizador.
8. Cerrar/cambiar de pantalla durante la tanda y confirmar recuperación del estado pendiente.
9. Confirmar que al terminar vuelve a `EN ESPERA DE VIAJES` y Consola refleja los 10 resultados.

Evidencia mínima: video corto de los pasos 3–6, identificador de tanda, tres resultados y estado final `completed`/`EN ESPERA DE VIAJES`.
