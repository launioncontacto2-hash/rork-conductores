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
    private var reloadRequested = false
    private var isObserving = false
    private var recoveryTask: Task<Void, Never>?

    init(membership: AcquisitionMembership, repository: any AcquisitionRepository) {
        self.membership = membership
        self.repository = repository
    }

    var unreadCount: Int { threads.reduce(0) { $0 + $1.unreadCount } }

    func load() async {
        if isLoading {
            reloadRequested = true
            return
        }
        repeat {
            reloadRequested = false
            isLoading = true
            feedbackMessage = nil
            do {
                let startedAt = ContinuousClock.now
                if membership.role == .provider,
                   let supplierID = membership.supplierID {
                    _ = try await repository.ensureChatThread(
                        supplierID: supplierID,
                        offerID: nil
                    )
                }
                threads = AcquisitionChatOrdering.newestFirst(
                    try await repository.loadChatThreads()
                )
                print("[Adquisiciones][Rendimiento] conversaciones=\(startedAt.duration(to: ContinuousClock.now))")
            } catch {
                feedbackMessage = "No pudimos cargar las conversaciones."
            }
            isLoading = false
        } while reloadRequested

        if !isObserving {
            isObserving = true
            realtime.startForChat(environmentID: membership.environmentID) { [weak self] in
                Task {
                    await self?.load()
                    await AcquisitionPushCoordinator.shared.refreshBadge()
                }
            }
            startRecoveryReload()
        }
    }

    func stop() {
        isObserving = false
        recoveryTask?.cancel()
        recoveryTask = nil
        realtime.stop()
    }

    private func startRecoveryReload() {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.load()
            }
        }
    }
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
    private var reloadRequested = false
    private var isObserving = false
    private var lastMarkedReadSequence: Int64 = 0
    private var recoveryTask: Task<Void, Never>?

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
        if isLoading {
            reloadRequested = true
            return
        }
        repeat {
            reloadRequested = false
            isLoading = true
            feedbackMessage = nil
            do {
                let startedAt = ContinuousClock.now
                messages = try await repository.loadChatMessages(threadID: thread.id)
                if let sequence = messages.last?.sequence,
                   sequence > lastMarkedReadSequence {
                    try await repository.markChatRead(threadID: thread.id, sequence: sequence)
                    lastMarkedReadSequence = sequence
                }
                await AcquisitionPushCoordinator.shared.markRead(.chat(
                    threadID: thread.id,
                    offerID: thread.offerID
                ))
                print("[Adquisiciones][Rendimiento] chat=\(startedAt.duration(to: ContinuousClock.now)) mensajes=\(messages.count)")
            } catch {
                feedbackMessage = "No pudimos actualizar esta conversación."
            }
            isLoading = false
        } while reloadRequested

        if !isObserving {
            isObserving = true
            realtime.startForChat(
                environmentID: membership.environmentID,
                threadID: thread.id
            ) { [weak self] in
                Task {
                    await self?.load()
                    await AcquisitionPushCoordinator.shared.refreshBadge()
                }
            }
            startRecoveryReload()
        }
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

    func stop() {
        isObserving = false
        recoveryTask?.cancel()
        recoveryTask = nil
        realtime.stop()
    }

    private func startRecoveryReload() {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.load()
            }
        }
    }
}
