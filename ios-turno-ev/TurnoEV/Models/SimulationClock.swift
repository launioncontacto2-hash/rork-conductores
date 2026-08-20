import Foundation

/// The single source of time of the whole application.
///
/// Nothing operational reads the clock of the phone any more. Every rule that depends on
/// time — tolerances, absences, check-ins, goals, weekly cuts, expirations — asks here.
///
/// In production it answers with real time and cannot be moved. In test mode it answers
/// with the logical time of the simulation, which is shared by every device and every
/// role: the supervisor on one phone and the driver on another read the same hour.
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

/// Logical time of the test environment. It is anchored: an instant of simulated time
/// pinned to an instant of real time, plus a speed. Everything else is derived, so no
/// device keeps a clock of its own.
nonisolated enum SimulationClock {
    nonisolated private struct State: Codable, Sendable {
        /// Simulated instant at the moment the clock was last set.
        var anchor: Date
        /// Real instant that anchor was pinned to.
        var pinnedAt: Date
        var speed: SimulationSpeed
    }

    private static let storageKey = "turnoev.simclock.v1"

    nonisolated(unsafe) private static var cache: State?

    private static func load() -> State {
        if let cache { return cache }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode(State.self, from: data) else {
            // A fresh simulation starts paused on the real hour: nothing moves until the
            // administrator decides it should.
            let fresh = State(anchor: Date(), pinnedAt: Date(), speed: .paused)
            cache = fresh
            return fresh
        }
        cache = decoded
        return decoded
    }

    private static func save(_ state: State) {
        cache = state
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// The hour the simulation is standing on.
    static func current() -> Date {
        let state = load()
        guard !state.speed.isPaused else { return state.anchor }
        let realElapsed = Date().timeIntervalSince(state.pinnedAt)
        return state.anchor.addingTimeInterval(realElapsed * Double(state.speed.rawValue))
    }

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
        var state = State(anchor: current(), pinnedAt: Date(), speed: speed)
        state.speed = speed
        save(state)
    }

    /// Puts the simulation back on the real hour, paused.
    static func reset() {
        save(State(anchor: Date(), pinnedAt: Date(), speed: .paused))
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

    /// Only the laboratory credential moves the environment or the clock. A driver, a
    /// supervisor, maintenance or recruitment can take part in a simulation once they are
    /// signed in, but none of them can switch it on or off.
    static func canSwitch(account: StaffAccount?) -> Bool {
        account?.role == .lab || isUnlocked
    }

    /// The clock is a simulation control: it only exists inside the test environment and
    /// only for whoever is allowed to move it.
    static func canControlClock(account: StaffAccount?, mode: LabMode) -> Bool {
        mode == .test && canSwitch(account: account)
    }

    /// The test badge is shown to everybody in the simulation, so nobody confuses it with
    /// the real operation.
    static func showsTestBadge(mode: LabMode) -> Bool { mode == .test }

    static let leavingTestNotice =
        "Vas a regresar al entorno de Producción. Los datos de prueba permanecerán separados y no afectarán la operación real."
}
