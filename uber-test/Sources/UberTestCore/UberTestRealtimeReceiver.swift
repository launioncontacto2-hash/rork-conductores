import Foundation

/// Foreground wake-up transport for TEST. The server remains authoritative:
/// every change only triggers `uber-test-next` recovery.
#if os(iOS)
import Supabase

public final class UberTestRealtimeReceiver: @unchecked Sendable {
    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var consumer: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    public init(url: URL, publishableKey: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }

    public func start(accessToken: String, onWakeup: @escaping @Sendable () async -> Void) async {
        client.realtime.setAuth(accessToken)
        let next = client.channel("uber-test-offer-events")
        let changes = next.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "uber_test_offer_events"
        )
        channel = next
        consumer?.cancel()
        statusTask?.cancel()
        // Start both streams before subscribe so the first INSERT and the
        // SUBSCRIBED transition cannot be lost during the handshake.
        statusTask = Task { [weak self] in
            for await status in next.statusChange {
                guard !Task.isCancelled else { return }
                if case .subscribed = status { await onWakeup() }
                _ = self
            }
        }
        consumer = Task {
            for await _ in changes { await onWakeup() }
        }
        await next.subscribe()
    }

    public func stop() async {
        consumer?.cancel(); consumer = nil
        statusTask?.cancel(); statusTask = nil
        if let channel { await client.removeChannel(channel); self.channel = nil }
    }
}
#else
/// Realtime is an iOS transport. macOS package tests keep a no-op type so the
/// deterministic queue/model tests do not initialize an iOS-only SDK runtime.
public final class UberTestRealtimeReceiver: @unchecked Sendable {
    public init(url: URL, publishableKey: String) {}
    public func start(accessToken: String, onWakeup: @escaping @Sendable () async -> Void) async {}
    public func stop() async {}
}
#endif
