import Foundation
import Supabase

/// Realtime is only a refresh signal. Every event triggers a fresh RLS-protected
/// read, so reopening the app reconstructs the same state without event history.
@MainActor
final class AcquisitionRealtimeObserver {
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?
    private var observedEnvironmentID: UUID?

    func start(
        environmentID: UUID,
        onChange: @escaping @MainActor () -> Void
    ) {
        guard observedEnvironmentID != environmentID else { return }
        stop()
        guard let client = SupabaseBridge.client else { return }

        observedEnvironmentID = environmentID
        let channel = client.channel("dori-acquisition-\(environmentID.uuidString.lowercased())")
        self.channel = channel

        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "acquisition_offers"
        )
        listenTask = Task {
            for await _ in inserts {
                guard !Task.isCancelled else { return }
                onChange()
            }
        }

        Task { await channel.subscribe() }
    }

    func stop() {
        observedEnvironmentID = nil
        listenTask?.cancel()
        listenTask = nil
        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
    }
}
