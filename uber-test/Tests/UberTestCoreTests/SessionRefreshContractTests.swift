import Foundation
import XCTest
@testable import UberTestCore

final class SessionRefreshContractTests: XCTestCase {
    private final class ProtocolStub: URLProtocol {
        nonisolated(unsafe) static var statuses: [Int] = []
        nonisolated(unsafe) static var authorization: [String] = []
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.authorization.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            let status = Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst()
            let body = Data(#"{"batch":null}"#.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [ProtocolStub.self]; return URLSession(configuration: c)
    }

    private actor Counter { var value = 0; func increment() { value += 1 }; func read() -> Int { value } }

    override func setUp() { super.setUp(); ProtocolStub.statuses = []; ProtocolStub.authorization = [] }

    func testValidTokenDoesNotRefresh() async throws {
        let refreshes = Counter()
        _ = try await UberTestBatchClient(functionURL: URL(string: "https://test.invalid/next")!, accessToken: { "valid" }, refreshAccessToken: { await refreshes.increment(); return "new" }, session: session()).loadPendingBatch()
        let count = await refreshes.read(); XCTAssertEqual(count, 0); XCTAssertEqual(ProtocolStub.authorization, ["Bearer valid"])
    }

    func test401RefreshesAndRetriesOnce() async throws {
        ProtocolStub.statuses = [401, 200]
        let refreshes = Counter()
        _ = try await UberTestBatchClient(functionURL: URL(string: "https://test.invalid/next")!, accessToken: { "expired" }, refreshAccessToken: { await refreshes.increment(); return "refreshed" }, session: session()).loadPendingBatch()
        let count = await refreshes.read(); XCTAssertEqual(count, 1); XCTAssertEqual(ProtocolStub.authorization, ["Bearer expired", "Bearer refreshed"])
    }

    func testRefreshFailureDoesNotLoop() async {
        ProtocolStub.statuses = [401, 401]
        let refreshes = Counter()
        do { _ = try await UberTestBatchClient(functionURL: URL(string: "https://test.invalid/next")!, accessToken: { "expired" }, refreshAccessToken: { await refreshes.increment(); return nil }, session: session()).loadPendingBatch(); XCTFail("expected failure") } catch {}
        let count = await refreshes.read(); XCTAssertEqual(count, 1); XCTAssertEqual(ProtocolStub.authorization.count, 1)
    }

    func testResultRetriesAfterRefresh() async throws {
        ProtocolStub.statuses = [401, 200]
        let refreshes = Counter()
        let result = UberTestResult(batchId: "b", offerId: "o", outcome: .accepted, occurredAt: .now)
        try await UberTestHTTPResultSink(functionURL: URL(string: "https://test.invalid/result")!, accessToken: { "expired" }, refreshAccessToken: { await refreshes.increment(); return "refreshed" }, session: session()).record(result)
        let count = await refreshes.read(); XCTAssertEqual(count, 1); XCTAssertEqual(ProtocolStub.authorization.last, "Bearer refreshed")
    }

    func testRepeated401IsSingleRetry() async {
        ProtocolStub.statuses = [401, 401]
        do { try await UberTestHTTPResultSink(functionURL: URL(string: "https://test.invalid/result")!, accessToken: { "expired" }, refreshAccessToken: { "refreshed" }, session: session()).record(.init(batchId: "b", offerId: "o", outcome: .discarded, occurredAt: .now)); XCTFail("expected failure") } catch {}
        XCTAssertEqual(ProtocolStub.authorization.count, 2)
    }
}
