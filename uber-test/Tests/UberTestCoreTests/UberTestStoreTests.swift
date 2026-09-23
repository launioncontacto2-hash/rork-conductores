import XCTest
@testable import UberTestCore

@MainActor
final class UberTestStoreTests: XCTestCase {
    func testAcceptAndDiscardProduceResults() throws {
        let store = UberTestStore()
        let offers = [
            UberTestOffer(id: "a", service: "UberX", fare: 100, pickup: "A", pickupDistanceKm: 1, tripDurationMinutes: 10, tripDistanceKm: 4),
            UberTestOffer(id: "b", service: "UberX", fare: 110, pickup: "B", pickupDistanceKm: 2, tripDurationMinutes: 11, tripDistanceKm: 5)
        ]
        store.receive(try UberTestOfferBatch(id: "batch", offers: offers))
        store.accept(); XCTAssertEqual(store.queue.results.map(\.outcome), [.accepted])
        store.discard(); XCTAssertEqual(store.queue.results.map(\.outcome), [.accepted, .discarded])
        XCTAssertTrue(store.queue.isWaiting)
    }

    func testTimerExpiresCurrentOfferAndAdvancesFIFO() async throws {
        let store = UberTestStore()
        let offers = [
            UberTestOffer(id: "timer-a", service: "UberX", fare: 100, pickup: "A", pickupDistanceKm: 1, tripDurationMinutes: 10, tripDistanceKm: 4, expiresAfterSeconds: 1),
            UberTestOffer(id: "timer-b", service: "UberX", fare: 110, pickup: "B", pickupDistanceKm: 2, tripDurationMinutes: 11, tripDistanceKm: 5, expiresAfterSeconds: 10),
        ]
        store.receive(try UberTestOfferBatch(id: "timer-batch", offers: offers))

        try await Task.sleep(for: .seconds(2))

        XCTAssertEqual(store.queue.results.map(\.outcome), [.expired])
        XCTAssertEqual(store.queue.current?.id, "timer-b")
        XCTAssertGreaterThan(store.remainingSeconds, 0)
    }
}
