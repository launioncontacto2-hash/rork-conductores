import SwiftUI

/// Root router. The session role is the only thing that decides which interface is
/// built: driver, supervisor, regional manager, maintenance, recruitment or national
/// direction.
/// No screen of another role is ever instantiated inside a session.
struct ContentView: View {
    @Environment(FleetStore.self) private var store
    @Environment(VisualEditorStore.self) private var editor

    var body: some View {
        Group {
            switch store.currentAccount {
            case .none:
                LoginView()
            case .some(let account) where account.role == .driver:
                if store.hasAccess(to: .driver) {
                    RootTabView()
                        .editorFloatingAccess(.driverShift)
                } else {
                    AccessDeniedView()
                }
            case .some(let account) where account.role == .supervisor:
                if store.hasAccess(to: .supervisor) {
                    SupervisorRootView(account: account, store: store)
                        .editorFloatingAccess(.supervisorHome)
                } else {
                    AccessDeniedView()
                }
            case .some(let account) where account.role == .manager:
                if store.hasAccess(to: .manager) {
                    ManagerRootView(account: account, store: store)
                        .editorFloatingAccess(.managerHome)
                } else {
                    AccessDeniedView()
                }
            case .some(let account) where account.role == .maintenance:
                if store.hasAccess(to: .maintenance) {
                    MaintenanceRootView(account: account, store: store)
                } else {
                    AccessDeniedView()
                }
            case .some(let account) where account.role == .recruiter:
                if store.hasAccess(to: .recruiter) {
                    RecruitmentRootView(account: account, store: store)
                } else {
                    AccessDeniedView()
                }
            case .some(let account) where account.role == .national:
                if store.hasAccess(to: .national) {
                    NationalRootView(account: account, store: store)
                } else {
                    AccessDeniedView()
                }
            case .some(let account) where account.role == .lab:
                if store.hasAccess(to: .lab) {
                    LabRootView(account: account)
                } else {
                    AccessDeniedView()
                }
            case .some(let account):
                RoleWorkspaceView(account: account)
            }
        }
        .labModeBanner()
        .animation(.smooth(duration: 0.35), value: store.session?.accountId)
        // The laboratory credential unlocks the editor and the simulation controls for
        // this device. Both stay unlocked while the administrator reviews the interface of
        // any other role through "Ver como…".
        .task(id: store.session?.accountId) {
            editor.observe(account: store.currentAccount)
            EnvironmentControl.observe(account: store.currentAccount)
        }
    }
}

/// Driver interface: five operational tabs. Station notices live behind the bell in
/// the shift header, not in the tab bar.
struct RootTabView: View {
    @Environment(FleetStore.self) private var store
    @Environment(CoverageStore.self) private var coverage
    @State private var selection: Int = 0

    /// Seats this driver could take right now, shown on the tab so an open guard is never
    /// missed while the person is on the floor.
    private var availableGuardCount: Int {
        coverage.availableGuards(for: coverage.profile(for: store.driver)).count
    }

    var body: some View {
        Group {
            if store.hasAccess(to: .driver) {
                TabView(selection: $selection) {
                    Tab("Turno", systemImage: "gauge.with.dots.needle.bottom.50percent", value: 0) {
                        ShiftView()
                    }
                    Tab(value: 1) {
                        DriverShiftsView()
                    } label: {
                        Label("Turnos", systemImage: "calendar")
                    }
                    .badge(availableGuardCount)
                    Tab("Metas", systemImage: "target", value: 2) {
                        GoalsView()
                    }
                    Tab("Bonos", systemImage: "rosette", value: 3) {
                        BonusesView()
                    }
                    Tab("Cartera", systemImage: "banknote.fill", value: 4) {
                        WalletView()
                    }
                    Tab("Historial", systemImage: "list.clipboard.fill", value: 5) {
                        HistoryView()
                    }
                }
                .tint(Palette.volt)
            } else {
                AccessDeniedView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(FleetStore())
        .environment(LabStore())
        .environment(CoverageStore())
        .preferredColorScheme(.dark)
}
