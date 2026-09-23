import Foundation

public struct UberTestHTTPResultSink: UberTestResultSink {
    public let functionURL: URL
    public let accessToken: @Sendable () async -> String?
    public let refreshAccessToken: (@Sendable () async -> String?)?
    private let session: URLSession

    public init(functionURL: URL, accessToken: @escaping @Sendable () async -> String?, refreshAccessToken: (@Sendable () async -> String?)? = nil, session: URLSession = .shared) {
        self.functionURL = functionURL; self.accessToken = accessToken; self.refreshAccessToken = refreshAccessToken; self.session = session
    }
    public func record(_ result: UberTestResult) async throws {
        guard let token = await accessToken() else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder.uberTest.encode(["offerId": result.offerId, "outcome": result.outcome.rawValue, "idempotencyKey": "uber-test-\(result.batchId)-\(result.offerId)-\(result.outcome.rawValue)"])
        var (_, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401, let refreshAccessToken, let refreshed = await refreshAccessToken() {
            request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
            (_, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
}

private extension JSONEncoder {
    static var uberTest: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
}
