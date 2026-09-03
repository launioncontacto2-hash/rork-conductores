import SwiftUI

/// Root router. The session role is the only thing that decides which interface is
/// built: driver, supervisor, regional manager, maintenance, recruitment or national
/// direction.
/// No screen of another role is ever instantiated inside a session.
struct ContentView: View {
    @Environment(FleetStore.self) private var store
    @Environment(LabStore.self) private var lab
    @Environment(VisualEditorStore.self) private var editor
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            // A backend session resolves to no directory account on purpose, so it is
            // routed by the role the server proved. Only roles with an authoritative
            // backend workspace are opened; every other role is refused rather than
            // silently routed into demonstration data.
            if let principal = store.currentPrincipal {
                if principal.role == .driver, store.hasAccess(to: .driver) {
                    RootTabView()
                } else if principal.role == .supervisor, store.hasAccess(to: .supervisor) {
                    BackendSupervisorAssignmentView(principal: principal)
                } else if principal.role == .maintenance, store.hasAccess(to: .maintenance) {
                    BackendMaintenanceView(principal: principal)
                } else {
                    AccessDeniedView()
                }
            } else {
                demonstrationWorkspace
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
            EnvironmentControl.observe(principal: store.currentPrincipal)

            let usesSharedClock = lab.isTest || store.isBackendTestSession
            SharedClockSync.shared.update(isTest: usesSharedClock)
            if store.isBackendTestSession {
                await SharedClockSync.shared.refresh()
                store.syncSimulationClock()
            }

            if store.currentPrincipal?.role == .driver {
                do {
                    try await store.refreshBackendOperationalState()
                } catch {
                    if SupabaseDriverDeviceService.isSessionReplacement(error) {
                        store.signOut()
                    }
                    print("[15D] No se pudo restaurar la operación: \(error.localizedDescription)")
                }
            }
        }
        // A second phone can take control while this one remains in the foreground.
        // Polling only this tiny lease endpoint keeps that window below 20 seconds; it
        // does not reload the assignment or the shift on every beat.
        .task(id: store.session?.startedAt) {
            guard store.currentPrincipal?.role == .driver else { return }

            while !Task.isCancelled,
                  store.currentPrincipal?.role == .driver {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }

                do {
                    try await SupabaseDriverDeviceService.heartbeat()
                } catch {
                    if SupabaseDriverDeviceService.isSessionReplacement(error) {
                        store.signOut()
                        return
                    }
                    // A transient network failure never signs a driver out. The next beat
                    // retries, while every protected mutation still verifies the lease.
                    print("[16A] Heartbeat pendiente: \(error.localizedDescription)")
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                if store.isBackendTestSession {
                    SharedClockSync.shared.update(isTest: true)
                    await SharedClockSync.shared.refresh()
                    store.syncSimulationClock()
                }

                guard store.currentPrincipal?.role == .driver else { return }
                do {
                    try await store.refreshBackendOperationalState()
                } catch {
                    if SupabaseDriverDeviceService.isSessionReplacement(error) {
                        store.signOut()
                    }
                    print("[15D] No se pudo actualizar la operación: \(error.localizedDescription)")
                }
            }
        }
    }

    /// The original router, untouched: every demonstration credential still opens exactly
    /// the interface it opened before.
    @ViewBuilder
    private var demonstrationWorkspace: some View {
        Group {
            switch store.currentAccount {
            case .none:
                LoginView()
            case .some(let account) where account.role == .driver:
                if store.hasAccess(to: .driver) {
                    // DIAGNÓSTICO TEMPORAL — `RootTabView` ya está restituido, pero el
                    // acceso flotante del editor sigue fuera: monta GeometryReader más
                    // tres stores y contaminaría la medición del contenedor. Original:
                    //
                    //     RootTabView()
                    //         .editorFloatingAccess(.driverShift)
                    RootTabView()
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
    }
}

/// Driver interface. Station notices live behind the bell in the shift header, not in the
/// tab bar.
///
/// Being signed in and being on shift are two different states: every tab here is the
/// driver's own profile and opens at any hour, with or without `activeShift`, inside the
/// start window or not. Only *starting* a shift is governed by `ShiftRules`.
struct RootTabView: View {
    @Environment(FleetStore.self) private var store
    @Environment(CoverageStore.self) private var coverage
    @State private var selection: Int = 0

    /// Seats this driver could take right now.
    ///
    /// Safe to read here. The chain — `availableGuards(for:)` → `evaluate(profile:vacancy:)`
    /// → `context(for:vacancy:)` — now touches only observable data: `vacancies`,
    /// `absences`, `policy`, `flags` and `store.driver`. The `now` that used to sit unused
    /// inside `EligibilityContext`, and that dragged the whole `TabView` onto
    /// `ClockSignal.generation`, was removed from the type itself rather than worked around
    /// here.
    ///
    /// So this count moves when the board moves, never when the hour does.
    private var availableGuardCount: Int {
        guard !store.usesBackendCoverageCycle else { return 0 }
        return coverage.availableGuards(for: coverage.profile(for: store.driver)).count
    }

    var body: some View {
        Group {
            if store.hasAccess(to: .driver) {
                // Values are fixed identities, not positions: the numbering was held while
                // Bonos was out precisely so restoring it renumbers nothing and cannot move
                // a driver to another tab.
                TabView(selection: $selection) {
                    Tab("Turno", systemImage: "gauge.with.dots.needle.bottom.50percent", value: 0) {
                        ShiftView()
                    }
                    Tab(value: 1) {
                        if let principal = store.currentPrincipal,
                           store.usesBackendCoverageCycle {
                            BackendDriverCoverageView(principal: principal)
                        } else {
                            DriverShiftsView()
                        }
                    } label: {
                        Label("Turnos", systemImage: "calendar")
                    }
                    // `badge(_: Int)` draws nothing at zero, which is exactly the wanted
                    // behaviour: no dot on a driver with nothing to take.
                    .badge(availableGuardCount)
                    Tab("Metas", systemImage: "target", value: 2) {
                        GoalsView()
                    }
                    Tab("Bonos", systemImage: "rosette", value: 3) {
                        BonusesView()
                    }
                    Tab("Cartera", systemImage: "banknote.fill", value: 4) {
                        if store.usesBackendFinancialCycle {
                            BackendDriverFinanceView()
                        } else {
                            WalletView()
                        }
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
