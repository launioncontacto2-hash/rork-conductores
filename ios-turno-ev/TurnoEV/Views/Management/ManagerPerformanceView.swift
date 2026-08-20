import SwiftUI

/// Desempeño: the station against its own thresholds. Money, punctuality, attendance,
/// fleet and the bonus and credit portfolios of the one station this manager runs.
struct ManagerPerformanceView: View {
    let regional: RegionalStore
    let header: ManagerHeader
    let onOpenStation: (String) -> Void

    @State private var lens: PerformanceLens = .money

    private enum PerformanceLens: String, CaseIterable, Identifiable {
        case money
        case punctuality
        case attendance
        case fleet

        var id: String { rawValue }

        var label: String {
            switch self {
            case .money: "Facturación"
            case .punctuality: "Puntualidad"
            case .attendance: "Asistencia"
            case .fleet: "Flotilla"
            }
        }

        var symbol: String {
            switch self {
            case .money: "banknote.fill"
            case .punctuality: "clock.badge.checkmark.fill"
            case .attendance: "person.3.fill"
            case .fleet: "car.2.fill"
            }
        }
    }

    private var metrics: RegionMetrics { regional.metrics }

    var body: some View {
        ZStack {
            ManagementBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    weekPanel
                    comparison
                    bonusPanel
                    creditPanel
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Week

    private var weekPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Semana de la estación",
                subtitle: "Lunes a domingo contra la meta de cada día",
                accent: MgTone.accent
            )

            WeekBarsChart(points: regional.weekSeries)

            HStack(spacing: 10) {
                StatTile(
                    label: "Acumulado",
                    value: Fmt.mxn(metrics.weekEarningsMxn),
                    hint: "Meta \(Fmt.mxn(metrics.weekGoalMxn))",
                    tone: .amber
                )
                StatTile(
                    label: "Cumplimiento",
                    value: "\(Int(metrics.weekGoalRatio * 100))%",
                    hint: metrics.weekGoalRatio >= 1 ? "Meta superada" : "En curso",
                    tone: metrics.weekGoalRatio >= RegionalRules.goalFloor ? .volt : .danger
                )
                StatTile(
                    label: "Viajes",
                    value: "\(metrics.tripsToday)",
                    hint: "Del turno en curso",
                    tone: .neutral
                )
            }

            Text("Las metas cambian de \(Fmt.mxn(ShiftRules.goals(for: .weekday).dailyMxn)) por conductor entre semana a \(Fmt.mxn(ShiftRules.goals(for: .weekend).dailyMxn)) en fin de semana, por eso las barras del sábado y domingo suben.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    // MARK: - Comparison

    /// A manager has one station, so there is nothing to rank. What matters instead is
    /// each indicator against the threshold that triggers an alert: the lens picks which
    /// one to read in detail, and all four stay visible underneath.
    @ViewBuilder
    private var comparison: some View {
        if let card = regional.card {
            VStack(alignment: .leading, spacing: 12) {
                SupSectionHeader(
                    title: "Indicadores de \(card.code)",
                    subtitle: "Cada uno contra el umbral que levanta una alerta",
                    accent: MgTone.accent
                )

                FilterScroller(
                    items: PerformanceLens.allCases,
                    title: { $0.label },
                    symbol: { $0.symbol },
                    count: { _ in 1 },
                    selection: $lens,
                    accent: MgTone.accent
                )
                .padding(.horizontal, -16)

                Button {
                    onOpenStation(card.id)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Text(lens.label.uppercased())
                                .font(.system(size: 10, weight: .black))
                                .tracking(1)
                                .foregroundStyle(Palette.textMuted)
                            if card.isLive {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(MgTone.good)
                            }
                            Spacer(minLength: 4)
                            HealthBadge(health: card.health, compact: true)
                        }
                        MeterRow(
                            label: detail(for: card),
                            value: value(for: card),
                            ratio: ratio(for: card),
                            tone: tone(for: card),
                            marker: lens == .money ? 1 : nil
                        )
                    }
                    .padding(13)
                    .panelFlat()
                }
                .buttonStyle(.plain)

                VStack(spacing: 9) {
                    ForEach(PerformanceLens.allCases.filter { $0 != lens }) { other in
                        MeterRow(
                            label: other.label,
                            value: value(for: card, lens: other),
                            ratio: ratio(for: card, lens: other),
                            tone: tone(for: card, lens: other)
                        )
                    }
                }
            }
            .padding(16)
            .panel()
        }
    }

    private func ratio(for card: StationScorecard, lens: PerformanceLens? = nil) -> Double {
        switch lens ?? self.lens {
        case .money: card.goalRatio
        case .punctuality: card.punctualityPct / 100
        case .attendance: card.attendanceRatio
        case .fleet: card.availabilityRatio
        }
    }

    private func value(for card: StationScorecard, lens: PerformanceLens? = nil) -> String {
        switch lens ?? self.lens {
        case .money: Fmt.mxn(card.earningsMxn)
        case .punctuality: "\(Int(card.punctualityPct))%"
        case .attendance: "\(card.presentDrivers)/\(card.rosterSize)"
        case .fleet: "\(Int(card.availabilityRatio * 100))%"
        }
    }

    private func detail(for card: StationScorecard) -> String {
        switch lens {
        case .money: "\(Int(card.goalRatio * 100))% de \(Fmt.mxn(card.goalMxn))"
        case .punctuality: "Cuidado de unidad \(Int(card.carePct))%"
        case .attendance: "\(card.absentDrivers) ausentes · \(card.lateDrivers) con atraso"
        case .fleet: "\(card.inMaintenance) en taller · \(card.outOfService) fuera de servicio"
        }
    }

    private func tone(for card: StationScorecard, lens: PerformanceLens? = nil) -> Color {
        let lens = lens ?? self.lens
        let value = ratio(for: card, lens: lens)
        switch lens {
        case .money: return value >= 1 ? MgTone.good : (value >= RegionalRules.goalFloor ? MgTone.warn : MgTone.bad)
        case .punctuality, .attendance: return value >= 0.94 ? MgTone.good : (value >= 0.86 ? MgTone.warn : MgTone.bad)
        case .fleet: return value >= RegionalRules.availabilityFloor ? MgTone.good : MgTone.bad
        }
    }

    // MARK: - Programs

    private var bonusPanel: some View {
        let eligible = regional.scorecards.reduce(0) { $0 + $1.bonusEligible }
        let atRisk = regional.scorecards.reduce(0) { $0 + $1.bonusAtRisk }
        let schedule = NationalBonusBoard.current
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Bonos de la estación",
                subtitle: "Automáticos: los libera y los cancela el motor de metas",
                accent: MgTone.accent
            )

            HStack(spacing: 10) {
                StatTile(label: "Autorizados", value: "\(eligible)", hint: "4 de 4 semanas", tone: .volt)
                StatTile(label: "En riesgo", value: "\(atRisk)", hint: "Una semana fallida los cancela", tone: .amber)
                StatTile(label: "Nómina del mes", value: Fmt.mxn(regional.bonusPayrollMxn), hint: "Se libera solo", tone: .neutral)
            }

            MeterRow(
                label: "Proporción de la plantilla con bono vigente",
                value: "\(metrics.onShiftDrivers > 0 ? Int(Double(eligible) / Double(metrics.onShiftDrivers) * 100) : 0)%",
                ratio: metrics.onShiftDrivers > 0 ? Double(eligible) / Double(metrics.onShiftDrivers) : 0,
                tone: MgTone.good
            )

            NoticeBanner(
                symbol: "lock.fill",
                title: "No requieren tu firma",
                message: "Cumplir la meta los autoriza y fallar una semana los cancela, conductor por conductor y sin bandeja. Solo la administración nacional puede cambiar montos o reglas.",
                tone: .volt
            )

            Text("Vigente por la política nacional v\(schedule.version): puntualidad \(Fmt.mxn(schedule.punctualityMxn)), facturación \(Fmt.mxn(schedule.billingMxn)), cuidado de unidad \(Fmt.mxn(schedule.careMxn)) y calidad de servicio según la calificación de la plataforma.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .panel()
    }

    private var creditPanel: some View {
        let current = regional.scorecards.reduce(0) { $0 + $1.creditCurrent }
        let behind = regional.scorecards.reduce(0) { $0 + $1.creditBehind }
        let delivered = regional.scorecards.reduce(0) { $0 + $1.creditDelivered }
        let total = max(1, current + behind + delivered)
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Cartera de crédito",
                subtitle: "\(CreditProgram.vehicleModel) · \(CreditProgram.termMonths) meses vía nómina",
                accent: MgTone.accent
            )

            HStack(alignment: .top, spacing: 14) {
                MgRing(
                    ratio: Double(current + delivered) / Double(total),
                    headline: "\(Int(Double(current + delivered) / Double(total) * 100))%",
                    caption: "Al corriente",
                    tone: MgTone.premium,
                    size: 132
                )

                VStack(alignment: .leading, spacing: 10) {
                    DetailRow(label: "Contratos activos", value: "\(current)")
                    DetailRow(label: "Con atraso", value: "\(behind)")
                    DetailRow(label: "Unidades entregadas", value: "\(delivered)")
                    DetailRow(label: "Abono semanal", value: Fmt.mxn(CreditProgram.weeklyMxn))
                    DetailRow(label: "Entrega de unidad", value: "Mes \(CreditProgram.deliveryMonth)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if behind > 0 {
                NoticeBanner(
                    symbol: "creditcard.trianglebadge.exclamationmark",
                    title: "\(behind) contratos con atraso",
                    message: "El comportamiento crediticio define las condiciones del conductor y puede posponer la entrega de su unidad.",
                    tone: .amber
                )
            }
        }
        .padding(16)
        .panel()
    }
}
