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
