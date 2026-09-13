import Foundation
import Testing
@testable import TurnoEV

struct AcquisitionPushTests {
    @Test func parsesOfferDeepLinkWithoutInternalFields() {
        let id = UUID()
        let destination = AcquisitionPushCoordinator.destination(from: [
            "kind": "offer",
            "offer_id": id.uuidString,
            "hard_cap": "must-not-be-used",
        ])
        #expect(destination == .offer(id))
    }

    @Test func parsesUnitChatDeepLinkAndKeepsOfferContext() {
        let threadID = UUID()
        let offerID = UUID()
        let destination = AcquisitionPushCoordinator.destination(from: [
            "kind": "chat_unit",
            "thread_id": threadID.uuidString,
            "offer_id": offerID.uuidString,
        ])
        #expect(destination == .chat(threadID: threadID, offerID: offerID))
    }

    @Test func rejectsMalformedOrUnknownDeepLinks() {
        #expect(AcquisitionPushCoordinator.destination(from: ["kind": "offer"]) == nil)
        #expect(AcquisitionPushCoordinator.destination(from: ["kind": "internal_score"]) == nil)
    }
}
