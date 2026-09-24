import Foundation
import SwiftUI

@MainActor
public final class UberTestReceiverState: ObservableObject {
    public enum LinkStatus: String, Sendable {
        case waiting, linked, interrupted

        public var label: String {
            switch self {
            case .waiting: return "ESPERANDO DORI"
            case .linked: return "DORI ENLAZADO"
            case .interrupted: return "ENLACE INTERRUMPIDO"
            }
        }
    }
    @Published public private(set) var displayName = "—"
    @Published public private(set) var employeeNumber = "—"
    @Published public private(set) var isActive = false
    @Published public private(set) var receiverState = "SIN CONEXIÓN"
    @Published public private(set) var linkState = "ESPERANDO DORI"
    public let installationID: String
    private let baseURL: URL?
    private let publishableKey: String?
    private var heartbeatTask: Task<Void, Never>?
    public init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "uber.test.installation.id") { installationID = saved }
        else { let value = UUID().uuidString.lowercased(); defaults.set(value, forKey: "uber.test.installation.id"); installationID = value }
        baseURL = (Bundle.main.object(forInfoDictionaryKey: "UBER_TEST_SUPABASE_URL") as? String).flatMap(URL.init(string:))
        publishableKey = Bundle.main.object(forInfoDictionaryKey: "UBER_TEST_SUPABASE_PUBLISHABLE_KEY") as? String
    }
    public func claim(using token: @escaping @Sendable () async -> String?, refresh: (@Sendable () async -> String?)? = nil) async { await call("uber_test_claim_receiver", token: token, refresh: refresh, body: ["p_installation_id": installationID, "p_app_version": "1.0.0"]) }
    public func heartbeat(using token: @escaping @Sendable () async -> String?, refresh: (@Sendable () async -> String?)? = nil) async { await call("uber_test_heartbeat_receiver", token: token, refresh: refresh, body: ["p_installation_id": installationID]) }
    public func release(using token: @escaping @Sendable () async -> String?, refresh: (@Sendable () async -> String?)? = nil) async { await call("uber_test_release_receiver", token: token, refresh: refresh, body: ["p_installation_id": installationID]) }
    private func call(_ function: String, token: @escaping @Sendable () async -> String?, refresh: (@Sendable () async -> String?)?, body: [String: String]) async {
        guard let token = await token() else { uberTestNotifySessionTerminated(); reset(); return }
        guard let baseURL, let publishableKey, !publishableKey.isEmpty, let url = URL(string: "rest/v1/rpc/\(function)", relativeTo: baseURL) else { isActive = false; receiverState = "SIN CONEXIÓN"; return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue(publishableKey, forHTTPHeaderField: "apikey"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var bearer = token
        var (data, response) = (try? await URLSession.shared.data(for: request)) ?? (Data(), URLResponse())
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            guard let refresh, let refreshed = await refresh() else { uberTestNotifySessionTerminated(); reset(); return }
            bearer = refreshed
            request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization"); request.setValue(publishableKey, forHTTPHeaderField: "apikey"); (data, response) = (try? await URLSession.shared.data(for: request)) ?? (Data(), URLResponse())
            if (response as? HTTPURLResponse)?.statusCode == 401 { uberTestNotifySessionTerminated(); reset(); return }
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { isActive = false; receiverState = "SIN CONEXIÓN"; return }
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { displayName = payload["displayName"] as? String ?? displayName; employeeNumber = payload["employeeNumber"] as? String ?? employeeNumber; isActive = payload["activeReceiver"] as? Bool ?? false; receiverState = isActive ? "ACTIVO" : "INACTIVO" }
        if function != "uber_test_release_receiver" { await refreshLinkStatus(token: bearer, refresh: refresh) }
    }

    private func refreshLinkStatus(token: String, refresh: (@Sendable () async -> String?)?) async {
        guard let baseURL, let publishableKey, !publishableKey.isEmpty,
              let url = URL(string: "rest/v1/rpc/get_dori_copilot_link_status", relativeTo: baseURL) else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue(publishableKey, forHTTPHeaderField: "apikey"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = Data("{}".utf8)
        var (data, response) = (try? await URLSession.shared.data(for: request)) ?? (Data(), URLResponse())
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            guard let refresh, let refreshed = await refresh() else { uberTestNotifySessionTerminated(); reset(); return }
            request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
            (data, response) = (try? await URLSession.shared.data(for: request)) ?? (Data(), URLResponse())
            if (response as? HTTPURLResponse)?.statusCode == 401 { uberTestNotifySessionTerminated(); reset(); return }
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let status = Self.decodeLinkStatus(data) else { linkState = LinkStatus.interrupted.label; return }
        linkState = status.label
    }

    nonisolated public static func decodeLinkStatus(_ data: Data) -> LinkStatus? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let value = object as? String { return LinkStatus(rawValue: value.lowercased()) }
        if let value = object as? [String: Any], let status = value["status"] as? String { return LinkStatus(rawValue: status.lowercased()) }
        if let values = object as? [[String: Any]], let status = values.first?["status"] as? String { return LinkStatus(rawValue: status.lowercased()) }
        return nil
    }
    public func startHeartbeat(using token: @escaping @Sendable () async -> String?, refresh: (@Sendable () async -> String?)? = nil) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.heartbeat(using: token, refresh: refresh)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
    public func stopHeartbeat() { heartbeatTask?.cancel(); heartbeatTask = nil }
    public func reset() { stopHeartbeat(); isActive = false; receiverState = "SIN CONEXIÓN" }
}
