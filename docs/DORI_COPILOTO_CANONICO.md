# DORI COPILOTO — CANÓNICO DE DOMINIO

**Estado:** ACTIVO  
**Versión:** 1.0  
**Fecha de adopción:** 2026-09-21  
**Propietario de gobierno:** DORI Analista  
**Repositorio objetivo:** `launioncontacto2-hash/rork-conductores`  
**Ruta canónica objetivo en repositorio:** `docs/DORI_COPILOTO_CANONICO.md`

---

## 0. Naturaleza y límite de autoridad

Este documento es el **canónico del dominio DORI Copiloto**.

No es el canónico general de DORI.

No gobierna Consola DORI completa.

No gobierna Conductores completo.

No gobierna Administración, Supervisores, Adquisiciones, Reclutamiento, Recursos Humanos ni otros módulos fuera del ámbito Copiloto.

Consola y Conductores son superficies compartidas por múltiples funciones de DORI. Cuando una tarea las toque **por motivos de Copiloto**, deberán consultar este documento junto con los demás canónicos aplicables a esa tarea.

---

# 1. Regla de alcance

Este canónico aplica exclusivamente a tareas relacionadas con uno o más de estos conceptos:

- DORI Copiloto;
- tarjeta de recomendación del conductor;
- lectura visual de ofertas de viaje;
- adaptadores visuales de plataformas externas;
- oferta canónica `TripOffer`;
- simulador de plataforma / receptor TEST;
- pruebas cruzadas Consola × Conductor × Copiloto;
- parámetros dinámicos propios de Copiloto;
- umbrales de $/km, $/hora y rating;
- aprendizaje y autoajuste futuro de esos umbrales;
- `EXPECTED vs ACTUAL` de pruebas Copiloto;
- persistencia y eventos propios de Copiloto;
- Edge Functions y contratos específicos de Copiloto.

Si una tarea de Consola o Conductores no toca Copiloto, este documento no tiene autoridad sobre ella.

---

# 2. Modelo de múltiples canónicos DORI

DORI puede tener múltiples canónicos de dominio coexistiendo.

Ejemplos:

- DORI Copiloto;
- DORI Consola;
- DORI Conductores;
- DORI Administración;
- DORI Supervisores;
- DORI Adquisiciones;
- otros futuros.

Ningún canónico de dominio puede apropiarse del alcance completo de una superficie compartida.

## Ejemplo

### Tarea
Agregar `PRUEBA DORI` a Consola.

### Canónicos aplicables
- `DORI_MASTER_STATE`
- `docs/DORI_COPILOTO_CANONICO.md`
- canónico vigente de Consola

### Tarea
Modificar inicio/finalización de turno sin relación con Copiloto.

### Canónicos aplicables
- `DORI_MASTER_STATE`
- canónico de Conductores

**No aplica DORI Copiloto.**

---

# 3. Precedencia

La precedencia es:

1. `DORI_MASTER_STATE` — arquitectura global y gobierno transversal.
2. Canónicos de dominio aplicables a la tarea.
3. Documentos de bloque.
4. Prompts de ejecución.
5. Decisiones locales de implementación.

Los canónicos de dominio tienen autoridad paralela dentro de sus propios ámbitos.

Un canónico de dominio no puede invalidar otro fuera de su materia.

Si dos canónicos producen una contradicción real:

**DETENER → regresar a DORI Analista.**

---

# 4. REGLA OBLIGATORIA DE CITACIÓN EN PROMPTS

Todo prompt dirigido a Work o a otra ventana que toque el dominio Copiloto debe incluir, cerca del inicio, la siguiente referencia:

`GOBIERNO CANÓNICO COPILOTO: docs/DORI_COPILOTO_CANONICO.md`

Y debe exigir:

1. leer el archivo antes de ejecutar;
2. reportar la versión leída;
3. declarar los demás canónicos aplicables;
4. no reinterpretar ni reemplazar su visión;
5. detenerse ante una contradicción no autorizada.

Formato mínimo obligatorio:

```text
GOBIERNO CANÓNICO COPILOTO:
docs/DORI_COPILOTO_CANONICO.md

ANTES DE EJECUTAR:
- leer el canónico completo;
- reportar versión;
- declarar CANÓNICOS CONSULTADOS;
- verificar SHA canonical real;
- confirmar apego al alcance.

Si existe contradicción entre canónicos:
DETENER → DORI Analista.
```

Al terminar una tarea relacionada con Copiloto, Work debe emitir:

`APEGO AL CANÓNICO DORI COPILOTO — PASS`

o:

`DESVIACIÓN DEL CANÓNICO DORI COPILOTO — DETENER`

Este control no sustituye los controles equivalentes de Consola, Conductores u otros dominios implicados.

---

# 5. Meta funcional de Copiloto

La meta de esta etapa es una prueba real y funcional:

```text
CONSOLA DORI
    ↓
crea una oferta simulada de alta fidelidad
    ↓
SIMULADOR / RECEPTOR EN TELÉFONO
    ↓
muestra una solicitud visual
    ↓
DORI VISUAL READER
    ↓
interpreta la pantalla
    ↓
OFERTA CANÓNICA DORI
    ↓
COPILOTO
    ↓
evalúa con contexto + parámetros vigentes
    ↓
CONDUCTOR
    ↓
ve TOMAR / NO TOMAR
    ↓
RESULTADO
    ↓
CONSOLA DORI
    ↓
EXPECTED vs ACTUAL
```

El 100% de esta etapa solo se alcanza cuando este circuito se valide de extremo a extremo con una prueba humana real.

---

# 6. Copiloto no es una identidad

Copiloto no es:

- rol;
- cuenta;
- identidad;
- workspace raíz;
- nueva aplicación comercial;
- nueva consola.

Su ubicación funcional permanece:

```text
Conductor
    ↓
Turno
    ↓
DORI Copiloto
```

Esto no significa que Copiloto gobierne todo Conductores.

Solo gobierna la experiencia y lógica de Copiloto dentro de esa superficie.

---

# 7. Papel de Consola dentro de Copiloto

Consola DORI participa como **laboratorio y emisor de pruebas Copiloto**.

Dentro de este dominio puede:

- crear casos simulados;
- elegir conductor TEST;
- definir oferta visual;
- definir contexto DORI;
- mover hora simulada;
- mover umbral $/km;
- mover umbral $/hora;
- mover umbral de rating;
- definir `EXPECTED`;
- consultar `ACTUAL`;
- consultar clasificación.

Este documento no gobierna otras funciones de Consola.

No se crea una segunda Consola.

---

# 8. Principio de desacoplamiento de plataformas

Copiloto no debe depender directamente del layout interno de Uber ni de otra plataforma.

Arquitectura obligatoria:

```text
Pantalla externa
    ↓
lector / adaptador visual
    ↓
TripOffer canónica DORI
    ↓
DORI Decision Input
    ↓
Motor Copiloto
    ↓
Recomendación
```

Si una plataforma cambia visualmente:

- se adapta el lector;
- no se reescribe Copiloto;
- no se duplican reglas;
- no se altera el motor solo para compensar un cambio visual.

Esta separación deja abierta la posibilidad técnica de adaptar otras plataformas en el futuro sin convertirlo en requisito del producto actual.

---

# 9. Lectura visual como frontera

La estrategia de prueba prioritaria debe poder procesar **píxeles**, no únicamente JSON estructurado.

Flujo:

```text
pantalla / captura
    ↓
OCR + análisis visual
    ↓
campos detectados
    ↓
validación de confianza
    ↓
TripOffer
```

Campos críticos mínimos:

- tarifa;
- rating;
- tiempo de recogida;
- distancia de recogida;
- tiempo de viaje;
- distancia de viaje.

Si un campo crítico no puede obtenerse con suficiente confianza:

**no inventar.**

Copiloto debe poder declarar datos insuficientes.

---

# 10. Simulador de plataforma

Puede existir una app/harness TEST independiente denominada internamente:

`DORI Trip Simulator`

Su función es:

- recibir un caso desde Consola;
- renderizar una solicitud visual;
- reproducir temporizador;
- reproducir estados de oferta;
- exponer la pantalla al lector visual.

No es un nuevo módulo de negocio.

No es una identidad de producción.

No sustituye a Copiloto.

---

# 11. Uso de capturas reales como referencia

Se permite utilizar capturas reales de pantalla, suministradas para pruebas internas, como referencia visual.

Pipeline preferido:

```text
captura de referencia
    ↓
mapa de campos editables
    ↓
renderizador controlado
    ↓
imagen simulada
```

La IA puede ayudar a:

- segmentar;
- localizar campos;
- clasificar pantalla;
- generar variantes de estrés;
- asistir validación.

La IA generativa no debe ser la única autoridad para recrear la pantalla final.

La imagen de prueba debe ser reproducible y verificable.

---

# 12. Oferta canónica DORI

Modelo conceptual:

```text
TripOffer
├── source
├── sourceOfferId
├── requestType
├── productType
├── offeredEarnings
├── currency
├── pickup
│   ├── location
│   ├── distanceKm
│   └── etaMinutes
├── trip
│   ├── destination
│   ├── distanceKm
│   ├── durationMinutes
│   └── stops
├── rider
│   └── rating
├── expiresAt
└── sourceMetadata
```

Este contrato pertenece al dominio Copiloto.

Las ampliaciones deben preservar compatibilidad o versionarse.

---

# 13. Tarjeta principal del conductor

La tarjeta principal de Copiloto debe mostrar:

1. precio efectivo por kilómetro;
2. precio efectivo por hora;
3. calificación observada del usuario;
4. recomendación fuerte `TOMAR / NO TOMAR`;
5. hasta tres razones claras.

Ejemplo conceptual:

```text
DORI COPILOTO

TOMAR VIAJE

$10.94 / km
$294 / hora
★ 4.92

Buena rentabilidad.
Destino favorable.
Sin conflicto con tu turno.
```

Esto no elimina los parámetros ya existentes del motor.

---

# 14. Precio efectivo por kilómetro

Debe considerar:

`distancia de recogida + distancia del viaje`

Conceptualmente:

`precioPorKm = ingresoOfrecido / distanciaEfectiva`

---

# 15. Precio efectivo por hora

Debe considerar:

`recogida + viaje + espera operativa atribuible a la oferta`

Conceptualmente:

`precioPorHora = ingresoOfrecido / tiempoEfectivoEnHoras`

La espera hipotética hasta una futura oferta pertenece al costo de oportunidad interno y no debe contaminar la métrica visible del viaje actual.

---

# 16. Rating

El rating visible es el rating observado del usuario.

Copiloto no lo modifica.

---

# 17. Valores observados vs umbrales DORI

Esta separación es obligatoria.

## Valores observados

- $/km real de la oferta;
- $/hora real de la oferta;
- rating real observado.

## Umbrales internos

- mínimo aceptable $/km;
- mínimo aceptable $/hora;
- mínimo aceptable rating.

Los primeros describen la oferta.

Los segundos describen la exigencia de DORI.

Nunca deben confundirse.

---

# 18. Parámetros configurables desde Consola

Dentro del laboratorio Copiloto, Consola debe poder modificar:

- hora simulada;
- mínimo $/km;
- mínimo $/hora;
- mínimo rating.

Esto debe permitir probar una misma oferta bajo distintos contextos.

No implica que Consola controle esos parámetros para otras funciones ajenas a Copiloto.

---

# 19. Escenarios de demanda

Copiloto debe soportar al menos:

- baja;
- intermedia;
- alta.

Las franjas exactas y valores exactos se determinarán con pruebas.

Un horario de baja demanda no debe usar automáticamente los mismos umbrales económicos que uno de alta demanda.

---

# 20. Aprendizaje por fases

## Fase A — Manual

Consola configura umbrales.

## Fase B — Sugerido

Copiloto propone ajustes basados en resultados.

## Fase C — Autoajuste controlado

Copiloto puede ajustar dentro de límites administrativos.

Debe existir:

- mínimo;
- máximo;
- versión;
- auditoría;
- reversión;
- trazabilidad.

No saltar directamente a autoaprendizaje autónomo.

---

# 21. Rating y límites

El rating debe tener límites administrativos.

La presión económica no puede reducir indefinidamente el umbral mínimo.

El piso exacto se definirá posteriormente con evidencia.

---

# 22. Datos para aprendizaje

Podrán utilizarse:

- hora;
- día;
- zona;
- oferta;
- $/km;
- $/hora;
- rating;
- aceptó/rechazó;
- ingreso real;
- duración real;
- distancia real;
- espera posterior;
- tiempo a siguiente oferta;
- batería;
- destino;
- demanda;
- retorno a estación;
- resultado operativo.

El objetivo es optimizar resultado real, no una sola métrica aislada.

---

# 23. EXPECTED vs ACTUAL

`EXPECTED` es una expectativa de laboratorio.

Debe permanecer en Consola/backend de prueba.

Nunca debe llegar al conductor antes de evaluar.

Copiloto produce `ACTUAL`.

Consola compara:

- `correct_recommend`
- `correct_reject`
- `false_positive`
- `false_negative`

`EXPECTED` no entrena automáticamente el motor.

---

# 24. Aislamiento simulación / operación real

Una `PRUEBA DORI` no puede por sí misma:

- iniciar turno;
- finalizar turno;
- cambiar ingresos reales;
- modificar batería real;
- cambiar vehículo;
- asignar vehículo;
- alterar ofertas reales;
- generar eventos live;
- activar flujo Supervisor.

Toda simulación debe ser identificable como TEST.

---

# 25. Contexto actual del motor

No se elimina ni reemplaza lo ya desarrollado.

Deben preservarse, entre otros:

- batería;
- autonomía;
- tiempo restante del turno;
- distancia a estación;
- distancia destino-estación;
- demanda;
- valor del destino;
- costo de oportunidad;
- reglas horarias;
- bloqueos operativos;
- puntuaciones internas;
- versiones del motor;
- contexto adicional existente.

La nueva capa visual aporta datos de la oferta.

No sustituye el cerebro existente.

---

# 26. Backend como autoridad

El cliente no puede enviar como verdad:

- recommendation;
- scores;
- classification;
- `EXPECTED` como entrada del motor;
- resultados fabricados.

El backend/motor canónico conserva autoridad sobre la evaluación.

`EXPECTED` existe únicamente para comparación posterior de laboratorio.

---

# 27. Matriz mínima de pruebas

Antes de considerar completa esta etapa deben probarse al menos:

1. recomendación positiva;
2. recomendación negativa;
3. aislamiento Driver A / Driver B;
4. `EXPECTED` oculto;
5. expiración;
6. idempotencia;
7. Supervisor bloqueado;
8. simulación no altera operación live;
9. lectura correcta de tarifa;
10. lectura correcta de $/km;
11. lectura correcta de $/hora;
12. lectura correcta de rating;
13. error seguro ante lectura insuficiente;
14. variación de hora;
15. variación de umbral $/km;
16. variación de umbral $/hora;
17. variación de umbral rating;
18. escenarios bajo/intermedio/alto;
19. regreso de `ACTUAL` a Consola;
20. clasificación `EXPECTED vs ACTUAL`;
21. prueba humana con teléfono real.

---

# 28. Roadmap funcional de la etapa

| Bloque | Peso |
|---|---:|
| Base técnica y contrato | 20% |
| Backend Copiloto en TEST | 15% |
| Consola / generador de casos | 15% |
| Simulador visual + lector | 20% |
| Conductor / tarjeta Copiloto | 10% |
| Pruebas cruzadas automatizadas | 10% |
| Prueba humana real | 10% |

Los porcentajes representan avance funcional validado, no volumen de código.

El porcentaje solo aumenta cuando la capacidad correspondiente funciona y está comprobada.

---

# 29. Regla de no regresión

No modificar trabajo ya aprobado de Copiloto salvo que:

- sea necesario para cumplir este canónico;
- exista incompatibilidad demostrada;
- DORI Analista autorice el cambio.

En particular:

- no eliminar parámetros actuales;
- no sustituir motor;
- no duplicar reglas;
- no romper modos existentes;
- no rediseñar por estética durante esta etapa;
- no alterar otros dominios para acomodar Copiloto;
- no redefinir Auth/roles/routing global desde este canónico.

---

# 30. Prueba humana y criterio de 100%

Esta etapa no llega a 100% porque:

- compile;
- el backend responda;
- una imagen se vea bien;
- OCR funcione aislado;
- Copiloto recomiende localmente;
- Consola pueda crear un caso.

Llega a 100% únicamente cuando:

```text
Consola
→ crea caso
→ teléfono receptor muestra oferta
→ lector visual obtiene datos
→ DORI normaliza
→ Copiloto evalúa
→ conductor recibe TOMAR / NO TOMAR
→ métricas visibles son correctas
→ resultado regresa a Consola
→ EXPECTED vs ACTUAL queda registrado
→ operación real permanece intacta
```

---

# 31. Gobierno de cambios a este canónico

Cualquier cambio requiere:

1. propuesta explícita;
2. revisión de DORI Analista;
3. confirmación del usuario si cambia producto/arquitectura;
4. incremento de versión;
5. registro breve del cambio.

Work no puede reescribir este documento para acomodar una implementación.

La implementación debe apegarse al documento.

---

# 32. Registro de versiones

## v1.0 — 2026-09-21

Adopción inicial.

Fija:

- alcance exclusivamente Copiloto;
- coexistencia con otros canónicos;
- obligación de citarlo en prompts pertinentes;
- lector visual como frontera;
- `TripOffer` canónica;
- simulador visual de alta fidelidad;
- uso controlado de capturas de referencia;
- tarjeta del conductor;
- $/km incluyendo recogida;
- $/hora incluyendo recogida + viaje + espera atribuible;
- rating observado;
- separación entre valores observados y umbrales;
- tres umbrales configurables desde Consola;
- escenarios de demanda;
- aprendizaje manual → sugerido → autoajuste controlado;
- `EXPECTED` oculto;
- aislamiento TEST/live;
- criterio de 100% basado en prueba humana real.

---

**CONTROL:** `DORI COPILOTO — CANÓNICO DE DOMINIO v1.0 — ACTIVO`
