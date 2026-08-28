//
//  TurnoEVApp.swift
//  TurnoEV
//
//  Created by Rork on August 16, 2026.
//

import SwiftUI

@main
struct TurnoEVApp: App {
    /// Foreground state of the app. It drives the clock beat and nothing else.
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = FleetStore()
    /// Owns the test environment. It is built before the first screen so every module
    /// already reads the right world.
    @State private var lab = LabStore()
    /// Cobertura de turnos. Shared by every role: the driver asks, the engine offers, the
    /// supervisor signs and Human Resources reads the trace, all off the same board.
    @State private var coverage = CoverageStore()
    /// Visual editor of the laboratory. It only wakes up for the test credential inside
    /// the test environment; for everybody else it is inert.
    @State private var visualEditor = VisualEditorStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(lab)
                .environment(coverage)
                .environment(visualEditor)
                // Dark only: the app is used while driving and saves battery.
                .preferredColorScheme(.dark)
                .tint(Palette.volt)
                .task {
                    lab.attach(fleet: store, coverage: coverage)
                    coverage.attach(fleet: store)
                    store.adoptEnvironment()

                    // A clock change arriving from another device has to re-evaluate the
                    // rules here too, without anybody refreshing a screen.
                    SharedClockSync.shared.onRemoteChange = { store.syncSimulationClock() }
                    SharedClockSync.shared.update(isTest: lab.isTest)

                    // The single producer of logical time. Started here and only here:
                    // one app, one beat, however many screens are mounted.
                    ClockBeat.shared.resume()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Nothing ticks in the background. On the way back the hour is
                    // recomputed from `AppClock.now()` — the anchored clock derives it
                    // exactly — instead of replaying the ticks that were missed.
                    switch phase {
                    case .active: ClockBeat.shared.resume()
                    case .inactive, .background: ClockBeat.shared.suspend()
                    @unknown default: ClockBeat.shared.suspend()
                    }
                }
                .onChange(of: lab.mode) { _, _ in
                    // The stores that hold state swap it in `LabStore.setMode`, which is
                    // the only door an environment changes through. What is left here is
                    // presentation: nothing that must happen for the data to be correct.
                    //
                    // `coverage.clear()` used to live here, and it wiped the production
                    // board — requests, vacancies, flags and all — every time anybody
                    // walked out of the laboratory.
                    //
                    // Production is never editable from a device.
                    if lab.mode == .production { visualEditor.deactivate() }
                    // Production has no shared clock: time there is real and untouchable.
                    SharedClockSync.shared.update(isTest: lab.isTest)
                }
        }
    }
}
