import SwiftUI

/// Interfaz de mantenimiento. The technician of a station sees only his own board:
/// work orders, the assets of the station and his own performance. No driver records,
/// no payroll, no hiring — the role decides what exists.
struct MaintenanceRootView: View {
    @Environment(FleetStore.self) private var fleet

    let account: StaffAccount

    @State private var office: StationOfficeStore
    @State private var tab: MaintenanceTab = .orders
    @State private var filter: OrderFilter = .open
    @State private var category: AssetFilter = .all
    @State private var openOrderId: String?

    init(account: StaffAccount, store: FleetStore) {
        self.account = account
        let station = StaffDirectory.station(id: account.stationId) ?? StaffDirectory.stations[0]
        _office = State(initialValue: StationOfficeStore(station: station, fleet: store, actor: account))
    }

    enum MaintenanceTab: Int, Hashable {
        case orders
        case assets
        case performance
    }

    enum AssetFilter: String, CaseIterable, Identifiable, Hashable {
        case all
        case vehicles
        case chargers
        case energy
        case facilities
        case tech

        var id: String { rawValue }

        var categories: [AssetCategory] {
            switch self {
            case .all: AssetCategory.allCases
            case .vehicles: [.vehicles]
            case .chargers: [.chargers]
            case .energy: [.electrical, .solar, .inverters]
            case .facilities: [.warehouse, .facilities, .tools, .other]
            case .tech: [.computers, .network, .surveillance]
            }
        }

        var label: String {
            switch self {
            case .all: "Todos"
            case .vehicles: "Vehículos"
            case .chargers: "Cargadores"
            case .energy: "Energía"
            case .facilities: "Instalaciones"
            case .tech: "Tecnología"
            }
        }

        var symbol: String {
            switch self {
            case .all: "square.grid.2x2.fill"
            case .vehicles: "car.2.fill"
            case .chargers: "ev.charger.fill"
            case .energy: "bolt.fill"
            case .facilities: "building.2.fill"
            case .tech: "wifi.router.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Órdenes", systemImage: "wrench.and.screwdriver.fill", value: MaintenanceTab.orders) {
                ordersScreen
            }
            Tab("Activos", systemImage: "square.grid.2x2.fill", value: MaintenanceTab.assets) {
                assetsScreen
            }
            Tab("Desempeño", systemImage: "chart.bar.xaxis", value: MaintenanceTab.performance) {
                performanceScreen
            }
        }
        .tint(Palette.volt)
        .task { office.refresh() }
        .onChange(of: fleet.clockOffsetMinutes) { _, _ in office.refresh() }
        .sheet(item: Binding(get: { openOrderId.map(OrderRoute.init) }, set: { openOrderId = $0?.id })) { route in
            WorkOrderDetailView(office: office, orderId: route.id, isTechnician: true)
        }
    }

    private struct OrderRoute: Identifiable, Hashable {
        let id: String
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Palette.volt)
                    .frame(width: 42, height: 42)
                    .background(Palette.volt.opacity(0.14), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Palette.volt.opacity(0.45), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("TALLER \(office.station.code)")
                        .font(.system(.subheadline, weight: .black))
                        .tracking(0.6)
                    Text("\(office.station.name) · turno \(account.slot?.label.lowercased() ?? "asignado")")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }

                Spacer(minLength: 0)
                DemoClockButton()
                SessionMenuButton()
            }

            HStack(spacing: 8) {
                StatePill(
                    text: "\(office.openOrders.count) abiertas",
                    symbol: "tray.full.fill",
                    tone: office.openOrders.isEmpty ? Palette.volt : Palette.amber,
                    compact: true
                )
                StatePill(
                    text: "\(Int(office.workshopMetrics.fleetAvailabilityRatio * 100))% flotilla",
                    symbol: "bolt.car.fill",
                    tone: office.workshopMetrics.fleetAvailabilityRatio >= 0.9 ? Palette.volt : Palette.danger,
                    compact: true
                )
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .panel(cornerRadius: 22)
    }

    // MARK: - Orders

    private var ordersScreen: some View {
        ZStack {
            SupervisionBackground()
            ScrollView {
                VStack(spacing: 14) {
                    header

                    ImmediateAttentionPanel(office: office) { openOrderId = $0 }

                    VStack(alignment: .leading, spacing: 10) {
                        FilterScroller(
                            items: OrderFilter.allCases,
                            title: { $0.label },
                            symbol: { $0.symbol },
                            count: { count(for: $0) },
                            selection: $filter
                        )
                        .padding(.horizontal, -16)

                        if visibleOrders.isEmpty {
                            SupEmptyState(
                                symbol: "checkmark.seal.fill",
                                title: "Nada pendiente",
                                message: "No tienes órdenes en este estado."
                            )
                        } else {
                            ForEach(visibleOrders) { order in
                                WorkOrderRow(order: order) { openOrderId = order.id }
                            }
                        }
                    }
                    .padding(16)
                    .panel()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func count(for filter: OrderFilter) -> Int {
        switch filter {
        case .open: office.openOrders.count
        case .all: office.orders.count
        default: office.orders.filter { $0.status == filter.status }.count
        }
    }

    private var visibleOrders: [WorkOrder] {
        switch filter {
        case .open: office.openOrders
        case .all: office.orders(status: nil)
        default: office.orders(status: filter.status)
        }
    }

    // MARK: - Assets

    private var assetsScreen: some View {
        ZStack {
            SupervisionBackground()
            ScrollView {
                VStack(spacing: 14) {
                    header

                    VStack(alignment: .leading, spacing: 10) {
                        SupSectionHeader(
                            title: "Activos de la estación",
                            subtitle: "No solo vehículos: energía, bodega, red y vigilancia"
                        )

                        FilterScroller(
                            items: AssetFilter.allCases,
                            title: { $0.label },
                            symbol: { $0.symbol },
                            count: { filter in office.assets.filter { filter.categories.contains($0.category) }.count },
                            selection: $category
                        )
                        .padding(.horizontal, -16)

                        ForEach(visibleAssets) { asset in
                            assetRow(asset)
                        }
                    }
                    .padding(16)
                    .panel()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var visibleAssets: [StationAsset] {
        office.assets
            .filter { category.categories.contains($0.category) }
            .sorted { lhs, rhs in
                lhs.state == rhs.state ? lhs.code < rhs.code : lhs.state.rawValue > rhs.state.rawValue
            }
    }

    private func assetRow(_ asset: StationAsset) -> some View {
        HStack(spacing: 10) {
            Image(systemName: asset.category.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(asset.state.tone)
                .frame(width: 30, height: 30)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.system(.footnote, weight: .bold))
                    .lineLimit(1)
                Text("\(asset.code) · último servicio \(Fmt.dateShort(asset.lastServiceAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }

            Spacer(minLength: 4)

            Menu {
                ForEach(StationAsset.State.allCases) { state in
                    Button(state.label, systemImage: state.symbol) {
                        office.setAssetState(state, id: asset.id)
                    }
                }
            } label: {
                Text(asset.state.label)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(asset.state.tone)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(asset.state.tone.opacity(0.14), in: .capsule)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat(cornerRadius: 14)
    }

    // MARK: - Performance

    private var performanceScreen: some View {
        ZStack {
            SupervisionBackground()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    metricsCard
                    bonusCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var metricsCard: some View {
        let metrics = office.workshopMetrics
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(title: "Tus indicadores", subtitle: "Lo que mide tu trabajo en la estación")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(label: "Completadas", value: "\(metrics.closed)", hint: "Órdenes cerradas", tone: .volt)
                StatTile(label: "Pendientes", value: "\(metrics.openTotal)", hint: "En tu tablero", tone: metrics.openTotal > 0 ? .amber : .volt)
                StatTile(label: "Resolución", value: Fmt.durationText(metrics.averageResolutionMinutes), hint: "Promedio", tone: .info)
                StatTile(label: "Preventivos", value: "\(metrics.preventiveDone)/\(metrics.preventiveProgrammed)", hint: "Realizados a tiempo", tone: .neutral)
                StatTile(label: "Unidades recuperadas", value: "\(metrics.recoveredVehicles)", hint: "Devueltas a operación", tone: .volt)
                StatTile(label: "Devueltas", value: "\(metrics.returned)", hint: "Regresadas por supervisión", tone: metrics.returned > 0 ? .danger : .volt)
                StatTile(label: "Críticas atendidas", value: "\(metrics.criticalHandled)", hint: "Prioridad máxima", tone: .info)
                StatTile(
                    label: "Disponibilidad",
                    value: "\(Int(metrics.fleetAvailabilityRatio * 100))%",
                    hint: "\(metrics.fleetAvailable) de \(metrics.fleetTotal) unidades",
                    tone: metrics.fleetAvailabilityRatio >= 0.9 ? .volt : .danger
                )
            }
        }
        .padding(16)
        .panel()
    }

    private var bonusCard: some View {
        let index = office.bonusIndex
        return VStack(alignment: .leading, spacing: 14) {
            SupSectionHeader(
                title: "Bonificación",
                subtitle: "No se paga por tareas cerradas, sino por un índice combinado"
            )

            HStack(alignment: .center, spacing: 16) {
                RingGauge(
                    value: Double(index.scorePct),
                    goal: 100,
                    headline: "\(index.scorePct)%",
                    caption: "rendimiento"
                )
                .scaleEffect(0.76)
                .frame(width: 136, height: 136)

                VStack(alignment: .leading, spacing: 9) {
                    DetailRow(label: "Meta", value: "\(index.goalPct)%")
                    DetailRow(
                        label: "Bono acumulado",
                        value: Fmt.mxn(index.earnedMxn),
                        tone: index.isEarned ? Palette.volt : Palette.amber
                    )
                    DetailRow(label: "Bono potencial", value: Fmt.mxn(index.potentialMxn))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 9) {
                ForEach(index.factors) { factor in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(factor.label)
                                .font(.system(size: 11, weight: .bold))
                            Spacer(minLength: 4)
                            Text("\(factor.weightPct)% · \(factor.scorePct)%")
                                .font(.system(size: 10, weight: .black))
                                .monospacedDigit()
                                .foregroundStyle(factor.ratio >= 0.9 ? Palette.volt : Palette.amber)
                        }
                        ProgressTrack(
                            value: factor.ratio,
                            goal: 1,
                            tone: factor.ratio >= 0.9 ? Palette.volt : Palette.amber
                        )
                        .frame(height: 7)
                        Text(factor.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                    .padding(11)
                    .panelFlat(cornerRadius: 14)
                }
            }

            if let worst = index.weakest.first {
                NoticeBanner(
                    symbol: "arrow.down.right.circle.fill",
                    title: "Lo que más te está costando: \(worst.label.lowercased())",
                    message: worst.detail,
                    tone: .amber
                )
            }
        }
        .padding(16)
        .panel()
    }
}

// MARK: - Immediate attention

/// Orders that cannot wait: critical priority, or past their commitment.
///
/// This is the one place in the module where the clock changes *membership* rather than a
/// label — an order joins the panel the minute it misses its `dueAt`. A filter like that
/// cannot be pushed into a leaf, so the panel is extracted into a view of its own and the
/// scope wraps its entire content. That is what keeps it honest: everything outside — the
/// `ScrollView`, the header, the filter scroller, the main board and its rows — is out of
/// reach. Declared exception to the leaf rule, on the same terms as the station meters.
private struct ImmediateAttentionPanel: View {
    let office: StationOfficeStore
    let onOpen: (String) -> Void

    var body: some View {
        TimeScope(.minute) { now in
            let critical = office.openOrders.filter {
                $0.priority == .critical || $0.isOverdue(now: now)
            }
            if !critical.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SupSectionHeader(
                        title: "Atención inmediata",
                        subtitle: "Prioridad crítica o fuera de tiempo"
                    )
                    ForEach(critical) { order in
                        WorkOrderRow(order: order) { onOpen(order.id) }
                    }
                }
                .padding(16)
                .panel()
            }
        }
    }
}
