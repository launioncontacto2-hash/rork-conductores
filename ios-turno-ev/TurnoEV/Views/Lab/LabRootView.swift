import SwiftUI

/// Console of the test administrator. It is the only interface this role can open, and it
/// is the only place in the app where every module can be written to at once.
struct LabRootView: View {
    let account: StaffAccount
    @Environment(LabStore.self) private var lab
    @Environment(FleetStore.self) private var fleet
    @Environment(VisualEditorStore.self) private var editor

    @State private var path: [LabSection] = []
    @State private var isModeChangePresented: Bool = false
    @State private var pendingMode: LabMode = .test

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    environmentCard
                    if lab.isTest {
                        stateOfTheWorld
                        alertsCard
                        quickActions
                    } else {
                        productionNotice
                    }
                    sectionsGrid
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 46)
            }
            .background(LabBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SessionMenuButton() }
            }
            .toolbarBackground(LabTone.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: LabSection.self) { section in
                LabSectionRouter(section: section)
            }
            .labToasts()
        }
        .tint(LabTone.accent)
        .confirmationDialog(
            pendingMode == .test ? "¿Entrar a modo prueba?" : "¿Volver a producción?",
            isPresented: $isModeChangePresented,
            titleVisibility: .visible
        ) {
            Button(pendingMode == .test ? "Entrar a modo prueba" : "Volver a producción") {
                lab.setMode(pendingMode)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(
                pendingMode == .test
                    ? "Todas las interfaces quedarán en cero y solo mostrarán lo que crees aquí. La red demostrativa no se borra."
                    : "Las interfaces vuelven a la red demostrativa sembrada. El entorno de pruebas se conserva intacto."
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "testtube.2")
                    .font(.system(.title3, weight: .black))
                    .foregroundStyle(LabTone.canvas)
                    .frame(width: 46, height: 46)
                    .background(LabTone.accent, in: .rect(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Laboratorio de pruebas")
                        .font(.system(.title3, weight: .black))
                        .foregroundStyle(.white)
                    Text("\(account.name) · \(account.employeeNumber)")
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                }
                Spacer(minLength: 0)
            }

            Text("Alimenta el sistema completo desde cero: estaciones, personal, flotilla, dinero, documentos e integraciones. Nada de lo que crees aquí toca un registro real.")
                .font(.footnote)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - Environment switch

    private var environmentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabCaps(text: "Entorno activo")

            HStack(spacing: 10) {
                ForEach(LabMode.allCases) { mode in
                    Button {
                        guard mode != lab.mode else { return }
                        pendingMode = mode
                        isModeChangePresented = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: mode.symbol)
                                    .font(.system(.caption, weight: .bold))
                                Text(mode.label)
                                    .font(.system(.subheadline, weight: .bold))
                                Spacer(minLength: 0)
                                if lab.mode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                }
                            }
                            Text(mode.shortLabel)
                                .font(.system(.caption2, weight: .black))
                                .tracking(1.6)
                                .opacity(0.7)
                        }
                        .foregroundStyle(lab.mode == mode ? LabTone.canvas : LabTone.muted)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            lab.mode == mode ? LabTone.accent : LabTone.raised.opacity(0.6),
                            in: .rect(cornerRadius: 15)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(lab.mode == mode ? .clear : LabTone.hairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(lab.mode.detail)
                .font(.caption)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .labPanel()
    }

    private var productionNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Estás viendo la red demostrativa", systemImage: "info.circle.fill")
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(LabTone.cool)
            Text("El laboratorio conserva todo lo que construiste, pero las interfaces de conductor, supervisión, gerencia, taller, reclutamiento y dirección siguen leyendo los datos sembrados. Cambia a modo prueba para que el sistema arranque en cero y responda solo a lo que crees aquí.")
                .font(.footnote)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Entrar a modo prueba") {
                pendingMode = .test
                isModeChangePresented = true
            }
            .buttonStyle(LabButtonStyle(kind: .solid))
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - State of the world

    private var stateOfTheWorld: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LabCaps(text: "Estado del sistema de pruebas")
                Spacer(minLength: 0)
                LabChip(
                    text: lab.world.isEmpty ? "Vacío" : "\(lab.world.totalRecords) registros",
                    symbol: lab.world.isEmpty ? "circle.dashed" : "cylinder.split.1x2.fill",
                    tint: lab.world.isEmpty ? LabTone.muted : LabTone.good
                )
            }

            if lab.world.isEmpty {
                LabEmptyState(
                    title: "Todo en cero",
                    message: "No existe ninguna estación, usuario, unidad ni movimiento. Empieza creando una estación o carga un escenario completo.",
                    symbol: "circle.dashed",
                    actionTitle: "Cargar un escenario",
                    action: { path.append(.scenarios) }
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(lab.counters) { counter in
                        LabStat(
                            label: counter.label,
                            value: "\(counter.value)",
                            tint: counter.value == 0 ? LabTone.muted : .white,
                            symbol: counter.symbol
                        )
                    }
                }

                coverageBar
            }
        }
        .padding(16)
        .labPanel()
    }

    private var coverageBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LabCaps(text: "Cobertura de plantilla")
                Spacer(minLength: 0)
                Text("\(lab.world.activeDriverUsers.count) / \(lab.world.requiredDrivers)")
                    .font(.system(.caption, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(lab.world.driverDeficit > 0 ? LabTone.bad : LabTone.good)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LabTone.raised)
                    Capsule()
                        .fill(lab.world.driverDeficit > 0 ? LabTone.accent : LabTone.good)
                        .frame(width: proxy.size.width * min(1, Double(lab.world.coveragePct) / 100))
                }
            }
            .frame(height: 8)
            Text(
                lab.world.requiredDrivers == 0
                    ? "Sin unidades instaladas todavía: la plantilla requerida es cero."
                    : "\(lab.world.installedVehicles.count) unidades × \(lab.world.shiftConfig.driversPerVehicle) conductores = \(lab.world.requiredDrivers) requeridos. Faltan \(lab.world.driverDeficit)."
            )
            .font(.caption2)
            .foregroundStyle(LabTone.muted)
        }
    }

    private var alertsCard: some View {
        Group {
            if !lab.openAlerts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        LabCaps(text: "Alertas abiertas")
                        Spacer(minLength: 0)
                        Button("Ver todas") { path.append(.alerts) }
                            .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))
                    }
                    ForEach(lab.openAlerts.prefix(3)) { alert in
                        LabRow(
                            title: alert.title,
                            subtitle: alert.detail,
                            detail: "\(alert.level.label) · \(alert.audience.shortLabel)",
                            symbol: alert.level.symbol,
                            tint: LabTone.tone(for: alert.level)
                        )
                    }
                }
                .padding(16)
                .labPanel()
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabCaps(text: "Atajos")
            HStack(spacing: 8) {
                Button("Nueva estación") { path.append(.stations) }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Button("Nuevo usuario") { path.append(.users) }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                Button("Ver como…") { path.append(.system) }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
            }
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - Sections

    private var sectionsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabCaps(text: "Módulos del laboratorio")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(LabSection.allCases) { section in
                    Button {
                        path.append(section)
                    } label: {
                        LabSectionTile(section: section, badge: badge(for: section))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func badge(for section: LabSection) -> Int? {
        let value: Int
        switch section {
        case .stations: value = lab.world.stations.count
        case .users: value = lab.world.users.count
        case .vehicles: value = lab.world.vehicles.count
        case .humanResources: value = lab.world.employeeFiles.count
        case .recruitment: value = lab.world.prospects.count
        case .credits: value = lab.world.credits.count
        case .bonuses: value = lab.world.bonuses.count
        case .goals: value = lab.world.goals.count
        case .maintenance: value = lab.world.orders.count
        case .finance: value = lab.world.settlements.count
        case .documents: value = lab.world.documents.count
        case .alerts: value = lab.openAlerts.count
        case .audit: value = lab.auditEntries.count
        case .integrations: value = lab.world.uberFeeds.count + lab.world.telemetry.count + lab.world.transfers.count
        case .operation: value = lab.world.incidents.count
        case .coverage: value = 0
        case .visualEditor: value = editor.editedScreens.count
        case .scenarios, .system, .reset: return nil
        }
        return value > 0 ? value : nil
    }
}

private struct LabSectionTile: View {
    let section: LabSection
    var badge: Int?

    private var tint: Color { section.isDestructive ? LabTone.bad : LabTone.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Image(systemName: section.symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.13), in: .rect(cornerRadius: 11))
                Spacer(minLength: 0)
                if let badge {
                    Text("\(badge)")
                        .font(.system(.caption2, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(LabTone.canvas)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint, in: .capsule)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(section.label)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(section.caption)
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 118, alignment: .top)
        .padding(13)
        .labPanel(cornerRadius: 19)
    }
}

/// Sends every section to its screen.
struct LabSectionRouter: View {
    let section: LabSection

    var body: some View {
        switch section {
        case .system: LabSystemView()
        case .stations: LabStationsView()
        case .users: LabUsersView()
        case .vehicles: LabVehiclesView()
        case .humanResources: LabHumanResourcesView()
        case .recruitment: LabRecruitmentView()
        case .operation: LabOperationView()
        case .coverage: LabCoverageView()
        case .credits: LabCreditsView()
        case .bonuses: LabBonusesView()
        case .goals: LabGoalsView()
        case .maintenance: LabMaintenanceView()
        case .finance: LabFinanceView()
        case .documents: LabDocumentsView()
        case .alerts: LabAlertsView()
        case .integrations: LabIntegrationsView()
        case .scenarios: LabScenariosView()
        case .visualEditor: LabVisualEditorView()
        case .audit: LabAuditView()
        case .reset: LabResetView()
        }
    }
}
