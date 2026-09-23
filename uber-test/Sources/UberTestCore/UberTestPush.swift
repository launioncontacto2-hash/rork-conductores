import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

public enum UberTestPushCoordinator {
    public static let batchNotification = Notification.Name("UberTest.batch.received")

    public static func registerForNotifications() async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
        #if canImport(UIKit)
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        #endif
    }

    public static func decodeBatch(from userInfo: [AnyHashable: Any]) -> UberTestOfferBatch? {
        guard let rawPayload = userInfo["uber_test_batch"] as? [AnyHashable: Any] else { return nil }
        let payload = rawPayload.reduce(into: [String: Any]()) { result, item in result[String(describing: item.key)] = item.value }
        guard JSONSerialization.isValidJSONObject(payload), let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return try? JSONDecoder.uberTest.decode(UberTestOfferBatch.self, from: data)
    }
}

private extension JSONDecoder {
    static var uberTest: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}
