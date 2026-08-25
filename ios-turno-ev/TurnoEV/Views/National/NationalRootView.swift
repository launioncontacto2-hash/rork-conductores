import SwiftUI

/// National direction interface. Four modules: el país, las regiones, las credenciales de
/// la red y la expansión. Dirección lee todo y decide poco: abre estaciones, genera mandos
/// y mueve las reglas. La operación diaria nunca pasa por aquí.
struct NationalRootView: View {
    @Environment(FleetStore.self) private var fleet

    let account: StaffAccount

    @State private var national: NationalStore
    @State private var tab: NationalTab = .country
    @State private var route: NationalRoute?

    init(account: StaffAccount, store: FleetStore) {
        self.account = account
        _national = State(initialValue: NationalStore(account: account, fleet: store))
    }

    enum NationalTab: Int, Hashable {
        case country
        case regions
        case directory
        case expansion
    }

    private enum NationalRoute: Identifiable, Hashable {
        case region(String)
        case station(String)
        case alerts

        var id: String {
            switch self {
            case .region(let id): "region-\(id)"
            case .station(let id): "station-\(id)"
            case .alerts: "alerts"
            }
        }
    }

    private var header: NationalHeader {
        NationalHeader(
            account: account,
            regionCount: StaffDirectory.regions.count,
            stationCount: national.metrics.stations,
            alertCount: national.alerts.count,
            onRegenerate: { national.regenerateNetwork() },
            onOpenAlerts: { route = .alerts }
        )
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("País", systemImage: "globe.americas.fill", value: NationalTab.country) {
                NavigationStack {
                    NationalHomeView(
                        national: national,
                        header: header,
                        onOpenRegion: { route = .region($0) },
                        onOpenRegions: { tab = .regions },
                        onOpenDirectory: { tab = .directory },
                        onOpenExpansion: { tab = .expansion },
                        onOpenPolicy: { tab = .expansion }
                    )
                }
            }

            Tab("Regiones", systemImage: "map.fill", value: NationalTab.regions) {
                NationalRegionsView(
                    national: national,
                    header: header,
                    onOpenRegion: { route = .region($0) },
                    onOpenStation: { route = .station($0) }
                )
            }

            Tab(value: NationalTab.directory) {
                NationalDirectoryView(national: national, header: header)
            } label: {
                Label("Credenciales", systemImage: "person.text.rectangle.fill")
            }
            .badge(
                national.stationsWithoutManager.count
                    + national.stationsWithoutRecruiter.count
                    + national.supervisionGaps.count
            )

            Tab(value: NationalTab.expansion) {
                NavigationStack {
                    NationalExpansionView(national: national)
                }
            } label: {
                Label("Expansión", systemImage: "map.circle.fill")
            }
            .badge(national.projects.filter { $0.stage != .operating }.count)
        }
        .tint(NatTone.accent)
        .task { national.refresh() }
        .onChange(of: fleet.clockOffsetMinutes) { _, _ in national.refresh() }
        .onChange(of: fleet.activeShift?.id) { _, _ in national.refresh() }
        .sheet(item: $route) { route in
            switch route {
            case .region(let id):
                NationalRegionDetailView(
                    national: national,
                    regionId: id,
                    onOpenStation: { stationId in
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            self.route = .station(stationId)
                        }
                    }
                )
            case .station(let id):
                NationalStationDetailView(national: national, stationId: id)
            case .alerts:
                NationalAlertsView(national: national)
            }
        }
    }
}

/// Every exception of the country in one board, ordered by gravity.
struct NationalAlertsView: View {
    let national: NationalStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NationalBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        if national.alerts.isEmpty {
                            NoticeBanner(
                                symbol: "checkmark.seal.fill",
                                title: "Sin excepciones abiertas",
                                message: "La red opera dentro de los umbrales de meta, plantilla, cartera y aperturas.",
                                tone: .volt
                            )
                        } else {
                            ForEach(national.alerts) { alert in
                                NationalAlertCard(
                                    alert: alert,
                                    onReview: { national.reviewAlert(id: alert.id) }
                                )
                            }
                        }

                        Button("Restaurar excepciones revisadas") {
                            national.restoreAlerts()
                        }
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Excepciones de la red")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
