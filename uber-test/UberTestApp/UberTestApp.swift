import SwiftUI
import UIKit
import UserNotifications

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
    @StateObject private var store = UberTestStore()
    var body: some Scene { WindowGroup { UberTestOfferView(store: store).task { await UberTestPushCoordinator.registerForNotifications() } } }
}
