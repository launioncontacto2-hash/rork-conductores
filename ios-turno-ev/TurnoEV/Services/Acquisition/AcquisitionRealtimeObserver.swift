import Foundation
import Supabase

/// Realtime is only a refresh signal. Every event triggers a fresh RLS-protected
/// read, so reopening the app reconstructs the same state without event history.
@MainActor
final class AcquisitionRealtimeObserver {
    private var channel: RealtimeChannelV2?
    private var listenTasks: [Task<Void, Never>] = []
    private var observationKey: String?
    private var reloadDebounceTask: Task<Void, Never>?

    func start(
        environmentID: UUID,
        onChange: @escaping @MainActor () -> Void
    ) {
        let key = "module:\(environmentID.uuidString.lowercased())"
        guard observationKey != key else { return }
        stop()
        guard let client = SupabaseBridge.client else { return }

        observationKey = key
        let channel = client.channel("dori-acquisition-\(environmentID.uuidString.lowercased())")
        self.channel = channel

        let offerChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_offers"
        )
        let negotiationChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_negotiations"
        )
        let orderChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_orders"
        )
        let deliveryChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_deliveries"
        )
        let receptionChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_receptions"
        )
        let holdChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_holds"
        )
        let chatChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_chat_messages"
        )
        let readChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_chat_read_receipts"
        )
        let notificationChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_notifications"
        )
        listenTasks = [offerChanges, negotiationChanges, orderChanges, deliveryChanges, receptionChanges, holdChanges, chatChanges, readChanges, notificationChanges].map { changes in
            Task {
                for await _ in changes {
                    guard !Task.isCancelled else { return }
                    scheduleReload(onChange)
                }
            }
        }

        Task {
            await channel.subscribe()
        }
    }

    func startForChat(
        environmentID: UUID,
        threadID: UUID? = nil,
        onChange: @escaping @MainActor () -> Void
    ) {
        let suffix = threadID?.uuidString.lowercased() ?? environmentID.uuidString.lowercased()
        let key = "chat:\(suffix)"
        guard observationKey != key else { return }
        stop()
        guard let client = SupabaseBridge.client else { return }

        observationKey = key
        let channel = client.channel("dori-acquisition-chat-\(suffix)")
        self.channel = channel

        let messageChanges: AsyncStream<AnyAction>
        let readChanges: AsyncStream<AnyAction>
        let notificationChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_notifications"
        )
        if let threadID {
            let value = threadID.uuidString.lowercased()
            messageChanges = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "acquisition_chat_messages",
                filter: .eq("thread_id", value: value)
            )
            readChanges = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "acquisition_chat_read_receipts",
                filter: .eq("thread_id", value: value)
            )
        } else {
            messageChanges = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "acquisition_chat_messages"
            )
            readChanges = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "acquisition_chat_read_receipts"
            )
        }
        listenTasks = [messageChanges, readChanges, notificationChanges].map { changes in
            Task {
                for await _ in changes {
                    guard !Task.isCancelled else { return }
                    scheduleReload(onChange)
                }
            }
        }
        Task { await channel.subscribe() }
    }

    /// A detail screen uses its own signal so it can reload the full authorized
    /// projection even when the dashboard is not visible.
    func startForOffer(
        environmentID: UUID,
        offerID: UUID,
        onChange: @escaping @MainActor () -> Void
    ) {
        let key = "offer:\(offerID.uuidString.lowercased())"
        guard observationKey != key else { return }
        stop()
        guard let client = SupabaseBridge.client else { return }

        observationKey = key
        let channel = client.channel("dori-acquisition-offer-\(offerID.uuidString.lowercased())")
        self.channel = channel
        let offerChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_offers",
            filter: .eq("id", value: offerID.uuidString.lowercased())
        )
        let negotiationChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_negotiations",
            filter: .eq("offer_id", value: offerID.uuidString.lowercased())
        )
        let orderChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_orders",
            filter: .eq("offer_id", value: offerID.uuidString.lowercased())
        )
        let deliveryChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_deliveries"
        )
        let receptionChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_receptions"
        )
        let holdChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "acquisition_holds"
        )
        listenTasks = [offerChanges, negotiationChanges, orderChanges, deliveryChanges, receptionChanges, holdChanges].map { changes in
            Task {
                for await _ in changes {
                    guard !Task.isCancelled else { return }
                    scheduleReload(onChange)
                }
            }
        }

        Task {
            await channel.subscribe()
        }
    }

    func stop() {
        observationKey = nil
        reloadDebounceTask?.cancel()
        reloadDebounceTask = nil
        listenTasks.forEach { $0.cancel() }
        listenTasks = []
        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
    }

    /// One backend command can update an offer, negotiation, notification and order.
    /// Treat that transaction burst as one invalidation instead of rebuilding the
    /// complete screen once per changed table.
    private func scheduleReload(_ onChange: @escaping @MainActor () -> Void) {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            onChange()
        }
    }
}
