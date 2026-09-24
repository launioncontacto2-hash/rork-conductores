import Foundation
import Combine

public protocol UberTestResultSink: Sendable {
    func record(_ result: UberTestResult) async throws
}

public protocol UberTestCopilotSink: Sendable {
    func evaluate(_ offer: UberTestOffer, batchId: String) async throws
}

@MainActor
public final class UberTestStore: ObservableObject {
    @Published public private(set) var queue = UberTestQueue()
    @Published public private(set) var remainingSeconds = 0
    @Published public private(set) var errorMessage: String?
    public var resultSink: (any UberTestResultSink)?
    public var copilotSink: (any UberTestCopilotSink)?
    private var timer: Timer?
    private let persistenceKey = "uber.test.pending.queue.v1"
    private let deadlineKey = "uber.test.current.offer.deadline.v1"
    private let pendingResultsKey = "uber.test.pending.results.v1"
    private let copilotEvaluatedOfferIDsKey = "uber.test.copilot.evaluated-offers.v1"
    private var copilotEvaluatedOfferIDs: Set<String> = []
    private var deadline: Date?
    private var pendingResults: [UberTestResult] = []
    private let alertSound = UberTestAlertSound()
    private var recoveryTask: Task<Void, Never>?

    public init(resultSink: (any UberTestResultSink)? = nil, copilotSink: (any UberTestCopilotSink)? = nil) {
        self.copilotSink = copilotSink
        self.resultSink = resultSink
        if let data = UserDefaults.standard.data(forKey: persistenceKey), let restored = try? UberTestQueue(snapshotData: data) {
            queue = restored
            deadline = UserDefaults.standard.object(forKey: deadlineKey) as? Date
            if queue.current != nil { startTimer(resetDeadline: deadline == nil) }
        }
        if let data = UserDefaults.standard.data(forKey: pendingResultsKey), let restored = try? JSONDecoder().decode([UberTestResult].self, from: data) { pendingResults = restored }
        copilotEvaluatedOfferIDs = Set(UserDefaults.standard.stringArray(forKey: copilotEvaluatedOfferIDsKey) ?? [])
        NotificationCenter.default.addObserver(forName: UberTestPushCoordinator.batchNotification, object: nil, queue: .main) { [weak self] notification in
            guard let batch = notification.object as? UberTestOfferBatch else { return }
            self?.receive(batch)
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("UIApplication.willEnterForegroundNotification"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.queue.current != nil { self.startTimer(resetDeadline: false) }
            Task { [weak self] in await self?.flushPendingResults() }
        }
    }
    public func receive(_ batch: UberTestOfferBatch) {
        do { try queue.receive(batch); persist(); startTimer(); evaluateCurrentOfferIfNeeded() }
        catch { errorMessage = String(describing: error) }
    }
    public func recover(using client: UberTestBatchClient) async {
        await flushPendingResults()
        guard queue.current == nil else { return }
        do { if let batch = try await client.loadPendingBatch() { receive(batch) } }
        catch { errorMessage = "No se pudo recuperar la tanda TEST." }
    }
    public func startForegroundRecovery(using client: UberTestBatchClient) async {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.queue.current == nil { await self.recover(using: client) }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    public func stopForegroundRecovery() { recoveryTask?.cancel(); recoveryTask = nil }
    public func accept() { finish(.accepted) }
    public func discard() { finish(.discarded) }
    private func finish(_ outcome: UberTestOutcome) {
        guard let result = queue.finishCurrent(as: outcome) else { return }
        pendingResults.append(result); persistPendingResults()
        if resultSink != nil { Task { [weak self] in await self?.flushPendingResults() } }
        persist()
        startTimer()
        evaluateCurrentOfferIfNeeded()
    }
    private func evaluateCurrentOfferIfNeeded() {
        guard let offer = queue.current, let batchId = queue.batch?.id, let copilotSink,
              !copilotEvaluatedOfferIDs.contains(offer.id) else { return }
        copilotEvaluatedOfferIDs.insert(offer.id)
        UserDefaults.standard.set(Array(copilotEvaluatedOfferIDs), forKey: copilotEvaluatedOfferIDsKey)
        Task { [weak self] in
            do { try await copilotSink.evaluate(offer, batchId: batchId) }
            catch { await MainActor.run { self?.errorMessage = "No se pudo preparar la evaluación DORI." } }
        }
    }
    private func persist() { if let data = try? queue.snapshotData() { UserDefaults.standard.set(data, forKey: persistenceKey) } }
    private func persistPendingResults() { if let data = try? JSONEncoder().encode(pendingResults) { UserDefaults.standard.set(data, forKey: pendingResultsKey) } }
    private func flushPendingResults() async {
        guard let resultSink else { return }
        while let result = pendingResults.first {
            do { try await resultSink.record(result); pendingResults.removeFirst(); persistPendingResults() }
            catch { errorMessage = "Resultado pendiente de sincronización TEST."; return }
        }
    }
    private func startTimer(resetDeadline: Bool = true) {
        timer?.invalidate()
        guard let current = queue.current else { remainingSeconds = 0; deadline = nil; UserDefaults.standard.removeObject(forKey: deadlineKey); return }
        if resetDeadline || deadline == nil { deadline = Date().addingTimeInterval(TimeInterval(current.expiresAfterSeconds)); UserDefaults.standard.set(deadline, forKey: deadlineKey) }
        remainingSeconds = max(0, Int(ceil((deadline ?? .now).timeIntervalSinceNow)))
        alertSound.playOfferAlert()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.remainingSeconds = max(0, Int(ceil((self.deadline ?? .now).timeIntervalSinceNow)))
                if self.remainingSeconds == 0 { self.timer?.invalidate(); self.finish(.expired) }
            }
        }
    }
    deinit { timer?.invalidate(); recoveryTask?.cancel() }
}
