import SwiftUI
import UIKit
import UserNotifications
import Security

@MainActor
final class UberTestAuth: ObservableObject {
    @Published private(set) var isSignedIn: Bool
    @Published var errorMessage: String?
    private let service = "uber.test.auth"
    private let baseURL: URL?
    private let publishableKey: String?
    init() {
        baseURL = (Bundle.main.object(forInfoDictionaryKey: "UBER_TEST_SUPABASE_URL") as? String).flatMap(URL.init(string:))
        publishableKey = Bundle.main.object(forInfoDictionaryKey: "UBER_TEST_SUPABASE_PUBLISHABLE_KEY") as? String
        isSignedIn = Self.read(account: "access-token", service: service) != nil
    }
    func signIn(email: String, password: String) async {
        guard let baseURL, let publishableKey, !publishableKey.isEmpty else { errorMessage = "Configuración TEST incompleta."; return }
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/v1/token?grant_type=password")); request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        do { let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.userAuthenticationRequired) }; let payload = try JSONDecoder().decode(AuthPayload.self, from: data); Self.write(payload.accessToken, account: "access-token", service: service); Self.write(payload.refreshToken, account: "refresh-token", service: service); errorMessage = nil; isSignedIn = true } catch { errorMessage = "No se pudo iniciar sesión en TEST." }
    }
    private struct AuthPayload: Decodable { let accessToken: String; let refreshToken: String; enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case refreshToken = "refresh_token" } }
    private static func read(account: String, service: String) -> String? { var item: CFTypeRef?; let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]; guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }; return String(data: data, encoding: .utf8) }
    private static func write(_ value: String, account: String, service: String) { let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]; SecItemDelete(query as CFDictionary); SecItemAdd(query.merging([kSecValueData as String:Data(value.utf8)]) { _, new in new } as CFDictionary, nil) }
}

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
    @StateObject private var auth = UberTestAuth()
    private let runtime: UberTestRuntimeConfiguration

    init() {
        let runtime = UberTestRuntimeConfiguration()
        self.runtime = runtime
        let sink = runtime.resultURL.map { UberTestHTTPResultSink(functionURL: $0, accessToken: runtime.accessToken) }
        _store = StateObject(wrappedValue: UberTestStore(resultSink: sink))
    }

    var body: some Scene {
        WindowGroup {
            Group { if auth.isSignedIn { UberTestOfferView(store: store) } else { UberTestLoginView(auth: auth) } }
                .task {
                    guard auth.isSignedIn else { return }
                    await UberTestPushCoordinator.registerForNotifications()
                    if let batchURL = runtime.batchURL {
                        await store.recover(using: UberTestBatchClient(functionURL: batchURL, accessToken: runtime.accessToken))
                        await store.startForegroundRecovery(using: UberTestBatchClient(functionURL: batchURL, accessToken: runtime.accessToken))
                    }
                }
        }
    }
}

private struct UberTestLoginView: View {
    @ObservedObject var auth: UberTestAuth
    @State private var email = ""
    @State private var password = ""
    var body: some View { VStack(spacing: 20) { Text("UBER test").font(.system(size: 42, weight: .bold, design: .rounded)); Text("Acceso de conductor TEST").foregroundStyle(.secondary); TextField("Correo", text: $email).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder).keyboardType(.emailAddress); SecureField("Contraseña", text: $password).textFieldStyle(.roundedBorder); Button("ENTRAR A TEST") { Task { await auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) } }.buttonStyle(.borderedProminent).disabled(email.isEmpty || password.isEmpty); if let error = auth.errorMessage { Text(error).foregroundStyle(.red) } }.padding(28).frame(maxWidth: 440).background(.black).foregroundStyle(.white) }
}
