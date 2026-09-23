import XCTest
@testable import UberTestCore

private actor RecordingSink: UberTestResultSink {
    private(set) var recorded: [UberTestResult] = []
    func record(_ result: UberTestResult) async throws { recorded.append(result) }
    func count() -> Int { recorded.count }
}

private actor CopilotSink: UberTestCopilotSink {
    private(set) var evaluated: [(String, String)] = []
    func evaluate(_ offer: UberTestOffer, batchId: String) async throws { evaluated.append((offer.id, batchId)) }
    func count() -> Int { evaluated.count }
}

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

    func testResultIsDeliveredToConfiguredSink() async throws {
        UserDefaults.standard.removeObject(forKey: "uber.test.pending.queue.v1")
        UserDefaults.standard.removeObject(forKey: "uber.test.pending.results.v1")
        UserDefaults.standard.removeObject(forKey: "uber.test.current.offer.deadline.v1")
        let sink = RecordingSink()
        let store = UberTestStore(resultSink: sink)
        store.receive(try UberTestOfferBatch(id: "sink-batch", offers: [UberTestOffer(id: "sink-offer", service: "UberX", fare: 100, pickup: "A", pickupDistanceKm: 1, tripDurationMinutes: 10, tripDistanceKm: 4)]))
        store.accept()

        try await Task.sleep(for: .milliseconds(100))

        let delivered = await sink.count()
        XCTAssertEqual(delivered, 1)
        UserDefaults.standard.removeObject(forKey: "uber.test.pending.queue.v1")
        UserDefaults.standard.removeObject(forKey: "uber.test.pending.results.v1")
        UserDefaults.standard.removeObject(forKey: "uber.test.current.offer.deadline.v1")
    }

    func testCopilotSinkEvaluatesPresentedOfferOnlyOnce() async throws {
        UserDefaults.standard.removeObject(forKey: "uber.test.copilot.evaluated-offers.v1")
        UserDefaults.standard.removeObject(forKey: "uber.test.pending.queue.v1")
        UserDefaults.standard.removeObject(forKey: "uber.test.current.offer.deadline.v1")
        let sink = CopilotSink()
        let store = UberTestStore(copilotSink: sink)
        let batch = try UberTestOfferBatch(id: "copilot-batch", offers: [
            UberTestOffer(id: "copilot-offer-1", service: "UberX", fare: 120, pickup: "A", pickupDistanceKm: 1, tripDurationMinutes: 20, tripDistanceKm: 8),
            UberTestOffer(id: "copilot-offer-2", service: "Uber Comfort", fare: 140, pickup: "B", pickupDistanceKm: 1.2, tripDurationMinutes: 22, tripDistanceKm: 9)
        ])
        store.receive(batch)
        store.receive(batch)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(await sink.count(), 1)
        store.accept()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(await sink.count(), 2)
        UserDefaults.standard.removeObject(forKey: "uber.test.copilot.evaluated-offers.v1")
        UserDefaults.standard.removeObject(forKey: "uber.test.pending.queue.v1")
        UserDefaults.standard.removeObject(forKey: "uber.test.current.offer.deadline.v1")
    }
}
