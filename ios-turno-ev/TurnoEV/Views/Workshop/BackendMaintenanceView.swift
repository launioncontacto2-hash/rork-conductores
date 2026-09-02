import Observation
import SwiftUI

/// Authoritative 15E workshop for a maintenance identity proved by Supabase.
/// It is deliberately separate from `MaintenanceRootView`, which remains the demo board.
@MainActor
@Observable
private final class BackendMaintenanceStore {
    let principal: SessionPrincipal

    var incidents: [SupabaseIncidentService.IncidentRow] = []
    var orders: [SupabaseWorkshopService.WorkOrderRow] = []
    var vehicles: [SupabaseAssignmentService.VehicleRow] = []
    var priority = "high"
    var estimatedMinutes = 60
    var selectedOrder: SupabaseWorkshopService.WorkOrderRow?
    var workDone = ""
    var isLoading = false
    var mutationId: UUID?
    var errorMessage: String?
    var successMessage: String?

    init(principal: SessionPrincipal) {
        self.principal = principal
    }

    var pendingIncidents: [SupabaseIncidentService.IncidentRow] {
        let linked = Set(orders.map(\.incident_id))
        return incidents.filter { $0.status != "closed" && !linked.contains($0.id) }
    }

    var openOrders: [SupabaseWorkshopService.WorkOrderRow] {
        orders.filter { $0.status != "closed" && $0.status != "cancelled" }
    }

    func vehicleLabel(_ vehicleId: UUID) -> String {
        vehicles.first { $0.id == vehicleId }?.internal_number ?? vehicleId.uuidString
    }

    func load() async {
        guard !isLoading else { return }
        guard let stationId = principal.stationId else {
            errorMessage = "La sesión de taller no contiene estación."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let incidentsRequest = SupabaseIncidentService.loadStationIncidents(stationId: stationId)
            async let ordersRequest = SupabaseWorkshopService.loadStationOrders(stationId: stationId)
            async let vehiclesRequest = SupabaseWorkshopService.loadStationVehicles(stationId: stationId)
            let (stationIncidents, stationOrders, stationVehicles) = try await (
                incidentsRequest,
                ordersRequest,
                vehiclesRequest
            )
            incidents = stationIncidents
            orders = stationOrders
            vehicles = stationVehicles
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openOrder(for incident: SupabaseIncidentService.IncidentRow) async {
        guard mutationId == nil else { return }
        mutationId = incident.id
        errorMessage = nil
        successMessage = nil
        defer { mutationId = nil }

        do {
            let order = try await SupabaseWorkshopService.open(
                incidentId: incident.id,
                priority: priority,
                estimatedMinutes: estimatedMinutes,
                idempotencyKey: "ios-workshop-open-\(UUID().uuidString.lowercased())"
            )
            orders.insert(order, at: 0)
            if let refreshed = try? await SupabaseIncidentService.loadStationIncidents(
                stationId: principal.stationId ?? ""
            ) {
                incidents = refreshed
            }
            successMessage = "\(order.folio) quedó abierta; la unidad pasó a mantenimiento."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func closeSelectedOrder() async {
        guard let order = selectedOrder, mutationId == nil else { return }
        let cleaned = workDone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 10 else {
            errorMessage = "Describe el trabajo realizado con al menos 10 caracteres."
            return
        }

        mutationId = order.id
        errorMessage = nil
        successMessage = nil
        defer { mutationId = nil }

        do {
            let closed = try await SupabaseWorkshopService.close(
                order: order,
                workDone: cleaned,
                idempotencyKey: "ios-workshop-close-\(UUID().uuidString.lowercased())"
            )
            if let index = orders.firstIndex(where: { $0.id == closed.id }) {
                orders[index] = closed
            }
            selectedOrder = nil
            workDone = ""
            successMessage = "\(closed.folio) quedó cerrada y la unidad fue liberada."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BackendMaintenanceView: View {
    @Environment(FleetStore.self) private var fleet
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: BackendMaintenanceStore

    init(principal: SessionPrincipal) {
        _model = State(initialValue: BackendMaintenanceStore(principal: principal))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identityCard
                    statusCard
                    configurationCard
                    pendingIncidentsCard
                    openOrdersCard
                }
                .padding(18)
            }
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle("Taller")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar sesión") { fleet.signOut() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    DemoClockButton()
                    Button { Task { await model.load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.load() }
            }
            .sheet(item: $model.selectedOrder) { order in
                closeSheet(order)
            }
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TALLER TEST")
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
                Text("Leyendo incidencias y órdenes reales…")
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
                "\(model.pendingIncidents.count) por recibir · \(model.openOrders.count) OT abiertas",
                systemImage: "wrench.and.screwdriver"
            )
            .font(.footnote)
            .foregroundStyle(Palette.textMuted)
        }
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONFIGURACIÓN DE LA NUEVA OT")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.textMuted)
            Picker("Prioridad", selection: $model.priority) {
                Text("Baja").tag("low")
                Text("Media").tag("medium")
                Text("Alta").tag("high")
                Text("Crítica").tag("critical")
            }
            .pickerStyle(.segmented)
            Stepper("Tiempo estimado: \(model.estimatedMinutes) min", value: $model.estimatedMinutes, in: 15...480, step: 15)
                .font(.footnote.weight(.semibold))
        }
        .padding(16)
        .panel()
    }

    private var pendingIncidentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INCIDENCIAS SIN ORDEN")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.textMuted)

            if model.pendingIncidents.isEmpty {
                Text("No hay incidencias pendientes de taller.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(model.pendingIncidents) { incident in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(incident.folio).font(.subheadline.weight(.bold))
                            Spacer()
                            Text(incident.severity.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Palette.amber)
                        }
                        Text("\(model.vehicleLabel(incident.vehicle_id)) · \(incident.kind.capitalized)")
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)
                        Text(incident.description).font(.footnote)
                        Button {
                            Task { await model.openOrder(for: incident) }
                        } label: {
                            Label(
                                model.mutationId == incident.id ? "Abriendo…" : "Abrir orden de trabajo",
                                systemImage: "wrench.and.screwdriver.fill"
                            )
                            .font(.footnote.weight(.bold))
                        }
                        .disabled(model.mutationId != nil)
                    }
                    Divider().overlay(Palette.hairline)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private var openOrdersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ÓRDENES ABIERTAS")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.textMuted)

            if model.openOrders.isEmpty {
                Text("No hay unidades retenidas por taller.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(model.openOrders) { order in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(order.folio).font(.subheadline.weight(.bold))
                            Spacer()
                            Text(order.status.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Palette.amber)
                        }
                        Text("\(model.vehicleLabel(order.vehicle_id)) · \(order.estimated_minutes) min · prioridad \(order.priority)")
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)
                        Text(order.problem).font(.footnote)
                        Button("Cerrar y liberar unidad") {
                            model.selectedOrder = order
                        }
                        .font(.footnote.weight(.bold))
                        .disabled(model.mutationId != nil)
                    }
                    Divider().overlay(Palette.hairline)
                }
            }
        }
        .padding(16)
        .panel()
    }

    private func closeSheet(_ order: SupabaseWorkshopService.WorkOrderRow) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(order.folio).font(.title2.weight(.bold))
                Text("Describe la reparación antes de liberar \(model.vehicleLabel(order.vehicle_id)).")
                    .foregroundStyle(Palette.textMuted)
                TextField("Trabajo realizado", text: $model.workDone, axis: .vertical)
                    .lineLimit(4...8)
                    .padding(14)
                    .panel()
                BigButton(
                    title: model.mutationId == order.id ? "Cerrando…" : "Cerrar orden y liberar",
                    symbol: "checkmark.seal.fill",
                    isEnabled: model.mutationId == nil && model.workDone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
                ) {
                    Task { await model.closeSelectedOrder() }
                }
                Spacer()
            }
            .padding(18)
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle("Cerrar OT")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        model.selectedOrder = nil
                        model.workDone = ""
                    }
                }
            }
        }
    }
}
