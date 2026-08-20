import Foundation

/// Resolver ausencias — internal name: cobertura de turnos.
///
/// When a driver does not show up, a unit that should be billing is parked. This module
/// recovers that capacity by itself: it waits out the tolerance, declares the absence,
/// opens the opportunities the station can actually fill, offers them to the
/// complementary roster, picks a substitute and reports the result.
///
/// The supervisor does not take part in the ordinary path. He is called only when the
/// rules cannot produce a valid answer.
///
/// Nothing here owns data of its own: attendance comes from the roster, units from the
/// fleet, candidates and eligibility from Guardias, and money from the weekly cut.

// MARK: - Policy

/// Every threshold of the module. Administration adjusts these; none of them is frozen
/// in code.
nonisolated struct AbsencePolicy: Codable, Sendable, Equatable {
    /// Minutes after the scheduled start before a missing driver stops being late and
    /// becomes an absence. Until this passes nothing is substituted.
    var toleranceMinutes: Int
    /// A substitute is only worth calling if he can still work at least this long.
    var minimumProductiveMinutes: Int
    /// How long a selected candidate holds the opportunity before it moves on.
    var confirmationWindowMinutes: Int
    /// Productivity objective of a coverage, per hour of effective work.
    var hourlyGoalMxn: Int
    /// Pay of a full shift, used to derive the per-minute rate.
    var shiftPayMxn: Int

    static let standard = AbsencePolicy(
        toleranceMinutes: 60,
        minimumProductiveMinutes: 120,
        confirmationWindowMinutes: 15,
        hourlyGoalMxn: 190,
        shiftPayMxn: 450
    )

    /// Objective per minute of effective work, derived — never hardcoded.
    var goalPerMinuteMxn: Double { Double(hourlyGoalMxn) / 60 }

    /// Rate per effective minute, derived from the pay of a full shift.
    func ratePerMinuteMxn(shiftMinutes: Int) -> Double {
        guard shiftMinutes > 0 else { return 0 }
        return Double(shiftPayMxn) / Double(shiftMinutes)
    }
}

/// How many reserve units a station keeps and how far the engine may go into them.
/// A young station runs with zero; a mature one keeps a few.
nonisolated struct ReservePolicy: Codable, Sendable, Equatable {
    /// Units the station is meant to hold as reserve.
    var targetUnits: Int
    /// Of those, the most that may be put to extraordinary production at once.
    var maxInExtraordinaryUse: Int
    /// Units always held back for a contingency, never offered.
    var minimumProtected: Int

    static let standard = ReservePolicy(targetUnits: 1, maxInExtraordinaryUse: 1, minimumProtected: 0)

    /// The engine can never promise more than the policy allows.
    func usableUnits(available: Int) -> Int {
        let free = max(0, available - minimumProtected)
        return min(free, maxInExtraordinaryUse)
    }
}

/// Configuration store of the module, per station. Written by the laboratory and by
/// Administration; read by the engine.
nonisolated enum AbsenceResolutionConfig {
    private static let policyKey = "turnoev.absence.policy.v1"

    nonisolated(unsafe) private static var policyCache: AbsencePolicy?

    static var policy: AbsencePolicy {
        if let policyCache { return policyCache }
        guard let data = UserDefaults.standard.data(forKey: policyKey),
              let decoded = try? JSONDecoder().decode(AbsencePolicy.self, from: data) else {
            policyCache = .standard
            return .standard
        }
        policyCache = decoded
        return decoded
    }

    static func setPolicy(_ policy: AbsencePolicy) {
        policyCache = policy
        guard let data = try? JSONEncoder().encode(policy) else { return }
        UserDefaults.standard.set(data, forKey: policyKey)
    }

    private static func reserveKey(_ stationId: String) -> String {
        "turnoev.absence.reserve.\(stationId)"
    }

    static func reservePolicy(stationId: String) -> ReservePolicy {
        guard let data = UserDefaults.standard.data(forKey: reserveKey(stationId)),
              let decoded = try? JSONDecoder().decode(ReservePolicy.self, from: data) else {
            return .standard
        }
        return decoded
    }

    static func setReservePolicy(_ policy: ReservePolicy, stationId: String) {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        UserDefaults.standard.set(data, forKey: reserveKey(stationId))
    }

    static func reset() {
        policyCache = nil
        UserDefaults.standard.removeObject(forKey: policyKey)
    }
}

// MARK: - Reserve fleet

/// A unit pulled out of the ordinary rotation does not become a reserve by itself. It has
/// to be approved as one, and only approved units ever appear in this group.
nonisolated enum ReserveFleetRegistry {
    private static let storageKey = "turnoev.absence.reservefleet.v1"

    nonisolated(unsafe) private static var cache: Set<String>?

    private static func load() -> Set<String> {
        if let cache { return cache }
        let stored = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
        cache = stored
        return stored
    }

    private static func save(_ ids: Set<String>) {
        cache = ids
        UserDefaults.standard.set(Array(ids), forKey: storageKey)
    }

    static func isApproved(vehicleId: String) -> Bool { load().contains(vehicleId) }

    static func approve(vehicleId: String) {
        var current = load()
        current.insert(vehicleId)
        save(current)
    }

    static func revoke(vehicleId: String) {
        var current = load()
        current.remove(vehicleId)
        save(current)
    }

    static func approvedIds() -> [String] { Array(load()).sorted() }

    static func clear() {
        cache = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

/// What the station can see of its reserve at a glance.
nonisolated struct ReserveStatus: Sendable {
    let configured: Int
    let approved: Int
    let available: Int
    let inUse: Int
    let inMaintenance: Int
    let policy: ReservePolicy

    /// Units the engine may commit right now, after protecting the contingency.
    var usable: Int { policy.usableUnits(available: available) }

    var label: String { "\(available)/\(max(configured, approved))" }
}

// MARK: - Attendance

/// The three states the tolerance produces. Nothing else decides an absence.
nonisolated enum AttendanceVerdict: String, Sendable {
    case pending
    case onTime
    case late
    case absent

    var label: String {
        switch self {
        case .pending: "Por iniciar"
        case .onTime: "A tiempo"
        case .late: "Demorado"
        case .absent: "Ausente"
        }
    }
}

nonisolated enum AttendanceRules {
    /// Late while inside the tolerance, absent the second it ends. A validated check-in
    /// closes the question whatever the hour.
    static func verdict(
        scheduledStart: Date,
        checkIn: Date?,
        now: Date,
        policy: AbsencePolicy
    ) -> AttendanceVerdict {
        if let checkIn {
            let lateMinutes = Int(checkIn.timeIntervalSince(scheduledStart) / 60)
            return lateMinutes > 0 ? .late : .onTime
        }
        guard now >= scheduledStart else { return .pending }
        let deadline = scheduledStart.addingTimeInterval(TimeInterval(policy.toleranceMinutes * 60))
        return now >= deadline ? .absent : .late
    }

    /// The instant a missing driver stops being late.
    static func absenceDeadline(scheduledStart: Date, policy: AbsencePolicy) -> Date {
        scheduledStart.addingTimeInterval(TimeInterval(policy.toleranceMinutes * 60))
    }
}

// MARK: - Opportunities

/// The two productive things an absence can generate.
nonisolated enum OpportunityKind: String, Codable, Sendable {
    /// The unit the absent driver left parked, until its return hour.
    case ordinary
    /// An approved reserve unit, with no owner and no fixed return hour.
    case extraordinary

    var label: String {
        switch self {
        case .ordinary: "Cobertura ordinaria"
        case .extraordinary: "Guardia extraordinaria"
        }
    }

    var symbol: String {
        switch self {
        case .ordinary: "car.side.fill"
        case .extraordinary: "sparkles"
        }
    }
}

nonisolated enum OpportunityStatus: String, Codable, Sendable {
    case searching
    case offered
    case held
    case assigned
    case working
    case completed
    case escalated
    case closed

    var label: String {
        switch self {
        case .searching: "Buscando sustituto"
        case .offered: "Ofertada"
        case .held: "Reservada temporalmente"
        case .assigned: "Sustituto asignado"
        case .working: "En curso"
        case .completed: "Completada"
        case .escalated: "Intervención requerida"
        case .closed: "Cerrada"
        }
    }

    var symbol: String {
        switch self {
        case .searching, .offered: "gearshape.2.fill"
        case .held: "hourglass"
        case .assigned: "checkmark.seal.fill"
        case .working: "steeringwheel"
        case .completed: "flag.checkered"
        case .escalated: "exclamationmark.triangle.fill"
        case .closed: "slash.circle.fill"
        }
    }

    var isOpen: Bool {
        switch self {
        case .searching, .offered, .held: true
        default: false
        }
    }

    var isResolved: Bool {
        switch self {
        case .assigned, .working, .completed: true
        default: false
        }
    }
}

/// A driver who accepted an opportunity and said when he can be at the station.
nonisolated struct OpportunityOffer: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    let driverName: String
    let employeeNumber: String
    /// Hour the driver committed to. It selects the candidate; it never pays anything.
    var eta: Date
    let acceptedAt: Date
    /// Guards this person already accumulated, used to spread opportunities around.
    let accumulatedGuards: Int
    /// 0–100 of how he behaves with guards.
    let reliabilityScore: Int
    var declined: Bool = false

    /// Minutes this offer can actually work before the unit has to be back.
    func productiveMinutes(until limit: Date) -> Int {
        max(0, Int(limit.timeIntervalSince(eta) / 60))
    }
}

/// One thing to fill: a unit, a window and whoever ends up driving it.
nonisolated struct CoverageOpportunity: Codable, Identifiable, Sendable {
    let id: String
    let kind: OpportunityKind
    var vehicleId: String?
    var vehicleNumber: String
    /// Earliest moment a substitute could be useful.
    let opensAt: Date
    /// Hour the unit has to be back. Reserve units are flexible, so this is the block end.
    let returnBy: Date
    /// Reserve units do not answer to the hour of the original block.
    var isFlexible: Bool
    var status: OpportunityStatus
    var offers: [OpportunityOffer]
    /// Driver holding the opportunity while he confirms.
    var heldByDriverId: String?
    var heldUntil: Date?
    var assignedDriverId: String?
    var assignedDriverName: String?
    var assignedEta: Date?
    /// Filled from the real check-in and check-out, never from the ETA.
    var checkInAt: Date?
    var checkOutAt: Date?
    var earningsMxn: Int
    /// Seat opened in Guardias, so this module never becomes a second engine.
    var vacancyId: String?
    var escalationReason: String?

    /// Minutes the assigned driver is expected to have. Flexible units are not cut short
    /// by the block of the absent driver.
    var plannedMinutes: Int {
        guard let eta = assignedEta else { return max(0, Int(returnBy.timeIntervalSince(opensAt) / 60)) }
        return max(0, Int(returnBy.timeIntervalSince(eta) / 60))
    }

    /// Minutes actually worked, from validated check-in to validated check-out.
    var effectiveMinutes: Int {
        guard let checkInAt else { return 0 }
        let end = checkOutAt ?? checkInAt
        return max(0, Int(end.timeIntervalSince(checkInAt) / 60))
    }

    var isPaid: Bool { checkInAt != nil }

    /// Live minutes while the coverage is running.
    func liveMinutes(now: Date) -> Int {
        guard let checkInAt else { return 0 }
        let end = checkOutAt ?? now
        return max(0, Int(end.timeIntervalSince(checkInAt) / 60))
    }

    var windowLabel: String {
        "\(Fmt.clock(assignedEta ?? opensAt))–\(Fmt.clock(returnBy))"
    }
}

// MARK: - Resolution case

nonisolated enum ResolutionStatus: String, Codable, Sendable {
    case detected
    case resolving
    case resolved
    case partiallyResolved
    case escalated
    case closed

    var label: String {
        switch self {
        case .detected: "Ausencia detectada"
        case .resolving: "Buscando sustituto"
        case .resolved: "Ausencia resuelta"
        case .partiallyResolved: "Resuelta parcialmente"
        case .escalated: "Intervención requerida"
        case .closed: "Cerrada"
        }
    }

    var symbol: String {
        switch self {
        case .detected: "exclamationmark.circle.fill"
        case .resolving: "gearshape.2.fill"
        case .resolved: "checkmark.seal.fill"
        case .partiallyResolved: "checkmark.circle"
        case .escalated: "exclamationmark.triangle.fill"
        case .closed: "flag.checkered"
        }
    }
}

/// How well the automatic engine did, so its real efficacy can be measured later.
nonisolated struct ResolutionMetrics: Codable, Sendable {
    var detectedAt: Date
    var firstAcceptanceAt: Date?
    var assignedAt: Date?
    var candidatesContacted: Int = 0
    var rejections: Int = 0
    var reassignments: Int = 0
    var escalatedAt: Date?

    /// From the moment the absence was confirmed to the moment somebody was assigned.
    var resolutionMinutes: Int? {
        guard let assignedAt else { return nil }
        return max(0, Int(assignedAt.timeIntervalSince(detectedAt) / 60))
    }

    var minutesToFirstAcceptance: Int? {
        guard let firstAcceptanceAt else { return nil }
        return max(0, Int(firstAcceptanceAt.timeIntervalSince(detectedAt) / 60))
    }

    var wasAutomatic: Bool { assignedAt != nil && escalatedAt == nil }
}

/// One absence and everything the engine did about it.
nonisolated struct AbsenceResolutionCase: Codable, Identifiable, Sendable {
    let id: String
    let stationId: String
    let stationCode: String
    let date: Date
    let slot: ShiftSlot
    let group: ShiftGroup
    let absentDriverId: String
    let absentDriverName: String
    let scheduledStart: Date
    let scheduledEnd: Date
    var status: ResolutionStatus
    var opportunities: [CoverageOpportunity]
    var metrics: ResolutionMetrics
    var closedAt: Date?

    var ordinary: CoverageOpportunity? { opportunities.first { $0.kind == .ordinary } }
    var extraordinary: CoverageOpportunity? { opportunities.first { $0.kind == .extraordinary } }

    var isOpen: Bool {
        switch status {
        case .detected, .resolving, .escalated: true
        default: false
        }
    }

    var needsSupervisor: Bool { status == .escalated }

    var resolvedCount: Int { opportunities.filter { $0.status.isResolved }.count }
    var searchingCount: Int { opportunities.filter { $0.status.isOpen }.count }

    /// Earliest substitute the engine managed to line up.
    var earliestEta: Date? {
        opportunities.compactMap(\.assignedEta).min()
    }

    var shiftMinutes: Int {
        max(1, Int(scheduledEnd.timeIntervalSince(scheduledStart) / 60))
    }
}

// MARK: - Weekly cut

/// One coverage as the weekly cut records it: separate from the ordinary day, paid by
/// effective minute, with its whole trace attached.
nonisolated struct CoverageEarning: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    let driverName: String
    let stationId: String
    let date: Date
    let kind: OpportunityKind
    let vehicleNumber: String
    let substitutedDriverName: String
    let declaredEta: Date
    let checkInAt: Date
    let checkOutAt: Date
    let effectiveMinutes: Int
    let ratePerMinuteMxn: Double
    let earningsMxn: Int
    let goalPerMinuteMxn: Double

    var payMxn: Int { Int((Double(effectiveMinutes) * ratePerMinuteMxn).rounded()) }
    /// Objective proportional to the time actually worked.
    var proportionalGoalMxn: Int { Int((Double(effectiveMinutes) * goalPerMinuteMxn).rounded()) }
    var attainment: Double {
        proportionalGoalMxn > 0 ? Double(earningsMxn) / Double(proportionalGoalMxn) : 0
    }

    var hourlyEarningsMxn: Double {
        effectiveMinutes > 0 ? Double(earningsMxn) / (Double(effectiveMinutes) / 60) : 0
    }

    /// Real arrival against the hour the driver promised. Information, never a sanction.
    var etaDriftMinutes: Int { Int(checkInAt.timeIntervalSince(declaredEta) / 60) }

    var windowLabel: String { "\(Fmt.clock(checkInAt))–\(Fmt.clock(checkOutAt))" }
}

/// Ledger of coverage pay. It sits beside the ordinary cut; it never mixes with it.
nonisolated enum CoverageEarningLedger {
    private static let storageKey = "turnoev.absence.earnings.v1"

    nonisolated(unsafe) private static var cache: [CoverageEarning]?

    private static func load() -> [CoverageEarning] {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            cache = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([CoverageEarning].self, from: data)) ?? []
        cache = decoded
        return decoded
    }

    private static func save(_ entries: [CoverageEarning]) {
        cache = entries
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func all() -> [CoverageEarning] { load().sorted { $0.date > $1.date } }

    static func entries(driverId: String) -> [CoverageEarning] {
        all().filter { $0.driverId == driverId }
    }

    static func entries(driverId: String, weekOf reference: Date) -> [CoverageEarning] {
        entries(driverId: driverId).filter { ShiftRules.isInSameWeek($0.date, as: reference) }
    }

    static func record(_ entry: CoverageEarning) {
        var current = load()
        current.removeAll { $0.id == entry.id }
        current.append(entry)
        save(current)
    }

    static func clear() {
        cache = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Live productivity

/// What a driver sees while covering: the objective grows with the minutes he has
/// actually worked. Being under it is measured, never punished by the app.
nonisolated struct CoverageProductivity: Sendable {
    let effectiveMinutes: Int
    let earningsMxn: Int
    let goalPerMinuteMxn: Double

    var goalSoFarMxn: Int { Int((Double(effectiveMinutes) * goalPerMinuteMxn).rounded()) }
    var attainment: Double { goalSoFarMxn > 0 ? Double(earningsMxn) / Double(goalSoFarMxn) : 0 }
    var hourlyMxn: Double {
        effectiveMinutes > 0 ? Double(earningsMxn) / (Double(effectiveMinutes) / 60) : 0
    }
    var isAboveGoal: Bool { earningsMxn >= goalSoFarMxn }
}
