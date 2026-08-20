import SwiftUI

/// Entrega y recepción: the five validations a supervisor signs before a unit leaves
/// the station or comes back into the fleet.
struct SupervisorHandoverView: View {
    let supervision: SupervisionStore
    let ticketId: String

    @Environment(\.dismiss) private var dismiss

    @State private var isScannerPresented: Bool = false
    @State private var scanFeedback: String?
    @State private var isRejecting: Bool = false
    @State private var rejectionReason: String = ""
    @State private var didApprove: Bool = false

    private var ticket: HandoverTicket? { supervision.ticket(id: ticketId) }

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()

                if let ticket {
                    ScrollView {
                        VStack(spacing: 14) {
                            summary(ticket)
                            readings(ticket)
                            evidence(ticket)
                            checklist(ticket)
                            observations(ticket)
                            decision(ticket)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    SupEmptyState(
                        symbol: "doc.badge.gearshape",
                        title: "Trámite no disponible",
                        message: "La entrega ya fue resuelta o pertenece a otro turno."
                    )
                    .padding(20)
                }
            }
            .navigationTitle(ticket?.kind.label ?? "Entrega")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(isPresented: $isScannerPresented) { scannerSheet }
        }
        .presentationContentInteraction(.scrolls)
    }

    // MARK: - Sections

    private func summary(_ ticket: HandoverTicket) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: ticket.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(ticket.kind == .delivery ? SupTone.accent : SupTone.cool)
                    .frame(width: 46, height: 46)
                    .background(
                        (ticket.kind == .delivery ? SupTone.accent : SupTone.cool).opacity(0.14),
                        in: .rect(cornerRadius: 15)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(ticket.vehicleNumber)
                        .font(.system(.title3, weight: .black))
                    Text(ticket.driverName)
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    StatePill(
                        text: ticket.status.label,
                        symbol: ticket.status == .approved ? "checkmark.seal.fill" : "clock.fill",
                        tone: ticket.status == .approved ? SupTone.good : (ticket.status == .rejected ? SupTone.bad : SupTone.warn),
                        compact: true
                    )
                    if ticket.isLiveSession {
                        StatePill(text: "En vivo", symbol: "antenna.radiowaves.left.and.right", tone: SupTone.good, compact: true)
                    }
                }
            }

            Divider().overlay(Palette.hairline)

            DetailRow(label: "Solicitud", value: Fmt.clock(ticket.createdAt))
            DetailRow(label: "Turno programado", value: Fmt.clock(ticket.scheduledStartAt))
            if ticket.lateMinutes > 0 {
                DetailRow(label: "Atraso registrado", value: Fmt.lateText(ticket.lateMinutes))
            }
            DetailRow(label: "Validaciones", value: "\(ticket.completedChecks) de \(ticket.requiredChecks.count)")
        }
        .padding(16)
        .panel()
    }

    private func readings(_ ticket: HandoverTicket) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Lecturas del trámite")

            HStack(spacing: 10) {
                StatTile(
                    label: "Odómetro inicial",
                    value: Fmt.km(ticket.startOdometerKm),
                    hint: "Registro: \(Fmt.km(ticket.expectedOdometerKm))",
                    tone: ticket.kind == .delivery && ticket.hasOdometerGap ? .danger : .neutral
                )
                StatTile(
                    label: "Odómetro final",
                    value: ticket.endOdometerKm.map { Fmt.km($0) } ?? "—",
                    hint: ticket.kind == .reception ? "Declarado por el conductor" : "Al cerrar turno",
                    tone: ticket.kind == .reception && ticket.hasOdometerGap ? .danger : .neutral
                )
            }

            HStack(spacing: 10) {
                StatTile(
                    label: "Km recorridos",
                    value: ticket.kmDriven.map { Fmt.km($0) } ?? "En ruta",
                    hint: "Diferencia de lecturas",
                    tone: .info
                )
                StatTile(
                    label: "Batería",
                    value: "\(ticket.batteryPct)%",
                    hint: ticket.kind == .delivery ? "Mínimo \(SupervisionRules.minBatteryPct)% para salir" : "Al entregar la unidad",
                    tone: ticket.kind == .delivery && ticket.batteryPct <= SupervisionRules.minBatteryPct ? .danger : .volt
                )
            }

            if ticket.hasOdometerGap {
                NoticeBanner(
                    symbol: "gauge.with.dots.needle.bottom.50percent",
                    title: "Diferencia de \(Fmt.km(ticket.odometerGapKm))",
                    message: "La lectura declarada no coincide con el registro de la estación. Verifica la fotografía del odómetro antes de firmar.",
                    tone: .danger
                )
            }

            if let code = ticket.qrCodeRead {
                NoticeBanner(
                    symbol: "qrcode",
                    title: "QR leído: \(code)",
                    message: "Coincide con la unidad del trámite.",
                    tone: .volt
                )
            } else {
                NoticeBanner(
                    symbol: "qrcode.viewfinder",
                    title: "Unidad sin escanear",
                    message: "Escanea el sticker del parabrisas para validar que la unidad es la correcta.",
                    tone: .amber
                )
            }
        }
        .padding(16)
        .panel()
    }

    private func evidence(_ ticket: HandoverTicket) -> some View {
        let live = supervision.liveEvidence(for: ticket)
        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Registro fotográfico",
                subtitle: "\(min(ticket.photosCaptured, InspectionSlot.driverSlots.count)) de \(InspectionSlot.driverSlots.count) lecturas del conductor"
            )

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    if live.isEmpty {
                        EvidenceThumb(
                            caption: ticket.kind == .delivery ? "Odómetro inicial" : "Odómetro final",
                            asset: ticket.odometerPhotoAsset ?? "electric_sedan_charging"
                        )
                        .frame(width: 150)
                        ForEach(InspectionSlot.driverSlots.dropFirst().prefix(max(0, ticket.photosCaptured - 1)), id: \.self) { slot in
                            EvidenceThumb(caption: slot.title, asset: "electric_hatchback_charging")
                                .frame(width: 120)
                        }
                    } else {
                        ForEach(Array(live.enumerated()), id: \.offset) { item in
                            EvidenceThumb(caption: item.element.slot.title, data: item.element.data)
                                .frame(width: 130)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            if ticket.photosCaptured < InspectionSlot.driverSlots.count {
                NoticeBanner(
                    symbol: "camera.badge.ellipsis",
                    title: "Faltan lecturas",
                    message: "El conductor solo fotografía odómetro y batería. Las fotos de carrocería las levanta supervisión cuando hay una incidencia.",
                    tone: .amber
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private func checklist(_ ticket: HandoverTicket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Validaciones", subtitle: "Toca cada punto para firmarlo")

            ForEach(ticket.requiredChecks) { check in
                let blocked = blockingReason(for: check, ticket: ticket)
                ChecklistRow(
                    check: check,
                    isDone: ticket.isChecked(check),
                    isBlocked: blocked != nil,
                    blockedReason: blocked
                ) {
                    if check == .qr, !ticket.isChecked(check) {
                        isScannerPresented = true
                        return
                    }
                    guard blocked == nil || ticket.isChecked(check) else { return }
                    supervision.setCheck(check, on: ticket.id, value: !ticket.isChecked(check))
                }
                .disabled(ticket.status != .pending)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    /// Rules that stop a signature: no evidence, low battery or unread sticker.
    private func blockingReason(for check: HandoverCheck, ticket: HandoverTicket) -> String? {
        switch check {
        case .photos:
            ticket.photosCaptured < InspectionSlot.driverSlots.count
                ? "Faltan las lecturas de odómetro y batería"
                : nil
        case .qr:
            ticket.qrCodeRead == nil ? "Escanea el código QR de la unidad" : nil
        case .shiftStart:
            ticket.batteryPct <= SupervisionRules.minBatteryPct
                ? "Batería en \(ticket.batteryPct)%, no puede iniciar turno"
                : nil
        case .vehicleReturn:
            ticket.endOdometerKm == nil ? "Falta la lectura final del odómetro" : nil
        case .assignment:
            nil
        }
    }

    private func observations(_ ticket: HandoverTicket) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Observaciones")
            Text(ticket.observations.isEmpty ? "Sin observaciones." : ticket.observations)
                .font(.subheadline)
            if let reason = ticket.rejectionReason {
                NoticeBanner(symbol: "xmark.octagon.fill", title: "Rechazada", message: reason, tone: .danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private func decision(_ ticket: HandoverTicket) -> some View {
        VStack(spacing: 10) {
            if ticket.status == .pending {
                BigButton(
                    title: ticket.kind == .delivery ? "Aprobar inicio de turno" : "Aprobar entrega del vehículo",
                    symbol: "checkmark.seal.fill",
                    isEnabled: ticket.isReadyToApprove
                ) {
                    guard supervision.approve(ticketId: ticket.id) else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    didApprove = true
                    dismiss()
                }

                if isRejecting {
                    VStack(spacing: 10) {
                        TextField("Motivo del rechazo", text: $rejectionReason, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(2...4)
                            .padding(14)
                            .panelFlat()
                        BigButton(
                            title: "Confirmar rechazo",
                            symbol: "xmark.octagon.fill",
                            tone: .danger,
                            isEnabled: rejectionReason.trimmingCharacters(in: .whitespaces).count > 5
                        ) {
                            supervision.reject(ticketId: ticket.id, reason: rejectionReason)
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            dismiss()
                        }
                    }
                } else {
                    Button("Rechazar trámite") { isRejecting = true }
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(SupTone.bad)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }

                if !ticket.isReadyToApprove {
                    Text("Firma las \(ticket.requiredChecks.count) validaciones para poder aprobar.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
            } else {
                NoticeBanner(
                    symbol: ticket.status == .approved ? "checkmark.seal.fill" : "xmark.octagon.fill",
                    title: "Trámite \(ticket.status.label.lowercased())",
                    message: ticket.resolvedAt.map { "Resuelto \(Fmt.clock($0))" },
                    tone: ticket.status == .approved ? .volt : .danger
                )
            }
        }
    }

    // MARK: - Scanner

    private var scannerSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                QRScannerView { code in
                    handleScan(code)
                }
                .ignoresSafeArea()
                ScannerFrame()

                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Text(scanFeedback ?? "Apunta al sticker del parabrisas de \(ticket?.vehicleNumber ?? "la unidad")")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Button("Registrar lectura manual") {
                            guard let ticket else { return }
                            handleScan(ticket.vehicleNumber)
                        }
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(SupTone.accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white.opacity(0.1), in: .rect(cornerRadius: 16))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Validar QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { isScannerPresented = false }
                }
            }
        }
    }

    private func handleScan(_ code: String) {
        guard let ticket else { return }
        if supervision.validateScan(code: code, on: ticket.id) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            scanFeedback = nil
            isScannerPresented = false
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            scanFeedback = "El código \(code) no corresponde a \(ticket.vehicleNumber)."
        }
    }
}
