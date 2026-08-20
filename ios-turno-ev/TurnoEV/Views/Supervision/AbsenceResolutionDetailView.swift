import SwiftUI
import UIKit

/// Detail behind the Resolver ausencias card. It shows the absences of the day and what
/// the engine did about each one — nothing else. It is not a second dashboard.
struct AbsenceResolutionDetailView: View {
    let resolution: AbsenceResolutionStore
    let supervision: SupervisionStore

    @Environment(\.dismiss) private var dismiss
    @State private var acknowledging: AbsenceResolutionCase?

    private var cases: [AbsenceResolutionCase] { resolution.todayCases }

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        reserveStrip

                        if cases.isEmpty {
                            SupEmptyState(
                                symbol: "checkmark.seal.fill",
                                title: "Plantilla completa",
                                message: "Ningún conductor de tu turno se pasó de la tolerancia. No hay nada que resolver."
                            )
                        } else {
                            ForEach(cases) { record in
                                CaseCard(
                                    record: record,
                                    now: supervision.now,
                                    policy: resolution.policy,
                                    onAcknowledge: { acknowledging = record }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Resolver ausencias")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(item: $acknowledging) { record in
                EscalationSheet(record: record) { note in
                    resolution.acknowledgeEscalation(caseId: record.id, note: note)
                }
            }
        }
        .presentationContentInteraction(.scrolls)
    }

    /// The reserve, read straight from the fleet board.
    private var reserveStrip: some View {
        let status = resolution.reserveStatus
        return HStack(spacing: 10) {
            Image(systemName: "car.side.fill")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(SupTone.cool)
                .frame(width: 32, height: 32)
                .background(SupTone.cool.opacity(0.13), in: .rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 1) {
                Text("Reservas disponibles: \(status.label)")
                    .font(.system(.footnote, weight: .bold))
                Text(reserveDetail(status))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func reserveDetail(_ status: ReserveStatus) -> String {
        guard status.approved > 0 else {
            return "Sin unidades aprobadas como reserva en esta estación."
        }
        var parts = ["\(status.inUse) en uso", "\(status.inMaintenance) fuera"]
        if status.policy.minimumProtected > 0 {
            parts.append("\(status.policy.minimumProtected) protegida(s)")
        }
        parts.append("máximo \(status.policy.maxInExtraordinaryUse) en extraordinaria")
        return parts.joined(separator: " · ")
    }
}

// MARK: - One absence

private struct CaseCard: View {
    let record: AbsenceResolutionCase
    let now: Date
    let policy: AbsencePolicy
    let onAcknowledge: () -> Void

    private var tint: Color {
        switch record.status {
        case .resolved, .partiallyResolved: SupTone.good
        case .escalated: SupTone.warn
        case .detected, .resolving: SupTone.bad
        case .closed: Palette.textMuted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: record.status.symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.13), in: .rect(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 1) {
                    Text(record.absentDriverName)
                        .font(.system(.subheadline, weight: .black))
                        .lineLimit(1)
                    Text("Ausente · \(Fmt.clock(record.scheduledStart))–\(Fmt.clock(record.scheduledEnd))")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
                StatePill(
                    text: record.status.label,
                    symbol: record.status.symbol,
                    tone: tint,
                    compact: true
                )
            }

            ForEach(record.opportunities) { opportunity in
                OpportunityRow(opportunity: opportunity, now: now, policy: policy)
            }

            if record.needsSupervisor {
                Button {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    onAcknowledge()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Revisar")
                            .font(.system(.footnote, weight: .black))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(SupTone.warn)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(SupTone.warn.opacity(0.12), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14).stroke(SupTone.warn.opacity(0.4), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }

            metricsLine
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    /// How the automatic engine performed on this case.
    private var metricsLine: some View {
        var parts: [String] = []
        if let minutes = record.metrics.resolutionMinutes {
            parts.append("resuelta en \(minutes) min")
        }
        parts.append("\(record.metrics.candidatesContacted) contactados")
        if record.metrics.rejections > 0 { parts.append("\(record.metrics.rejections) rechazos") }
        if record.metrics.reassignments > 0 { parts.append("\(record.metrics.reassignments) reasignaciones") }

        return Text(parts.joined(separator: " · "))
            .font(.system(size: 9))
            .foregroundStyle(Palette.textMuted)
            .lineLimit(2)
    }
}

// MARK: - One opportunity

private struct OpportunityRow: View {
    let opportunity: CoverageOpportunity
    let now: Date
    let policy: AbsencePolicy

    private var tint: Color {
        switch opportunity.status {
        case .assigned, .working, .completed: SupTone.good
        case .escalated: SupTone.warn
        case .closed: Palette.textMuted
        default: SupTone.cool
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: opportunity.kind.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(opportunity.kind == .extraordinary ? SupTone.cool : SupTone.accent)
                Text(opportunity.kind.label)
                    .font(.system(size: 11, weight: .black))
                Spacer(minLength: 0)
                Text(opportunity.vehicleNumber)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textMuted)
            }

            HStack(spacing: 8) {
                Image(systemName: opportunity.status.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            Text(windowText)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .lineLimit(2)

            if let reason = opportunity.escalationReason {
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(SupTone.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat(cornerRadius: 14)
    }

    private var statusText: String {
        switch opportunity.status {
        case .assigned, .working, .completed:
            let name = opportunity.assignedDriverName ?? "Sustituto"
            let eta = opportunity.assignedEta.map { " · ETA \(Fmt.clock($0))" } ?? ""
            return "\(name)\(eta)"
        case .held:
            return "Reservada mientras confirma · \(policy.confirmationWindowMinutes) min"
        default:
            return opportunity.status.label
        }
    }

    private var windowText: String {
        if opportunity.isFlexible, opportunity.assignedEta == nil {
            return "Horario flexible · unidad de reserva sin conductor permanente"
        }
        let minutes = opportunity.plannedMinutes
        let hours = Double(minutes) / 60
        let window = "\(opportunity.windowLabel) · \(String(format: "%.1f", hours)) h disponibles"

        if opportunity.isPaid {
            let effective = opportunity.liveMinutes(now: now)
            let rate = policy.ratePerMinuteMxn(shiftMinutes: max(1, opportunity.plannedMinutes))
            let pay = Int((Double(effective) * rate).rounded())
            return "\(window) · \(effective) min efectivos · \(Fmt.mxn(pay))"
        }
        return window
    }
}

// MARK: - Escalation

/// The only moment this module asks the supervisor for something.
private struct EscalationSheet: View {
    let record: AbsenceResolutionCase
    let onAcknowledge: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()

                VStack(alignment: .leading, spacing: 14) {
                    NoticeBanner(
                        symbol: "exclamationmark.triangle.fill",
                        title: "El motor no pudo resolverlo",
                        message: reason,
                        tone: .amber
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        CapsLabel(text: "Qué hiciste")
                        TextField("Cómo se resolvió fuera del sistema", text: $note, axis: .vertical)
                            .font(.system(.footnote, weight: .semibold))
                            .lineLimit(2...5)
                            .padding(12)
                            .panelFlat()
                    }

                    BigButton(title: "Marcar como atendida", symbol: "checkmark.seal.fill") {
                        onAcknowledge(note)
                        dismiss()
                    }

                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .navigationTitle(record.absentDriverName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(380)])
    }

    private var reason: String {
        record.opportunities.compactMap(\.escalationReason).first
            ?? "No fue posible construir una asignación válida con las reglas configuradas."
    }
}
