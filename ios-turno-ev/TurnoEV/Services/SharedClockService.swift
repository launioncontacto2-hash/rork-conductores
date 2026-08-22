import Foundation
import Supabase

// MARK: - Environment

/// The shared laboratory environment. Its identifier is fixed and seeded by
/// `supabase/migrations/0001_lab_shared_clock.sql`, so every device that opens the
/// simulation lands on the same logical clock without anybody typing an id.
nonisolated enum LabEnvironment {
    static let sharedTestId = "9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10"

    static var sharedTestUUID: UUID? { UUID(uuidString: sharedTestId) }
}

// MARK: - Wire format

/// Date handling for Supabase payloads.
///
/// Two different producers send us timestamps and they do **not** agree on format. PostgREST
/// answers ISO-8601 (`2026-08-22T05:59:50.123456+00:00`), while a Realtime `postgres_changes`
/// payload carries the value as Postgres prints it (`2026-08-22 05:59:50.123456+00`) — a space
/// instead of `T` and a two-digit offset. `ISO8601DateFormatter` rejects both the space and the
/// six-digit fraction, so the clock would silently fail to parse exactly the messages it exists
/// to receive. This parser normalises the shape first and keeps the fraction separately.
nonisolated enum SupabaseCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { source in
            let container = try source.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = timestamp(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Marca de tiempo no reconocida: \(raw)"
                )
            }
            return date
        }
        return decoder
    }()

    /// Writes timestamps in the one shape Postgres always accepts.
    static func text(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.string(from: date)
    }

    static func timestamp(from raw: String) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Postgres prints `2026-08-22 05:59:50+00`; ISO wants a `T`.
        if let space = text.firstIndex(of: " ") {
            text.replaceSubrange(space...space, with: "T")
        }

        // Pull the fractional seconds out: their digit count varies (3 to 6) and no fixed
        // format string parses all of them reliably.
        var fraction: TimeInterval = 0
        if let dot = text.firstIndex(of: ".") {
            var cursor = text.index(after: dot)
            var digits = ""
            while cursor < text.endIndex, text[cursor].isNumber {
                digits.append(text[cursor])
                cursor = text.index(after: cursor)
            }
            fraction = Double("0.\(digits)") ?? 0
            text.removeSubrange(dot..<cursor)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // X matches `+00` / `Z`, XX matches `+0000`, XXXXX matches `+00:00`.
        for pattern in [
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXX",
            "yyyy-MM-dd'T'HH:mm:ssX",
            "yyyy-MM-dd'T'HH:mm:ss"
        ] {
            formatter.dateFormat = pattern
            if let parsed = formatter.date(from: text) {
                return parsed.addingTimeInterval(fraction)
            }
        }
        return nil
    }
}

/// One row of `test_clock`, exactly as the table defines it.
nonisolated struct SharedClockRow: Decodable, Sendable, Equatable {
    let environmentId: UUID
    let anchorSimulatedAt: Date
    let anchorRealAt: Date
    let speed: Double
    let isPaused: Bool
    let revision: Int64
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case environmentId = "environment_id"
        case anchorSimulatedAt = "anchor_simulated_at"
        case anchorRealAt = "anchor_real_at"
        case speed
        case isPaused = "is_paused"
        case revision
        case updatedAt = "updated_at"
    }
}

/// Arguments of `update_test_clock`, the single write this phase performs.
///
/// There is no `revision` field on purpose: the final number is assigned by Postgres under a
/// row lock. `expectedRevision` is the opposite — it declares which revision this device was
/// standing on, so the server can refuse to overwrite a change it never saw.
nonisolated struct SharedClockCommand: Encodable, Sendable {
    let environmentId: String
    let anchorSimulatedAt: String
    let anchorRealAt: String
    let speed: Double
    let isPaused: Bool
    let expectedRevision: Int64?

    enum CodingKeys: String, CodingKey {
        case environmentId = "p_environment_id"
        case anchorSimulatedAt = "p_anchor_simulated_at"
        case anchorRealAt = "p_anchor_real_at"
        case speed = "p_speed"
        case isPaused = "p_is_paused"
        case expectedRevision = "p_expected_revision"
    }
}

// MARK: - Sync engine

/// Keeps the logical clock of the test environment identical on every device.
///
/// The contract is deliberately narrow: this type owns **one** row of **one** table. It does
/// not migrate attendance, vehicles, coverage, users or payments, and it never writes the
/// running hour — only the anchors it is derived from.
@MainActor
@Observable
final class SharedClockSync {
    static let shared = SharedClockSync()

    /// What the compact indicator shows.
    enum Status: Equatable {
        /// No shared source: not configured, not in test, or the link is down.
        case offline
        /// Reaching the environment, or the channel has not confirmed yet.
        case connecting
        /// Subscribed and holding an authoritative row.
        case synced

        var label: String {
            switch self {
            case .offline: return "Offline"
            case .connecting: return "Conectando"
            case .synced: return "Sincronizado"
            }
        }
    }

    private(set) var status: Status = .offline {
        didSet { SharedSimulationClock.setConnected(status == .synced) }
    }
    private(set) var revision: Int64 = 0
    private(set) var lastSyncedAt: Date?
    /// Verbatim state of the Realtime channel, for the laboratory diagnostic.
    private(set) var channelState: String = "sin canal"
    private(set) var lastError: String?

    // MARK: Diagnostics
    //
    // These exist to answer one question during a two-device test: did the UPDATE never
    // arrive, or did it arrive and the interface fail to redraw? `received` counts what
    // Realtime handed us; `applied` counts what actually became the hour of this device.

    private(set) var remoteEventsReceived: Int = 0
    private(set) var remoteEventsApplied: Int = 0
    /// Revision carried by the last Realtime payload, applied or not.
    private(set) var lastRemoteRevision: Int64 = 0
    private(set) var lastRemoteEventAt: Date?
    /// True once the channel reported `subscribed`.
    private(set) var isSubscribed: Bool = false

    /// Called after a remote change has been adopted, so the modules that read the hour
    /// re-evaluate without anybody refreshing a screen.
    var onRemoteChange: (() -> Void)?

    /// Speed the environment resumes at. `is_paused` is the switch; `speed` is the pace, and
    /// pausing must not forget it — the acceptance test pauses an environment running at x10.
    private var resumeSpeed: Double = 1

    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var isRunning: Bool = false

    private init() {}

    var environmentId: String { LabEnvironment.sharedTestId }

    // MARK: Lifecycle

    /// Starts (or stops) the shared clock according to the environment.
    ///
    /// Production has no shared clock to keep: time there is real and untouchable.
    func update(isTest: Bool) {
        if isTest, SupabaseBridge.isConfigured {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard !isRunning else { return }
        guard let client = SupabaseBridge.client, let environment = LabEnvironment.sharedTestUUID else {
            status = .offline
            return
        }

        isRunning = true
        status = .connecting
        lastError = nil

        let channel = client.channel("lab-shared-clock")
        self.channel = channel

        // Postgres change callbacks must be registered *before* subscribing, otherwise the
        // SDK rejects them.
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "test_clock")

        statusTask = Task { [weak self] in
            for await state in channel.statusChange {
                guard let self else { return }
                self.channelState = String(describing: state)
                if case .subscribed = state {
                    self.isSubscribed = true
                    if self.lastSyncedAt != nil { self.status = .synced }
                } else if self.isRunning {
                    self.isSubscribed = false
                    self.status = .connecting
                }
            }
        }

        // The stream is consumed in its own task started *before* `subscribe()`. Previously
        // the loop only began after subscribing and after an awaited network read, leaving a
        // window in which the first UPDATE was handed to nobody.
        listenTask = Task { [weak self] in
            for await update in updates {
                guard let self else { return }
                self.remoteEventsReceived += 1
                self.lastRemoteEventAt = Date()
                do {
                    let row = try update.decodeRecord(as: SharedClockRow.self, decoder: SupabaseCoding.decoder)
                    self.lastRemoteRevision = row.revision
                    guard row.environmentId == environment else { continue }
                    self.applyRealtime(row)
                } catch {
                    self.lastError = "No se pudo leer un cambio del reloj: \(error.localizedDescription)"
                }
            }
        }

        Task { [weak self] in
            await channel.subscribe()
            // The first authoritative value comes from a plain read: a device that joins an
            // already-running simulation must not wait for somebody to move the clock.
            await self?.refresh()
        }
    }

    private func stop() {
        isRunning = false
        isSubscribed = false
        listenTask?.cancel()
        statusTask?.cancel()
        listenTask = nil
        statusTask = nil

        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
        status = .offline
        channelState = "sin canal"
    }

    // MARK: Reading

    /// Authoritative read. Whatever the table says wins, including a revision lower than the
    /// one held locally — that only happens after a write of ours never landed.
    func refresh() async {
        guard let client = SupabaseBridge.client else {
            status = .offline
            return
        }

        do {
            let response = try await client
                .from("test_clock")
                .select()
                .eq("environment_id", value: LabEnvironment.sharedTestId)
                .limit(1)
                .execute()

            let rows = try SupabaseCoding.decoder.decode([SharedClockRow].self, from: response.data)
            guard let row = rows.first else {
                lastError = "El entorno \(LabEnvironment.sharedTestId) no tiene reloj. Ejecuta la migración 0001."
                status = .offline
                return
            }
            adopt(row)
            lastError = nil
        } catch {
            status = .offline
            lastError = "No se pudo leer el reloj compartido: \(error.localizedDescription)"
        }
    }

    /// A change pushed by another device. Guarded by `revision`: a state older than the one
    /// already held is dropped, never applied.
    private func applyRealtime(_ row: SharedClockRow) {
        guard row.revision > revision else { return }
        adopt(row)
        remoteEventsApplied += 1
    }

    private func adopt(_ row: SharedClockRow) {
        resumeSpeed = row.speed
        revision = row.revision
        lastSyncedAt = Date()
        status = .synced
        // Persisting bumps `ClockSignal.generation`, and that is what actually invalidates
        // every view showing or computing with the hour.
        SimulationClock.adopt(row.asLocalState)
        onRemoteChange?()
    }

    // MARK: Writing

    /// Publishes a locally produced state.
    ///
    /// The caller has already done the re-anchoring — `SimulationClock` computes the current
    /// simulated hour, pins it to the real instant and only then hands the state over. This
    /// device never chooses the resulting revision: it sends the anchors plus the revision it
    /// was standing on, and Postgres decides the rest.
    func push(_ state: SimulationClockState) {
        guard isRunning, SupabaseBridge.client != nil else { return }

        let isPaused = state.speed.isPaused
        let speed = isPaused ? resumeSpeed : Double(state.speed.rawValue)
        if !isPaused { resumeSpeed = speed }

        let command = SharedClockCommand(
            environmentId: LabEnvironment.sharedTestId,
            anchorSimulatedAt: SupabaseCoding.text(from: state.anchor),
            anchorRealAt: SupabaseCoding.text(from: state.pinnedAt),
            speed: speed,
            isPaused: isPaused,
            // Zero means this device has not read an authoritative row yet, so it cannot claim
            // to know what it is overwriting. The server then just appends a revision.
            expectedRevision: revision > 0 ? revision : nil
        )

        Task { await send(command) }
    }

    private func send(_ command: SharedClockCommand) async {
        guard let client = SupabaseBridge.client else { return }
        do {
            let response = try await client
                .rpc("update_test_clock", params: command)
                .execute()

            let row = try Self.decodeRow(from: response.data)
            // Guarded on purpose: the Realtime echo of this very write can arrive before the
            // call returns, and re-adopting the same state would notify every module twice.
            applyRealtime(row)
            lastSyncedAt = Date()
            status = .synced
            lastError = nil
        } catch {
            let notice: String
            if Self.isRevisionConflict(error) {
                notice = "Otro dispositivo movió el reloj en el mismo instante. Se adoptó el estado del entorno; vuelve a aplicar tu cambio si sigue haciendo falta."
            } else {
                status = .offline
                notice = "No se pudo publicar el reloj: \(error.localizedDescription)"
            }
            // Either way this device stops believing in a state the environment never saw.
            await refresh()
            lastError = notice
        }
    }

    /// True when Postgres refused the write because the row had already moved on.
    /// Raised by `update_test_clock` as SQLSTATE 40001 with a named message.
    private static func isRevisionConflict(_ error: Error) -> Bool {
        if let postgrest = error as? PostgrestError {
            if postgrest.code == "40001" { return true }
            if postgrest.message.contains("revision_conflict") { return true }
        }
        return String(describing: error).contains("revision_conflict")
    }

    /// `update_test_clock` returns one composite row. Accept the array shape too, so a
    /// PostgREST version that wraps it does not break the write path.
    private static func decodeRow(from data: Data) throws -> SharedClockRow {
        if let row = try? SupabaseCoding.decoder.decode(SharedClockRow.self, from: data) {
            return row
        }
        let rows = try SupabaseCoding.decoder.decode([SharedClockRow].self, from: data)
        guard let row = rows.first else {
            throw SharedClockError.emptyResponse
        }
        return row
    }
}

nonisolated enum SharedClockError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "El entorno no devolvió el reloj actualizado."
        }
    }
}

private extension SharedClockRow {
    /// Maps the row onto the state the app already reasons with.
    var asLocalState: SimulationClockState {
        SimulationClockState(
            anchor: anchorSimulatedAt,
            pinnedAt: anchorRealAt,
            speed: isPaused ? .paused : SimulationSpeed.nearest(to: speed),
            environmentId: environmentId.uuidString,
            updatedAt: updatedAt,
            revision: revision
        )
    }
}
