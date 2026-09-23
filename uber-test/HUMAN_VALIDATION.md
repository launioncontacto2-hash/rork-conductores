# UBER Test — validación humana TEST

Estado requerido: `ESPERANDO VALIDACIÓN HUMANA — MISIÓN ABIERTA` cuando sólo falte dispositivo físico.

1. Abrir Consola TEST con un conductor TEST habilitado; esta prueba no requiere Copiloto ni un turno abierto.
2. Crear exactamente 10 ofertas y confirmar que Consola muestra el orden `#1` a `#10`.
3. Pulsar `MANDAR TANDA DE VIAJES` y confirmar que UBER Test recibe las 10 ofertas.
4. Confirmar que UBER Test mantiene el orden FIFO.
5. Confirmar que solo aparece un viaje a la vez.
6. Confirmar que la tarjeta muestra servicio, tarifa, recogida, distancias, duración y rating cuando corresponde.
7. Confirmar que aparece el temporizador/barra visual y avanza correctamente.
8. Confirmar alerta sonora TEST propia y respuesta háptica.
9. En la oferta 1 pulsar `ACEPTAR`; confirmar resultado `accepted` y avance automático.
10. En la oferta 2 pulsar `DESCARTAR`; confirmar resultado `discarded` y avance automático.
11. Dejar expirar la oferta 3; confirmar resultado `expired`, cierre y avance automático.
12. Completar las 10 ofertas con una combinación de aceptar, descartar y expirar.
13. Confirmar que cada uno de los 10 resultados queda registrado.
14. Confirmar que no hay duplicados ni viajes perdidos.
15. Cerrar/cambiar de pantalla durante la tanda; confirmar recuperación, sin destrucción de la cola ni reinicio indebido del temporizador.
16. Confirmar que al terminar vuelve a `EN ESPERA DE VIAJES` y Consola refleja correctamente los 10 resultados.

Evidencia mínima: video corto de los pasos 3–6, identificador de tanda, tres resultados y estado final `completed`/`EN ESPERA DE VIAJES`.
