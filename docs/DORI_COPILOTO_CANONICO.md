# DORI COPILOTO — CANÓNICO DE DOMINIO

**Estado:** ACTIVO  
**Versión:** 1.3  
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

# 33. Principio de mínima intervención del usuario

El usuario propietario de DORI debe intervenir lo menos posible en tareas técnicas de implementación, infraestructura, autenticación, despliegue, pruebas y gobierno operativo.

La razón es práctica: el usuario define visión, prioridades, aceptación de producto y decisiones de negocio, pero no se debe asumir que conoce ni debe ejecutar procedimientos técnicos de bajo nivel.

## 33.1 Obligación de DORI Analista y Work

Antes de pedir una acción al usuario, DORI Analista y Work deben agotar primero las capacidades disponibles para resolverla de forma autónoma y segura, incluyendo cuando aplique:

- herramientas y conectores disponibles;
- GitHub Actions;
- Cloud Browser / Work;
- Supabase Dashboard o APIs administrativas autorizadas;
- scripts automatizados controlados;
- variables y secretos administrados por el entorno;
- pruebas automatizadas;
- lectura y modificación segura de repositorio;
- mecanismos oficiales de la plataforma implicada.

No se debe trasladar al usuario una tarea técnica solo porque sea más rápido pedirle que la haga manualmente.

## 33.2 Acciones que no deben pedirse al usuario salvo necesidad real

Evitar pedir al usuario que:

- ejecute SQL;
- manipule tablas internas;
- edite `auth.users`;
- cree hashes;
- maneje `service_role`;
- copie secretos entre herramientas;
- configure variables de entorno manualmente;
- ejecute scripts de PowerShell, Bash o Node;
- resuelva conflictos Git;
- modifique archivos de configuración;
- interprete logs técnicos;
- gestione JWT;
- rote credenciales;
- cambie RLS;
- ejecute migraciones;
- despliegue Edge Functions;
- configure CI/CD;
- tome decisiones técnicas de implementación que correspondan a DORI Analista o Work.

## 33.3 Cuándo sí puede intervenir el usuario

La intervención del usuario se reserva principalmente para:

- decisiones de producto;
- aprobación de cambios de alcance;
- aceptación visual o funcional;
- definición de reglas de negocio;
- autorización de acciones irreversibles o de alto impacto;
- acciones físicas sobre dispositivos;
- MFA, biometría o confirmaciones que solo el titular puede completar;
- acceso a cuentas cuando la plataforma exige interacción del propietario;
- pruebas humanas finales;
- acciones que ninguna herramienta autorizada pueda realizar.

## 33.4 Forma de pedir una intervención inevitable

Si la intervención del usuario es realmente necesaria:

1. explicar en lenguaje simple qué debe hacer y por qué;
2. reducirla al mínimo número de pasos;
3. preferir una acción visual en interfaz antes que terminal o código;
4. no pedir secretos en el chat;
5. no pedir operaciones destructivas sin explicar el impacto;
6. no asumir conocimientos técnicos;
7. detenerse antes de una acción riesgosa si existe una alternativa más segura;
8. retomar automáticamente la tarea en cuanto la intervención mínima termine.

## 33.5 Regla de autonomía operativa

Para tareas de Copiloto, el comportamiento esperado es:

`Work/DORI Analista resuelven → usuario valida`

y no:

`usuario ejecuta → Work interpreta`

La participación humana debe concentrarse en visión, decisiones y validación del resultado.

## 33.6 Gate obligatorio en prompts

Todo prompt relevante a Copiloto debe incluir una instrucción equivalente a:

`MÍNIMA INTERVENCIÓN DEL USUARIO: resolver autónomamente todo lo técnicamente posible. No pedir al usuario ejecutar comandos, manejar secretos, editar infraestructura o realizar procedimientos técnicos salvo que sea estrictamente inevitable.`

Si una tarea requiere intervención humana, Work debe reportar:

- por qué no puede resolverla;
- qué capacidad falta;
- cuál es la acción mínima exacta del usuario;
- por qué no existe una alternativa automatizada segura.

---

# 34. Registro de versiones actualizado

## v1.1 — 2026-09-21

Añade el principio de **mínima intervención del usuario**.

Fija que:

- DORI Analista y Work deben agotar primero las capacidades técnicas disponibles;
- el usuario no debe ser convertido en operador técnico;
- secretos, Auth, infraestructura, CI/CD, SQL y despliegues deben resolverse por mecanismos automatizados o administrativos cuando sea posible;
- la intervención humana se reserva para decisiones, aprobaciones, acciones físicas, MFA y validación final;
- los prompts de Copiloto deben incluir explícitamente esta regla.


---

# 35. Herencia del Gobierno de Ejecución Autónoma

Toda misión relacionada con DORI Copiloto hereda obligatoriamente:

`docs/DORI_GOBIERNO_EJECUCION_AUTONOMA.md`

y:

`docs/DORI_MISION_MAESTRA_STANDARD.md`

La metodología de trabajo queda fijada así:

`usuario autoriza misión → DORI Analista realiza pre-flight → Work ejecuta todas las fases internas → DORI Analista audita → usuario prueba producto final`

Las fases del roadmap Copiloto siguen existiendo para control y trazabilidad, pero no constituyen puntos normales de retorno al usuario.

Work debe recorrerlas automáticamente cuando formen parte de una misma Misión Maestra.

---

# 36. Regla de entrega end-to-end para Copiloto

Cuando el usuario autorice continuar con Copiloto, DORI Analista debe preparar una única Misión Maestra cuyo Definition of Done cubra todo el alcance autorizado.

Work no debe entregar bloques técnicos aislados cuando todavía pueda continuar autónomamente.

Para la etapa funcional actual, la entrega objetivo debe aproximarse a:

`Consola crea caso → receptor/teléfono muestra oferta → lector visual interpreta → TripOffer → motor Copiloto evalúa → conductor recibe TOMAR/NO TOMAR → resultado vuelve a Consola → EXPECTED vs ACTUAL queda registrado → operación live permanece intacta → pruebas automatizadas pasan → listo para prueba humana`

La implementación, correcciones y validaciones intermedias pertenecen a Work.

---

# 37. Pre-flight específico antes de una misión Copiloto

Antes de emitir la Misión Maestra de Copiloto, DORI Analista debe verificar en una sola preparación:

- canónicos vigentes;
- SHA canonical real;
- rama de trabajo;
- estado de Supabase TEST;
- secrets TEST necesarios;
- identidades TEST;
- GitHub Actions;
- permisos de repositorio;
- disponibilidad de builds/dispositivos;
- capturas/assets visuales necesarios;
- dependencias del lector visual;
- herramientas necesarias;
- decisiones de producto todavía ambiguas;
- criterio de prueba humana final.

Las credenciales no se almacenan en este canónico ni en prompts.

Si una prueba visual necesita usuarios TEST, sus credenciales deben consumirse desde un almacén seguro.

---

# 38. Registro v1.2

## v1.2 — 2026-09-21

Incorpora:

- herencia del Gobierno de Ejecución Autónoma;
- uso obligatorio del Estándar de Misión Maestra;
- ejecución end-to-end de todas las fases internas;
- usuario como aprobador y probador final;
- pre-flight único antes de iniciar;
- prohibición de devolver microtareas técnicamente resolubles;
- credenciales TEST únicamente desde almacenes seguros.


## 39. Soporte de servicio para BYD Dolphin Mini

Para la flota actual BYD Dolphin Mini, el alcance operativo de Copiloto admite únicamente:

- `UberX`;
- `Uber Comfort`.

El lector puede reconocer otras categorías para clasificarlas, pero cualquier categoría fuera de esta lista debe producir `SERVICIO NO SOPORTADO` y no puede emitir una recomendación fuerte `TOMAR` o `NO TOMAR`. Esta whitelist es una condición crítica de recomendación y no sustituye el motor económico ni sus parámetros versionados.

## 40. Registro v1.3

## v1.3 — 2026-09-21

Incorpora la whitelist funcional `UberX` + `Uber Comfort` para BYD Dolphin Mini y el estado explícito `SERVICIO NO SOPORTADO` para categorías reconocidas pero no habilitadas.

**CONTROL:** `DORI COPILOTO — CANÓNICO DE DOMINIO v1.3 — ACTIVO`
