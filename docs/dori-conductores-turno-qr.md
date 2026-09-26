# DORI Conductores — Turno y QR de unidad

## Criterio visual

La pantalla `Turno` muestra la identidad del conductor, los avisos junto a la
fotografía y una tarjeta de unidad asignada inmediatamente debajo de la tarjeta
principal del turno. La tarjeta usa únicamente los datos autoritativos de la
asignación vigente: modelo e identificador interno DORI. Si no existe una
asignación, muestra `Sin unidad asignada`.

En esta pantalla no se muestra el círculo de iniciales de cuenta ni el acceso
visual de Copiloto. El reloj de TEST permanece en la franja amarilla global.
La tarjeta principal conserva el horario operativo y muestra la tolerancia:
`Tolerancia de 15 minutos antes de afectar bonos`.

## Contrato QR

El QR de la unidad debe contener exactamente el identificador interno DORI de
la unidad asignada, recortado de espacios. En la prueba vigente el valor es
`DMP-003`. El lector compara el payload completo, una vez recortado y
normalizado a mayúsculas, contra `Vehicle.internalNumber` de la asignación
vigente. No se aceptan payloads enriquecidos, JSON ni texto adicional.

Un valor distinto produce un mensaje específico indicando que el QR no coincide
con la unidad asignada. La validación posterior de estación, estado y dispositivo
continúa en `FleetStore`; este cambio no modifica autenticación, RLS ni backend.

## Lecturas del tablero

El kilometraje usa Vision en el dispositivo. Sólo una línea anclada por `ODO`,
un número y `KM` es válida; `TRIP`, números sueltos y fotos borrosas producen
`unreadable`. La comparación contra el valor manual es exacta, sin tolerancia.

La batería usa un porcentaje `NN%` de 0 a 100 localizado en la región esperada
del indicador. La barra de cinco segmentos sólo confirma contexto y nunca se
convierte en un porcentaje estimado. La comparación también es exacta.

Los estados son `matched`, `mismatch` y `unreadable`. Cambiar el valor manual
después de una coincidencia invalida la lectura y exige volver a cotejarla. Las
fotos originales ya se entregan al repositorio de evidencia de inicio de turno;
no se crea un almacenamiento paralelo.
