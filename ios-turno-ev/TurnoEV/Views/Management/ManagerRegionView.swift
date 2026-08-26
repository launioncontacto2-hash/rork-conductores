import SwiftUI

/// Estación: the consolidated picture of the manager's own station and the board of
/// generated alerts. There is nothing to compare against, because a manager runs one
/// station: every number here is theirs to answer for.
struct ManagerRegionView: View {
    let regional: RegionalStore
    let header: ManagerHeader
    let onOpenStation: (String) -> Void
    let onOpenStations: () -> Void
    let onOpenApprovals: (RequestFilter) -> Void
    let onOpenRequest: (String) -> Void
    let onOpenPerformance: () -> Void
    let onOpenStaff: () -> Void

    /// Instant the counters of this screen are measured against.
    ///
    /// `.minute`: `metrics.agingRequests` crosses twenty-four hours from a `createdAt` that
    /// fell at an arbitrary hour, and the goal board turns on a shift boundary. The anchor
    /// is written by an invisible leaf, so the `ScrollView` is never invalidated by the
    /// clock — only the panels that read the anchor are.
    @State private var minuteAnchor: Date = AppClock.now()

    private var metrics: RegionMetrics { regional.metrics(now: minuteAnchor) }

    var body: some View {
        ZStack {
            ManagementBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    goalPanel
                    hero
                    tiles
                    attention
                    alertBoard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .background {
            ClockAnchor(.minute, date: $minuteAnchor)
        }
    }

    // MARK: - Fixed goal

    /// The number the station exists to reach, fixed for the whole shift: authorized
    /// units by the driver goal of the day. It never drops when a seat is empty.
    private var goalPanel: some View {
        let board = regional.goalBoard(now: minuteAnchor)
        return VStack(spacing: 10) {
            StationGoalPanel(
                board: board,
                caption: "Meta de facturación del turno",
                accent: MgTone.accent
            )

            if board.uncoveredSeats > 0 {
                NoticeBanner(
                    symbol: "person.fill.xmark",
                    title: "\(board.uncoveredSeats) unidades sin conductor este turno",
                    message: "El supervisor debe notificar a cada conductor que faltó que tiene que reponer ese día con el programa de recuperación de bonos.",
                    tone: .amber
                )
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    MgRing(
                        ratio: metrics.attendanceRatio,
                        headline: "\(metrics.presentDrivers)",
                        caption: "En calle",
                        tone: metrics.attendanceRatio >= 0.94 ? MgTone.good : MgTone.accent,
                        size: 148
                    )
                    HStack(spacing: 6) {
                        InfoChip(
                            symbol: "person.fill.xmark",
                            text: "\(metrics.absentDrivers) faltaron",
                            tone: metrics.absentDrivers > 0 ? MgTone.bad : Palette.textMuted
                        )
                        InfoChip(
                            symbol: "clock.badge.exclamationmark",
                            text: "\(metrics.lateDrivers) tarde",
                            tone: metrics.lateDrivers > 0 ? MgTone.warn : Palette.textMuted
                        )
                    }
                    Text("de \(metrics.onShiftDrivers) programados en el turno")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textMuted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        CapsLabel(text: "Facturación de la estación")
                        Text(Fmt.mxn(metrics.earningsMxn))
                            .font(.system(size: 27, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("Meta fija del turno \(Fmt.mxn(metrics.goalMxn))")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }

                    Divider().overlay(Palette.hairline)

                    MeterRow(
                        label: "Meta del turno",
                        value: "\(Int(metrics.goalRatio * 100))%",
                        ratio: metrics.goalRatio,
                        tone: metrics.goalRatio >= RegionalRules.goalFloor ? MgTone.good : MgTone.bad,
                        marker: 1
                    )
                    MeterRow(
                        label: "Flotilla en operación",
                        value: "\(metrics.operatingVehicles)/\(metrics.fleetSize)",
                        ratio: metrics.utilizationRatio,
                        tone: MgTone.cool
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CapsLabel(text: "Semana en curso")
                    Spacer()
                    Text("\(Fmt.mxn(metrics.weekEarningsMxn)) · \(Int(metrics.weekGoalRatio * 100))% de meta")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                        .monospacedDigit()
                }
                WeekBarsChart(points: regional.weekSeries(now: minuteAnchor))
            }
        }
        .padding(16)
        .panel()
    }

    // MARK: - Tiles

    private var tiles: some View {
        VStack(spacing: 12) {
            SupSectionHeader(
                title: "Pulso de la estación",
                subtitle: "Toca una tarjeta para entrar al módulo que la resuelve",
                accent: MgTone.accent
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(
                    label: "Por autorizar",
                    value: "\(metrics.pendingRequests)",
                    symbol: "checkmark.seal.fill",
                    detail: metrics.agingRequests > 0 ? "\(metrics.agingRequests) con más de 24 h" : "Bandeja al día",
                    tone: metrics.pendingRequests > 0 ? MgTone.accent : MgTone.good,
                    isAlarming: metrics.agingRequests > 0
                ) { onOpenApprovals(.all) }

                MetricCard(
                    label: "Salud de la estación",
                    value: "\(Int((regional.card?.healthScore ?? 0) * 100))",
                    symbol: "building.2.fill",
                    detail: regional.card?.health.label ?? "Sin datos",
                    tone: regional.card?.health.tone ?? MgTone.cool,
                    isAlarming: !regional.stationsNeedingAttention.isEmpty
                ) { onOpenStations() }

                MetricCard(
                    label: "Conductores presentes",
                    value: "\(metrics.presentDrivers)",
                    symbol: "person.3.fill",
                    detail: "\(metrics.absentDrivers) ausentes · \(metrics.lateDrivers) con atraso",
                    tone: metrics.attendanceRatio >= 0.94 ? MgTone.good : MgTone.accent
                ) { onOpenPerformance() }

                MetricCard(
                    label: "Unidades detenidas",
                    value: "\(metrics.idleVehicles)",
                    symbol: "wrench.and.screwdriver.fill",
                    detail: "Taller y fuera de servicio",
                    tone: metrics.idleVehicles > 14 ? MgTone.bad : MgTone.cool,
                    isAlarming: metrics.idleVehicles > 14
                ) { onOpenStations() }

                MetricCard(
                    label: "Cartera de crédito",
                    value: "\(metrics.creditPortfolio)",
                    symbol: "creditcard.fill",
                    detail: metrics.creditBehind > 0 ? "\(metrics.creditBehind) con atraso" : "Toda al corriente",
                    tone: MgTone.premium
                ) { onOpenApprovals(.credit) }

                MetricCard(
                    label: "Bonos en riesgo",
                    value: "\(metrics.bonusAtRisk)",
                    symbol: "rosette",
                    detail: "Se cancelan solos si falla la semana",
                    tone: MgTone.accent
                ) { onOpenPerformance() }

                MetricCard(
                    label: "Incidencias abiertas",
                    value: "\(metrics.openIncidents)",
                    symbol: "exclamationmark.triangle.fill",
                    detail: "\(metrics.criticalIncidents) crítica(s)",
                    tone: metrics.criticalIncidents > 0 ? MgTone.bad : MgTone.accent,
                    isAlarming: metrics.criticalIncidents > 0
                ) { onOpenStations() }

                MetricCard(
                    label: "Plantilla de la estación",
                    value: "\(metrics.payrollSize)",
                    symbol: "person.text.rectangle.fill",
                    detail: "Requiere \(regional.station.requiredDrivers) · 4 turnos",
                    tone: metrics.payrollSize < regional.station.requiredDrivers ? MgTone.warn : MgTone.cool,
                    isAlarming: metrics.payrollSize < regional.station.requiredDrivers
                ) { onOpenStaff() }
            }
        }
    }

    // MARK: - Attention

    @ViewBuilder
    private var attention: some View {
        if let card = regional.card, card.health == .watch || card.health == .critical {
            VStack(alignment: .leading, spacing: 10) {
                SupSectionHeader(
                    title: "Tu estación necesita atención",
                    subtitle: "Índice de salud por debajo del umbral operativo",
                    accent: MgTone.accent
                )
                StationRankCard(rank: 1, card: card) { onOpenStation(card.id) }
            }
        }
    }

    // MARK: - Alerts

    private var alertBoard: some View {
        let alerts = regional.alerts(now: minuteAnchor)
        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Tablero de alertas",
                subtitle: "Generadas por reglas de la red, no capturadas a mano",
                actionTitle: alerts.isEmpty ? "Restaurar" : nil,
                accent: MgTone.accent,
                action: alerts.isEmpty ? { regional.restoreAlerts() } : nil
            )

            if alerts.isEmpty {
                SupEmptyState(
                    symbol: "checkmark.shield.fill",
                    title: "Estación sin alertas",
                    message: "Tu estación va dentro de sus umbrales de meta, asistencia, flotilla y taller.",
                    accent: MgTone.accent
                )
            } else {
                ForEach(alerts) { alert in
                    RegionalAlertRow(
                        alert: alert,
                        onOpen: {
                            if let requestId = alert.requestId {
                                onOpenRequest(requestId)
                            } else if let stationId = alert.stationId {
                                onOpenStation(stationId)
                            }
                        },
                        onResolve: { regional.resolveAlert(id: alert.id) }
                    )
                }
            }
        }
    }
}
