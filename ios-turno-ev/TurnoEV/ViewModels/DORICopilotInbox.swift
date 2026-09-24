import Foundation
import Observation
import Supabase
import AudioToolbox
import UIKit

@MainActor
final class DORICopilotPushCoordinator {
    static let shared = DORICopilotPushCoordinator()
    private var deviceToken: String?
    private var isShiftActive = false
    private let bundleID = Bundle.main.bundleIdentifier ?? "com.turnoev.mobility"

    func receivedDeviceToken(_ data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await registerIfReady() }
    }

    func setShiftActive(_ active: Bool) {
        guard active != isShiftActive else { return }
        isShiftActive = active
        if active { Task { await registerIfReady() } }
        else { revokeCurrentDevice() }
    }

    func receivedNotification(_ userInfo: [AnyHashable: Any]) {
        guard let dori = userInfo["dori"] as? [String: Any], let offerID = dori["offerId"] as? String else { return }
        NotificationCenter.default.post(name: .doriCopilotOfferReceived, object: nil, userInfo: ["offerId": offerID, "payload": dori])
    }

    private func registerIfReady() async {
        guard isShiftActive, let token = deviceToken, let client = SupabaseBridge.client else { return }
        struct Parameters: Encodable { let p_device_token: String; let p_bundle_id: String }
        do {
            try await client.rpc("register_dori_copilot_push_device", params: Parameters(p_device_token: token, p_bundle_id: bundleID)).execute()
        } catch {
            // Registration is best-effort while the TEST session is being restored.
        }
    }

    func revokeCurrentDevice() {
        guard let token = deviceToken, let client = SupabaseBridge.client else { return }
        struct Parameters: Encodable { let p_device_token: String; let p_bundle_id: String }
        Task { try? await client.rpc("revoke_dori_copilot_push_device", params: Parameters(p_device_token: token, p_bundle_id: bundleID)).execute() }
    }
}

extension Notification.Name {
    static let doriCopilotOfferReceived = Notification.Name("dori.copilot.offer.received")
}

@MainActor
@Observable
final class DORICopilotInbox {
    let store: DORICopilotStore
    var isOfferAlertPresented = false
    private var channel: RealtimeChannelV2?
    private var listenerTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var sessionKey: String?
    private var deliveryGate = DORICopilotDeliveryGate()

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
        channel = nil; sessionKey = nil; deliveryGate.reset()
    }

    func receiveAndAnnounce() async {
        let previous = store.simulationCaseId
        await store.receiveSimulationCase(silent: true)
        guard let current = store.simulationCaseId, current != previous, deliveryGate.accept(current) else { return }
        isOfferAlertPresented = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1007)
    }

    func dismissOffer() { isOfferAlertPresented = false }
}

struct DORICopilotDeliveryGate: Sendable {
    private(set) var activeCaseId: UUID?
    mutating func accept(_ id: UUID) -> Bool {
        guard activeCaseId != id else { return false }
        activeCaseId = id
        return true
    }
    mutating func reset() { activeCaseId = nil }
}
