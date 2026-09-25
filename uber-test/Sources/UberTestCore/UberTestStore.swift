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
    private var copilotEvaluatedOfferIDs: [String] = []
    private let maxRememberedOfferIDs = 100
    private var deadline: Date?
    private var pendingResults: [UberTestResult] = []
    private var resultFlushTask: Task<Void, Never>?
    private let alertSound = UberTestAlertSound()
    private var recoveryTask: Task<Void, Never>?
    private var isFinishing = false
    /// TEST-only transport telemetry. It records timing labels without payloads or secrets.
    public var transportTelemetry: (@Sendable (String, Date) -> Void)?

    public init(resultSink: (any UberTestResultSink)? = nil, copilotSink: (any UberTestCopilotSink)? = nil) {
        self.copilotSink = copilotSink
        self.resultSink = resultSink
        if let data = UserDefaults.standard.data(forKey: persistenceKey), let restored = try? UberTestQueue(snapshotData: data) {
            queue = restored
            deadline = UserDefaults.standard.object(forKey: deadlineKey) as? Date
            if queue.current != nil { startTimer(resetDeadline: deadline == nil) }
        }
        if let data = UserDefaults.standard.data(forKey: pendingResultsKey), let restored = try? JSONDecoder().decode([UberTestResult].self, from: data) { pendingResults = restored }
        copilotEvaluatedOfferIDs = UserDefaults.standard.stringArray(forKey: copilotEvaluatedOfferIDsKey) ?? []
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
        do {
            try queue.receive(batch)
            transportTelemetry?("presented_at", .now)
            persist(); startTimer(); evaluateCurrentOfferIfNeeded()
        }
        catch { errorMessage = String(describing: error) }
    }
    public func recover(using client: UberTestBatchClient, transport: String = "fallback") async {
        transportTelemetry?("recover_started_at", .now)
        await flushPendingResults()
        guard queue.current == nil else { return }
        do {
            if let batch = try await client.loadPendingBatch() {
                transportTelemetry?("transport_used=\(transport)", .now)
                receive(batch)
            }
        }
        catch UberTestSessionError.terminated { stopForegroundRecovery() }
        catch { errorMessage = "No se pudo recuperar la tanda TEST." }
    }
    public func startForegroundRecovery(using client: UberTestBatchClient) async {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.queue.current == nil { await self.recover(using: client, transport: "fallback") }
                // Realtime/push is the primary transport; this bounded loop is
                // recovery only when the app resumes without a delivered event.
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
    public func stopForegroundRecovery() { recoveryTask?.cancel(); recoveryTask = nil }
    public func accept() { finish(.accepted) }
    public func discard() { finish(.discarded) }
    private func finish(_ outcome: UberTestOutcome) {
        guard !isFinishing else { return }
        guard queue.current != nil else { return }
        isFinishing = true
        timer?.invalidate()
        timer = nil
        guard let result = queue.finishCurrent(as: outcome) else { isFinishing = false; return }
        pendingResults.append(result); persistPendingResults()
        if resultSink != nil { Task { [weak self] in await self?.flushPendingResults() } }
        persist()
        startTimer()
        evaluateCurrentOfferIfNeeded()
        isFinishing = false
    }
    private func evaluateCurrentOfferIfNeeded() {
        guard let offer = queue.current, let batchId = queue.batch?.id, let copilotSink,
              !copilotEvaluatedOfferIDs.contains(offer.id) else { return }
        copilotEvaluatedOfferIDs.append(offer.id)
        if copilotEvaluatedOfferIDs.count > maxRememberedOfferIDs { copilotEvaluatedOfferIDs.removeFirst(copilotEvaluatedOfferIDs.count - maxRememberedOfferIDs) }
        UserDefaults.standard.set(copilotEvaluatedOfferIDs, forKey: copilotEvaluatedOfferIDsKey)
        Task { [weak self] in
            do { try await copilotSink.evaluate(offer, batchId: batchId) }
            catch { await MainActor.run { self?.errorMessage = "No se pudo preparar la evaluación DORI." } }
        }
    }
    private func persist() { if let data = try? queue.snapshotData() { UserDefaults.standard.set(data, forKey: persistenceKey) } }
    private func persistPendingResults() { if let data = try? JSONEncoder().encode(pendingResults) { UserDefaults.standard.set(data, forKey: pendingResultsKey) } }
    private func flushPendingResults() async {
        if let resultFlushTask { await resultFlushTask.value; return }
        guard resultSink != nil else { return }
        let task = Task { @MainActor [weak self] in
            await self?.drainPendingResults()
            self?.resultFlushTask = nil
        }
        resultFlushTask = task
        await task.value
    }

    /// The single-flight boundary is intentionally internal so concurrency tests
    /// can exercise the same path used by expiry, recovery, and foreground wakeup.
    internal func flushPendingResultsForTesting() async { await flushPendingResults() }

    private func drainPendingResults() async {
        guard let resultSink else { return }
        var attempts = 0
        while let result = pendingResults.first {
            do {
                try await resultSink.record(result)
                removePendingResultIfStillCurrent(result)
                attempts = 0
            }
            catch UberTestResultError.terminal {
                removePendingResultIfStillCurrent(result)
                attempts = 0
            }
            catch {
                attempts += 1
                if attempts >= 3 { errorMessage = "Resultado pendiente de sincronización TEST."; return }
                try? await Task.sleep(for: .milliseconds(250 * attempts))
            }
        }
    }

    private func removePendingResultIfStillCurrent(_ result: UberTestResult) {
        guard let first = pendingResults.first,
              first.batchId == result.batchId,
              first.offerId == result.offerId,
              first.outcome == result.outcome,
              first.occurredAt == result.occurredAt else { return }
        pendingResults.removeFirst()
        persistPendingResults()
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
                if self.remainingSeconds == 0 { self.finish(.expired) }
            }
        }
    }
    deinit { timer?.invalidate(); recoveryTask?.cancel() }
}
