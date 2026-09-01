import Observation
import SwiftUI

/// Narrow 15D workspace for a supervisor authenticated by Supabase.
///
/// It intentionally does not reuse `SupervisionStore`: that store is the rich local
/// simulation used by demo accounts. This screen has one authority and one purpose — read
/// the station catalogue and open shifts through RLS, and call the assignment RPC.
@MainActor
@Observable
private final class BackendAssignmentStore {
    let principal: SessionPrincipal

    var drivers: [SupabaseAssignmentService.DriverRow] = []
    var vehicles: [SupabaseAssignmentService.VehicleRow] = []
    var assignments: [SupabaseAssignmentService.AssignmentRow] = []
    var activeShifts: [SupabaseShiftService.ShiftRow] = []
    var selectedDriverId: UUID?
    var selectedVehicleId: UUID?
    var kind: AssignedUnitKind = .titular
    var note: String = ""
    var isLoading = false
    var isAssigning = false
    var errorMessage: String?
    var successMessage: String?

    init(principal: SessionPrincipal) {
        self.principal = principal
    }

    var selectedDriver: SupabaseAssignmentService.DriverRow? {
        drivers.first { $0.id == selectedDriverId }
    }

    var selectedVehicle: SupabaseAssignmentService.VehicleRow? {
        vehicles.first { $0.id == selectedVehicleId }
    }

    var currentAssignment: SupabaseAssignmentService.AssignmentRow? {
        guard let selectedDriverId else { return nil }
        return assignments.first { $0.driver_profile_id == selectedDriverId }
    }

    var currentVehicle: SupabaseAssignmentService.VehicleRow? {
        guard let currentAssignment else { return nil }
        return vehicles.first { $0.id == currentAssignment.vehicle_id }
    }

    var availableVehicles: [SupabaseAssignmentService.VehicleRow] {
        vehicles.filter { $0.status == "available" }
    }

    var canAssign: Bool {
        guard selectedDriver != nil, selectedVehicle != nil, !isAssigning else { return false }
        return kind == .titular || currentAssignment != nil
    }

    func driverLabel(for shift: SupabaseShiftService.ShiftRow) -> String {
        drivers.first { $0.id == shift.driver_profile_id }?.employee_number
            ?? shift.driver_profile_id.uuidString
    }

    func vehicleLabel(for shift: SupabaseShiftService.ShiftRow) -> String {
        vehicles.first { $0.id == shift.vehicle_id }?.internal_number
            ?? shift.vehicle_id.uuidString
    }

    func load() async {
        guard let stationId = principal.stationId else {
            errorMessage = "La sesión del supervisor no contiene estación."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let snapshotRequest = SupabaseAssignmentService.loadSupervisorSnapshot(
                stationId: stationId
            )
            async let shiftsRequest = SupabaseShiftService.loadSupervisorOpenShifts(
                stationId: stationId
            )
            let (snapshot, shifts) = try await (snapshotRequest, shiftsRequest)
            drivers = snapshot.drivers
            vehicles = snapshot.vehicles
            assignments = snapshot.assignments
            activeShifts = shifts

            if selectedDriverId == nil || !drivers.contains(where: { $0.id == selectedDriverId }) {
                selectedDriverId = drivers.first?.id
            }
            if selectedVehicleId == nil || !availableVehicles.contains(where: { $0.id == selectedVehicleId }) {
                selectedVehicleId = availableVehicles.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assign() async {
        guard let driver = selectedDriver, let vehicle = selectedVehicle else { return }

        let titularId: String?
        if kind == .substitute {
            guard let currentAssignment else {
                errorMessage = "Primero debe existir una unidad titular vigente."
                return
            }
            titularId = (currentAssignment.titular_vehicle_id ?? currentAssignment.vehicle_id).uuidString
        } else {
            titularId = nil
        }

        isAssigning = true
        errorMessage = nil
        successMessage = nil
        defer { isAssigning = false }

        do {
            try await SupabaseAssignmentService.assign(
                driverId: driver.id.uuidString,
                vehicleId: vehicle.id.uuidString,
                kind: kind,
                titularVehicleId: titularId,
                note: note
            )
            successMessage = "\(vehicle.internal_number) quedó asignada a \(driver.employee_number)."
            note = ""
            selectedVehicleId = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BackendSupervisorAssignmentView: View {
    @Environment(FleetStore.self) private var fleet
    @State private var model: BackendAssignmentStore

    init(principal: SessionPrincipal) {
        _model = State(initialValue: BackendAssignmentStore(principal: principal))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identityCard
                    statusCard
                    activeShiftsCard
                    driverPicker
                    currentCard
                    kindPicker
                    vehiclePicker
                    noteField
                    assignButton
                }
                .padding(18)
            }
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle("Asignar unidad")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar sesión") { fleet.signOut() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    DemoClockButton()
                    Button {
                        Task { await model.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                    .accessibilityLabel("Actualizar datos")
                }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
            .onChange(of: model.selectedDriverId) { _, _ in
                model.kind = .titular
                model.selectedVehicleId = model.availableVehicles.first?.id
            }
        }
    }

    private var activeShiftsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TURNOS ACTIVOS")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Text("\(model.activeShifts.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(model.activeShifts.isEmpty ? Palette.textMuted : Palette.volt)
            }

            if model.activeShifts.isEmpty {
                Text("Ningún conductor tiene un turno abierto.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(model.activeShifts) { shift in
                    HStack(spacing: 12) {
                        Image(systemName: "car.side.fill")
                            .foregroundStyle(Palette.volt)
                            .frame(width: 34, height: 34)
                            .background(Palette.volt.opacity(0.12), in: .circle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.driverLabel(for: shift))
                                .font(.subheadline.weight(.bold))
                            Text("\(model.vehicleLabel(for: shift)) · inició \(Fmt.clock(shift.started_at))")
                                .font(.caption)
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer(minLength: 6)
                        Text("ABIERTO")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Palette.volt)
                    }

                    if shift.id != model.activeShifts.last?.id {
                        Divider().overlay(Palette.hairline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUPERVISIÓN TEST")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.volt)
            Text(model.principal.name)
                .font(.title3.weight(.bold))
            Text("\(model.principal.stationName ?? "Estación") · \(model.principal.stationCode ?? "—")")
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    @ViewBuilder
    private var statusCard: some View {
        if model.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Leyendo conductores, vehículos y asignaciones…")
            }
            .font(.footnote)
            .foregroundStyle(Palette.textMuted)
        } else if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        } else if let success = model.successMessage {
            Label(success, systemImage: "checkmark.seal.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.green)
        }
    }

    private var driverPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONDUCTOR")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.textMuted)
            if model.drivers.isEmpty {
                Text("No hay conductores activos visibles en esta estación.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                Picker("Conductor", selection: $model.selectedDriverId) {
                    ForEach(model.drivers) { driver in
                        Text(driver.employee_number).tag(Optional(driver.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .panel()
    }

    @ViewBuilder
    private var currentCard: some View {
        if let assignment = model.currentAssignment {
            VStack(alignment: .leading, spacing: 6) {
                Text("ASIGNACIÓN VIGENTE")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.textMuted)
                Text(model.currentVehicle?.internal_number ?? assignment.vehicle_id.uuidString)
                    .font(.headline)
                Text(assignment.kind == "substitute" ? "Unidad sustituta" : "Unidad titular")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .panel()
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIPO")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.textMuted)
            Picker("Tipo", selection: $model.kind) {
                Text("Titular").tag(AssignedUnitKind.titular)
                Text("Sustituta").tag(AssignedUnitKind.substitute)
            }
            .pickerStyle(.segmented)
            if model.kind == .substitute, model.currentAssignment == nil {
                Text("La sustituta requiere una asignación titular vigente.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .panel()
    }

    private var vehiclePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VEHÍCULO DISPONIBLE")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.textMuted)
            if model.availableVehicles.isEmpty {
                Text("No hay vehículos disponibles.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                Picker("Vehículo", selection: $model.selectedVehicleId) {
                    ForEach(model.availableVehicles) { vehicle in
                        Text("\(vehicle.internal_number) · \(vehicle.plate ?? "sin placa")")
                            .tag(Optional(vehicle.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .panel()
    }

    private var noteField: some View {
        TextField("Nota opcional", text: $model.note, axis: .vertical)
            .lineLimit(2...4)
            .padding(16)
            .panel()
    }

    private var assignButton: some View {
        BigButton(
            title: model.isAssigning ? "Asignando…" : "Confirmar asignación",
            symbol: model.isAssigning ? "hourglass" : "car.side.fill",
            isEnabled: model.canAssign
        ) {
            Task { await model.assign() }
        }
    }
}
