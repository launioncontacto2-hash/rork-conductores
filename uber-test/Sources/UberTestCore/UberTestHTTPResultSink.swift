import Foundation

public struct UberTestHTTPResultSink: UberTestResultSink {
    public let functionURL: URL
    public let accessToken: @Sendable () async -> String?
    private let session: URLSession

    public init(functionURL: URL, accessToken: @escaping @Sendable () async -> String?, session: URLSession = .shared) {
        self.functionURL = functionURL; self.accessToken = accessToken; self.session = session
    }
    public func record(_ result: UberTestResult) async throws {
        guard let token = await accessToken() else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder.uberTest.encode(["offerId": result.offerId, "outcome": result.outcome.rawValue, "idempotencyKey": "uber-test-\(result.batchId)-\(result.offerId)-\(result.outcome.rawValue)"])
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
}

private extension JSONEncoder {
    static var uberTest: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
}
