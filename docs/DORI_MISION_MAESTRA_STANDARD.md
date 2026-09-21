# DORI — ESTÁNDAR DE MISIÓN MAESTRA

**Estado:** ACTIVO  
**Versión:** 1.1  
**Fecha de adopción:** 2026-09-21  
**Dependencia:** `docs/DORI_GOBIERNO_EJECUCION_AUTONOMA.md`  
**Ruta canónica objetivo:** `docs/DORI_MISION_MAESTRA_STANDARD.md`

---

# 1. Uso

Este documento define la estructura mínima que DORI Analista debe usar al encargar a Work una tarea completa.

La unidad normal de trabajo ya no es una microtarea.

La unidad normal es una **misión end-to-end**.

---

# 2. Encabezado obligatorio

Toda misión debe declarar:

- motor recomendado y razón;
- nombre de misión;
- estado inicial;
- objetivo final;
- rama/base;
- canónicos aplicables;
- entornos permitidos;
- producción permitida/prohibida;
- Definition of Done.

---

# 3. Pre-flight requerido

Antes de emitir la misión, DORI Analista debe haber validado:

- accesos;
- secrets;
- herramientas;
- dependencias;
- cuentas TEST;
- decisiones de producto;
- restricciones;
- hardware;
- assets;
- permisos;
- canónicos;
- SHA.

La misión debe incluir:

`PRE-FLIGHT: PASS`

Si no existe PASS, la misión no debe arrancar.

---

# 4. Autoridad concedida

La misión debe especificar que Work puede, dentro del alcance:

- investigar;
- implementar;
- refactorizar localmente;
- crear pruebas;
- ejecutar pruebas;
- corregir;
- volver a probar;
- desplegar TEST;
- usar herramientas autorizadas;
- crear helpers temporales;
- continuar automáticamente entre fases.

No debe pedir aprobación entre fases internas.

---

# 5. Fases internas

La misión puede contener N fases.

Cada fase debe tener:

- objetivo;
- entradas;
- trabajo esperado;
- pruebas;
- gate de salida.

Cuando una fase pasa, Work continúa automáticamente a la siguiente.

---

# 6. Bucle de autocorrección

Texto obligatorio o equivalente:

`NO DEVOLVER ERRORES TÉCNICOS ORDINARIOS AL USUARIO. Investigar, corregir, volver a ejecutar pruebas y continuar hasta PASS o bloqueo externo real.`

También debe incluir la regla:

`PROCESOS ASÍNCRONOS NO SON BLOQUEO. Esperar/pollear workflows, builds, deploys y procesamientos remotos hasta conocer su conclusión; corregir y reejecutar si fallan.`

---

# 7. Seguridad

Toda misión debe declarar:

- secretos nunca en logs;
- no tokens completos;
- no producción salvo autorización;
- no `service_role` para simular usuarios;
- no bypass de RLS en pruebas funcionales;
- no tocar módulos congelados;
- no merges finales sin gate.

---

# 8. Evidencia

Work debe entregar evidencia suficiente para que DORI Analista audite:

- SHA inicial/final;
- archivos relevantes;
- pruebas ejecutadas;
- resultados;
- despliegues TEST;
- invariantes;
- regresiones verificadas;
- bloqueos inexistentes o reales;
- deuda residual permitida;
- instrucciones de prueba humana.

---

# 9. Definition of Done

Debe formularse en términos funcionales observables.

Ejemplo correcto:

`Consola crea caso → teléfono lo recibe → lector interpreta → motor decide → resultado vuelve → operación live intacta.`

Ejemplo insuficiente:

`Se agregó endpoint y pantalla.`

---

# 10. Progreso y condición de salida

El progreso puede mostrarse como porcentaje o fase, pero es únicamente informativo.

Un reporte como:

`MISIÓN — 55%`

NO es condición de salida, no pausa el trabajo y no requiere aprobación del usuario para continuar.

Si la plataforma permite publicar progreso sin finalizar, Work puede informar avances.

Si publicar progreso implica terminar el turno o devolver el control, Work debe omitir el reporte intermedio y continuar trabajando.

Procesos `queued`, `pending`, `in_progress` o equivalentes deben ser monitoreados por Work hasta conclusión.

Cierre válido:

`MISIÓN COMPLETA — LISTA PARA PRUEBA HUMANA`

Bloqueo válido:

`MISIÓN BLOQUEADA POR DEPENDENCIA EXTERNA REAL`

No son cierres válidos:

- workflow en ejecución;
- build en ejecución;
- deploy pendiente;
- TestFlight procesando;
- dependencias no instaladas;
- test fallando;
- error técnico corregible;
- reporte parcial de porcentaje.

En caso de bloqueo externo real, Work debe pedir una sola intervención mínima y conservar el punto exacto de reanudación.

---

# 11. Después de la prueba humana

Si el usuario detecta una falla:

- el usuario describe el síntoma;
- DORI Analista diagnostica/encarga;
- Work recibe una nueva misión completa de corrección;
- no se delega diagnóstico técnico al usuario.

---

# 12. Plantilla mínima

```text
MOTOR:
[modelo/esfuerzo y razón]

MISIÓN:
[nombre]

GOBIERNO:
docs/DORI_GOBIERNO_EJECUCION_AUTONOMA.md

CANÓNICOS:
[listado]

PRE-FLIGHT:
PASS

ESTADO INICIAL:
[...]

OBJETIVO FINAL:
[...]

AUTORIDAD:
Work puede ejecutar end-to-end en TEST dentro del alcance.

FASES INTERNAS:
1. [...]
2. [...]
N. [...]

AUTOCORRECCIÓN:
No devolver fallos técnicos ordinarios. Corregir y continuar.
Esperar/pollear procesos asíncronos hasta conclusión. Un proceso en ejecución no es bloqueo.

PROGRESO:
Informativo y no terminal. Si reportarlo termina el turno, omitir el reporte y continuar.

PROHIBIDO:
[...]

PRUEBAS OBLIGATORIAS:
[...]

DEFINITION OF DONE:
[...]

EVIDENCIA:
[...]

SALIDA:
MISIÓN COMPLETA — LISTA PARA PRUEBA HUMANA
o
MISIÓN BLOQUEADA POR DEPENDENCIA EXTERNA REAL
```

---

# 13. Registro

## v1.1 — 2026-09-21

Añade la regla de continuidad sobre procesos asíncronos y establece que porcentajes/fases son telemetría no terminal.

## v1.0 — 2026-09-21

Adopción inicial del estándar de Misión Maestra.

---

**CONTROL:** `DORI — ESTÁNDAR DE MISIÓN MAESTRA v1.1 — ACTIVO`
