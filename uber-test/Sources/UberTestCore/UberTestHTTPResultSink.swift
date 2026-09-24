import Foundation

public enum UberTestResultError: Error, Equatable { case terminal, retryable }

public struct UberTestHTTPResultSink: UberTestResultSink {
    public let functionURL: URL
    public let accessToken: @Sendable () async -> String?
    public let refreshAccessToken: (@Sendable () async -> String?)?
    public let installationID: String
    private let session: URLSession

    public init(functionURL: URL, accessToken: @escaping @Sendable () async -> String?, refreshAccessToken: (@Sendable () async -> String?)? = nil, installationID: String = "", session: URLSession = .shared) {
        self.functionURL = functionURL; self.accessToken = accessToken; self.refreshAccessToken = refreshAccessToken; self.installationID = installationID; self.session = session
    }
    public func record(_ result: UberTestResult) async throws {
        guard let token = await accessToken() else {
            uberTestNotifySessionTerminated()
            throw UberTestSessionError.terminated
        }
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(installationID, forHTTPHeaderField: "x-uber-test-installation-id")
        request.httpBody = try? JSONEncoder.uberTest.encode(["offerId": result.offerId, "outcome": result.outcome.rawValue, "idempotencyKey": "uber-test-\(result.batchId)-\(result.offerId)-\(result.outcome.rawValue)"])
        var (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            guard let refreshAccessToken, let refreshed = await refreshAccessToken() else {
                uberTestNotifySessionTerminated()
                throw UberTestSessionError.terminated
            }
            request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
            request.setValue(installationID, forHTTPHeaderField: "x-uber-test-installation-id")
            (data, response) = try await session.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 401 {
                uberTestNotifySessionTerminated()
                throw UberTestSessionError.terminated
            }
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if (200..<300).contains(http.statusCode) { return }
        if http.statusCode == 429 || http.statusCode >= 500 { throw UberTestResultError.retryable }
        if (400..<500).contains(http.statusCode) { throw UberTestResultError.terminal }
        throw URLError(.badServerResponse)
    }
}

private extension JSONEncoder {
    static var uberTest: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
}
