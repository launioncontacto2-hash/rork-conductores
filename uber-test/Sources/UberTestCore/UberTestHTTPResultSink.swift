import Foundation

public struct UberTestHTTPResultSink: UberTestResultSink {
    public let functionURL: URL
    public let accessToken: @Sendable () async -> String?
    private let session: URLSession

    public init(functionURL: URL, accessToken: @escaping @Sendable () async -> String?, session: URLSession = .shared) {
        self.functionURL = functionURL; self.accessToken = accessToken; self.session = session
    }
    public func record(_ result: UberTestResult) async {
        guard let token = await accessToken() else { return }
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder.uberTest.encode(["offerId": result.offerId, "outcome": result.outcome.rawValue, "idempotencyKey": "uber-test-\(result.batchId)-\(result.offerId)-\(result.outcome.rawValue)"])
        _ = try? await session.data(for: request)
    }
}

private extension JSONEncoder {
    static var uberTest: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
}
