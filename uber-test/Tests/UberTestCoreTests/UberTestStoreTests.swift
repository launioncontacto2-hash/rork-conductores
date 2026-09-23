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
}
