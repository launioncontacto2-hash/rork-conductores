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
        isSignedIn = false
    }
    func restoreSession() async { isSignedIn = await UberTestSession.shared.validToken() != nil }
    func signOut() async {
        await UberTestSession.shared.clearTokens()
        isSignedIn = false
        errorMessage = nil
    }
    func signIn(email: String, password: String) async {
        guard let baseURL, let publishableKey, !publishableKey.isEmpty else { errorMessage = "Configuración TEST incompleta."; return }
        guard let authURL = Self.authURL(baseURL: baseURL) else { errorMessage = AuthFailure.network.message; return }
        var request = URLRequest(url: authURL); request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthFailure.network }
            guard (200..<300).contains(http.statusCode) else {
                let apiError = try? JSONDecoder().decode(AuthErrorPayload.self, from: data)
                if apiError?.errorCode == "invalid_credentials" || http.statusCode == 400 {
                    throw AuthFailure.invalidCredentials
                }
                throw AuthFailure.http(http.statusCode)
            }
            let payload = try JSONDecoder().decode(AuthPayload.self, from: data)
            await UberTestSession.shared.save(accessToken: payload.accessToken, refreshToken: payload.refreshToken)
            errorMessage = nil
            isSignedIn = true
        } catch let failure as AuthFailure {
            errorMessage = failure.message
        } catch {
            errorMessage = AuthFailure.network.message
        }
    }
    static func authURL(baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        return components?.url
    }
    private enum AuthFailure: Error {
        case invalidCredentials
        case http(Int)
        case network
        var message: String {
            switch self {
            case .invalidCredentials: return "Correo o contraseña TEST incorrectos."
            case .http(let status): return "Supabase TEST respondió HTTP \(status)."
            case .network: return "No se pudo conectar con Supabase TEST."
            }
        }
    }
    private struct AuthPayload: Decodable { let accessToken: String; let refreshToken: String; enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case refreshToken = "refresh_token" } }
    private struct AuthErrorPayload: Decodable { let errorCode: String?; enum CodingKeys: String, CodingKey { case errorCode = "error_code" } }
    fileprivate static func read(account: String, service: String) -> String? { var item: CFTypeRef?; let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]; guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }; return String(data: data, encoding: .utf8) }
    fileprivate static func write(_ value: String, account: String, service: String) { let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]; SecItemDelete(query as CFDictionary); SecItemAdd(query.merging([kSecValueData as String:Data(value.utf8)]) { _, new in new } as CFDictionary, nil) }
}

private actor UberTestSession {
    static let shared = UberTestSession()
    private let baseURL = (Bundle.main.object(forInfoDictionaryKey: "UBER_TEST_SUPABASE_URL") as? String).flatMap(URL.init(string:))
    private let publishableKey = Bundle.main.object(forInfoDictionaryKey: "UBER_TEST_SUPABASE_PUBLISHABLE_KEY") as? String
    private var refreshTask: Task<String?, Never>?
    func save(accessToken: String, refreshToken: String) { Self.write(accessToken, account: "access-token"); Self.write(refreshToken, account: "refresh-token") }
    func clearTokens() { Self.clear(account: "access-token"); Self.clear(account: "refresh-token") }
    func validToken(force: Bool = false) async -> String? {
        if !force, let token = Self.read(account: "access-token"), let exp = Self.expiration(token), exp > Date().addingTimeInterval(60) { return token }
        guard let refresh = Self.read(account: "refresh-token"), let baseURL, let publishableKey, !publishableKey.isEmpty else { return nil }
        if let refreshTask { return await refreshTask.value }
        let task = Task { await Self.refresh(baseURL: baseURL, key: publishableKey, token: refresh) }
        refreshTask = task
        let token = await task.value
        refreshTask = nil
        if let token { return token }
        Self.clear(account: "access-token"); Self.clear(account: "refresh-token"); return nil
    }
    private static func refresh(baseURL: URL, key: String, token: String) async -> String? {
        var c = URLComponents(url: baseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false); c?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = c?.url else { return nil }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue(key, forHTTPHeaderField: "apikey"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": token])
        guard let (data, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        write(payload.accessToken, account: "access-token"); write(payload.refreshToken, account: "refresh-token"); return payload.accessToken
    }
    private struct Payload: Decodable { let accessToken: String; let refreshToken: String; enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case refreshToken = "refresh_token" } }
    private static func expiration(_ token: String) -> Date? { let p = token.split(separator: "."); guard p.count == 3 else { return nil }; var s = String(p[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); s += String(repeating: "=", count: (4 - s.count % 4) % 4); guard let d = Data(base64Encoded: s), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let e = o["exp"] as? TimeInterval else { return nil }; return Date(timeIntervalSince1970: e) }
    private static func read(account: String) -> String? { var item: CFTypeRef?; let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"uber.test.auth",kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]; guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }; return String(data: data, encoding: .utf8) }
    private static func write(_ value: String, account: String) { let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"uber.test.auth",kSecAttrAccount as String:account]; SecItemDelete(q as CFDictionary); SecItemAdd(q.merging([kSecValueData as String:Data(value.utf8)]) { _, new in new } as CFDictionary, nil) }
    private static func clear(account: String) { let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"uber.test.auth",kSecAttrAccount as String:account]; SecItemDelete(q as CFDictionary) }
}

private struct UberTestRuntimeConfiguration {
    let resultURL: URL?
    let batchURL: URL?
    let accessToken: @Sendable () async -> String?
    let refreshAccessToken: @Sendable () async -> String?

    init() {
        let configuredURL = Bundle.main.object(forInfoDictionaryKey: "UBER_TEST_SUPABASE_URL") as? String
        let legacyURL = UserDefaults.standard.string(forKey: "uber.test.supabase.url")
        let base = (configuredURL ?? legacyURL).flatMap(URL.init(string:))
        resultURL = base?.appendingPathComponent("functions/v1/uber-test-result")
        batchURL = base?.appendingPathComponent("functions/v1/uber-test-next")
        accessToken = { await UberTestSession.shared.validToken() }
        refreshAccessToken = { await UberTestSession.shared.validToken(force: true) }
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
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(UberTestAppDelegate.self) private var appDelegate
    @StateObject private var store: UberTestStore
    @StateObject private var auth = UberTestAuth()
    @StateObject private var receiver = UberTestReceiverState()
    private let runtime: UberTestRuntimeConfiguration

    init() {
        let runtime = UberTestRuntimeConfiguration()
        let receiver = UberTestReceiverState()
        self.runtime = runtime
        _receiver = StateObject(wrappedValue: receiver)
        let sink = runtime.resultURL.map { UberTestHTTPResultSink(functionURL: $0, accessToken: runtime.accessToken, refreshAccessToken: runtime.refreshAccessToken, installationID: receiver.installationID) }
        _store = StateObject(wrappedValue: UberTestStore(resultSink: sink))
    }

    var body: some Scene {
        WindowGroup {
            Group { if auth.isSignedIn { UberTestOfferView(store: store, receiver: receiver, signOut: { Task { receiver.stopHeartbeat(); await receiver.release(using: runtime.accessToken, refresh: runtime.refreshAccessToken); await auth.signOut() } }) } else { UberTestLoginView(auth: auth) } }
                .task(id: auth.isSignedIn) {
                    if !auth.isSignedIn { await auth.restoreSession() }
                    guard auth.isSignedIn else { return }
                    await receiver.claim(using: runtime.accessToken, refresh: runtime.refreshAccessToken)
                    receiver.startHeartbeat(using: runtime.accessToken, refresh: runtime.refreshAccessToken)
                    await UberTestPushCoordinator.registerForNotifications()
                    if let batchURL = runtime.batchURL {
                        let client = UberTestBatchClient(functionURL: batchURL, accessToken: runtime.accessToken, refreshAccessToken: runtime.refreshAccessToken, installationID: receiver.installationID)
                        await store.recover(using: client)
                        await store.startForegroundRecovery(using: client)
                    }
                }
                .onChange(of: scenePhase) { phase in
                    guard auth.isSignedIn else { return }
                    if phase == .active {
                        Task {
                            await receiver.claim(using: runtime.accessToken, refresh: runtime.refreshAccessToken)
                            receiver.startHeartbeat(using: runtime.accessToken, refresh: runtime.refreshAccessToken)
                            if let batchURL = runtime.batchURL {
                                let client = UberTestBatchClient(functionURL: batchURL, accessToken: runtime.accessToken, refreshAccessToken: runtime.refreshAccessToken, installationID: receiver.installationID)
                                await store.recover(using: client)
                                await store.startForegroundRecovery(using: client)
                            }
                        }
                    } else if phase == .background {
                        receiver.stopHeartbeat()
                        store.stopForegroundRecovery()
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
