# DORI Conductores — auditoría canónica

Esta matriz separa las superficies que ya están conectadas al contrato actual de las que requieren un contrato remoto adicional. No convierte datos locales o de demostración en autoridad operativa.

| Función | Estado actual | Cumple canon | Evidencia / límite |
|---|---|---:|---|
| Turno | Vista principal con identidad, jornada, progreso y unidad; acciones de incidencia y documentos en segunda capa | Sí | `Views/ShiftView.swift` |
| Metas | Meta diaria, telemetría, mejores horas y avance semanal en scroll | Sí | `Views/GoalsView.swift`; mejores horas son referencia mock declarada |
| Bonos | Cuatro bonos independientes y recuperación solo para pérdida atribuible | Sí | `Views/BonusesView.swift` |
| Cartera | Snapshot, cuenta bancaria, ingresos, liquidaciones e historial desde Supabase; detalles seguros para bonos/crédito/efectivo | Parcial | `Views/BackendDriverFinanceView.swift`; operaciones de transferencia, depósito y crédito requieren contrato remoto |
| Guardias | Flujo backend de cobertura y vista local con escenarios de oferta/aceptación/rechazo/no-show | Parcial | `Views/Coverage/BackendDriverCoverageView.swift`, `Views/Coverage/DriverCoverageViews.swift`; escenarios locales no son autoridad backend |
| Recuperación de horas | 15 minutos, 1–5 h, >5 h y corte semanal | Sí | `Views/HourRecoveryView.swift` |
| Accidente/incidencia | Clasificación, texto, audio, ubicación y seis slots de foto; envío operativo registra texto y contexto | Parcial | `Views/IncidentView.swift`; fotos permanecen como borrador hasta contrato de almacenamiento/evidencia |
| Documentos | Segunda capa de consulta de documentos de unidad/conductor | Sí | `Views/UnitDocumentsView.swift` |
| Crédito automotriz | Estado explícito no disponible; sin simulación ni pagos locales | Sí (seguro) | Detalle de crédito en `BackendDriverFinanceView.swift` |
| Historial | Historial financiero por mes/semana dentro de Cartera | Sí | `Views/BackendDriverFinanceView.swift` |
| Depósito de efectivo | Estado vacío/pendiente cuando no hay movimiento real; sin depósito simulado | Parcial | `Models/CashDeposits.swift`; falta contrato remoto de evidencia y cuenta destino |

## Navegación aprobada

La navegación de conductor es `Turno / Metas / Bonos / Cartera / Guardias`. Copiloto permanece dentro de Turno; el historial financiero vive dentro de Cartera.

## Límites deliberados

`WalletView`, `IncomeView` y `CreditView` contienen superficies locales históricas y no son fuente operativa para sesiones backend. No se reactivan hasta disponer de contratos remotos equivalentes. Esta auditoría no modifica Supabase ni inventa importes, depósitos, créditos o evidencias remotas.
