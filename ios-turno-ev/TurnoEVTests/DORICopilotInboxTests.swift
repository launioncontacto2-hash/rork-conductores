import XCTest
@testable import TurnoEV

final class DORICopilotInboxTests: XCTestCase {
    func testRepeatedCaseIDIsAcceptedOnlyOnceUntilReset() {
        var gate = DORICopilotDeliveryGate()
        let id = UUID()
        XCTAssertTrue(gate.accept(id))
        XCTAssertFalse(gate.accept(id))
        XCTAssertFalse(gate.accept(id))
        gate.reset()
        XCTAssertTrue(gate.accept(id))
    }

    func testNewCaseIDStartsASeparateDelivery() {
        var gate = DORICopilotDeliveryGate()
        XCTAssertTrue(gate.accept(UUID()))
        XCTAssertTrue(gate.accept(UUID()))
    }
}
