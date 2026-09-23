# UBER Test — validación humana TEST

Estado requerido: `ESPERANDO VALIDACIÓN HUMANA — MISIÓN ABIERTA` cuando sólo falte dispositivo físico.

1. Abrir Consola TEST con un conductor cuyo turno esté abierto.
2. Crear 3 ofertas y confirmar el orden `#1`, `#2`, `#3`.
3. Pulsar `MANDAR TANDA DE VIAJES` y confirmar que UBER Test recibe una sola oferta, reproduce la alerta TEST y muestra la barra.
4. En la primera oferta pulsar `ACEPTAR`; confirmar que aparece la segunda.
5. En la segunda pulsar `DESCARTAR`; confirmar que aparece la tercera.
6. Dejar expirar la tercera; confirmar que se registra `expired` y vuelve a `EN ESPERA DE VIAJES`.
7. Repetir con 10 ofertas y verificar FIFO, sin duplicados.
8. Cerrar el turno, mandar otra tanda y confirmar que no aparece despacho DORI Copiloto.
9. Reabrir la app durante una tanda y confirmar recuperación del estado pendiente.

Evidencia mínima: video corto de los pasos 3–6, identificador de tanda, tres resultados y estado final `completed`/`EN ESPERA DE VIAJES`.
