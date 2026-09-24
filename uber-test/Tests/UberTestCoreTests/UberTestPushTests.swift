import XCTest
@testable import UberTestCore

final class UberTestPushTests: XCTestCase {
    func testDecodesAnyHashablePushPayload() {
        let payload: [AnyHashable: Any] = [
            "id": "push-batch", "environment": "TEST", "createdAt": "2026-09-23T12:00:00Z",
            "offers": [["id": "push-offer", "service": "UberX", "fare": 120.0, "currency": "MXN", "pickup": "Centro", "pickupDistanceKm": 1.2, "tripDurationMinutes": 20.0, "tripDistanceKm": 8.0, "riderRating": 4.9, "expiresAfterSeconds": 15]]
        ]
        let batch = UberTestPushCoordinator.decodeBatch(from: ["uber_test_batch": payload])
        XCTAssertEqual(batch?.id, "push-batch")
        XCTAssertEqual(batch?.offers.first?.service, "UberX")
    }
}
