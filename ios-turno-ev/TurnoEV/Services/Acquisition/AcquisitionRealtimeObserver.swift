import Foundation
import Supabase

/// Realtime is only a refresh signal. Every event triggers a fresh RLS-protected
/// read, so reopening the app reconstructs the same state without event history.
@MainActor
final class AcquisitionRealtimeObserver {
    private var channel: RealtimeChannelV2?
    private var listenTasks: [Task<Void, Never>] = []
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
        listenTasks = [offerChanges, negotiationChanges, orderChanges, deliveryChanges, receptionChanges, holdChanges].map { changes in
            Task {
                for await _ in changes {
                    guard !Task.isCancelled else { return }
                    onChange()
                }
            }
        }

        Task {
            await channel.subscribe()
        }
    }

    /// A detail screen uses its own signal so it can reload the full authorized
    /// projection even when the dashboard is not visible.
    func startForOffer(
        environmentID: UUID,
        offerID: UUID,
        onChange: @escaping @MainActor () -> Void
    ) {
        stop()
        guard let client = SupabaseBridge.client else { return }

        observedEnvironmentID = environmentID
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
                    onChange()
                }
            }
        }

        Task {
            await channel.subscribe()
        }
    }

    func stop() {
        observedEnvironmentID = nil
        listenTasks.forEach { $0.cancel() }
        listenTasks = []
        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
    }
}
