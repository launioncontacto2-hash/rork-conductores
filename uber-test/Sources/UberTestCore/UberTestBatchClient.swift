import Foundation

public struct UberTestBatchClient: Sendable {
    public let functionURL: URL
    public let accessToken: @Sendable () async -> String?
    public let refreshAccessToken: (@Sendable () async -> String?)?
    public let installationID: String
    private let session: URLSession

    public init(functionURL: URL, accessToken: @escaping @Sendable () async -> String?, refreshAccessToken: (@Sendable () async -> String?)? = nil, installationID: String = "", session: URLSession = .shared) {
        self.functionURL = functionURL; self.accessToken = accessToken; self.refreshAccessToken = refreshAccessToken; self.installationID = installationID; self.session = session
    }

    public func loadPendingBatch() async throws -> UberTestOfferBatch? {
        guard let token = await accessToken() else { return nil }
        var request = URLRequest(url: functionURL); request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(installationID, forHTTPHeaderField: "x-uber-test-installation-id")
        var (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401, let refreshAccessToken, let refreshed = await refreshAccessToken() {
            request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
            request.setValue(installationID, forHTTPHeaderField: "x-uber-test-installation-id")
            (data, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        struct Envelope: Decodable { let batch: UberTestOfferBatch? }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Envelope.self, from: data).batch
    }
}
