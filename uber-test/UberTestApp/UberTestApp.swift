import SwiftUI
import UIKit
import UserNotifications
import Security

private struct UberTestRuntimeConfiguration {
    let resultURL: URL?
    let batchURL: URL?
    let accessToken: @Sendable () async -> String?

    init() {
        let configuredURL = Bundle.main.object(forInfoDictionaryKey: "UBER_TEST_SUPABASE_URL") as? String
        let legacyURL = UserDefaults.standard.string(forKey: "uber.test.supabase.url")
        let base = (configuredURL ?? legacyURL).flatMap(URL.init(string:))
        resultURL = base?.appendingPathComponent("functions/v1/uber-test-result")
        batchURL = base?.appendingPathComponent("functions/v1/uber-test-next")
        accessToken = {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "uber.test.auth",
                kSecAttrAccount as String: "access-token",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}

final class UberTestAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: Notification.Name("UberTest.deviceToken"), object: deviceToken)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if let batch = UberTestPushCoordinator.decodeBatch(from: notification.request.content.userInfo) {
            NotificationCenter.default.post(name: UberTestPushCoordinator.batchNotification, object: batch)
        }
        return [.banner, .sound, .badge]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let batch = UberTestPushCoordinator.decodeBatch(from: response.notification.request.content.userInfo) {
            NotificationCenter.default.post(name: UberTestPushCoordinator.batchNotification, object: batch)
        }
    }
}

@main
struct UberTestApp: App {
    @UIApplicationDelegateAdaptor(UberTestAppDelegate.self) private var appDelegate
    @StateObject private var store: UberTestStore
    private let runtime: UberTestRuntimeConfiguration

    init() {
        let runtime = UberTestRuntimeConfiguration()
        self.runtime = runtime
        let sink = runtime.resultURL.map { UberTestHTTPResultSink(functionURL: $0, accessToken: runtime.accessToken) }
        _store = StateObject(wrappedValue: UberTestStore(resultSink: sink))
    }

    var body: some Scene {
        WindowGroup {
            UberTestOfferView(store: store)
                .task {
                    await UberTestPushCoordinator.registerForNotifications()
                    if let batchURL = runtime.batchURL {
                        await store.recover(using: UberTestBatchClient(functionURL: batchURL, accessToken: runtime.accessToken))
                        await store.startForegroundRecovery(using: UberTestBatchClient(functionURL: batchURL, accessToken: runtime.accessToken))
                    }
                }
        }
    }
}
