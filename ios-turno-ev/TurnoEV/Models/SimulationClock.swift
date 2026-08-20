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
            updatedAt: now
        )
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
        cache = updated
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(updated) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)

        // Hand the same state to the shared layer. Today it only keeps it; when the
        // backend exists this is the single line that starts publishing it.
        SharedSimulationClock.publish(updated)
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
        set(current().addingTimeInterval(TimeInterval(minutes * 60)))
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

    /// Builds an instant from a date and a time of day, which is what the picker gives.
    static func combine(day: Date, time: Date) -> Date {
        let calendar = ShiftRules.calendar
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        var parts = DateComponents()
        parts.year = dayParts.year
        parts.month = dayParts.month
        parts.day = dayParts.day
        parts.hour = timeParts.hour
        parts.minute = timeParts.minute
        return calendar.date(from: parts) ?? day
    }
}

// MARK: - Shared clock (pending backend)

/// Where the simulated clock will live once the test environment has a shared backend, so
/// an iPhone running Supervisor and an Android running Conductor stand on the same hour.
///
/// **It is not connected yet.** There is no server behind it: `UserDefaults` cannot cross
/// devices, and pretending otherwise would make every two-device test a lie. Until the
/// backend exists this type only holds the last local state and reports honestly that it
/// is not synchronised.
///
/// Wiring it later touches exactly two places: `publish` sends the state, and `remote`
/// returns what the environment last published. `SimulationClockState` already carries the
/// `environmentId` and `updatedAt` such a service needs.
nonisolated enum SharedSimulationClock {
    /// True only when a real shared source is answering. Deliberately false today.
    static var isConnected: Bool { false }

    nonisolated(unsafe) private static var lastPublished: SimulationClockState?

    /// Last state this device wrote. With a backend, this is what would be sent.
    static func publish(_ state: SimulationClockState) {
        lastPublished = state
    }

    /// The hour the environment agrees on. Nil while there is no shared source, which is
    /// what tells callers to fall back to the local clock.
    static func remote() -> SimulationClockState? {
        guard isConnected else { return nil }
        return lastPublished
    }

    /// Shown in the clock panel so nobody assumes a second device is following along.
    static let pendingNotice =
        "Este reloj gobierna todos los roles de este dispositivo. Compartirlo con un segundo teléfono requiere el backend del entorno de pruebas, que aún no está conectado."
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
