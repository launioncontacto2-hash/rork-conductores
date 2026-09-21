# DORI — ESTÁNDAR DE MISIÓN MAESTRA

**Estado:** ACTIVO  
**Versión:** 1.0  
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

# 10. Condición de salida

Cierre válido:

`MISIÓN COMPLETA — LISTA PARA PRUEBA HUMANA`

Bloqueo válido:

`MISIÓN BLOQUEADA POR DEPENDENCIA EXTERNA REAL`

En caso de bloqueo, Work debe pedir una sola intervención mínima y conservar el punto exacto de reanudación.

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

**CONTROL:** `DORI — ESTÁNDAR DE MISIÓN MAESTRA v1.0 — ACTIVO`
