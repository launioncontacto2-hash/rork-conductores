# DORI Copiloto — estabilización TEST de un solo iPhone

## Estado verificable

- Rama: `stabilize/copilot-single-iphone-e2e`
- La validación reproducible de base limpia reconstruye la base y pasa el lint local.
- Las pruebas SQL específicas de Copiloto y Uber Test pasan en CI.
- Node Copiloto: 38/38. Node Uber Test: 17/17.
- El puente usa `source=simulated`, exige receptor activo por instalación y mantiene idempotencia por oferta.
- La evaluación no recrea ni reinicia una notificación existente y el push filtra dispositivos recientes, revoca tokens permanentes y limita reintentos transitorios.

## Fallos externos separados

La suite SQL completa del repositorio conserva un fallo histórico ajeno al alcance Copiloto/Uber Test (`dori_recruitment_hr_consolidation.sql`, plan 33 sin ejecuciones). CI lo conserva como diagnóstico separado; la suite específica del módulo es el gate aplicable.

El despliegue remoto TEST no se ejecutó porque el environment `test` carece de `SUPABASE_ACCESS_TOKEN` y `SUPABASE_DB_PASSWORD_TEST`. No se intentó sustituirlos con `service_role` ni se tocó producción.

## Pendiente antes de afirmar equivalencia remota

1. Ejecutar `supabase db push --linked` únicamente contra `yyxzuiantrmoyozetswv`.
2. Desplegar `uber-test-next`, `uber-test-result`, `uber-test-copilot-evaluate` y `dori-copilot-push`.
3. Repetir el smoke TEST de receptor, evaluación, APNs simulado y recuperación server-authoritative.
4. Ejecutar la regresión física en el único iPhone usando el baseline aprobado.

No se modifican el motor económico, OCR, tarjeta, producción ni los módulos congelados.
