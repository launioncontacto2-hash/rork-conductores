import Observation
import SwiftUI

/// Authoritative station workspace for a supervisor authenticated by Supabase.
///
/// It intentionally does not reuse `SupervisionStore`: that store is the rich local
/// simulation used by demo accounts. It reads the station catalogue, open shifts and
/// incidents through RLS, and performs assignment/review only through backend RPCs.
@MainActor
@Observable
private final class BackendAssignmentStore {
    let principal: SessionPrincipal

    var drivers: [SupabaseAssignmentService.DriverRow] = []
    var vehicles: [SupabaseAssignmentService.VehicleRow] = []
    var assignments: [SupabaseAssignmentService.AssignmentRow] = []
    var activeShifts: [SupabaseShiftService.ShiftRow] = []
    var incidents: [SupabaseIncidentService.IncidentRow] = []
    var workOrders: [SupabaseWorkshopService.WorkOrderRow] = []
    var absences: [SupabaseCoverageService.AbsenceRow] = []
    var coverageVacancies: [SupabaseCoverageService.VacancyRow] = []
    var coverageClaims: [SupabaseCoverageService.ClaimRow] = []
    var selectedDriverId: UUID?
    var selectedVehicleId: UUID?
    var kind: AssignedUnitKind = .titular
    var note: String = ""
    var isLoading = false
    var isAssigning = false
    var updatingIncidentId: UUID?
    var updatingCoverageId: UUID?
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

    var assignmentBlockReason: String? {
        guard !isLoading else { return "Actualizando inventario…" }
        guard selectedDriver != nil else { return "Selecciona un conductor." }
        guard selectedVehicle != nil else {
            return availableVehicles.isEmpty
                ? "No hay vehículos disponibles; actualiza el inventario."
                : "Selecciona un vehículo disponible."
        }
        guard kind == .titular || currentAssignment != nil else {
            return "La unidad sustituta requiere una asignación titular vigente."
        }
        guard note.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 else {
            return "Escribe un motivo de al menos 5 caracteres."
        }
        return nil
    }

    var canAssign: Bool {
        !isAssigning && assignmentBlockReason == nil
    }

    func driverLabel(for shift: SupabaseShiftService.ShiftRow) -> String {
        drivers.first { $0.id == shift.driver_profile_id }.map(driverName)
            ?? shift.driver_profile_id.uuidString
    }

    func driverName(_ driver: SupabaseAssignmentService.DriverRow) -> String {
        driver.display_name ?? driver.employee_number
    }

    func vehicleLabel(for shift: SupabaseShiftService.ShiftRow) -> String {
        vehicles.first { $0.id == shift.vehicle_id }?.internal_number
            ?? shift.vehicle_id.uuidString
    }

    func vehicleLabel(for incident: SupabaseIncidentService.IncidentRow) -> String {
        vehicles.first { $0.id == incident.vehicle_id }?.internal_number
            ?? incident.vehicle_id.uuidString
    }

    var openCoverageVacancies: [SupabaseCoverageService.VacancyRow] {
        coverageVacancies.filter { ["searching", "reserved", "confirmed"].contains($0.status) }
    }

    func absence(for vacancy: SupabaseCoverageService.VacancyRow) -> SupabaseCoverageService.AbsenceRow? {
        guard let absenceId = vacancy.absence_id else { return nil }
        return absences.first { $0.id == absenceId }
    }

    func winner(for vacancy: SupabaseCoverageService.VacancyRow) -> SupabaseCoverageService.ClaimRow? {
        coverageClaims.first {
            $0.vacancy_id == vacancy.id && ["won", "approved"].contains($0.status)
        }
    }

    func driverLabel(for claim: SupabaseCoverageService.ClaimRow) -> String {
        drivers.first { $0.id == claim.driver_profile_id }?.employee_number
            ?? claim.driver_profile_id.uuidString
    }

    func load() async {
        guard !isLoading else { return }
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
            async let incidentsRequest = SupabaseIncidentService.loadStationIncidents(
                stationId: stationId
            )
            async let coverageRequest = SupabaseCoverageService.loadStationSnapshot(
                stationId: stationId
            )
            async let workOrdersRequest = SupabaseWorkshopService.loadStationOrders(
                stationId: stationId
            )
            let (snapshot, shifts, stationIncidents, stationCoverage, stationWorkOrders) = try await (
                snapshotRequest,
                shiftsRequest,
                incidentsRequest,
                coverageRequest,
                workOrdersRequest
            )
            drivers = snapshot.drivers
            vehicles = snapshot.vehicles
            assignments = snapshot.assignments
            activeShifts = shifts
            incidents = stationIncidents
            absences = stationCoverage.absences
            coverageVacancies = stationCoverage.vacancies
            coverageClaims = stationCoverage.claims
            workOrders = stationWorkOrders

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
            successMessage = "\(vehicle.operationalUnitLabel) quedó asignada a \(driverName(driver))."
            note = ""
            selectedVehicleId = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markReviewed(
        _ incident: SupabaseIncidentService.IncidentRow,
        reason: String
    ) async {
        guard updatingIncidentId == nil else { return }
        updatingIncidentId = incident.id
        errorMessage = nil
        successMessage = nil
        defer { updatingIncidentId = nil }

        do {
            let updated = try await SupabaseIncidentService.update(
                incident: incident,
                status: "review",
                note: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: "ios-supervisor-review-\(UUID().uuidString.lowercased())"
            )
            if let index = incidents.firstIndex(where: { $0.id == updated.id }) {
                incidents[index] = updated
            }
            successMessage = "\(updated.folio) quedó recibida por supervisión."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func approveGuard(
        _ vacancy: SupabaseCoverageService.VacancyRow,
        reason: String
    ) async {
        guard updatingCoverageId == nil else { return }
        updatingCoverageId = vacancy.id
        errorMessage = nil
        successMessage = nil
        defer { updatingCoverageId = nil }

        do {
            let updated = try await SupabaseCoverageService.approve(
                vacancy: vacancy,
                note: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: "ios-supervisor-guard-\(UUID().uuidString.lowercased())"
            )
            successMessage = "\(updated.folio) quedó confirmada."
            await load()
        } catch {
            errorMessage = SupabaseCoverageService.userMessage(for: error)
        }
    }

    func resolveAbsence(
        _ absence: SupabaseCoverageService.AbsenceRow,
        approved: Bool,
        reason: String
    ) async {
        guard updatingCoverageId == nil else { return }
        updatingCoverageId = absence.id
        errorMessage = nil
        successMessage = nil
        defer { updatingCoverageId = nil }

        do {
            let updated = try await SupabaseCoverageService.resolve(
                absence: absence,
                decision: approved ? "approved" : "rejected",
                note: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: "ios-supervisor-absence-\(UUID().uuidString.lowercased())"
            )
            successMessage = "\(updated.folio) quedó \(approved ? "autorizada" : "rechazada")."
            await load()
        } catch {
            errorMessage = SupabaseCoverageService.userMessage(for: error)
        }
    }

}

private enum SupervisorPendingAction: Identifiable {
    case assignment
    case reviewIncident(SupabaseIncidentService.IncidentRow)
    case approveGuard(SupabaseCoverageService.VacancyRow)
    case approveAbsence(SupabaseCoverageService.AbsenceRow)
    case rejectAbsence(SupabaseCoverageService.AbsenceRow)

    var id: String {
        switch self {
        case .assignment: "assignment"
        case .reviewIncident(let incident): "incident-\(incident.id)"
        case .approveGuard(let vacancy): "guard-\(vacancy.id)"
        case .approveAbsence(let absence): "approve-absence-\(absence.id)"
        case .rejectAbsence(let absence): "reject-absence-\(absence.id)"
        }
    }

    var title: String {
        switch self {
        case .assignment: "Confirmar asignación"
        case .reviewIncident: "Recibir incidencia"
        case .approveGuard: "Confirmar reemplazo"
        case .approveAbsence: "Autorizar ausencia"
        case .rejectAbsence: "Rechazar ausencia"
        }
    }

    var reference: String {
        switch self {
        case .assignment: "La asignación seleccionada"
        case .reviewIncident(let incident): incident.folio
        case .approveGuard(let vacancy): vacancy.folio
        case .approveAbsence(let absence), .rejectAbsence(let absence): absence.folio
        }
    }
}

struct BackendSupervisorAssignmentView: View {
    @Environment(FleetStore.self) private var fleet
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: BackendAssignmentStore
    @State private var section: Int = 0
    @State private var pendingAction: SupervisorPendingAction?
    @State private var confirmationReason: String = ""

    init(principal: SessionPrincipal) {
        _model = State(initialValue: BackendAssignmentStore(principal: principal))
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $section) {
                Tab("Operación", systemImage: "waveform.path.ecg", value: 0) {
                    page {
                        identityCard
                        statusCard
                        activeShiftsCard
                    }
                }
                Tab("Asignar", systemImage: "car.badge.gearshape", value: 1) {
                    page {
                        statusCard
                        driverPicker
                        currentCard
                        kindPicker
                        vehiclePicker
                        noteField
                        assignButton
                    }
                }
                Tab("Incidencias", systemImage: "exclamationmark.triangle", value: 2) {
                    page {
                        statusCard
                        incidentsCard
                        workOrdersCard
                    }
                }
                Tab("Cobertura", systemImage: "person.2.badge.gearshape", value: 3) {
                    page {
                        statusCard
                        coverageCard
                    }
                }
                Tab("Flota", systemImage: "person.2", value: 4) {
                    page {
                        statusCard
                        fleetCard
                    }
                }
            }
            .tint(Palette.volt)
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle(navigationTitle)
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
            .task {
                while !Task.isCancelled {
                    await model.load()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.load() }
            }
            .onChange(of: model.selectedDriverId) { _, _ in
                model.kind = .titular
                model.selectedVehicleId = model.availableVehicles.first?.id
            }
            .sheet(item: $pendingAction) { action in
                confirmationSheet(for: action)
            }
        }
    }

    private var navigationTitle: String {
        switch section {
        case 1: "Asignar unidad"
        case 2: "Incidencias"
        case 3: "Cobertura"
        case 4: "Conductores y flota"
        default: "Supervisión"
        }
    }

    private var fleetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CONDUCTORES")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.textMuted)

            if model.drivers.isEmpty {
                Text("No hay conductores activos en esta estación.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(model.drivers) { driver in
                    let assignment = model.assignments.first { $0.driver_profile_id == driver.id }
                    let shift = model.activeShifts.first { $0.driver_profile_id == driver.id }
                    HStack(spacing: 12) {
                        Image(systemName: shift == nil ? "person.crop.circle" : "steeringwheel")
                            .foregroundStyle(shift == nil ? Palette.textMuted : Palette.volt)
                            .frame(width: 34, height: 34)
                            .background(Palette.surfaceRaised, in: .circle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.driverName(driver))
                                .font(.subheadline.weight(.bold))
                            if let vehicle = assignment.flatMap({ assignmentRow in
                                model.vehicles.first { $0.id == assignmentRow.vehicle_id }
                            }) {
                                Text(vehicle.operationalUnitLabel)
                                    .font(.caption.weight(.bold))
                                Text(vehicle.modelAndColorLabel)
                                    .font(.caption2)
                                    .foregroundStyle(Palette.textMuted)
                            } else {
                                Text("Sin unidad asignada")
                                    .font(.caption)
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(shift == nil ? "SIN TURNO" : "EN TURNO")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(shift == nil ? Palette.textMuted : Palette.volt)
                    }
                }
            }

            Divider().overlay(Palette.hairline)
            Text("VEHÍCULOS")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.textMuted)

            if model.vehicles.isEmpty {
                Text("No hay vehículos visibles en esta estación.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(model.vehicles) { vehicle in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vehicle.operationalUnitLabel)
                                .font(.subheadline.weight(.bold))
                            Text(vehicle.modelAndColorLabel)
                                .font(.caption)
                                .foregroundStyle(Palette.textMuted)
                            if let operationalCode = vehicle.operational_code {
                                Text(operationalCode)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                        Spacer()
                        Text(vehicleStatusLabel(vehicle.status))
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(vehicle.status == "available" ? Palette.volt : Palette.amber)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private var workOrdersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TALLER")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Text("\(model.workOrders.filter { $0.status != "closed" }.count) ABIERTAS")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Palette.amber)
            }

            if model.workOrders.isEmpty {
                Text("No hay órdenes de trabajo para esta estación.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(Array(model.workOrders.prefix(12))) { order in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundStyle(order.status == "closed" ? Palette.textMuted : Palette.amber)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(order.folio)
                                .font(.subheadline.weight(.bold))
                            Text("\(model.vehicles.first { $0.id == order.vehicle_id }?.internal_number ?? "Unidad") · \(order.problem)")
                                .font(.caption)
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer(minLength: 8)
                        Text(order.status.uppercased())
                            .font(.system(size: 9, weight: .black))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private func vehicleStatusLabel(_ status: String) -> String {
        switch status {
        case "available": "DISPONIBLE"
        case "occupied": "ASIGNADO"
        case "maintenance": "TALLER"
        default: status.uppercased()
        }
    }

    private func page<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }

    private var incidentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INCIDENCIAS DE LA ESTACIÓN")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Text("\(model.incidents.filter { $0.status != "closed" }.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.amber)
            }

            if model.incidents.isEmpty {
                Text("No hay incidencias reportadas.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(Array(model.incidents.prefix(8))) { incident in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(incident.folio)
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Text(incident.status == "open" ? "NUEVA" : incident.status.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(incident.status == "closed" ? Palette.textMuted : Palette.amber)
                        }
                        Text("\(model.vehicleLabel(for: incident)) · \(incident.kind.capitalized) · \(incident.severity.capitalized)")
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)
                        Text(incident.description)
                            .font(.footnote)

                        if incident.status == "open" {
                            Button {
                                requestConfirmation(.reviewIncident(incident))
                            } label: {
                                Label(
                                    model.updatingIncidentId == incident.id ? "Registrando…" : "Marcar como recibida",
                                    systemImage: "checkmark.circle"
                                )
                                .font(.footnote.weight(.bold))
                            }
                            .disabled(model.updatingIncidentId != nil)
                        }
                    }

                    if incident.id != model.incidents.prefix(8).last?.id {
                        Divider().overlay(Palette.hairline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("COBERTURA Y GUARDIAS")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Text("\(model.openCoverageVacancies.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(model.openCoverageVacancies.isEmpty ? Palette.textMuted : Palette.amber)
            }

            if model.openCoverageVacancies.isEmpty {
                Text("No hay vacantes de cobertura abiertas.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(model.openCoverageVacancies) { vacancy in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(vacancy.folio)
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Text(coverageStatus(vacancy.status))
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(vacancy.status == "confirmed" ? Palette.volt : Palette.amber)
                        }
                        Text("\(vacancy.operating_date) · \(ShiftSlot(rawValue: vacancy.shift_slot)?.label ?? vacancy.shift_slot)")
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)

                        if let winner = model.winner(for: vacancy) {
                            Text("Ganador: \(model.driverLabel(for: winner))")
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                        } else {
                            Text("Esperando que un conductor elegible la tome.")
                                .font(.caption2)
                                .foregroundStyle(Palette.textMuted)
                        }

                        if vacancy.status == "reserved" {
                            BigButton(
                                title: model.updatingCoverageId == vacancy.id
                                    ? "Confirmando…" : "Aprobar reemplazo",
                                symbol: "person.fill.checkmark",
                                isEnabled: model.updatingCoverageId == nil
                            ) {
                                requestConfirmation(.approveGuard(vacancy))
                            }
                        }

                        if vacancy.status == "confirmed",
                           let absence = model.absence(for: vacancy),
                           absence.status == "awaiting_authorization" {
                            HStack(spacing: 8) {
                                Button {
                                    requestConfirmation(.approveAbsence(absence))
                                } label: {
                                    Label("Autorizar ausencia", systemImage: "checkmark.seal.fill")
                                        .font(.caption.weight(.bold))
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(Palette.volt, in: .rect(cornerRadius: 12))
                                        .foregroundStyle(Palette.canvas)
                                }
                                .buttonStyle(.plain)
                                .disabled(model.updatingCoverageId != nil)

                                Button {
                                    requestConfirmation(.rejectAbsence(absence))
                                } label: {
                                    Text("Rechazar")
                                        .font(.caption.weight(.bold))
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(Color.red.opacity(0.14), in: .rect(cornerRadius: 12))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .disabled(model.updatingCoverageId != nil)
                            }
                        }
                    }

                    if vacancy.id != model.openCoverageVacancies.last?.id {
                        Divider().overlay(Palette.hairline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private func coverageStatus(_ raw: String) -> String {
        switch raw {
        case "searching": "ABIERTA"
        case "reserved": "POR APROBAR"
        case "confirmed": "CONFIRMADA"
        default: raw.uppercased()
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
        } else {
            Label(
                "\(model.drivers.count) conductores · \(model.availableVehicles.count) vehículos disponibles",
                systemImage: "checkmark.circle"
            )
            .font(.footnote)
            .foregroundStyle(Palette.textMuted)
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
        TextField("Motivo obligatorio", text: $model.note, axis: .vertical)
            .lineLimit(2...4)
            .padding(16)
            .panel()
    }

    private var assignButton: some View {
        VStack(spacing: 8) {
            BigButton(
                title: model.isAssigning ? "Asignando…" : "Confirmar asignación",
                symbol: model.isAssigning ? "hourglass" : "car.side.fill",
                isEnabled: model.canAssign
            ) {
                requestConfirmation(.assignment, reason: model.note)
            }

            if let reason = model.assignmentBlockReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func requestConfirmation(
        _ action: SupervisorPendingAction,
        reason: String = ""
    ) {
        confirmationReason = reason
        model.errorMessage = nil
        model.successMessage = nil
        pendingAction = action
    }

    private var isConfirmingAction: Bool {
        model.isAssigning || model.updatingIncidentId != nil || model.updatingCoverageId != nil
    }

    private func confirmationSheet(for action: SupervisorPendingAction) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("ACCIÓN SENSIBLE", systemImage: "shield.lefthalf.filled")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.amber)

                Text(action.reference)
                    .font(.title3.weight(.bold))

                Text("Escribe el motivo operativo. Supabase lo conservará junto con la identidad, la estación y la clave única del comando.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)

                TextField("Motivo obligatorio", text: $confirmationReason, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(16)
                    .panelFlat()

                if confirmationReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 {
                    Text("El motivo debe tener al menos 5 caracteres.")
                        .font(.caption)
                        .foregroundStyle(Palette.amber)
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }

                BigButton(
                    title: isConfirmingAction ? "Registrando…" : "Confirmar y auditar",
                    symbol: isConfirmingAction ? "hourglass" : "checkmark.shield.fill",
                    isEnabled: !isConfirmingAction
                        && confirmationReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
                ) {
                    Task { await execute(action) }
                }

                Spacer()
            }
            .padding(20)
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        pendingAction = nil
                        confirmationReason = ""
                    }
                    .disabled(isConfirmingAction)
                }
            }
        }
        .interactiveDismissDisabled(isConfirmingAction)
    }

    private func execute(_ action: SupervisorPendingAction) async {
        let reason = confirmationReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 5 else { return }

        switch action {
        case .assignment:
            model.note = reason
            await model.assign()
        case .reviewIncident(let incident):
            await model.markReviewed(incident, reason: reason)
        case .approveGuard(let vacancy):
            await model.approveGuard(vacancy, reason: reason)
        case .approveAbsence(let absence):
            await model.resolveAbsence(absence, approved: true, reason: reason)
        case .rejectAbsence(let absence):
            await model.resolveAbsence(absence, approved: false, reason: reason)
        }

        if model.errorMessage == nil {
            pendingAction = nil
            confirmationReason = ""
        }
    }
}
