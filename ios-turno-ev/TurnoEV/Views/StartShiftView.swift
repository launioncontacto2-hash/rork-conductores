import SwiftUI
import UIKit

/// Start of shift in three blocking steps: unit sticker against the assigned unit,
/// odometer scan with a 5 km tolerance and battery scan against the fleet minimum.
/// Any failed step stops the flow and offers to report it to the supervisor.
struct StartShiftView: View {
    @Environment(FleetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The three gates of the start flow, in order.
    private enum Step: Int, CaseIterable, Identifiable {
        case unit
        case odometer
        case battery

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .unit: "Cotejo de unidad"
            case .odometer: "Escaneo de kilometraje"
            case .battery: "Escaneo de batería"
            }
        }

        var shortTitle: String {
            switch self {
            case .unit: "Unidad"
            case .odometer: "Kilometraje"
            case .battery: "Batería"
            }
        }

        var symbol: String {
            switch self {
            case .unit: "qrcode.viewfinder"
            case .odometer: "gauge.with.dots.needle.bottom.50percent"
            case .battery: "bolt.batteryblock.fill"
            }
        }
    }

    @State private var step: Step = .unit
    @State private var scannedVehicle: Vehicle?
    @State private var odometerText: String = ""
    @State private var odometerPhoto: Data?
    @State private var batteryText: String = ""
    @State private var batteryPhoto: Data?
    @State private var issues: [AssignmentIssue] = []
    @State private var manualCode: String = ""
    @State private var isManualEntry: Bool = false
    @State private var scanMessage: String?
    @State private var supervisorNotified: Bool = false

    private var assignment: VehicleAssignment? { store.unitAssignment }
    private var assignedVehicle: Vehicle? { store.assignedVehicle }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                if assignment != nil, let assignedVehicle {
                    ScrollView {
                        VStack(spacing: 18) {
                            stepper

                            if supervisorNotified {
                                NoticeBanner(
                                    symbol: "checkmark.seal.fill",
                                    title: "Supervisor notificado",
                                    message: "Se envió el detalle del bloqueo a tu estación. Espera indicaciones.",
                                    tone: .volt
                                )
                            }

                            switch step {
                            case .unit:
                                unitStep(vehicle: assignedVehicle)
                            case .odometer:
                                odometerStep(vehicle: scannedVehicle ?? assignedVehicle)
                            case .battery:
                                batteryStep(vehicle: scannedVehicle ?? assignedVehicle)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 34)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    unassignedState
                }
            }
            .navigationTitle("Inicio de turno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    DemoClockButton()
                }
            }
            .alert("Inicio bloqueado", isPresented: .constant(!issues.isEmpty)) {
                Button("Notificar a supervisor", role: .destructive) {
                    supervisorNotified = store.notifySupervisor(
                        reason: issues.map(\.message).joined(separator: " · ")
                    )
                    issues = []
                }
                Button("Corregir", role: .cancel) { issues = [] }
            } message: {
                Text(issues.map(\.message).joined(separator: "\n\n"))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { store.reloadAssignment() }
    }

    // MARK: - Header

    private var stepper: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases) { item in
                let isDone = item.rawValue < step.rawValue
                let isCurrent = item == step

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isDone || isCurrent ? Palette.volt.opacity(isCurrent ? 0.22 : 1) : Palette.surfaceRaised)
                            .frame(width: 34, height: 34)
                        Image(systemName: isDone ? "checkmark" : item.symbol)
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(isDone ? Palette.canvas : isCurrent ? Palette.volt : Palette.textMuted)
                    }
                    .overlay {
                        Circle()
                            .stroke(isCurrent ? Palette.volt : .clear, lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                    }

                    Text(item.shortTitle)
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(isCurrent ? Palette.volt : Palette.textMuted)
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .panelFlat()
    }

    // MARK: - Step 1 · unit

    private func unitStep(vehicle: Vehicle) -> some View {
        VStack(spacing: 14) {
            ZStack {
                QRScannerView(onDetected: handleDetected)
                ScannerFrame()
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "viewfinder")
                            .foregroundStyle(Palette.volt)
                        Text("Centra el QR de \(vehicle.internalNumber)")
                            .font(.system(.caption, weight: .semibold))
                    }
                    .padding(10)
                    .background(.black.opacity(0.65), in: .capsule)
                    .padding(.bottom, 14)
                }
            }
            .frame(height: 320)
            .clipShape(.rect(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).stroke(Palette.hairline, lineWidth: 1) }

            if let scanMessage {
                NoticeBanner(symbol: "exclamationmark.circle.fill", title: scanMessage, tone: .danger)
            }

            if isManualEntry {
                VStack(spacing: 10) {
                    TextField(vehicle.qrCode, text: $manualCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.system(.title3, weight: .black))
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .panelFlat()

                    BigButton(
                        title: "Cotejar unidad",
                        symbol: "qrcode",
                        isEnabled: manualCode.trimmingCharacters(in: .whitespaces).count >= 3
                    ) {
                        handleDetected(code: manualCode)
                    }
                }
            } else {
                Button {
                    isManualEntry = true
                } label: {
                    Label("Capturar número interno", systemImage: "keyboard")
                        .font(.system(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .panelFlat()
                }
                .buttonStyle(.plain)
            }

            // Demo shortcut: reading any sticker of the station proves the cross-check.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.vehicles.filter { $0.stationId == store.driver.stationId }) { item in
                        Button {
                            handleDetected(code: item.qrCode)
                        } label: {
                            Text(item.qrCode)
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(item.id == vehicle.id ? Palette.volt : Palette.textMuted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Palette.surfaceRaised, in: .capsule)
                                .overlay {
                                    Capsule().stroke(
                                        item.id == vehicle.id ? Palette.volt.opacity(0.6) : Palette.hairline,
                                        lineWidth: 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, 2)

            Text("El sistema compara el QR leído contra la unidad que tu supervisor te asignó. Si no coinciden, el turno no inicia.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Step 2 · odometer

    private func odometerStep(vehicle: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ReadingHeader(
                title: "Fotografía y captura el odómetro",
                message: "Tolerancia de \(ShiftRules.odometerToleranceKm) km contra el registro de la estación."
            )

            HStack(spacing: 12) {
                StatTile(
                    label: "Registro de estación",
                    value: Fmt.km(vehicle.odometerKm),
                    symbol: "gauge.with.dots.needle.bottom.50percent"
                )
                StatTile(
                    label: "Rango aceptado",
                    value: "±\(ShiftRules.odometerToleranceKm) km",
                    hint: "\(Fmt.km(vehicle.odometerKm - ShiftRules.odometerToleranceKm)) — \(Fmt.km(vehicle.odometerKm + ShiftRules.odometerToleranceKm))",
                    tone: .info,
                    symbol: "arrow.left.and.right"
                )
            }

            PhotoSlotView(
                title: "Odómetro de inicio",
                hint: "Lectura legible",
                data: odometerPhoto
            ) { data in
                odometerPhoto = data
            }

            BigNumberField(
                title: "Kilometraje leído",
                symbol: "gauge.with.dots.needle.bottom.50percent",
                placeholder: "\(vehicle.odometerKm)",
                text: $odometerText
            )

            BigButton(
                title: "Validar kilometraje",
                symbol: "checkmark.circle.fill",
                isEnabled: odometerPhoto != nil && !odometerText.isEmpty
            ) {
                validateOdometer(vehicle: vehicle)
            }

            BigButton(title: "Volver al cotejo de unidad", symbol: "chevron.left", tone: .outline) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step = .unit }
            }
        }
    }

    // MARK: - Step 3 · battery

    private func batteryStep(vehicle: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ReadingHeader(
                title: "Fotografía y captura la batería",
                message: "Se requiere más de \(ShiftRules.minBatteryPct)% de carga para salir a operar."
            )

            HStack(spacing: 12) {
                StatTile(
                    label: "Carga registrada",
                    value: "\(vehicle.batteryPct)%",
                    symbol: "bolt.batteryblock.fill"
                )
                StatTile(
                    label: "Mínimo de salida",
                    value: "\(ShiftRules.minBatteryPct)%",
                    hint: "Regla de flotilla",
                    tone: .info,
                    symbol: "checkmark.shield.fill"
                )
            }

            PhotoSlotView(
                title: "Tablero de batería",
                hint: "Tablero encendido",
                data: batteryPhoto
            ) { data in
                batteryPhoto = data
            }

            BigNumberField(
                title: "Porcentaje leído",
                symbol: "bolt.fill",
                placeholder: "\(vehicle.batteryPct)",
                text: $batteryText
            )

            BigButton(
                title: "Iniciar turno",
                symbol: "bolt.car.fill",
                isEnabled: batteryPhoto != nil && !batteryText.isEmpty
            ) {
                start(vehicle: vehicle)
            }

            BigButton(title: "Volver al kilometraje", symbol: "chevron.left", tone: .outline) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step = .odometer }
            }
        }
    }

    // MARK: - Empty state

    private var unassignedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.badge.gearshape")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Palette.textMuted)
            Text("Sin unidad asignada")
                .font(.system(.title3, weight: .black))
            Text("Tu supervisor de estación es quien asigna la unidad con la que trabajas. En cuanto la registre, aparecerá aquí y podrás iniciar turno.")
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
            if store.canSimulateOperationalCoordination {
                BigButton(title: "Solicitar unidad a supervisión", symbol: "paperplane.fill", tone: .outline) {
                    supervisorNotified = store.notifySupervisor(
                        reason: "\(store.driver.name) solicita asignación de unidad para su turno \(store.driver.slot.label.lowercased())."
                    )
                    dismiss()
                }
            } else {
                // No station service receives this yet. A button that answers "enviado"
                // would be the second lie on a screen whose whole job is to say the truth
                // about a unit that does not exist.
                Text("La solicitud de unidad se registra en el sistema de tu estación. Aún no está disponible desde la aplicación.")
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
    }

    // MARK: - Actions

    private func handleDetected(code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Two different truths, and saying the wrong one sends the driver looking for a
        // sticker problem that does not exist. "No pertenece a la flotilla" is a claim
        // about the code; with no published assignment the problem is upstream of it.
        guard store.unitAssignment != nil else {
            scanMessage = "Todavía no tienes una unidad asignada. El cotejo se activa cuando tu estación la registre."
            return
        }
        guard let found = store.vehicles.first(where: {
            $0.qrCode.uppercased() == normalized || $0.internalNumber.uppercased() == normalized
        }) else {
            scanMessage = "El código \(normalized) no pertenece a la flotilla"
            return
        }

        let blocking = store.validateScannedUnit(vehicle: found)
        guard blocking.isEmpty else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            scanMessage = nil
            issues = blocking
            return
        }

        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        scanMessage = nil
        scannedVehicle = found
        batteryText = ""
        odometerText = ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = .odometer }
    }

    private func validateOdometer(vehicle: Vehicle) {
        guard let reading = Int(odometerText.trimmingCharacters(in: .whitespaces)), reading > 0 else {
            issues = [AssignmentIssue(code: .odometerMismatch, message: "Captura el kilometraje que muestra el tablero.")]
            return
        }
        if let issue = store.validateOdometerReading(vehicle: vehicle, reading: reading) {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            issues = [issue]
            return
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = .battery }
    }

    private func start(vehicle: Vehicle) {
        guard let battery = Int(batteryText.trimmingCharacters(in: .whitespaces)), battery > 0, battery <= 100 else {
            issues = [AssignmentIssue(code: .lowBattery, message: "Captura el porcentaje de batería del tablero.")]
            return
        }
        if let issue = store.validateBatteryReading(battery) {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            issues = [issue]
            return
        }

        let odometer = Int(odometerText.trimmingCharacters(in: .whitespaces)) ?? vehicle.odometerKm
        let blocking = store.validateScannedUnit(vehicle: vehicle)
        guard blocking.isEmpty else {
            issues = blocking
            return
        }

        do {
            try store.startShift(
                vehicle: vehicle,
                odometerKm: odometer,
                batteryPct: battery,
                odometerPhoto: odometerPhoto,
                batteryPhoto: batteryPhoto
            )
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            issues = [
                AssignmentIssue(
                    code: .notAssigned,
                    message: (error as? UnitAssignmentError)?.failureReason
                        ?? "No se pudo iniciar el turno con esta unidad."
                )
            ]
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Pieces

/// Small heading used by the reading steps.
private struct ReadingHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.headline, weight: .black))
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The unit the station tied to the driver, with the reason when it is a substitute.
struct AssignedUnitBadgeCard: View {
    let assignment: VehicleAssignment
    let vehicle: Vehicle
    var showsPhoto: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if showsPhoto {
                Color.black
                    .frame(height: 132)
                    .overlay {
                        Image(vehicle.photoAsset)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        LinearGradient(
                            colors: [.clear, Palette.surface.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 5) {
                            Image(systemName: assignment.kind.symbol)
                                .font(.system(size: 9, weight: .black))
                            Text(assignment.kind.label.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .tracking(0.8)
                        }
                        .foregroundStyle(assignment.isSubstitute ? Palette.canvas : Palette.volt)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            assignment.isSubstitute ? Palette.amber : Palette.volt.opacity(0.16),
                            in: .capsule
                        )
                        .padding(12)
                    }
                    .overlay(alignment: .bottom) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                CapsLabel(text: "Tu unidad")
                                Text(vehicle.internalNumber)
                                    .font(.system(size: 28, weight: .black))
                            }
                            Spacer()
                            BatteryPill(level: vehicle.batteryPct)
                        }
                        .padding(14)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(vehicle.model) · \(vehicle.plates)")
                        .font(.system(.caption, weight: .bold))
                    Spacer(minLength: 8)
                    Text(Fmt.km(vehicle.odometerKm))
                        .font(.system(.caption, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textMuted)
                }

                if assignment.isSubstitute, let titular = assignment.titularVehicleNumber {
                    Text("Sustituta de \(titular) mientras se libera.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                }

                if !assignment.note.isEmpty {
                    Text(assignment.note)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                }

                Text("Asignada por \(assignment.assignedBy) · \(Fmt.dateShort(assignment.assignedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .panel()
        .clipShape(.rect(cornerRadius: 26))
    }
}

#Preview {
    StartShiftView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
