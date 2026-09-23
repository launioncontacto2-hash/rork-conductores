import Foundation
import Combine

public protocol UberTestResultSink: Sendable {
    func record(_ result: UberTestResult) async
}

@MainActor
public final class UberTestStore: ObservableObject {
    @Published public private(set) var queue = UberTestQueue()
    @Published public private(set) var remainingSeconds = 0
    @Published public private(set) var errorMessage: String?
    public var resultSink: (any UberTestResultSink)?
    private var timer: Timer?
    private let persistenceKey = "uber.test.pending.queue.v1"
    private let alertSound = UberTestAlertSound()

    public init(resultSink: (any UberTestResultSink)? = nil) {
        self.resultSink = resultSink
        if let data = UserDefaults.standard.data(forKey: persistenceKey), let restored = try? UberTestQueue(snapshotData: data) { queue = restored; if queue.current != nil { startTimer() } }
        NotificationCenter.default.addObserver(forName: UberTestPushCoordinator.batchNotification, object: nil, queue: .main) { [weak self] notification in
            guard let batch = notification.object as? UberTestOfferBatch else { return }
            self?.receive(batch)
        }
    }
    public func receive(_ batch: UberTestOfferBatch) {
        do { try queue.receive(batch); persist(); startTimer() } catch { errorMessage = String(describing: error) }
    }
    public func recover(using client: UberTestBatchClient) async {
        guard queue.current == nil else { return }
        do { if let batch = try await client.loadPendingBatch() { receive(batch) } }
        catch { errorMessage = "No se pudo recuperar la tanda TEST." }
    }
    public func accept() { finish(.accepted) }
    public func discard() { finish(.discarded) }
    private func finish(_ outcome: UberTestOutcome) {
        guard let result = queue.finishCurrent(as: outcome) else { return }
        if let resultSink { Task { await resultSink.record(result) } }
        persist()
        startTimer()
    }
    private func persist() { if let data = try? queue.snapshotData() { UserDefaults.standard.set(data, forKey: persistenceKey) } }
    private func startTimer() {
        timer?.invalidate(); remainingSeconds = queue.current?.expiresAfterSeconds ?? 0
        guard queue.current != nil else { return }
        alertSound.playOfferAlert()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.remainingSeconds <= 1 { self.timer?.invalidate(); self.finish(.expired) }
            else { self.remainingSeconds -= 1 }
        }
    }
    deinit { timer?.invalidate() }
}
