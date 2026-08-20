import SwiftUI

/// Recruitment interface of one station. Every station runs its own desk, so this whole
/// module only ever reads the vacancies, leads and candidates of `account.stationId`.
/// Five tabs: el tablero de demanda, la bandeja de leads, los candidatos, la agenda y el
/// análisis. Vacantes vive dentro del inicio porque no es una lista: es la razón de
/// existir del área.
struct RecruitmentRootView: View {
    @Environment(FleetStore.self) private var fleet

    let account: StaffAccount

    @State private var recruit: RecruitmentStore
    @State private var tab: RecruitTab = .home
    @State private var analyticsTab: RecruitAnalyticsTab = .pipeline
    @State private var prospectFilter: RecruitStage?
    @State private var route: RecruitRoute?

    init(account: StaffAccount, store: FleetStore) {
        self.account = account
        _recruit = State(initialValue: RecruitmentStore(account: account, fleet: store))
    }

    enum RecruitTab: Int, Hashable {
        case home
        case leads
        case prospects
        case appointments
        case analytics
    }

    private enum RecruitRoute: Identifiable, Hashable {
        case prospect(String)
        case vacancies
        case alerts

        var id: String {
            switch self {
            case .prospect(let id): "prospect-\(id)"
            case .vacancies: "vacancies"
            case .alerts: "alerts"
            }
        }
    }

    private var header: RecruitHeader {
        RecruitHeader(
            account: account,
            station: recruit.stations.first,
            now: fleet.now,
            vacancies: recruit.totalVacancies,
            alertCount: recruit.alerts.count,
            onRegenerate: { recruit.regenerate() },
            onOpenAlerts: { route = .alerts }
        )
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inicio", systemImage: "square.grid.2x2.fill", value: RecruitTab.home) {
                RecruitHomeView(
                    recruit: recruit,
                    header: header,
                    onOpenLeads: { tab = .leads },
                    onOpenProspects: { stage in
                        prospectFilter = stage
                        tab = .prospects
                    },
                    onOpenAppointments: { tab = .appointments },
                    onOpenVacancies: { route = .vacancies },
                    onOpenAnalytics: { section in
                        analyticsTab = section
                        tab = .analytics
                    },
                    onOpenAlerts: { route = .alerts }
                )
            }

            Tab(value: RecruitTab.leads) {
                RecruitLeadsView(
                    recruit: recruit,
                    header: header,
                    onOpenProspect: { route = .prospect($0) }
                )
            } label: {
                Label("Leads", systemImage: "sparkles")
            }
            .badge(recruit.count(stage: .lead))

            Tab(value: RecruitTab.prospects) {
                RecruitProspectsView(
                    recruit: recruit,
                    header: header,
                    initialStage: prospectFilter,
                    onOpenProspect: { route = .prospect($0) }
                )
                .id(prospectFilter?.rawValue ?? "all")
            } label: {
                Label("Candidatos", systemImage: "person.3.fill")
            }
            .badge(recruit.awaitingDocuments.count + recruit.readyToHire.count)

            Tab(value: RecruitTab.appointments) {
                RecruitAppointmentsView(
                    recruit: recruit,
                    header: header,
                    onOpenProspect: { route = .prospect($0) }
                )
            } label: {
                Label("Citas", systemImage: "calendar")
            }
            .badge(recruit.todayAppointments.count)

            Tab("Análisis", systemImage: "chart.bar.xaxis", value: RecruitTab.analytics) {
                RecruitAnalyticsView(recruit: recruit, header: header, tab: $analyticsTab)
            }
        }
        .tint(RecTone.accent)
        .task { recruit.refresh() }
        .onChange(of: fleet.clockOffsetMinutes) { _, _ in recruit.refresh() }
        .onChange(of: tab) { _, _ in recruit.refresh() }
        .sheet(item: $route) { route in
            switch route {
            case .prospect(let id):
                ProspectDetailView(recruit: recruit, prospectId: id)
            case .vacancies:
                NavigationStack {
                    RecruitVacanciesView(recruit: recruit, header: header)
                        .navigationTitle("Vacantes")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(Palette.canvas, for: .navigationBar)
                }
            case .alerts:
                RecruitAlertsView(recruit: recruit) { destination in
                    self.route = nil
                    open(destination)
                }
            }
        }
    }

    private func open(_ destination: RecruitDestination) {
        switch destination {
        case .leads: tab = .leads
        case .prospects:
            prospectFilter = nil
            tab = .prospects
        case .appointments: tab = .appointments
        case .vacancies:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                route = .vacancies
            }
        case .campaigns:
            analyticsTab = .campaigns
            tab = .analytics
        case .pipeline:
            analyticsTab = .pipeline
            tab = .analytics
        }
    }
}

/// Every exception of the recruitment desk in one board, ordered by gravity.
struct RecruitAlertsView: View {
    let recruit: RecruitmentStore
    let onOpen: (RecruitDestination) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                RecruitmentBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        if recruit.alerts.isEmpty {
                            NoticeBanner(
                                symbol: "checkmark.seal.fill",
                                title: "Sin alertas abiertas",
                                message: "Cobertura, tiempos de contacto, agenda y documentación dentro de los umbrales.",
                                tone: .volt
                            )
                        } else {
                            ForEach(recruit.alerts) { alert in
                                RecruitAlertCard(
                                    alert: alert,
                                    onOpen: {
                                        onOpen(alert.destination)
                                        dismiss()
                                    },
                                    onReview: { recruit.reviewAlert(id: alert.id) }
                                )
                            }
                        }

                        Button("Restaurar alertas revisadas") {
                            recruit.restoreAlerts()
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
            .navigationTitle("Alertas de reclutamiento")
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
