import Foundation
import Observation
import Supabase
import AudioToolbox
import UIKit

@MainActor
@Observable
final class DORICopilotInbox {
    let store: DORICopilotStore
    var isOfferAlertPresented = false
    private var channel: RealtimeChannelV2?
    private var listenerTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var sessionKey: String?

    init(store: DORICopilotStore = DORICopilotStore()) { self.store = store }

    func start(environmentID: UUID?) {
        guard let environmentID, sessionKey != environmentID.uuidString else { return }
        stop()
        sessionKey = environmentID.uuidString
        if let client = SupabaseBridge.client {
            let channel = client.channel("dori-copilot-simulation-\(environmentID.uuidString.lowercased())")
            self.channel = channel
            let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "dori_copilot_simulation_cases")
            listenerTask = Task { [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled else { return }
                    await self?.receiveAndAnnounce()
                }
            }
            Task { await channel.subscribe() }
        }
        fallbackTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.receiveAndAnnounce()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        listenerTask?.cancel(); fallbackTask?.cancel()
        listenerTask = nil; fallbackTask = nil
        if let channel { Task { await channel.unsubscribe() } }
        channel = nil; sessionKey = nil
    }

    func receiveAndAnnounce() async {
        let previous = store.simulationCaseId
        await store.receiveSimulationCase(silent: true)
        guard let current = store.simulationCaseId, current != previous else { return }
        isOfferAlertPresented = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1007)
    }

    func dismissOffer() { isOfferAlertPresented = false }
}
