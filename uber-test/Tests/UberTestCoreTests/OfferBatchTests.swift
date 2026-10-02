import XCTest
@testable import UberTestCore

final class OfferBatchTests: XCTestCase {
    private func offer(_ id: Int, seconds: Int = 15) -> UberTestOffer {
        UberTestOffer(id: "offer-\(id)", service: "UberX", fare: 100, pickup: "Centro", pickupDistanceKm: 1.2, tripDurationMinutes: 20, tripDistanceKm: 8, riderRating: 4.9, expiresAfterSeconds: seconds)
    }
    func testReceivesBatchFIFOAndAdvancesAfterAcceptDiscardExpire() throws {
        var queue = UberTestQueue()
        try queue.receive(try UberTestOfferBatch(id: "batch-1", offers: [offer(1), offer(2), offer(3)]))
        XCTAssertEqual(queue.current?.id, "offer-1")
        XCTAssertEqual(queue.finishCurrent(as: .accepted)?.outcome, .accepted)
        XCTAssertEqual(queue.current?.id, "offer-2")
        XCTAssertEqual(queue.finishCurrent(as: .discarded)?.offerId, "offer-2")
        XCTAssertEqual(queue.finishCurrent(as: .expired)?.offerId, "offer-3")
        XCTAssertTrue(queue.isWaiting); XCTAssertEqual(queue.results.count, 3)
    }
    func testRejectsMoreThanTenAndProduction() {
        XCTAssertThrowsError(try UberTestOfferBatch(id: "too-many", offers: (0..<11).map { offer($0) }))
        XCTAssertThrowsError(try UberTestOfferBatch(id: "prod", environment: "PRODUCTION", offers: [offer(1)]))
    }
    func testDeduplicatesBatchAndOffers() throws {
        var queue = UberTestQueue(); let first = try UberTestOfferBatch(id: "same", offers: [offer(1)])
        try queue.receive(first)
        XCTAssertNoThrow(try queue.receive(first))
        XCTAssertEqual(queue.current?.id, "offer-1")
        XCTAssertThrowsError(try queue.receive(try UberTestOfferBatch(id: "other", offers: [offer(1)])))
    }
    func testRecoveryResumesSameBatchAfterPersistedResult() throws {
        var queue = UberTestQueue(); let incoming = try UberTestOfferBatch(id: "recover", offers: [offer(1), offer(2)])
        try queue.receive(incoming); _ = queue.finishCurrent(as: .accepted)
        try queue.receive(incoming)
        XCTAssertEqual(queue.current?.id, "offer-2")
    }
    func testTenConsecutiveOffers() throws {
        var queue = UberTestQueue()
        try queue.receive(try UberTestOfferBatch(id: "ten", offers: (0..<10).map { offer($0) }))
        for _ in 0..<10 { XCTAssertNotNil(queue.finishCurrent(as: .accepted)) }
        XCTAssertTrue(queue.isWaiting)
    }
}
