import XCTest
@testable import UberTestCore

final class UberTestLinkStatusTests: XCTestCase {
    func testWaitingMapsToSpanishLabel() {
        XCTAssertEqual(UberTestReceiverState.decodeLinkStatus(Data(#"{"status":"waiting"}"#.utf8))?.label, "ESPERANDO DORI")
    }

    func testLinkedMapsToSpanishLabel() {
        XCTAssertEqual(UberTestReceiverState.decodeLinkStatus(Data(#"[{"status":"linked"}]"#.utf8))?.label, "DORI ENLAZADO")
    }

    func testInterruptedMapsToSpanishLabel() {
        XCTAssertEqual(UberTestReceiverState.decodeLinkStatus(Data(#"{"status":"interrupted"}"#.utf8))?.label, "ENLACE INTERRUMPIDO")
    }

    func testUnknownStatusDoesNotPretendToBeLinked() {
        XCTAssertNil(UberTestReceiverState.decodeLinkStatus(Data(#"{"status":"unknown"}"#.utf8)))
    }
}
