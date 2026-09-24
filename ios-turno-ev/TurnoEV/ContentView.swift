import SwiftUI

/// Root router. The session role is the only thing that decides which interface is
/// built. DORI exposes the operational driver, supervisor and maintenance surfaces plus
/// the isolated acquisition workspace; later organizational modules remain frozen.
/// No screen of another role is ever instantiated inside a session.
struct ContentView: View {
    @Environment(FleetStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        routedContent
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

    @ViewBuilder
    private var routedContent: some View {
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
            } else if principal.role == .recruiter, store.hasAccess(to: .recruiter) {
                BackendRecruitmentView(principal: principal)
            } else if AcquisitionNavigation.destination(for: principal.role) != nil,
                      store.hasAccess(to: principal.role) {
                AcquisitionRootView(principal: principal)
            } else {
                AccessDeniedView()
            }
        } else {
            LoginView()
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Int = 0
    @State private var copilotInbox = DORICopilotInbox()

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
                .environment(copilotInbox.store)
                .overlay {
                    if copilotInbox.isOfferAlertPresented { DORICopilotOfferAlert(inbox: copilotInbox) }
                }
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
        .task(id: "\(store.currentPrincipal?.environmentId ?? ""):\(store.activeShift?.id ?? "")") {
            guard store.currentPrincipal?.role == .driver, store.isBackendTestSession,
                  store.activeShift != nil,
                  let environment = store.currentPrincipal?.environmentId,
                  let environmentID = UUID(uuidString: environment) else {
                copilotInbox.stop()
                return
            }
            copilotInbox.start(environmentID: environmentID)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.activeShift != nil { Task { await copilotInbox.receiveAndAnnounce() } }
        }
    }
}

private struct DORICopilotOfferAlert: View {
    @Bindable var inbox: DORICopilotInbox

    var body: some View {
        VStack(spacing: 12) {
            Label("NUEVA OFERTA", systemImage: "bell.badge.fill")
                .font(.system(.headline, weight: .black))
                .foregroundStyle(Palette.volt)
            Text(inbox.store.simulationMessage ?? "DORI está leyendo la oferta.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.text)
            if let result = inbox.store.state.result {
                Text(result.recommendation.rawValue)
                    .font(.system(.title, weight: .black))
                    .foregroundStyle(result.recommendation == .recommended ? Palette.volt : Palette.danger)
                ForEach(Array(result.reasons.prefix(3).enumerated()), id: \.offset) { _, reason in
                    Text(reason).font(.caption).foregroundStyle(Palette.textMuted)
                }
                HStack {
                    Button("TOMAR") { inbox.store.confirmDecision(true); inbox.dismissOffer() }
                        .buttonStyle(.borderedProminent).tint(Palette.volt)
                    Button("NO TOMAR") { inbox.store.confirmDecision(false); inbox.dismissOffer() }
                        .buttonStyle(.bordered).tint(Palette.surfaceRaised)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 360)
        .background(Palette.surfaceRaised, in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(Palette.volt.opacity(0.65), lineWidth: 1) }
        .shadow(radius: 20)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black.opacity(0.25))
        .accessibilityAddTraits(.isModal)
    }
}
#Preview {
    ContentView()
        .environment(FleetStore())
        .environment(LabStore())
        .environment(CoverageStore())
        .preferredColorScheme(.dark)
}
