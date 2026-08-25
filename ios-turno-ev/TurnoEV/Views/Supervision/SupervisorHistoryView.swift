import SwiftUI

/// Historial: every handover already signed, with the readings that closed it.
struct SupervisorHistoryView: View {
    let supervision: SupervisionStore
    let header: SupervisorHeader
    let onOpenTicket: (String) -> Void

    private var resolved: [HandoverTicket] { supervision.resolvedTickets }

    var body: some View {
        ZStack {
            SupervisionBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    summary
                    log
                    closedIncidents
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var summary: some View {
        let approved = resolved.filter { $0.status == .approved }
        let rejected = resolved.filter { $0.status == .rejected }
        let km = approved.compactMap(\.kmDriven).reduce(0, +)
        return VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Bitácora del turno")
            HStack(spacing: 10) {
                StatTile(label: "Aprobadas", value: "\(approved.count)", hint: "Entregas y recepciones", tone: .volt)
                StatTile(label: "Rechazadas", value: "\(rejected.count)", hint: "Con motivo registrado", tone: rejected.isEmpty ? .neutral : .danger)
            }
            HStack(spacing: 10) {
                StatTile(label: "Km recibidos", value: Fmt.km(km), hint: "Suma de recepciones firmadas", tone: .info)
                StatTile(
                    label: "Incidencias cerradas",
                    value: "\(supervision.allIncidents.filter { $0.status == .closed }.count)",
                    hint: "Del periodo",
                    tone: .volt
                )
            }
        }
        .padding(16)
        .panel()
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Trámites firmados", subtitle: "Toca uno para ver su expediente")

            if resolved.isEmpty {
                SupEmptyState(
                    symbol: "clock.arrow.circlepath",
                    title: "Sin trámites firmados",
                    message: "Cuando apruebes o rechaces una entrega quedará registrada aquí con sus lecturas y evidencias."
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(resolved) { ticket in
                        Button {
                            onOpenTicket(ticket.id)
                        } label: {
                            HistoryRow(ticket: ticket)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var closedIncidents: some View {
        let closed = supervision.allIncidents.filter { $0.status == .closed }
        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Incidencias cerradas", subtitle: "Historial de estación")
            if closed.isEmpty {
                SupEmptyState(
                    symbol: "checkmark.shield.fill",
                    title: "Sin incidencias cerradas",
                    message: "Las incidencias resueltas quedarán archivadas en esta sección."
                )
            } else {
                ForEach(closed) { incident in
                    IncidentRow(incident: incident, onStatus: nil)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let ticket: HandoverTicket

    private var tone: Color { ticket.status == .approved ? SupTone.good : SupTone.bad }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: ticket.status == .approved ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(tone)
                    .frame(width: 30, height: 30)
                    .background(tone.opacity(0.14), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ticket.vehicleNumber) · \(ticket.kind.shortLabel)")
                        .font(.system(.subheadline, weight: .black))
                    Text(ticket.driverName)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(Fmt.clock(ticket.resolvedAt ?? ticket.createdAt))
                    .font(.system(.caption, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textMuted)
            }

            HStack(spacing: 8) {
                if let km = ticket.kmDriven {
                    InfoChip(symbol: "road.lanes", text: Fmt.km(km), tone: SupTone.cool)
                }
                InfoChip(symbol: "battery.75percent", text: "\(ticket.batteryPct)%", tone: Palette.textMuted)
                InfoChip(symbol: "camera.fill", text: "\(ticket.photosCaptured)/6", tone: Palette.textMuted)
                if ticket.hasOdometerGap {
                    InfoChip(symbol: "exclamationmark.triangle.fill", text: Fmt.km(ticket.odometerGapKm), tone: SupTone.bad)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(13)
        .panelFlat()
    }
}
