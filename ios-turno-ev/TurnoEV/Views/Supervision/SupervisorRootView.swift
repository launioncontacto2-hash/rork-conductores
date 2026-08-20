import SwiftUI

/// Supervisor interface. Five modules in the bottom bar — operación, conductores,
/// vehículos, personal y taller — plus alertas e historial detrás del encabezado.
/// It reads the same station database the drivers and the technician write to.
struct SupervisorRootView: View {
    @Environment(FleetStore.self) private var fleet
    @Environment(CoverageStore.self) private var coverage

    let account: StaffAccount

    @State private var supervision: SupervisionStore
    @State private var office: StationOfficeStore
    /// Recovers the capacity an absence takes away. It reads attendance and the fleet
    /// board, and uses Guardias as its engine.
    @State private var resolution: AbsenceResolutionStore
    @State private var tab: SupervisorTab = .operation
    @State private var driverFilter: DriverFilter = .all
    @State private var vehicleFilter: VehicleFilter = .all
    @State private var showsIncidents: Bool = false
    @State private var route: SupervisorRoute?

    init(account: StaffAccount, store: FleetStore) {
        self.account = account
        let station = StaffDirectory.station(id: account.stationId) ?? StaffDirectory.stations[0]
        _supervision = State(initialValue: SupervisionStore(account: account, fleet: store))
        _office = State(initialValue: StationOfficeStore(station: station, fleet: store, actor: account))
        _resolution = State(initialValue: AbsenceResolutionStore(stationId: station.id))
    }

    enum SupervisorTab: Int, Hashable {
        case operation
        case coverage
        case drivers
        case vehicles
        case people
        case workshop
    }

    private enum SupervisorRoute: Identifiable, Hashable {
        case driver(String)
        case vehicle(String)
        case handover(String)
        case newIncident(driverId: String?, vehicleNumber: String?)
        case alerts
        case history

        var id: String {
            switch self {
            case .driver(let id): "driver-\(id)"
            case .vehicle(let id): "vehicle-\(id)"
            case .handover(let id): "handover-\(id)"
            case .newIncident(let driverId, let vehicleNumber): "incident-\(driverId ?? "-")-\(vehicleNumber ?? "-")"
            case .alerts: "alerts"
            case .history: "history"
            }
        }
    }

    /// Alerts of the whole station: operational rules plus people, banking and workshop.
    private var alertCount: Int {
        supervision.alerts.count + office.criticalAlerts.count
    }

    /// Seats waiting on this supervisor: nobody driving them, or a substitute proposed and
    /// unsigned, or two drivers waiting on a swap.
    private var coverageBadge: Int {
        let stationId = supervision.station.id
        return coverage.openVacancies(stationId: stationId).count
            + coverage.vacanciesAwaitingApproval(stationId: stationId).count
            + coverage.swaps(stationId: stationId).filter { $0.status == .awaitingSupervisor }.count
    }

    private var header: SupervisorHeader {
        SupervisorHeader(
            account: account,
            station: supervision.station,
            slot: supervision.slot,
            now: fleet.now,
            pendingCount: supervision.pendingTickets.count,
            alertCount: alertCount,
            onSignOut: { fleet.signOut() },
            onRegenerate: {
                supervision.regenerateStation()
                office.regenerate()
            },
            onOpenAlerts: { route = .alerts },
            onOpenHistory: { route = .history }
        )
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Operación", systemImage: "square.grid.2x2.fill", value: SupervisorTab.operation) {
                SupervisorOperationView(
                    supervision: supervision,
                    office: office,
                    resolution: resolution,
                    header: header.titled("Operación"),
                    onOpenDrivers: { filter in
                        driverFilter = filter
                        tab = .drivers
                    },
                    onOpenVehicles: { state in
                        vehicleFilter = VehicleFilter.from(state)
                        tab = .vehicles
                    },
                    onOpenAlerts: { incidents in
                        showsIncidents = incidents
                        route = .alerts
                    },
                    onOpenTicket: { route = .handover($0) },
                    onNewIncident: { route = .newIncident(driverId: nil, vehicleNumber: nil) },
                    onOpenPeople: { tab = .people },
                    onOpenWorkshop: { tab = .workshop }
                )
            }

            Tab(value: SupervisorTab.coverage) {
                SupervisorCoverageView(
                    supervision: supervision,
                    account: account,
                    header: header.titled("Cobertura")
                )
            } label: {
                Label("Cobertura", systemImage: "calendar.badge.clock")
            }
            .badge(coverageBadge)

            Tab("Conductores", systemImage: "person.2.fill", value: SupervisorTab.drivers) {
                SupervisorDriversView(
                    supervision: supervision,
                    header: header.titled("Conductores"),
                    filter: $driverFilter,
                    onOpenDriver: { route = .driver($0) },
                    onOpenTicket: { route = .handover($0) }
                )
            }

            Tab("Vehículos", systemImage: "car.2.fill", value: SupervisorTab.vehicles) {
                SupervisorVehiclesView(
                    supervision: supervision,
                    header: header.titled("Vehículos"),
                    filter: $vehicleFilter,
                    onOpenVehicle: { route = .vehicle($0) }
                )
            }

            Tab(value: SupervisorTab.people) {
                HRHomeView(office: office, header: header.titled("Personal"))
            } label: {
                Label("Personal", systemImage: "person.text.rectangle.fill")
            }
            .badge(office.capacityPlan.deficit)

            Tab(value: SupervisorTab.workshop) {
                SupervisorWorkshopView(office: office, header: header.titled("Taller"))
            } label: {
                Label("Taller", systemImage: "wrench.and.screwdriver.fill")
            }
            .badge(office.ordersAwaitingValidation.count)
        }
        .tint(SupTone.accent)
        .task {
            supervision.refresh()
            office.refresh()
            resolution.configure(supervision: supervision, coverage: coverage)
            resolution.refresh()
        }
        .onChange(of: fleet.clockOffsetMinutes) { _, _ in
            supervision.refresh()
            office.refresh()
            // Moving the clock is what crosses the tolerance, so the engine re-reads.
            resolution.refresh()
        }
        .onChange(of: fleet.activeShift?.id) { _, _ in
            supervision.refresh()
            resolution.refresh()
        }
        .sheet(item: $route) { route in
            switch route {
            case .driver(let id):
                SupervisorDriverDetailView(
                    supervision: supervision,
                    driverId: id,
                    onOpenTicket: { ticketId in
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            self.route = .handover(ticketId)
                        }
                    },
                    onReportIncident: { driverId in
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            self.route = .newIncident(driverId: driverId, vehicleNumber: nil)
                        }
                    }
                )
            case .vehicle(let id):
                SupervisorVehicleDetailView(
                    supervision: supervision,
                    vehicleId: id,
                    onReportIncident: { number in
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            self.route = .newIncident(driverId: nil, vehicleNumber: number)
                        }
                    }
                )
            case .handover(let id):
                SupervisorHandoverView(supervision: supervision, ticketId: id)
            case .newIncident(let driverId, let vehicleNumber):
                SupervisorIncidentFormView(
                    supervision: supervision,
                    presetDriverId: driverId,
                    presetVehicleNumber: vehicleNumber
                )
            case .alerts:
                SupervisorAlertsView(
                    supervision: supervision,
                    header: header.titled("Alertas") { self.route = nil },
                    showsIncidents: $showsIncidents,
                    onOpenTicket: { ticketId in
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            self.route = .handover(ticketId)
                        }
                    },
                    onOpenDriver: { driverId in
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            self.route = .driver(driverId)
                        }
                    },
                    onNewIncident: {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            self.route = .newIncident(driverId: nil, vehicleNumber: nil)
                        }
                    }
                )
            case .history:
                SupervisorHistoryView(
                    supervision: supervision,
                    header: header.titled("Historial") { self.route = nil },
                    onOpenTicket: { ticketId in
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            self.route = .handover(ticketId)
                        }
                    }
                )
            }
        }
    }
}
