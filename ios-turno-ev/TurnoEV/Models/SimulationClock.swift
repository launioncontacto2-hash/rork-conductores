import Foundation

/// The single source of time of the whole application.
///
/// Nothing operational reads the clock of the phone any more. Every rule that depends on
/// time — tolerances, absences, check-ins, goals, weekly cuts, expirations — asks here.
///
/// In production it answers with real time and cannot be moved. In test mode it answers
/// with the logical time of the simulation.
///
/// Scope, stated plainly: that logical time is **local to this device**. Every role
/// signed in on this phone shares it, which is what makes "Ver como…" work. Two physical
/// devices do NOT share it yet — see `SharedSimulationClock`.
nonisolated enum AppClock {
    /// Time the app must obey right now.
    static func now() -> Date {
        LabRuntime.isTest ? SimulationClock.current() : Date()
    }

    /// Real time, for the few places that legitimately need to contrast it — the clock
    /// panel itself and the audit trail.
    static func realNow() -> Date { Date() }

    /// Difference between the logical hour and the real one, in minutes. Kept so the
    /// screens that already observe an offset keep working untouched.
    static func offsetMinutes() -> Int {
        guard LabRuntime.isTest else { return 0 }
        return Int(SimulationClock.current().timeIntervalSince(Date()) / 60)
    }
}

/// How fast the logical time of the simulation runs.
nonisolated enum SimulationSpeed: Int, Codable, CaseIterable, Identifiable, Sendable {
    case paused = 0
    case realTime = 1
    case fast = 5
    case faster = 10
    case fastest = 30

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .paused: "Pausado"
        case .realTime: "x1"
        case .fast: "x5"
        case .faster: "x10"
        case .fastest: "x30"
        }
    }

    var detail: String {
        switch self {
        case .paused: "La hora no avanza sola. Solo cambia cuando tú la mueves."
        case .realTime: "1 minuto real = 1 minuto de prueba."
        default: "1 minuto real = \(rawValue) minutos de prueba."
        }
    }

    var isPaused: Bool { self == .paused }

    /// Closest selectable speed to a numeric pace. The shared table stores speed as a
    /// `double precision`, so a value written by another client (or edited by hand in
    /// Supabase) still lands on a speed this app can display.
    static func nearest(to value: Double) -> SimulationSpeed {
        let running = allCases.filter { !$0.isPaused }
        return running.min {
            abs(Double($0.rawValue) - value) < abs(Double($1.rawValue) - value)
        } ?? .realTime
    }
}

/// State of the simulated clock. It is anchored rather than stored as a running number:
/// an instant of simulated time pinned to an instant of real time, plus a speed. Any
/// reader can derive the current hour from those three values, which is exactly what a
/// shared backend would need to hand out later.
nonisolated struct SimulationClockState: Codable, Sendable, Equatable {
    /// Simulated instant at the moment the clock was last set.
    var anchor: Date
    /// Real instant that anchor was pinned to.
    var pinnedAt: Date
    var speed: SimulationSpeed
    /// Test environment this clock belongs to. Reserved for the shared backend, so one
    /// simulation never reads the hour of another.
    var environmentId: String
    /// Last write, used to resolve which device wrote most recently.
    var updatedAt: Date
    /// Monotonic counter of the shared clock. A device must never replace what it holds with
    /// a state carrying a lower revision — that is how a slow network is prevented from
    /// resurrecting an hour the environment already left behind.
    var revision: Int64

    /// Hour this state stands on right now.
    func current(realNow: Date = Date()) -> Date {
        guard !speed.isPaused else { return anchor }
        let elapsed = realNow.timeIntervalSince(pinnedAt)
        return anchor.addingTimeInterval(elapsed * Double(speed.rawValue))
    }

    static func fresh(environmentId: String) -> SimulationClockState {
        let now = Date()
        // A fresh simulation starts paused on the real hour: nothing moves until the
        // administrator decides it should.
        return SimulationClockState(
            anchor: now,
            pinnedAt: now,
            speed: .paused,
            environmentId: environmentId,
            updatedAt: now,
            revision: 0
        )
    }

    init(
        anchor: Date,
        pinnedAt: Date,
        speed: SimulationSpeed,
        environmentId: String,
        updatedAt: Date,
        revision: Int64
    ) {
        self.anchor = anchor
        self.pinnedAt = pinnedAt
        self.speed = speed
        self.environmentId = environmentId
        self.updatedAt = updatedAt
        self.revision = revision
    }

    /// Hand-written so a state stored before the shared clock existed still decodes: it
    /// simply has no revision yet and starts at zero.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anchor = try container.decode(Date.self, forKey: .anchor)
        pinnedAt = try container.decode(Date.self, forKey: .pinnedAt)
        speed = try container.decode(SimulationSpeed.self, forKey: .speed)
        environmentId = try container.decode(String.self, forKey: .environmentId)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        revision = try container.decodeIfPresent(Int64.self, forKey: .revision) ?? 0
    }
}

/// Logical time of the test environment **on this device**.
///
/// This is the working implementation today. It is stored in `UserDefaults`, so it is
/// shared by every role signed in on this phone and survives a restart — but it does not
/// travel to another device. Anything that needs two devices on one hour has to go
/// through `SharedSimulationClock` once its backend exists.
nonisolated enum SimulationClock {
    private static let storageKey = "turnoev.simclock.v1"

    /// Identifier of the local simulation. Replaced by the real environment id when the
    /// shared clock lands.
    static let localEnvironmentId = "local"

    nonisolated(unsafe) private static var cache: SimulationClockState?

    static func load() -> SimulationClockState {
        if let cache { return cache }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode(SimulationClockState.self, from: data) else {
            let fresh = SimulationClockState.fresh(environmentId: localEnvironmentId)
            cache = fresh
            return fresh
        }
        cache = decoded
        return decoded
    }

    private static func save(_ state: SimulationClockState) {
        var updated = state
        updated.updatedAt = Date()
        persist(updated)

        // Hand the same state to the shared layer, which publishes it to the environment.
        SharedSimulationClock.publish(updated)
    }

    /// Stores a state **without** publishing it. Used when the value came from the shared
    /// environment: echoing it straight back would loop two devices against each other.
    static func adopt(_ state: SimulationClockState) {
        persist(state)
    }

    private static func persist(_ state: SimulationClockState) {
        cache = state
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        // Single choke point: every path that changes the clock — set, shift, setSpeed,
        // reset, adopt — lands here, so the observable signal can never fall out of step.
        announce(state)
    }

    private static func announce(_ state: SimulationClockState) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { ClockSignal.shared.adopted(state) }
        } else {
            Task { @MainActor in ClockSignal.shared.adopted(state) }
        }
    }

    /// The hour the simulation is standing on.
    static func current() -> Date { load().current() }

    static var speed: SimulationSpeed { load().speed }

    /// Moves the simulation to an exact instant and re-pins it to now.
    static func set(_ date: Date) {
        var state = load()
        state.anchor = date
        state.pinnedAt = Date()
        save(state)
    }

    /// Shifts the logical time. Negative values go back, which is legitimate for testing
    /// and never rewrites what already happened.
    static func shift(minutes: Int) {
        shift(seconds: minutes * 60)
    }

    /// Second-level nudge. Needed to stand exactly on a boundary — 05:59:50 → 06:00:00 is
    /// the moment a late driver becomes an absence.
    static func shift(seconds: Int) {
        set(current().addingTimeInterval(TimeInterval(seconds)))
    }

    static func setSpeed(_ speed: SimulationSpeed) {
        // Re-anchor first, so changing the speed never jumps the hour.
        var state = load()
        state.anchor = current()
        state.pinnedAt = Date()
        state.speed = speed
        save(state)
    }

    /// Puts the simulation back on the real hour, paused.
    static func reset() {
        save(SimulationClockState.fresh(environmentId: localEnvironmentId))
    }

    /// Builds an instant from a date, a time of day and a second.
    ///
    /// The wheel picker only yields hours and minutes, so the second arrives separately.
    /// It is kept: standing on 05:59:50 is the whole point of testing a boundary, and
    /// silently zeroing it made an exact instant impossible to reach.
    static func combine(day: Date, time: Date, second: Int = 0) -> Date {
        let calendar = ShiftRules.calendar
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        var parts = DateComponents()
        parts.year = dayParts.year
        parts.month = dayParts.month
        parts.day = dayParts.day
        parts.hour = timeParts.hour
        parts.minute = timeParts.minute
        parts.second = min(max(second, 0), 59)
        return calendar.date(from: parts) ?? day
    }

    /// Second of the minute an instant stands on, to preload the picker.
    static func second(of date: Date) -> Int {
        ShiftRules.calendar.component(.second, from: date)
    }
}

// MARK: - Observable signal

/// The one thing SwiftUI is allowed to watch to know the logical hour moved.
///
/// `SimulationClock` is a static enum: nothing about it is observable, so a view that read
/// `AppClock.now()` had no dependency to invalidate and simply kept its last render. This
/// type is the missing dependency. `generation` changes on **every** adopted state — local
/// or remote — whether or not the minute, the offset or anything else visibly changed.
@MainActor
@Observable
final class ClockSignal {
    static let shared = ClockSignal()

    /// Bumped once per adopted state. Views read it to register the dependency.
    private(set) var generation: Int = 0
    /// Revision of the shared row currently in force on this device.
    private(set) var revision: Int64 = 0
    /// Mirror of the clock speed. Observable, so the selector highlights the right button
    /// the moment another device changes the pace.
    private(set) var speed: SimulationSpeed = .paused

    private init() {
        speed = SimulationClock.speed
        revision = SimulationClock.load().revision
    }

    func adopted(_ state: SimulationClockState) {
        speed = state.speed
        revision = state.revision
        generation &+= 1
    }
}

// MARK: - Shared clock (pending backend)

/// Seam between the synchronous clock and the shared environment.
///
/// `AppClock.now()` is called from everywhere and must answer instantly, so it can never
/// await the network. This type keeps a nonisolated mirror of the sync engine's status for
/// those callers, and forwards local changes to it.
///
/// The engine itself — `SharedClockSync` — owns the Supabase row and the Realtime channel.
nonisolated enum SharedSimulationClock {
    /// Mirror of `SharedClockSync.status`, readable from non-isolated code.
    nonisolated(unsafe) private static var connected: Bool = false

    /// True only when a real shared source is answering.
    static var isConnected: Bool { connected }

    static func setConnected(_ value: Bool) {
        connected = value
    }

    /// Sends a locally produced state to the environment. Does nothing when the shared clock
    /// is not running, which is exactly the old single-device behaviour.
    static func publish(_ state: SimulationClockState) {
        Task { @MainActor in
            SharedClockSync.shared.push(state)
        }
    }

    /// Shown in the clock panel while no second device can be following along.
    static let pendingNotice =
        "Este reloj sólo gobierna este dispositivo. Para compartirlo con un segundo teléfono hace falta conexión con el entorno de pruebas."

    static let sharedNotice =
        "Este reloj es el del entorno de prueba compartido: cualquier cambio aquí se aplica en todos los dispositivos conectados."
}

// MARK: - Authorization

nonisolated enum EnvironmentControl {
    private static let unlockKey = "turnoev.simulation.unlocked"

    /// A laboratory credential signed in on this device. Remembered separately from the
    /// active session, because "Ver como…" replaces the session with the driver's or the
    /// supervisor's — the human at the phone is still the administrator, and locking the
    /// clock at exactly the moment he reaches the screen he wants to test defeats it.
    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: unlockKey)
    }

    /// Called whenever a session is observed.
    static func observe(account: StaffAccount?) {
        guard account?.role == .lab else { return }
        UserDefaults.standard.set(true, forKey: unlockKey)
    }

    static func lock() {
        UserDefaults.standard.set(false, forKey: unlockKey)
    }

    /// May this device turn the simulation on and off. It does not depend on the
    /// environment: turning test mode ON is precisely what you do while in production.
    ///
    /// Only the laboratory credential qualifies. A driver, a supervisor, maintenance or
    /// recruitment can take part in a simulation once they are signed in, but none of them
    /// can switch it on or off.
    static func canSwitchEnvironment(account: StaffAccount?) -> Bool {
        account?.role == .lab || isUnlocked
    }

    /// May this session return to Producción from inside the simulation.
    ///
    /// Deliberately looser than `canSwitchEnvironment`, and only in one direction. The
    /// thing worth guarding is a real operation being dragged *into* a simulation: that
    /// stays a laboratory act. Walking *out* of one is the safe direction — production is
    /// the real hour and the real data — so any signed-in session may take it.
    ///
    /// Without this, a profile handed a test environment had no way back except signing
    /// out, and signing out does not change the environment either: it would come back
    /// into the simulation on the next access.
    static func canLeaveTestEnvironment(account: StaffAccount?, mode: LabMode) -> Bool {
        mode == .test && account != nil
    }

    /// Whether this session can reach the environment sheet at all, in either direction.
    static func canReachEnvironment(account: StaffAccount?, mode: LabMode) -> Bool {
        canSwitchEnvironment(account: account) || canLeaveTestEnvironment(account: account, mode: mode)
    }

    /// May this session select `mode` in the environment sheet.
    static func canAdopt(mode: LabMode, account: StaffAccount?, current: LabMode) -> Bool {
        if canSwitchEnvironment(account: account) { return true }
        // The one-way valve: Producción is always reachable, Modo prueba never is.
        return mode == .production && canLeaveTestEnvironment(account: account, mode: current)
    }

    /// May this device move the logical time. This one does depend on the environment:
    /// there is no clock to move in production, where time is real and untouchable.
    static func canControlClock(account: StaffAccount?, mode: LabMode) -> Bool {
        mode == .test && canSwitchEnvironment(account: account)
    }

    /// The test badge is shown to everybody in the simulation, so nobody confuses it with
    /// the real operation.
    static func showsTestBadge(mode: LabMode) -> Bool { mode == .test }

    static let leavingTestNotice =
        "Vas a regresar al entorno de Producción. Los datos de prueba permanecerán separados y no afectarán la operación real."
}
