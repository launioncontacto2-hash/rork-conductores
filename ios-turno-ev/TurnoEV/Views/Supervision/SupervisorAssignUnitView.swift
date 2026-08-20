import SwiftUI
import UIKit

/// The supervisor is the only role that ties a unit to a driver. Recruitment hands the
/// person over; here the station decides which unit that person drives, swaps it at will
/// and hands a substitute while the titular one is released.
struct SupervisorAssignUnitView: View {
    let supervision: SupervisionStore
    let driverId: String
    let driverName: String
    /// Employee number, block or origin of the person receiving the unit.
    let subtitle: String

    @Environment(\.dismiss) private var dismiss

    @State private var kind: AssignedUnitKind = .titular
    @State private var selectedVehicleId: String?
    @State private var note: String = ""
    @State private var isRemoving: Bool = false

    private var current: VehicleAssignment? { supervision.assignment(driverId: driverId) }
    private var options: [StationVehicle] { supervision.assignableVehicles(for: driverId) }
    private var selected: StationVehicle? { options.first { $0.id == selectedVehicleId } }

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        personCard
                        currentCard
                        kindPicker
                        unitList
                        noteField
                        actions
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Asignación de unidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .alert("Retirar unidad", isPresented: $isRemoving) {
                Button("Retirar", role: .destructive) {
                    supervision.removeAssignment(driverId: driverId)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("\(Fmt.firstName(driverName)) se quedará sin unidad y no podrá iniciar turno hasta que le asignes otra.")
            }
        }
        .presentationContentInteraction(.scrolls)
        .onAppear {
            selectedVehicleId = current?.vehicleId ?? options.first?.id
            kind = current?.kind ?? .titular
        }
    }

    // MARK: - Sections

    private var personCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.text.rectangle.fill")
                .font(.title3)
                .foregroundStyle(SupTone.accent)
                .frame(width: 44, height: 44)
                .background(SupTone.accent.opacity(0.14), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(driverName)
                    .font(.system(.subheadline, weight: .black))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .panel(cornerRadius: 22)
    }

    @ViewBuilder
    private var currentCard: some View {
        if let current {
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: "Asignación vigente")
                HStack(spacing: 10) {
                    StatePill(
                        text: current.kind.label,
                        symbol: current.kind.symbol,
                        tone: current.isSubstitute ? SupTone.warn : SupTone.good
                    )
                    Spacer(minLength: 0)
                    Text(current.vehicleNumber)
                        .font(.system(.subheadline, weight: .black))
                }
                if current.isSubstitute, let titular = current.titularVehicleNumber {
                    Text("Sustituye a \(titular) mientras se libera.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SupTone.warn)
                }
                Text("Asignada por \(current.assignedBy) · \(Fmt.dateShort(current.assignedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                if !current.note.isEmpty {
                    Text(current.note)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .panel()
        } else {
            SupEmptyState(
                symbol: "car.badge.gearshape",
                title: "Sin unidad asignada",
                message: "Este conductor no puede iniciar turno hasta que le asignes una unidad de la estación."
            )
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Tipo de asignación")
            Picker("Tipo", selection: $kind) {
                Text("Fija").tag(AssignedUnitKind.titular)
                Text("Sustituta").tag(AssignedUnitKind.substitute)
            }
            .pickerStyle(.segmented)
            Text(
                kind == .titular
                    ? "La unidad queda ligada al conductor hasta que la cambies."
                    : "Temporal: se guarda la unidad titular para regresarlo en cuanto se libere."
            )
            .font(.system(size: 11))
            .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private var unitList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CapsLabel(text: "Unidades disponibles")
                Spacer()
                Text("\(options.count) libres")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }

            if options.isEmpty {
                Text("Todas las unidades de la estación están ocupadas, en taller o fuera de servicio.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(options) { vehicle in
                    unitRow(vehicle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private func unitRow(_ vehicle: StationVehicle) -> some View {
        let isSelected = vehicle.id == selectedVehicleId

        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedVehicleId = vehicle.id
            }
        } label: {
            HStack(spacing: 12) {
                Color.black
                    .frame(width: 56, height: 44)
                    .overlay {
                        Image(vehicle.photoAsset)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .opacity(0.85)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(vehicle.internalNumber)
                        .font(.system(.subheadline, weight: .black))
                    Text("\(vehicle.plates) · bahía \(vehicle.bay)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }

                Spacer(minLength: 0)

                BatteryPill(level: vehicle.batteryPct)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(isSelected ? SupTone.accent : Palette.textMuted)
            }
            .padding(12)
            .background(
                isSelected ? SupTone.accent.opacity(0.12) : Palette.surfaceRaised.opacity(0.55),
                in: .rect(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? SupTone.accent.opacity(0.5) : Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var noteField: some View {
        TextField(
            kind == .substitute ? "Motivo del cambio (taller, servicio, siniestro)" : "Nota de la asignación",
            text: $note,
            axis: .vertical
        )
        .font(.subheadline)
        .lineLimit(2...4)
        .padding(14)
        .panelFlat()
    }

    private var actions: some View {
        VStack(spacing: 10) {
            BigButton(
                title: kind == .substitute ? "Asignar unidad sustituta" : "Asignar unidad fija",
                symbol: kind.symbol,
                isEnabled: selected != nil
            ) {
                guard let selected else { return }
                supervision.assignUnit(
                    driverId: driverId,
                    driverName: driverName,
                    vehicleId: selected.id,
                    kind: kind,
                    note: note
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }

            if current != nil {
                BigButton(title: "Retirar asignación", symbol: "xmark.circle.fill", tone: .danger) {
                    isRemoving = true
                }
            }

            Text("El conductor solo puede iniciar turno con la unidad que aparece aquí: el cotejo del QR se hace contra esta asignación.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
    }
}
