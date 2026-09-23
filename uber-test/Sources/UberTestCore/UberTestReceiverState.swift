import Foundation
import SwiftUI

@MainActor
public final class UberTestReceiverState: ObservableObject {
    @Published public private(set) var displayName = "—"
    @Published public private(set) var employeeNumber = "—"
    @Published public private(set) var isActive = false
    @Published public private(set) var linkState = "ESPERANDO DORI"
    public let installationID: String
    private let baseURL: URL?
    public init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "uber.test.installation.id") { installationID = saved }
        else { let value = UUID().uuidString.lowercased(); defaults.set(value, forKey: "uber.test.installation.id"); installationID = value }
        baseURL = (Bundle.main.object(forInfoDictionaryKey: "UBER_TEST_SUPABASE_URL") as? String).flatMap(URL.init(string:))
    }
    public func claim(using token: String?) async { await call("uber_test_claim_receiver", token: token, body: ["p_installation_id": installationID, "p_app_version": "1.0.0"]) }
    public func release(using token: String?) async { await call("uber_test_release_receiver", token: token, body: ["p_installation_id": installationID]) }
    private func call(_ function: String, token: String?, body: [String: String]) async {
        guard let token, let baseURL, let url = URL(string: "rest/v1/rpc/\(function)", relativeTo: baseURL) else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue(token, forHTTPHeaderField: "apikey"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { isActive = false; linkState = "ENLACE INTERRUMPIDO"; return }
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { displayName = payload["displayName"] as? String ?? displayName; employeeNumber = payload["employeeNumber"] as? String ?? employeeNumber; isActive = payload["activeReceiver"] as? Bool ?? false; linkState = "ESPERANDO DORI" }
    }
}
