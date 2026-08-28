import Foundation
import Observation

/// The execution environment, held apart from everything it used to travel with.
///
/// Four things were living in one blob and one of them was load-bearing for the other
/// three. `LabWorld` carried the mode, the fixtures, the clock offset and the audit in a
/// single `Codable` struct under `turnoev.lab.v1`, decoded all-or-nothing: any release
/// that added a field to any nested laboratory type made the whole payload fail to
/// decode, `LabPersistence.load()` answered `.empty`, and `.empty.mode` is
/// `.production`. That is the "first session after an update behaves like production"
/// report, exactly: the environment was silently lost because a *scenario* could not be
/// read.
///
/// So the environment now owns a key of its own, holding one string. It cannot be
/// invalidated by a fixture, a credit, a document or anything else the laboratory grows.
///
/// The four concerns and where each lives now:
/// 1. **Identity** — `StaffSession` / `SessionPrincipal`, under the session's storage key.
///    Never touched from here.
/// 2. **Execution environment** — this file, `turnoev.environment.v1`.
/// 3. **Scenario and fixtures** — `LabWorld`, `turnoev.lab.v1`.
/// 4. **Test clock** — `SimulationClock`, its own key already.
nonisolated enum EnvironmentStore {
    static let storageKey = "turnoev.environment.v1"

    /// Read by the `nonisolated` seed layer (`MockData`, `StaffDirectory`, `LabRuntime`)
    /// on the same synchronous main-actor call stack that writes it, exactly like
    /// `LabRuntime.cache`. No concurrent mutation exists.
    nonisolated(unsafe) private static var cache: LabMode?

    /// The environment this device is running in.
    static var current: LabMode {
        if let cache { return cache }
        let resolved = load(defaults: .standard)
        cache = resolved
        return resolved
    }

    /// Resolves the environment from storage, with the legacy blob as a fallback.
    ///
    /// The fallback is a **partial** decode on purpose: it asks the laboratory payload
    /// for one field and tolerates every other field being new, renamed or malformed.
    /// A device that was in test mode before this key existed keeps its environment, and
    /// keeps it across an update that breaks the rest of the payload.
    static func load(defaults: UserDefaults) -> LabMode {
        if let raw = defaults.string(forKey: storageKey), let mode = LabMode(rawValue: raw) {
            return mode
        }
        guard let data = defaults.data(forKey: LabPersistence.storageKey) else { return .production }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let probe = try? decoder.decode(ModeProbe.self, from: data) else { return .production }
        return probe.mode
    }

    static func persist(_ mode: LabMode, defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: storageKey)
        // An isolated suite is a test's own world; it must not move the environment the
        // seed layer of the running app reads.
        guard defaults === UserDefaults.standard else { return }
        cache = mode
    }

    /// One field out of the laboratory payload. Everything else in it is ignored, which
    /// is the whole point.
    private struct ModeProbe: Decodable {
        let mode: LabMode
    }
}

/// Single observable source of the execution environment.
///
/// Before this, the environment was readable in three shapes — `LabRuntime.mode` (a
/// `nonisolated` static, invisible to SwiftUI), `LabStore.world.mode` (observable but
/// owned by the console) and, in practice, "which door did this session come through" —
/// and the capability boundaries read none of them. Consumers now read this one object,
/// so a change invalidates every view that asked, without anybody calling `reload()`
/// from a screen.
@Observable
final class RuntimeEnvironment {
    /// The instance the app runs on. Tests build their own against an isolated suite.
    static let shared = RuntimeEnvironment()

    private let defaults: UserDefaults

    private(set) var mode: LabMode

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mode = EnvironmentStore.load(defaults: defaults)
    }

    var isTest: Bool { mode == .test }

    /// The only writer. `LabStore` funnels every environment change through it.
    func set(_ mode: LabMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        EnvironmentStore.persist(mode, defaults: defaults)
    }
}
