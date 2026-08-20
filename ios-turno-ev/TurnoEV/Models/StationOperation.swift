import Foundation

/// Support for the Operación window of the supervisor: the goal progress the station has
/// actually recorded, the replacement units it keeps on hand, and the short list of
/// situations that need the supervisor today.
///
/// Nothing here creates operational records. It reads what already exists and shapes it
/// for a screen meant to be understood in a couple of seconds.

// MARK: - Replacement units

/// A replacement unit is not owned by anybody. It exists so an unexpected absence does
/// not leave a productive unit parked for the whole day: the seat can be covered later in
/// the day with one of these.
///
/// The count is per station and configurable. Until the configuration screen exists, the
/// station keeps the value written here and falls back to the network default.
nonisolated enum StationReplacementPolicy {
    /// Units a station holds back for coverage when nothing has been configured yet.
    static let networkDefault = 1

    private static func key(_ stationId: String) -> String {
        "turnoev.station.replacement.\(stationId)"
    }

    /// How many replacement units this station is authorized to hold.
    static func configuredUnits(stationId: String) -> Int {
        let stored = UserDefaults.standard.object(forKey: key(stationId)) as? Int
        return max(0, stored ?? networkDefault)
    }

    /// Written by the configuration screen when it lands. Kept here so the number the
    /// interface shows always comes from one place.
    static func setConfiguredUnits(_ units: Int, stationId: String) {
        UserDefaults.standard.set(max(0, units), forKey: key(stationId))
    }
}

// MARK: - Goal progress

/// Day, week and month progress of the station, each against its own fixed goal.
nonisolated struct StationGoalProgress: Sendable {
    let dayEarningsMxn: Int
    let dayGoalMxn: Int
    let weekEarningsMxn: Int
    let weekGoalMxn: Int
    let monthEarningsMxn: Int
    let monthGoalMxn: Int

    var dayRatio: Double { dayGoalMxn > 0 ? min(1.5, Double(dayEarningsMxn) / Double(dayGoalMxn)) : 0 }
    var weekRatio: Double { weekGoalMxn > 0 ? min(1.5, Double(weekEarningsMxn) / Double(weekGoalMxn)) : 0 }
    var monthRatio: Double { monthGoalMxn > 0 ? min(1.5, Double(monthEarningsMxn) / Double(monthGoalMxn)) : 0 }

    static let empty = StationGoalProgress(
        dayEarningsMxn: 0,
        dayGoalMxn: 0,
        weekEarningsMxn: 0,
        weekGoalMxn: 0,
        monthEarningsMxn: 0,
        monthGoalMxn: 0
    )
}

/// Day by day record of what the station billed. The week and the month are the sum of
/// the days that were actually recorded — never an estimate.
nonisolated enum StationGoalLedger {
    private static let storageKey = "turnoev.station.billing.v1"

    /// Decoded once and kept in memory: the Operación window reads it while drawing.
    nonisolated(unsafe) private static var cache: [String: Int]?

    private static func load() -> [String: Int] {
        if let cache { return cache }
        let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
        cache = stored
        return stored
    }

    private static func save(_ values: [String: Int]) {
        cache = values
        UserDefaults.standard.set(values, forKey: storageKey)
    }

    private static func key(stationId: String, day: Date) -> String {
        let calendar = ShiftRules.calendar
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(stationId)|\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// Stores what the station has billed today. Called on every refresh, so the figure
    /// of the day is always the latest one rather than an accumulation of reads.
    static func record(stationId: String, day: Date, earningsMxn: Int) {
        var values = load()
        let entry = key(stationId: stationId, day: day)
        guard values[entry] != earningsMxn else { return }
        values[entry] = earningsMxn
        save(values)
    }

    static func earnings(stationId: String, day: Date) -> Int {
        load()[key(stationId: stationId, day: day)] ?? 0
    }

    /// Adds up the days of the week that contains the reference date.
    static func weekEarnings(stationId: String, reference: Date) -> Int {
        let calendar = ShiftRules.calendar
        let start = ShiftRules.weekStart(for: reference)
        return (0..<7).reduce(0) { total, offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return total }
            return total + earnings(stationId: stationId, day: day)
        }
    }

    static func monthEarnings(stationId: String, reference: Date) -> Int {
        let calendar = ShiftRules.calendar
        guard let range = calendar.range(of: .day, in: .month, for: reference) else { return 0 }
        var components = calendar.dateComponents([.year, .month], from: reference)
        return range.reduce(0) { total, dayNumber in
            components.day = dayNumber
            guard let day = calendar.date(from: components) else { return total }
            return total + earnings(stationId: stationId, day: day)
        }
    }

    static func clear() {
        cache = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Attention

/// Where a situation sends the supervisor when he taps it.
nonisolated enum StationAttentionTarget: Sendable {
    case drivers(DriverFilter)
    case vehicles(FleetVehicleState?)
    case coverage
    case alerts
}

nonisolated enum StationAttentionLevel: String, Sendable {
    case problem
    case warning
    case info

    var symbol: String {
        switch self {
        case .problem: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "arrow.triangle.2.circlepath"
        }
    }
}

/// One line of the Atención card. It is never a permanent metric: if the situation is
/// resolved, the line disappears.
nonisolated struct StationAttentionItem: Identifiable, Sendable {
    let id: String
    let title: String
    let level: StationAttentionLevel
    let symbol: String
    let target: StationAttentionTarget
}
