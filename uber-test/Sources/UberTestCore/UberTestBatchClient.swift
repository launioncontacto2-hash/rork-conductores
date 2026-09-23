import Foundation

public struct UberTestBatchClient: Sendable {
    public let functionURL: URL
    public let accessToken: @Sendable () async -> String?
    private let session: URLSession

    public init(functionURL: URL, accessToken: @escaping @Sendable () async -> String?, session: URLSession = .shared) {
        self.functionURL = functionURL; self.accessToken = accessToken; self.session = session
    }

    public func loadPendingBatch() async throws -> UberTestOfferBatch? {
        guard let token = await accessToken() else { return nil }
        var request = URLRequest(url: functionURL); request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        struct Envelope: Decodable { let batch: UberTestOfferBatch? }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Envelope.self, from: data).batch
    }
}
