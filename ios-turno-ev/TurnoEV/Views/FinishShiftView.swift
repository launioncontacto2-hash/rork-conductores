import SwiftUI

/// Shift closing: final odometer photo, delivery confirmation and automatic totals.
struct FinishShiftView: View {
    @Environment(FleetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var odometer: String = ""
    @State private var battery: String = ""
    @State private var photo: Data?
    @State private var confirmDelivery: Bool = false
    @State private var summary: ShiftSummary?
    @State private var errorMessage: String?
    @State private var isFinishing: Bool = false
    @State private var idempotencyKey = "ios-finish-\(UUID().uuidString.lowercased())"

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                if let shift = store.activeShift, let vehicle = store.activeVehicle {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 12) {
                                StatTile(
                                    label: "Odómetro inicial",
                                    value: Fmt.km(shift.startOdometerKm),
                                    symbol: "gauge.with.dots.needle.bottom.50percent"
                                )
                                StatTile(
                                    label: "Km estimados",
                                    value: Fmt.km(store.estimatedKmDriven(at: store.now)),
                                    hint: "GPS simulado",
                                    symbol: "point.topleft.down.to.point.bottomright.curvepath"
                                )
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                BigNumberField(
                                    title: "Kilometraje final",
                                    symbol: "gauge.with.dots.needle.100percent",
                                    placeholder: "\(suggestedOdometer(shift: shift))",
                                    text: $odometer
                                )
                                Button {
                                    odometer = "\(suggestedOdometer(shift: shift))"
                                } label: {
                                    Text("Usar estimado \(Fmt.km(suggestedOdometer(shift: shift)))")
                                        .font(.system(.caption, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Palette.surfaceRaised, in: .capsule)
                                        .overlay { Capsule().stroke(Palette.hairline, lineWidth: 1) }
                                }
                                .buttonStyle(.plain)
                            }

                            BigNumberField(
                                title: "Nivel de batería de entrega",
                                symbol: "bolt.batteryblock.fill",
                                placeholder: "28",
                                text: $battery
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                CapsLabel(text: "Fotografía final del odómetro")
                                PhotoSlotView(title: "Odómetro final", hint: "Lectura legible", data: photo) { data in
                                    photo = data
                                }
                            }

                            deliveryToggle(vehicle: vehicle)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.danger)
                            }

                            BigButton(
                                title: isFinishing ? "Cerrando…" : "Cerrar turno",
                                symbol: isFinishing ? "hourglass" : "checkmark.seal.fill",
                                isEnabled: !isFinishing
                            ) {
                                close(shift: shift)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                    }
                } else {
                    ContentUnavailableView(
                        "Sin turno activo",
                        systemImage: "checkmark.seal",
                        description: Text("No hay un turno por cerrar.")
                    )
                }
            }
            .navigationTitle("Finalización de turno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(item: $summary) { result in
                SummarySheet(summary: result, driverName: store.driver.name) {
                    summary = nil
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func suggestedOdometer(shift: ActiveShift) -> Int {
        shift.startOdometerKm + store.estimatedKmDriven(at: store.now)
    }

    private func deliveryToggle(vehicle: Vehicle) -> some View {
        Button {
            confirmDelivery.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: confirmDelivery ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(confirmDelivery ? Palette.volt : Palette.textMuted)
                Text("Confirmo la entrega de la unidad en \(vehicle.station) conectada al cargador.")
                    .font(.system(.footnote, weight: .semibold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background((confirmDelivery ? Palette.volt.opacity(0.1) : Palette.surfaceRaised.opacity(0.6)), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(confirmDelivery ? Palette.volt.opacity(0.5) : Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func close(shift: ActiveShift) {
        guard let odometerValue = Int(odometer), odometerValue >= shift.startOdometerKm else {
            errorMessage = "El kilometraje final debe ser mayor o igual a \(Fmt.km(shift.startOdometerKm))."
            return
        }
        guard photo != nil else {
            errorMessage = "Falta la fotografía final del odómetro."
            return
        }
        guard let batteryValue = Int(battery), batteryValue >= 0, batteryValue <= 100 else {
            errorMessage = "Captura un nivel de batería entre 0 y 100%."
            return
        }
        guard confirmDelivery else {
            errorMessage = "Confirma la entrega de la unidad."
            return
        }
        errorMessage = nil
        isFinishing = true
        Task {
            defer { isFinishing = false }
            do {
                summary = try await store.finishAvailableShift(
                    endOdometerKm: odometerValue,
                    endBatteryPct: batteryValue,
                    photo: photo,
                    idempotencyKey: idempotencyKey
                )
            } catch {
                // Nothing was written, so nothing is claimed. Prefer the concrete server
                // response; the legacy explanation remains for a blocked local workflow.
                let failure = error as? OperationalMutationError
                let legacyMessage = [failure?.errorDescription, failure?.failureReason]
                    .compactMap { $0 }
                    .joined(separator: " ")
                errorMessage = legacyMessage.isEmpty ? error.localizedDescription : legacyMessage
            }
        }
    }
}

/// End-of-shift messages, in the order defined by operations.
private struct SummarySheet: View {
    let summary: ShiftSummary
    let driverName: String
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "party.popper.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Palette.volt)
                    .frame(width: 60, height: 60)
                    .background(Palette.volt.opacity(0.14), in: .rect(cornerRadius: 20))

                Text("Turno finalizado")
                    .font(.system(.title2, weight: .black))

                Text("\(Fmt.firstName(driverName)), tu turno ha finalizado. ¡Bien hecho!, ahora, vuelve a la estación.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(label: "Kilómetros", value: Fmt.km(summary.kmDriven), tone: .volt)
                    StatTile(label: "Duración", value: Fmt.durationText(summary.durationMinutes), symbol: "timer")
                    StatTile(label: "Ingresos", value: Fmt.mxn(summary.earningsMxn))
                    StatTile(label: "Viajes", value: "\(summary.trips) / \(ShiftRules.tripsGoalPerDay)")
                }

                if summary.missingMxn > 0 {
                    NoticeBanner(
                        symbol: "exclamationmark.circle.fill",
                        title: "\(Fmt.firstName(driverName)), faltó \(Fmt.mxn(summary.missingMxn)) para llegar a la meta del día.",
                        tone: .amber
                    )
                }

                if summary.missingTrips > 0 {
                    NoticeBanner(
                        symbol: "flag.checkered",
                        title: "\(Fmt.firstName(driverName)), faltaron \(summary.missingTrips) viajes para la meta.",
                        message: "Recupéralos mañana.",
                        tone: .amber
                    )
                }

                if summary.lateMinutes > 0 {
                    NoticeBanner(
                        symbol: "timer",
                        title: "Atraso registrado: \(Fmt.lateText(summary.lateMinutes))",
                        message: "Se agregó a tu bitácora semanal.",
                        tone: .amber
                    )
                }

                BigButton(title: "Entendido", symbol: "checkmark") {
                    onDismiss()
                }
            }
            .padding(20)
        }
        .background { StationBackground() }
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
    }
}

extension ShiftSummary: Identifiable {
    nonisolated public var id: String {
        "\(kmDriven)-\(durationMinutes)-\(earningsMxn)-\(trips)"
    }
}

#Preview {
    FinishShiftView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
