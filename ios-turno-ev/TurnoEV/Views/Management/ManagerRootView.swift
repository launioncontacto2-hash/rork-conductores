import SwiftUI

/// Station management interface. Five modules, one station. It reads the same fleet
/// database the station writes to and can only decide what a manager decides: authorize
/// hires, sign bonuses, credits and unit retirements — all of them for their station.
struct ManagerRootView: View {
    @Environment(FleetStore.self) private var fleet

    let account: StaffAccount

    @State private var regional: RegionalStore
    @State private var tab: ManagerTab = .region
    @State private var requestFilter: RequestFilter = .all
    @State private var route: ManagerRoute?

    init(account: StaffAccount, store: FleetStore) {
        self.account = account
        _regional = State(initialValue: RegionalStore(account: account, fleet: store))
    }

    enum ManagerTab: Int, Hashable {
        case region
        case stations
        case approvals
        case performance
        case staff
    }

    private enum ManagerRoute: Identifiable, Hashable {
        case station(String)
        case request(String)

        var id: String {
            switch self {
            case .station(let id): "station-\(id)"
            case .request(let id): "request-\(id)"
            }
        }
    }

    private var header: ManagerHeader {
        ManagerHeader(
            account: account,
            station: regional.station,
            fleetSize: regional.card?.fleetSize ?? regional.station.vehicleCapacity,
            pendingCount: regional.pendingRequests.count,
            onRegenerate: { regional.regenerateRegion() }
        )
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Estación", systemImage: "square.grid.2x2.fill", value: ManagerTab.region) {
                ManagerRegionView(
                    regional: regional,
                    header: header,
                    onOpenStation: { route = .station($0) },
                    onOpenStations: { tab = .stations },
                    onOpenApprovals: { filter in
                        requestFilter = filter
                        tab = .approvals
                    },
                    onOpenRequest: { route = .request($0) },
                    onOpenPerformance: { tab = .performance },
                    onOpenStaff: { tab = .staff }
                )
            }

            Tab("Expediente", systemImage: "building.2.fill", value: ManagerTab.stations) {
                ManagerStationsView(
                    regional: regional,
                    header: header,
                    onOpenStation: { route = .station($0) }
                )
            }

            Tab(value: ManagerTab.approvals) {
                ManagerApprovalsView(
                    regional: regional,
                    header: header,
                    filter: $requestFilter,
                    onOpenRequest: { route = .request($0) }
                )
            } label: {
                Label("Autorizar", systemImage: "checkmark.seal.fill")
            }
            .badge(regional.pendingRequests.count)

            Tab("Desempeño", systemImage: "chart.line.uptrend.xyaxis", value: ManagerTab.performance) {
                ManagerPerformanceView(
                    regional: regional,
                    header: header,
                    onOpenStation: { route = .station($0) }
                )
            }

            Tab("Personal", systemImage: "person.2.badge.gearshape.fill", value: ManagerTab.staff) {
                ManagerStaffView(
                    regional: regional,
                    header: header,
                    onOpenStation: { route = .station($0) }
                )
            }
        }
        .tint(MgTone.accent)
        .task { regional.refresh() }
        .onChange(of: fleet.clockOffsetMinutes) { _, _ in regional.refresh() }
        .onChange(of: fleet.activeShift?.id) { _, _ in regional.refresh() }
        .onChange(of: fleet.credit?.contractId) { _, _ in regional.refresh() }
        .sheet(item: $route) { route in
            switch route {
            case .station(let id):
                ManagerStationDetailView(
                    regional: regional,
                    stationId: id,
                    onOpenRequest: { requestId in
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            self.route = .request(requestId)
                        }
                    }
                )
            case .request(let id):
                ManagerRequestDetailView(regional: regional, requestId: id)
            }
        }
    }
}
