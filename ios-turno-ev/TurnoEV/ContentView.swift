import SwiftUI

/// Root router. The session role is the only thing that decides which interface is
/// built. DORI currently exposes only the operational driver, supervisor and maintenance
/// surfaces; later organizational modules remain compiled but frozen and unreachable.
/// No screen of another role is ever instantiated inside a session.
struct ContentView: View {
    @Environment(FleetStore.self) private var store
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
                // A local account left by an earlier demonstration build is never an
                // authority in DORI. Without a principal proved by Supabase, the only
                // reachable surface is the real sign-in door.
                LoginView()
            }
        }
        .labModeBanner()
        .animation(.smooth(duration: 0.35), value: store.session?.accountId)
        .task(id: store.session?.accountId) {
            EnvironmentControl.observe(principal: store.currentPrincipal)

            SharedClockSync.shared.update(isTest: store.isBackendTestSession)
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
        // A second phone can take control while this one remains in the foreground. The
        // same 20-second beat also adopts assignments, incidents, the open shift, finances
        // and history written by supervision or Consola DORI. Supabase remains the only
        // source of truth; this device never fabricates an intermediate state.
        .task(id: store.session?.startedAt) {
            guard store.currentPrincipal?.role == .driver else { return }

            while !Task.isCancelled,
                  store.currentPrincipal?.role == .driver {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }

                do {
                    try await store.refreshBackendOperationalState()
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
                    Tab("Finanzas", systemImage: "banknote.fill", value: 3) {
                        if store.usesBackendFinancialCycle {
                            BackendDriverFinanceView()
                        } else {
                            WalletView()
                        }
                    }
                    Tab("Historial", systemImage: "list.clipboard.fill", value: 4) {
                        HistoryView()
                    }
                }
                .tint(Palette.volt)
                .safeAreaInset(edge: .top) {
                    if store.backendOperationalError != nil {
                        HStack(spacing: 10) {
                            Image(systemName: "wifi.exclamationmark")
                                .foregroundStyle(Palette.amber)
                            Text("Sincronización pendiente. Las operaciones seguirán protegidas por el servidor.")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(store.isBackendRefreshing ? "Conectando…" : "Reintentar") {
                                Task { try? await store.refreshBackendOperationalState() }
                            }
                            .font(.system(.caption, weight: .bold))
                            .disabled(store.isBackendRefreshing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Palette.surfaceRaised)
                        .overlay(alignment: .bottom) {
                            Divider().overlay(Palette.hairline)
                        }
                    }
                }
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
