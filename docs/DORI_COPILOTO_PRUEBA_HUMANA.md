# DORI Copiloto — guía de prueba humana TEST

Esta guía se ejecuta únicamente sobre el entorno TEST y el grupo interno de TestFlight. No usar datos de producción.

## Preparación

1. Instalar en el iPhone el build TEST aprobado de TurnoEV desde TestFlight.
2. Confirmar que el build corresponde a `com.turnoev.mobility` y al entorno TEST configurado.
3. Tener disponibles las identidades TEST de Consola y Conductor. No compartir contraseñas ni tokens.
4. Registrar el `case_id`, la hora de inicio y el build antes de crear el caso.

## Circuito

1. En Consola, crear un caso simulado para el conductor de prueba y registrar su expectativa `EXPECTED`.
2. En el iPhone del conductor, abrir Copiloto y comprobar que aparece la oferta visual.
3. Confirmar que el lector visual obtiene la oferta como `TripOffer` y reconoce `UberX` o `Uber Comfort`.
4. Confirmar que una oferta incompleta muestra `DATOS INSUFICIENTES` y que `Uber Priority` muestra `SERVICIO NO SOPORTADO`.
5. Ejecutar la evaluación y comprobar que el conductor sólo ve `TOMAR` o `NO TOMAR` y hasta tres razones sencillas.
6. Registrar la recomendación observada y el identificador de evaluación.
7. Volver a Consola y confirmar `ACTUAL`, `match` y `classification` frente a `EXPECTED`.
8. Repetir con una segunda oferta válida y confirmar que cada evaluación conserva su propio identificador.

## Evidencia y límites

Registrar capturas del caso en Consola, de la oferta y de la respuesta del conductor, junto con build, `case_id`, evaluación y hora. No incluir credenciales, tokens ni datos personales innecesarios.

La prueba es PASS sólo si el caso simulado no cambia `shifts`, eventos live, asignaciones, vehículos ni finanzas. Si aparece una escritura live, una filtración de `EXPECTED` o una recomendación distinta a la evaluación registrada, detener la prueba y conservar la evidencia para DORI Analista.

La ejecución física completa es la validación canónica final; esta guía no sustituye esa validación.
