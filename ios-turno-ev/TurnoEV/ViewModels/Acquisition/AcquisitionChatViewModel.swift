import Foundation
import Observation

nonisolated enum AcquisitionUnitChatResolutionError: LocalizedError, Sendable {
    case wrongConversation

    var errorDescription: String? {
        "La conversación no corresponde a esta unidad."
    }
}

@MainActor
enum AcquisitionUnitChatResolver {
    static func resolve(
        offerID: UUID,
        membership: AcquisitionMembership,
        repository: any AcquisitionRepository
    ) async throws -> AcquisitionChatThreadSummary {
        let thread = try await repository.ensureChatThread(
            supplierID: membership.supplierID,
            offerID: offerID
        )
        guard thread.scope == .unit, thread.offerID == offerID else {
            throw AcquisitionUnitChatResolutionError.wrongConversation
        }
        return thread
    }
}

@MainActor
@Observable
final class AcquisitionChatListViewModel {
    let membership: AcquisitionMembership
    private let repository: any AcquisitionRepository
    private let realtime = AcquisitionRealtimeObserver()

    var threads: [AcquisitionChatThreadSummary] = []
    var isLoading = false
    var feedbackMessage: String?

    init(membership: AcquisitionMembership, repository: any AcquisitionRepository) {
        self.membership = membership
        self.repository = repository
    }

    var unreadCount: Int { threads.reduce(0) { $0 + $1.unreadCount } }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        feedbackMessage = nil
        do {
            if membership.role == .provider,
               let supplierID = membership.supplierID {
                _ = try await repository.ensureChatThread(
                    supplierID: supplierID,
                    offerID: nil
                )
            }
            threads = try await repository.loadChatThreads()
            realtime.startForChat(environmentID: membership.environmentID) { [weak self] in
                Task { await self?.load() }
            }
        } catch {
            feedbackMessage = "No pudimos cargar las conversaciones."
        }
        isLoading = false
    }

    func stop() { realtime.stop() }
}

@MainActor
@Observable
final class AcquisitionChatViewModel {
    let thread: AcquisitionChatThreadSummary
    let membership: AcquisitionMembership
    let profileID: UUID
    private let repository: any AcquisitionRepository
    private let realtime = AcquisitionRealtimeObserver()

    var messages: [AcquisitionChatMessage] = []
    var draft = ""
    var attachment: AcquisitionChatAttachment?
    var isLoading = false
    var isSending = false
    var feedbackMessage: String?

    init(
        thread: AcquisitionChatThreadSummary,
        membership: AcquisitionMembership,
        profileID: UUID,
        repository: any AcquisitionRepository
    ) {
        self.thread = thread
        self.membership = membership
        self.profileID = profileID
        self.repository = repository
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || attachment != nil
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        feedbackMessage = nil
        do {
            messages = try await repository.loadChatMessages(threadID: thread.id)
            if let sequence = messages.last?.sequence {
                try await repository.markChatRead(threadID: thread.id, sequence: sequence)
            }
            realtime.startForChat(
                environmentID: membership.environmentID,
                threadID: thread.id
            ) { [weak self] in
                Task { await self?.load() }
            }
        } catch {
            feedbackMessage = "No pudimos actualizar esta conversación."
        }
        isLoading = false
    }

    func capture(_ data: Data) {
        capture(AcquisitionChatAttachment(data: data))
    }

    func capture(_ newAttachment: AcquisitionChatAttachment) {
        guard !newAttachment.data.isEmpty else {
            feedbackMessage = "El archivo seleccionado está vacío."
            return
        }
        guard newAttachment.data.count <= 10 * 1_024 * 1_024 else {
            feedbackMessage = "El archivo supera el límite de 10 MB."
            return
        }
        attachment = newAttachment
        feedbackMessage = nil
    }

    func removeAttachment() { attachment = nil }

    func send() async {
        guard canSend, !isSending else { return }
        isSending = true
        feedbackMessage = nil
        do {
            _ = try await repository.sendChatMessage(
                thread: thread,
                body: draft,
                attachment: attachment
            )
            draft = ""
            attachment = nil
            await load()
        } catch {
            feedbackMessage = (error as? AcquisitionChatSendError)?.localizedDescription
                ?? "No pudimos enviar el mensaje. Intenta nuevamente."
        }
        isSending = false
    }

    func stop() { realtime.stop() }
}
