import Foundation
import Observation
import UIKit
import UserNotifications

nonisolated enum AcquisitionPushDestination: Codable, Equatable, Sendable {
    case offer(UUID)
    case chat(threadID: UUID, offerID: UUID?)
    case request(UUID)
}

@MainActor
@Observable
final class AcquisitionPushCoordinator {
    static let shared = AcquisitionPushCoordinator()

    private let destinationKey = "dori.acquisition.pending-push-destination"
    private var deviceToken: String?
    private var membership: AcquisitionMembership?
    private var repository: (any AcquisitionRepository)?
    private var registeredToken: String?
    private(set) var pendingDestination: AcquisitionPushDestination?
    private(set) var authorizationDenied = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: destinationKey) {
            pendingDestination = try? JSONDecoder().decode(AcquisitionPushDestination.self, from: data)
        }
    }

    func activate(membership: AcquisitionMembership, repository: any AcquisitionRepository) async {
        // This delivery is deliberately TEST-only. A production membership can
        // never register against the APNs configuration introduced in this cut.
        guard let testEnvironmentID = LabEnvironment.sharedTestUUID,
              membership.environmentID == testEnvironmentID else { return }
        self.membership = membership
        self.repository = repository
        let center = UNUserNotificationCenter.current()
        do {
            let settings = await center.notificationSettings()
            var granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            }
            authorizationDenied = !granted
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
            await registerIfReady()
            await refreshBadge()
        } catch {
            authorizationDenied = true
        }
    }

    func receivedDeviceToken(_ data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await registerIfReady() }
    }

    func receivedRegistrationError(_ error: Error) {
        print("[Adquisiciones][Push] No se pudo registrar APNs: \(type(of: error))")
    }

    func receivedNotification(_ userInfo: [AnyHashable: Any]) {
        guard let payload = userInfo["dori"] as? [String: Any],
              let destination = Self.destination(from: payload) else { return }
        pendingDestination = destination
        persist(destination)
    }

    func consume(_ destination: AcquisitionPushDestination) async {
        guard pendingDestination == destination else { return }
        pendingDestination = nil
        UserDefaults.standard.removeObject(forKey: destinationKey)
        await markRead(destination)
    }

    func markRead(_ destination: AcquisitionPushDestination) async {
        guard let repository else { return }
        let context: (String, UUID)
        switch destination {
        case .offer(let id): context = ("offer", id)
        case .chat(let threadID, _): context = ("thread", threadID)
        case .request(let id): context = ("request", id)
        }
        try? await repository.markNotificationContextRead(type: context.0, id: context.1)
        await refreshBadge()
    }

    func refreshBadge() async {
        guard let repository else { return }
        if let count = try? await repository.notificationBadgeCount() {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }

    func revokeCurrentDevice() async {
        guard let deviceToken, let repository else { return }
        try? await repository.revokePushDevice(token: deviceToken)
        registeredToken = nil
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    private func registerIfReady() async {
        guard let membership,
              let testEnvironmentID = LabEnvironment.sharedTestUUID,
              membership.environmentID == testEnvironmentID,
              let repository, let deviceToken, registeredToken != deviceToken,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        do {
            try await repository.registerPushDevice(
                token: deviceToken,
                appEnvironment: "test",
                bundleID: bundleID
            )
            registeredToken = deviceToken
        } catch {
            print("[Adquisiciones][Push] Registro TEST pendiente: \(type(of: error))")
        }
    }

    private func persist(_ destination: AcquisitionPushDestination) {
        if let data = try? JSONEncoder().encode(destination) {
            UserDefaults.standard.set(data, forKey: destinationKey)
        }
    }

    nonisolated static func destination(from payload: [String: Any]) -> AcquisitionPushDestination? {
        guard let kind = payload["kind"] as? String else { return nil }
        switch kind {
        case "offer":
            return (payload["offer_id"] as? String)
                .flatMap(UUID.init(uuidString:))
                .map { .offer($0) }
        case "chat_general", "chat_unit":
            guard let threadID = (payload["thread_id"] as? String).flatMap(UUID.init(uuidString:)) else {
                return nil
            }
            let offerID = (payload["offer_id"] as? String).flatMap(UUID.init(uuidString:))
            return .chat(threadID: threadID, offerID: offerID)
        case "request":
            return (payload["request_id"] as? String)
                .flatMap(UUID.init(uuidString:))
                .map { .request($0) }
        default:
            return nil
        }
    }
}

final class AcquisitionAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            Task { @MainActor in
                AcquisitionPushCoordinator.shared.receivedNotification(remote)
                DORICopilotPushCoordinator.shared.receivedNotification(remote)
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            AcquisitionPushCoordinator.shared.receivedDeviceToken(deviceToken)
            DORICopilotPushCoordinator.shared.receivedDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            AcquisitionPushCoordinator.shared.receivedRegistrationError(error)
            DORICopilotPushCoordinator.shared.receivedRegistrationError(error)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        await MainActor.run {
            DORICopilotPushCoordinator.shared.receivedNotification(userInfo)
        }
        return [.banner, .sound, .badge, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            AcquisitionPushCoordinator.shared.receivedNotification(
                response.notification.request.content.userInfo
            )
            DORICopilotPushCoordinator.shared.receivedNotification(
                response.notification.request.content.userInfo
            )
        }
    }
}
