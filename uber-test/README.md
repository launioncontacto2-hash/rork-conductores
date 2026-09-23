# UBER Test

Aplicación TEST independiente para recepción y procesamiento FIFO de tandas de viajes. Este módulo no contiene el motor de recomendación DORI y sólo acepta payloads marcados como `TEST`.

Contrato de entrada mínimo:

```json
{"id":"batch-001","environment":"TEST","offers":[{"id":"offer-001","service":"UberX","fare":120,"currency":"MXN","pickup":"Centro","pickupDistanceKm":1.2,"tripDurationMinutes":25,"tripDistanceKm":9.4,"riderRating":4.92,"expiresAfterSeconds":15}]}
```

La entrega remota debe ser idempotente por `batch.id` y `offer.id`. Los resultados son `accepted`, `discarded` o `expired`, y regresan al backend TEST para que Consola observe el estado y DORI Copiloto analice el evento cuando exista turno abierto.
