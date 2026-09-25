import Foundation

/// Foreground wake-up transport for TEST. The server remains authoritative:
/// every change only triggers `uber-test-next` recovery.
#if os(iOS)
import Supabase

public actor UberTestRealtimeReceiver {
    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var consumer: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var subscribed = false

    public init(url: URL, publishableKey: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }

    public func start(accessToken: String, onWakeup: @escaping @Sendable () async -> Void) async {
        if subscribed { return }
        if let startTask { await startTask.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performStart(accessToken: accessToken, onWakeup: onWakeup)
        }
        startTask = task
        await task.value
        startTask = nil
    }

    private func performStart(accessToken: String, onWakeup: @escaping @Sendable () async -> Void) async {
        client.realtime.setAuth(accessToken)
        subscribed = false
        consumer?.cancel(); consumer = nil
        statusTask?.cancel(); statusTask = nil
        if let oldChannel = channel {
            channel = nil
            await client.removeChannel(oldChannel)
        }
        let next = client.channel("uber-test-offer-events")
        let changes = next.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "uber_test_offer_events"
        )
        channel = next
        // Start both streams before subscribe so the first INSERT and the
        // SUBSCRIBED transition cannot be lost during the handshake.
        statusTask = Task { [weak self] in
            for await status in next.statusChange {
                guard !Task.isCancelled else { return }
                if case .subscribed = status {
                    await self?.markSubscribed()
                    await onWakeup()
                }
            }
        }
        consumer = Task {
            for await _ in changes { await onWakeup() }
        }
        await next.subscribe()
    }

    private func markSubscribed() { subscribed = true }

    public func stop() async {
        consumer?.cancel(); consumer = nil
        statusTask?.cancel(); statusTask = nil
        subscribed = false
        if let channel { self.channel = nil; await client.removeChannel(channel) }
    }
}
#else
/// Realtime is an iOS transport. macOS package tests keep a no-op type so the
/// deterministic queue/model tests do not initialize an iOS-only SDK runtime.
public actor UberTestRealtimeReceiver {
    public init(url: URL, publishableKey: String) {}
    public func start(accessToken: String, onWakeup: @escaping @Sendable () async -> Void) async {}
    public func stop() async {}
}
#endif
