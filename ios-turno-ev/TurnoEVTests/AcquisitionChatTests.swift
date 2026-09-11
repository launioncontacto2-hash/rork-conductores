import Foundation
import Testing
@testable import TurnoEV

struct AcquisitionChatModelTests {
    @Test func buildsAPrivateImmutableAttachmentPath() {
        let path = AcquisitionChatAttachmentPath.make(
            environmentID: Self.environmentID,
            supplierID: Self.supplierID,
            threadID: Self.threadID,
            fileExtension: "JPG"
        )
        #expect(path.hasPrefix(
            "\(Self.environmentID.uuidString.lowercased())/"
                + "\(Self.supplierID.uuidString.lowercased())/"
                + "\(Self.threadID.uuidString.lowercased())/"
        ))
        #expect(path.hasSuffix(".jpg"))
    }

    @Test func threadUsesAReadablePreviewForAnAttachment() {
        let thread = Self.thread(lastMessage: nil, kind: .attachment, unread: 1)
        #expect(thread.previewText == "Adjunto")
        #expect(thread.unreadCount == 1)
    }

    static let environmentID = UUID(uuidString: "AD900000-0000-4000-8000-000000000001")!
    static let supplierID = UUID(uuidString: "AD900000-0000-4000-8000-000000000002")!
    static let threadID = UUID(uuidString: "AD900000-0000-4000-8000-000000000003")!
    static let profileID = UUID(uuidString: "AD900000-0000-4000-8000-000000000004")!

    static func thread(
        lastMessage: String? = "Mensaje de prueba",
        kind: AcquisitionChatMessageKind? = .text,
        unread: Int = 0
    ) -> AcquisitionChatThreadSummary {
        AcquisitionChatThreadSummary(
            id: threadID,
            supplierID: supplierID,
            offerID: nil,
            scope: .general,
            title: "Chat general",
            supplierName: "Agencia Puebla Centro",
            lastMessage: lastMessage,
            lastMessageKind: kind,
            lastMessageAt: Date(),
            unreadCount: unread
        )
    }

    static var membership: AcquisitionMembership {
        AcquisitionMembership(
            id: UUID(),
            environmentID: environmentID,
            profileID: profileID,
            supplierID: supplierID,
            role: .provider
        )
    }
}

@MainActor
struct AcquisitionChatFlowTests {
    @Test func providerEnsuresGeneralChatAndLoadsUnreadBadge() async {
        let repository = Repository()
        repository.threads = [AcquisitionChatModelTests.thread(unread: 3)]
        let model = AcquisitionChatListViewModel(
            membership: AcquisitionChatModelTests.membership,
            repository: repository
        )

        await model.load()

        #expect(repository.ensuredSupplierID == AcquisitionChatModelTests.supplierID)
        #expect(repository.ensuredOfferID == nil)
        #expect(model.unreadCount == 3)
    }

    @Test func loadsMessagesAndMarksTheLatestAsRead() async {
        let repository = Repository()
        repository.messages = [repository.message(sequence: 7, body: "Hola")]
        let model = Self.model(repository: repository)

        await model.load()

        #expect(model.messages.count == 1)
        #expect(repository.lastReadSequence == 7)
    }

    @Test func sendsTextOnlyThroughRepositoryBoundary() async {
        let repository = Repository()
        let model = Self.model(repository: repository)
        model.draft = "  Unidad disponible  "

        await model.send()

        #expect(repository.sentBody == "  Unidad disponible  ")
        #expect(repository.sentAttachment == nil)
        #expect(model.draft.isEmpty)
    }

    @Test func sendsAPrivateAttachmentWithTheMessage() async {
        let repository = Repository()
        let model = Self.model(repository: repository)
        model.draft = "Fotografía adicional"
        model.capture(Data([1, 2, 3]))

        await model.send()

        #expect(repository.sentAttachment?.data == Data([1, 2, 3]))
        #expect(model.attachment == nil)
    }

    private static func model(repository: Repository) -> AcquisitionChatViewModel {
        AcquisitionChatViewModel(
            thread: AcquisitionChatModelTests.thread(),
            membership: AcquisitionChatModelTests.membership,
            profileID: AcquisitionChatModelTests.profileID,
            repository: repository
        )
    }

    private final class Repository: AcquisitionRepository {
        var threads: [AcquisitionChatThreadSummary] = []
        var messages: [AcquisitionChatMessage] = []
        var ensuredSupplierID: UUID?
        var ensuredOfferID: UUID?
        var sentBody: String?
        var sentAttachment: AcquisitionChatAttachment?
        var lastReadSequence: Int64?

        func loadMembership(profileID: UUID, environmentID: UUID) async throws -> AcquisitionMembership {
            AcquisitionChatModelTests.membership
        }
        func loadRequests() async throws -> [AcquisitionRequest] { [] }
        func loadOffers() async throws -> [AcquisitionOfferSummary] { [] }
        func loadOfferDetail(
            offerID: UUID,
            membership: AcquisitionMembership
        ) async throws -> AcquisitionOfferDetail { throw CancellationError() }
        func submitOffer(
            _ submission: AcquisitionOfferSubmission,
            membership: AcquisitionMembership
        ) async throws -> AcquisitionOfferSummary { throw CancellationError() }
        func respondToOffer(
            _ command: AcquisitionOfferCommand
        ) async throws -> AcquisitionOfferCommandResult { throw CancellationError() }
        func completeDelivery(
            _ command: AcquisitionDeliveryCommand
        ) async throws -> AcquisitionDeliveryCommandResult { throw CancellationError() }

        func loadChatThreads() async throws -> [AcquisitionChatThreadSummary] { threads }
        func ensureChatThread(
            supplierID: UUID?,
            offerID: UUID?
        ) async throws -> AcquisitionChatThreadSummary {
            ensuredSupplierID = supplierID
            ensuredOfferID = offerID
            return AcquisitionChatModelTests.thread()
        }
        func loadChatMessages(threadID: UUID) async throws -> [AcquisitionChatMessage] { messages }
        func sendChatMessage(
            thread: AcquisitionChatThreadSummary,
            body: String,
            attachment: AcquisitionChatAttachment?
        ) async throws -> AcquisitionChatMessage {
            sentBody = body
            sentAttachment = attachment
            let result = message(sequence: Int64(messages.count + 1), body: body)
            messages.append(result)
            return result
        }
        func markChatRead(threadID: UUID, sequence: Int64) async throws {
            lastReadSequence = sequence
        }

        func message(sequence: Int64, body: String) -> AcquisitionChatMessage {
            AcquisitionChatMessage(
                id: UUID(),
                sequence: sequence,
                threadID: AcquisitionChatModelTests.threadID,
                senderProfileID: AcquisitionChatModelTests.profileID,
                senderRole: .provider,
                kind: .text,
                body: body,
                attachmentPath: nil,
                createdAt: Date(),
                attachmentData: nil
            )
        }
    }
}
