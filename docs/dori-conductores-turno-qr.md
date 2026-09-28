# DORI Conductores — Turno y QR de unidad

## Criterio visual

La pantalla `Turno` muestra la identidad del conductor y coloca primero la
tarjeta de unidad asignada, seguida de la tarjeta de inicio/estado del turno.
La tarjeta resume modelo, código operativo, placas, ODO y batería actuales; VIN
y color se muestran como `No registrado` mientras el contrato de flota no los
exponga. Si no existe una asignación, muestra `Sin unidad asignada`.

En esta pantalla no se muestra el círculo de iniciales de cuenta ni el acceso
visual de Copiloto. El reloj de TEST permanece en la franja amarilla global.
La tarjeta principal conserva el horario operativo sin exponer tolerancias
internas ni reglas de bonos.

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

El flujo exige primero introducir el valor manual y sólo después habilita la
captura de fotografía. Capturar una foto no equivale a validar la evidencia:
la máquina única de estados inicia en `pending`, permanece sin éxito mientras
Vision analiza y sólo muestra verde/check y habilita `Validar kilometraje` en
`matched`. `mismatch` y `unreadable` se muestran en rojo, bloquean la
validación y ofrecen `Tomar otra foto`; una nueva foto invalida la evidencia
anterior. Editar el valor manual después de `matched` también invalida el
estado.

El kilometraje usa Vision en el dispositivo. Sólo una línea anclada por `ODO`,
un número y `KM` es válida; `TRIP`, números sueltos y fotos borrosas producen
`unreadable`. La comparación visible entre el valor manual y la fotografía es
exacta, sin tolerancia: 12,438 contra 12,439 es `mismatch`.

Después de esa coincidencia exacta, la operación compara internamente el ODO
validado contra el kilometraje maestro de la unidad. La tolerancia administrativa
inicial es de 5 km mediante `OdometerAdministrationPolicy.default`; es una
configuración desacoplada, invisible al conductor y preparada para ser inyectada
por Administración. No altera la comparación manual-foto ni se duplica en la UI.

La batería usa un porcentaje `NN%` de 0 a 100 localizado en la región esperada
del indicador. La barra de cinco segmentos sólo confirma contexto y nunca se
convierte en un porcentaje estimado. La comparación también es exacta.

Los estados son `pending`, `matched`, `mismatch` y `unreadable`. Cambiar el valor manual
después de una coincidencia invalida la lectura y exige volver a cotejarla. Las
fotos originales ya se entregan al repositorio de evidencia de inicio de turno;
no se crea un almacenamiento paralelo.

## Cierre de turno

El cierre usa la misma máquina de evidencia que el inicio: primero se captura
manualmente ODO y batería, luego se habilita cada fotografía, y sólo las dos
lecturas en estado `matched` permiten cerrar. `mismatch`, `unreadable`, edición
manual y una nueva foto invalidan la evidencia y mantienen el cierre bloqueado.
El contrato remoto actual conserva la foto ODO en el cierre; la foto de batería
queda en la sesión de validación hasta que el contrato remoto la exponga.

## Puente de datos de unidad

Conductores consume la asignación y los datos dinámicos (`odometer_km`,
`battery_pct`, placa y modelo) desde el contrato de flota de Supabase. El código
operativo se presenta como `DMP-XXX` para la unidad visible y no sustituye al
identificador interno de compatibilidad. VIN y color no se inventan: requieren
que Adquisiciones/Flota los publique en el contrato compartido.

## Layout final de inicio y turno activo

La pantalla de inicio mantiene únicamente el título `Inicio de turno`, la barra
`Unidad / Kilometraje / Batería` y el flujo manual primero, fotografía después.
El paso de kilometraje usa `Captura el kilometraje` y `Fotografía el odómetro`.
El paso de batería usa `Comprobación de carga`, muestra provisionalmente `100%`
como dato registrado del auto, un mínimo de salida de `90%` y avisa que una carga
insuficiente se notifica a supervisión. La integración futura del dato en vivo debe
reemplazar sólo esa fuente, sin cambiar el estado de validación manual/fotografía.

En turno activo no se muestra el título duplicado `Turno`, la cápsula `Activo`, la
barra de progreso, el resumen de jornada/restante, el horario inferior ni la tarjeta
de unidad. Se conservan el turno en curso, inicio, finalizar turno, atraso,
incidencia, documentos y cerrar sesión.

## Ventana Metas

La ventana presenta, en este orden, la meta económica, viajes de hoy, avance
semanal, mejores horas del turno (05:00–14:00) y recorrido/batería. El encabezado
conserva la meta diaria y el círculo sólo muestra el avance actual; no incluye
ingresos, cartera, atrasos ni alertas ajenas. El último bloque usa kilómetros,
consumo de batería y conversión a kWh como estructura preparada para telemetría
real, sin inventar valores operativos.
