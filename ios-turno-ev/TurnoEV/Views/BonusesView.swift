import SwiftUI

/// Monthly bonuses: paid at month end, evaluated week by week, plus the
/// recovery program calendar for the weeks the driver already lost.
struct BonusesView: View {
    @Environment(FleetStore.self) private var store
    @Environment(CoverageStore.self) private var coverage

    @State private var alert: BonusAlert?
    @State private var expanded: Set<String> = []

    /// Guard bonuses come from cobertura de turnos and follow one rule only: the turn has
    /// to have been worked. Accepting a guard never pays.
    @ViewBuilder
    private var guardBonusSection: some View {
        let profile = coverage.profile(for: store.driver)
        let completed = coverage.completedGuards(driverId: profile.id)
        let pending = coverage.activeGuards(driverId: profile.id).filter { $0.bonusMode != .none }

        if !completed.isEmpty || !pending.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    CapsLabel(text: "Bonos por guardia")
                    Spacer(minLength: 6)
                    Text(Fmt.mxn(coverage.earnedGuardBonusMxn(driverId: profile.id)))
                        .font(.system(.title3, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(Palette.volt)
                }

                ForEach(completed) { vacancy in
                    HStack(spacing: 10) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.volt)
                            .frame(width: 28, height: 28)
                            .background(Palette.volt.opacity(0.12), in: .rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("BONO POR GUARDIA")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1)
                                .foregroundStyle(Palette.textMuted)
                            Text(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot))
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("+\(Fmt.mxn(vacancy.payableBonusMxn))")
                            .font(.system(.subheadline, weight: .black))
                            .monospacedDigit()
                            .foregroundStyle(Palette.volt)
                    }
                    .padding(11)
                    .panelFlat()
                }

                ForEach(pending) { vacancy in
                    HStack(spacing: 10) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.neutral)
                            .frame(width: 28, height: 28)
                            .background(Palette.neutral.opacity(0.12), in: .rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("POR COMPLETAR")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1)
                                .foregroundStyle(Palette.textMuted)
                            Text(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot))
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(Fmt.mxn(vacancy.bonusMxn))
                            .font(.system(.subheadline, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.neutral)
                    }
                    .padding(11)
                    .panelFlat()
                }

                Text("El bono se suma a tu liquidación cuando el turno queda completado. Tomarlo no lo genera.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(16)
            .panel()
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    let now = store.now
                    let evaluations = store.bonusEvaluations(reference: now)
                    let lost = evaluations.filter(\.isLost)

                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(evaluations) { evaluation in
                                bonusCard(evaluation: evaluation, now: now)
                            }

                            guardBonusSection

                            RecoveryProgramSection(suggestedBonus: lost.first?.kind ?? .punctuality)

                            supervisorLog
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Bonos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SessionMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    DemoClockButton()
                }
            }
            .task {
                // Weekly cut-off popup: announced once per bonus and week.
                alert = store.raiseBonusAlert(reference: store.now)
            }
            .sheet(item: $alert) { pending in
                BonusAlertSheet(alert: pending) {
                    alert = nil
                }
            }
        }
    }

    private func color(for status: BonusWeekStatus) -> Color {
        switch status {
        case .achieved: Palette.volt
        case .lost: Palette.danger
        case .inProgress: Palette.info
        case .upcoming: Palette.hairline
        }
    }

    // MARK: - Bonus card

    private func bonusCard(evaluation: BonusEvaluation, now: Date) -> some View {
        let kind = evaluation.kind
        let isOpen = expanded.contains(kind.rawValue)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(evaluation.isLost ? Palette.danger : Palette.volt)
                    .frame(width: 42, height: 42)
                    .background((evaluation.isLost ? Palette.danger : Palette.volt).opacity(0.12), in: .rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(.subheadline, weight: .black))
                    Text(evaluation.statusText)
                        .font(.caption2)
                        .foregroundStyle(evaluation.isLost ? Palette.danger : Palette.textMuted)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(kind.isExternal ? "Uber" : Fmt.mxn(evaluation.monthlyMxn))
                        .font(.system(.subheadline, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(evaluation.isLost ? Palette.textMuted : Palette.volt)
                        .strikethrough(evaluation.isLost, color: Palette.danger)
                    CapsLabel(text: "Mensual")
                }
            }

            decisionStrip(evaluation.decision)

            HStack(spacing: 8) {
                ForEach(evaluation.weeks) { result in
                    weekChip(result: result)
                }
            }

            ForEach(evaluation.weeks) { result in
                if result.status != .upcoming {
                    HStack(spacing: 8) {
                        Text("S\(result.week.index)")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(color(for: result.status))
                            .frame(width: 20, alignment: .leading)
                        Text(result.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textMuted)
                        Spacer(minLength: 0)
                        Text(result.week.rangeLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted.opacity(0.7))
                    }
                }
            }

            Button {
                withAnimation(.smooth(duration: 0.25)) {
                    if isOpen { expanded.remove(kind.rawValue) } else { expanded.insert(kind.rawValue) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOpen ? "chevron.up" : "info.circle")
                        .font(.system(size: 11, weight: .bold))
                    Text(isOpen ? "Ocultar reglas" : "Cómo se gana y cómo se pierde")
                        .font(.system(size: 11, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.info)
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    ruleRow(symbol: "checkmark.circle.fill", tint: Palette.volt, text: kind.howToWin)
                    ruleRow(symbol: "xmark.circle.fill", tint: Palette.danger, text: kind.howToLose)
                    if kind == .service {
                        ruleRow(
                            symbol: "antenna.radiowaves.left.and.right",
                            tint: Palette.info,
                            text: "En pruebas la métrica es positiva: \(Fmt.rating(BonusRules.mockQualityScore)) estrellas."
                        )
                    }
                }
                .padding(12)
                .panelFlat()
            }
        }
        .padding(18)
        .panel()
    }

    /// The verdict of the engine, spelled out so no one looks for a signature.
    private func decisionStrip(_ decision: BonusDecision) -> some View {
        let tint: Color = switch decision {
        case .authorized: Palette.volt
        case .cancelled: Palette.danger
        case .running: Palette.info
        }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: decision.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(decision.label.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(1)
                    .foregroundStyle(tint)
                Text(decision.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 14))
    }

    private func weekChip(result: BonusWeekResult) -> some View {
        let tint = color(for: result.status)
        return VStack(spacing: 5) {
            Image(systemName: result.status.symbol)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(result.status == .upcoming ? Palette.textMuted : tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(result.status == .upcoming ? 0.25 : 0.16), in: .circle)
                .overlay { Circle().stroke(tint.opacity(0.5), lineWidth: 1) }
            Text(result.week.shortLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func ruleRow(symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Supervisor log

    @ViewBuilder
    private var supervisorLog: some View {
        if !store.supervisorReports.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Reportes del supervisor", systemImage: "person.badge.shield.checkmark")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)

                Text("Un reporte cancela el bono de limpieza en automático. El supervisor puede levantarlo, pero no puede autorizar ni devolver un bono.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(store.supervisorReports) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(report.kind.label)
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(Palette.danger)
                            Spacer()
                            Text(Fmt.dateShort(report.createdAt).capitalized)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                        }
                        Text(report.note)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textMuted)
                        Text(report.vehicleInternalNumber)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.textMuted.opacity(0.8))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelFlat()
                }
            }
            .padding(18)
            .panel()
        }
    }
}

/// Weekly cut-off popup with the exact operations copy.
private struct BonusAlertSheet: View {
    let alert: BonusAlert
    let onSchedule: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(Palette.danger)
                .frame(width: 62, height: 62)
                .background(Palette.danger.opacity(0.14), in: .rect(cornerRadius: 20))

            Text(alert.message)
                .font(.system(.title3, weight: .black))
                .multilineTextAlignment(.center)

            Text("Corte de la semana \(alert.weekIndex). El bono de \(alert.kind.shortName) se recupera reservando un día en tu turno opuesto.")
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)

            BigButton(title: "Ir al programa de recuperación", symbol: "calendar.badge.plus") {
                onSchedule()
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .background { StationBackground() }
        .presentationDetents([.medium])
    }
}

#Preview {
    BonusesView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
