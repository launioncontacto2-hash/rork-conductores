//
//  TurnoEVApp.swift
//  TurnoEV
//
//  Created by Rork on August 16, 2026.
//

import SwiftUI

@main
struct TurnoEVApp: App {
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
                    lab.attach(fleet: store)
                    coverage.attach(fleet: store)
                    store.adoptEnvironment()
                }
                .onChange(of: lab.mode) { _, _ in
                    // Test and production never share coverage records.
                    coverage.clear()
                    // Production is never editable from a device.
                    if lab.mode == .production { visualEditor.deactivate() }
                }
        }
    }
}
