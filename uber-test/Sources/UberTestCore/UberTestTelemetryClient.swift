import Foundation

public struct UberTestTelemetryClient: Sendable {
    public let functionURL: URL
    public let accessToken: @Sendable () async -> String?
    public let installationID: String
    public let appBuild: String
    public let sessionGeneration: String
    private let session: URLSession

    public init(functionURL: URL, accessToken: @escaping @Sendable () async -> String?, installationID: String, appBuild: String, sessionGeneration: String = UUID().uuidString, session: URLSession = .shared) {
        self.functionURL = functionURL; self.accessToken = accessToken; self.installationID = installationID; self.appBuild = appBuild; self.sessionGeneration = sessionGeneration; self.session = session
    }

    public func record(event: String, at date: Date = .now, batchID: String? = nil, transport: String? = nil) async {
        guard let token = await accessToken() else { return }
        var request = URLRequest(url: functionURL); request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["installationId": installationID, "appBuild": appBuild, "sessionGeneration": sessionGeneration, "eventName": event, "eventAt": ISO8601DateFormatter().string(from: date)]
            .merging(batchID.map { ["batchId": $0] } ?? [:]) { _, new in new }
            .merging(transport.map { ["transport": $0] } ?? [:]) { _, new in new }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: request)
    }
}
