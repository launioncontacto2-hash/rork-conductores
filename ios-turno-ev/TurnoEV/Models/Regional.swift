import Foundation

/// Regional management domain: what a regional manager reads and decides. The scope is
/// a region — several stations, each with up to 100 units, 4 driver shifts, 2
/// supervisors and its maintenance staff. A manager never operates a station: it
/// compares them, authorizes hires, and signs off bonuses, credits and unit retirements.

// MARK: - Station scorecard

nonisolated enum StationHealth: String, Codable, Sendable {
    case strong
    case steady
    case watch
    case critical

    var label: String {
        switch self {
        case .strong: "Sólida"
        case .steady: "Estable"
        case .watch: "En observación"
        case .critical: "Crítica"
        }
    }

    var symbol: String {
        switch self {
        case .strong: "checkmark.seal.fill"
        case .steady: "equal.circle.fill"
        case .watch: "eye.trianglebadge.exclamationmark.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

/// One station as the region reads it: money, people, fleet and risk in a single card.
nonisolated struct StationScorecard: Codable, Identifiable, Sendable {
    let id: String
    let code: String
    let name: String
    let city: String

    // Fleet
    /// Units the network authorized for this station. The billing goal hangs from this
    /// number, never from how many seats are covered today.
    var vehicleCapacity: Int
    var fleetSize: Int
    var operatingVehicles: Int
    var availableVehicles: Int
    var inMaintenance: Int
    var outOfService: Int

    // People on the current shift
    var slot: ShiftSlot
    var rosterSize: Int
    var presentDrivers: Int
    var lateDrivers: Int
    var absentDrivers: Int
    /// Full payroll of the station: 4 shifts.
    var payrollSize: Int

    // Money
    var earningsMxn: Int
    /// Fixed goal of the observed shift: authorized units × the driver goal of the day.
    var goalMxn: Int
    var tripsToday: Int
    /// Monday to Sunday billing of the current week.
    var weekEarnings: [Int]
    var weekGoalMxn: Int
    /// Group the fixed goal was computed with, so the card can name it.
    var goalGroup: ShiftGroup

    // Quality
    var punctualityPct: Double
    var carePct: Double
    var ratingAvg: Double
    var pendingHandovers: Int
    var openIncidents: Int
    var criticalIncidents: Int

    // Program portfolio
    var creditCurrent: Int
    var creditBehind: Int
    var creditDelivered: Int
    var bonusEligible: Int
    var bonusAtRisk: Int

    var supervisorIds: [String]
    var maintenanceIds: [String]
    /// True for the station whose live operation comes from the shared database.
    var isLive: Bool

    var goalRatio: Double { goalMxn > 0 ? Double(earningsMxn) / Double(goalMxn) : 0 }

    /// Money still missing to close the fixed goal of the shift.
    var goalGapMxn: Int { max(0, goalMxn - earningsMxn) }

    /// Per-driver goal the fixed station goal is built from.
    var driverGoalMxn: Int { ShiftRules.goals(for: goalGroup).dailyMxn }

    /// Both blocks of the day at the fixed rate.
    var dayGoalMxn: Int { goalMxn * ShiftRules.slotsPerDay }

    /// What each present driver must bill for the shift to reach its fixed goal.
    var shareOfGoalMxn: Int {
        ShiftRules.shareOfShiftGoalMxn(
            capacity: vehicleCapacity,
            group: goalGroup,
            presentDrivers: presentDrivers
        )
    }

    /// Seats of the shift that nobody is covering: each one is a full driver goal that
    /// the drivers on the floor have to absorb.
    var uncoveredSeats: Int { max(0, vehicleCapacity - presentDrivers) }

    /// Money the uncovered seats leave on the table at the standard rate.
    var uncoveredGoalMxn: Int { uncoveredSeats * driverGoalMxn }

    var weekEarningsMxn: Int { weekEarnings.reduce(0, +) }

    var weekGoalRatio: Double { weekGoalMxn > 0 ? Double(weekEarningsMxn) / Double(weekGoalMxn) : 0 }

    var attendanceRatio: Double { rosterSize > 0 ? Double(presentDrivers) / Double(rosterSize) : 0 }

    /// Units that can be handed to a driver right now.
    var availabilityRatio: Double { fleetSize > 0 ? Double(fleetSize - inMaintenance - outOfService) / Double(fleetSize) : 0 }

    var utilizationRatio: Double { fleetSize > 0 ? Double(operatingVehicles) / Double(fleetSize) : 0 }

    var creditPortfolio: Int { creditCurrent + creditBehind + creditDelivered }

    /// Weighted health: money first, then attendance, fleet availability and quality,
    /// with a penalty for every critical incident on the floor.
    var healthScore: Double {
        let money = min(1.2, goalRatio) / 1.2
        let people = attendanceRatio
        let fleet = availabilityRatio
        let quality = (punctualityPct + carePct) / 200
        let penalty = min(0.25, Double(criticalIncidents) * 0.08)
        return max(0, min(1, money * 0.4 + people * 0.24 + fleet * 0.18 + quality * 0.18 - penalty))
    }

    var health: StationHealth {
        if criticalIncidents > 1 || healthScore < 0.55 { return .critical }
        if healthScore < 0.68 { return .watch }
        if healthScore < 0.82 { return .steady }
        return .strong
    }
}

// MARK: - Station directory

/// One person of the station's plantilla, with the line that reaches them. The
/// manager does not need an org chart: they need the four desks that hold the
/// station up — the two supervisors, the workshop and the recruitment desk — and a
/// way to call any of them in one tap.
nonisolated struct StationContact: Identifiable, Sendable {
    nonisolated enum Desk: String, CaseIterable, Hashable, Sendable {
        case supervision
        case workshop
        case recruitment

        var symbol: String {
            switch self {
            case .supervision: "person.2.badge.gearshape.fill"
            case .workshop: "wrench.and.screwdriver.fill"
            case .recruitment: "person.crop.circle.badge.plus"
            }
        }

        var label: String {
            switch self {
            case .supervision: "Supervisión"
            case .workshop: "Mantenimiento"
            case .recruitment: "Reclutamiento"
            }
        }
    }

    let id: String
    let name: String
    let employeeNumber: String
    let desk: Desk
    /// What this person covers: the shift they hold or the scope of their desk.
    let duty: String
    let phone: String

    /// Digits only, ready for a `tel://` URL. Nil when the line is incomplete, so the
    /// interface never offers a call it cannot place.
    var dialablePhone: String? {
        let digits = phone.filter(\.isNumber)
        return digits.count >= 10 ? digits : nil
    }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    /// Stable line for staff that only exists in the simulated roster: the same person
    /// always shows the same number, so the directory never looks like it is guessing.
    static func derivedPhone(id: String, city: String) -> String {
        let lada: String
        switch city.lowercased() {
        case let value where value.contains("guadalajara"): lada = "33"
        case let value where value.contains("monterrey"): lada = "81"
        default: lada = "55"
        }
        var hash = 5381
        for scalar in id.unicodeScalars {
            hash = (hash &* 33 &+ Int(scalar.value)) & 0x00FF_FFFF
        }
        let first = 1000 + (hash % 9000)
        let second = 1000 + ((hash / 9000) % 9000)
        return "\(lada) \(first) \(second)"
    }
}

// MARK: - Supervisor scorecard

/// How each supervisor of the region is holding their shift.
nonisolated struct SupervisorScorecard: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let employeeNumber: String
    let stationId: String
    let stationCode: String
    let slot: ShiftSlot
    var driversManaged: Int
    var approvalsToday: Int
    var pendingHandovers: Int
    /// Minutes a driver waits, on average, for the supervisor's signature.
    var avgResponseMinutes: Int
    var punctualityPct: Double
    var incidentsRaised: Int
    var isLive: Bool

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    /// Slow signatures hold the whole shift back, so response time drives the flag.
    var isBacklogged: Bool { pendingHandovers >= 8 || avgResponseMinutes >= 14 }
}

// MARK: - Authorizations

nonisolated enum RegionalRequestKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Recruitment wants to sign a plaza above the authorized plantilla. Ordinary hires
    /// never reach the manager: the recruitment desk signs them by itself.
    case hiring
    /// Credit application of a driver of the region.
    case credit
    /// Unit leaving the fleet, by kilometres or after an accident.
    case retirement

    // Bonuses are deliberately absent: they are resolved by the goal engine, never
    // signed driver by driver. See `BonusRules` and the national policy book.

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hiring: "Plaza adicional"
        case .credit: "Solicitud de crédito"
        case .retirement: "Baja de unidad"
        }
    }

    var shortLabel: String {
        switch self {
        case .hiring: "Plazas"
        case .credit: "Créditos"
        case .retirement: "Bajas"
        }
    }

    var symbol: String {
        switch self {
        case .hiring: "person.badge.plus.fill"
        case .credit: "creditcard.fill"
        case .retirement: "car.badge.xmark"
        }
    }

    var subjectLabel: String {
        switch self {
        case .hiring, .credit: "Conductor"
        case .retirement: "Unidad"
        }
    }

    /// What the manager confirms before signing. Reuses the supervisor's checklist idea.
    var checks: [RequestCheck] {
        switch self {
        case .hiring:
            [
                RequestCheck(id: "record", title: "Expediente completo de reclutamiento", hint: "Entrevista firmada y documentación al 100 %"),
                RequestCheck(id: "payroll", title: "La plaza cabe en el costo del mes", hint: "Es una plaza adicional a la plantilla autorizada"),
                RequestCheck(id: "capacity", title: "El turno admite un conductor más", hint: "Máximo 100 conductores por turno"),
            ]
        case .credit:
            [
                RequestCheck(id: "seniority", title: "Antigüedad mínima cumplida", hint: "Historial dentro del programa"),
                RequestCheck(id: "behaviour", title: "Cumplimiento de metas y asistencia", hint: "Comportamiento crediticio del conductor"),
                RequestCheck(id: "unit", title: "Unidad reservada para el contrato", hint: "Sale de flotilla entre 110 y 120 mil km"),
                RequestCheck(id: "terms", title: "Condiciones explicadas al conductor", hint: "48 meses, 192 abonos vía nómina"),
            ]
        case .retirement:
            [
                RequestCheck(id: "diagnosis", title: "Diagnóstico de taller firmado", hint: "Mantenimiento documentó el daño"),
                RequestCheck(id: "evidence", title: "Evidencia fotográfica completa", hint: "Estado de la unidad al retirarse"),
                RequestCheck(id: "replacement", title: "Reemplazo cubierto en la estación", hint: "La capacidad del turno no se afecta"),
            ]
        }
    }
}

nonisolated struct RequestCheck: Identifiable, Sendable {
    let id: String
    let title: String
    let hint: String
}

nonisolated enum ApprovalStatus: String, Codable, Sendable {
    case pending
    case authorized
    case rejected

    var label: String {
        switch self {
        case .pending: "Por autorizar"
        case .authorized: "Autorizada"
        case .rejected: "Rechazada"
        }
    }
}

/// One decision waiting on the regional manager's desk.
nonisolated struct RegionalRequest: Codable, Identifiable, Sendable {
    let id: String
    let kind: RegionalRequestKind
    let stationId: String
    let stationCode: String
    /// Person or unit the request is about.
    let subject: String
    let subjectDetail: String
    let amountMxn: Int?
    let detail: String
    let createdAt: Date
    let requestedBy: String
    let requestedByRole: StaffRole
    var priority: IncidentSeverity
    var checks: [String: Bool]
    var status: ApprovalStatus
    var resolvedAt: Date?
    var decisionNote: String?
    let photoAsset: String?
    /// The request belongs to the driver running the app on this device.
    let isLiveSession: Bool

    var requiredChecks: [RequestCheck] { kind.checks }

    func isChecked(_ check: RequestCheck) -> Bool { checks[check.id] == true }

    var completedChecks: Int { requiredChecks.filter { isChecked($0) }.count }

    var isReadyToAuthorize: Bool { completedChecks == requiredChecks.count }

    func ageHours(now: Date) -> Int { max(0, Int(now.timeIntervalSince(createdAt) / 3_600)) }

    /// Anything older than a day blocks a station, so it is escalated on the board.
    func isAging(now: Date) -> Bool { status == .pending && ageHours(now: now) >= 24 }
}

nonisolated enum RequestFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case hiring
    case credit
    case retirement

    var id: String { rawValue }

    var kind: RegionalRequestKind? {
        switch self {
        case .all: nil
        case .hiring: .hiring
        case .credit: .credit
        case .retirement: .retirement
        }
    }

    var label: String { kind?.shortLabel ?? "Todas" }

    var symbol: String { kind?.symbol ?? "tray.full.fill" }
}

// MARK: - Regional alerts

nonisolated enum RegionalAlertKind: String, Codable, CaseIterable, Sendable {
    case belowGoal
    case absenteeism
    case fleetIdle
    case maintenanceBacklog
    case criticalIncident
    case agingRequest
    case supervisorBacklog

    var label: String {
        switch self {
        case .belowGoal: "Facturación por debajo de meta"
        case .absenteeism: "Ausentismo alto"
        case .fleetIdle: "Flotilla detenida"
        case .maintenanceBacklog: "Rezago de taller"
        case .criticalIncident: "Incidente crítico"
        case .agingRequest: "Autorización detenida"
        case .supervisorBacklog: "Supervisión saturada"
        }
    }

    var symbol: String {
        switch self {
        case .belowGoal: "chart.line.downtrend.xyaxis"
        case .absenteeism: "person.fill.xmark"
        case .fleetIdle: "car.badge.xmark"
        case .maintenanceBacklog: "wrench.and.screwdriver.fill"
        case .criticalIncident: "exclamationmark.octagon.fill"
        case .agingRequest: "hourglass.badge.plus"
        case .supervisorBacklog: "person.2.badge.gearshape.fill"
        }
    }
}

nonisolated struct RegionalAlert: Identifiable, Sendable {
    let id: String
    let kind: RegionalAlertKind
    let severity: IncidentSeverity
    let title: String
    let detail: String
    let stationId: String?
    let requestId: String?
    let createdAt: Date
}

// MARK: - Consolidated metrics

nonisolated struct RegionMetrics: Sendable {
    let stations: Int
    let fleetSize: Int
    let operatingVehicles: Int
    let idleVehicles: Int
    let payrollSize: Int
    let onShiftDrivers: Int
    let presentDrivers: Int
    let absentDrivers: Int
    let lateDrivers: Int
    let earningsMxn: Int
    let goalMxn: Int
    let weekEarningsMxn: Int
    let weekGoalMxn: Int
    let tripsToday: Int
    let pendingRequests: Int
    let agingRequests: Int
    let openIncidents: Int
    let criticalIncidents: Int
    let creditPortfolio: Int
    let creditBehind: Int
    let bonusAtRisk: Int

    var goalRatio: Double { goalMxn > 0 ? Double(earningsMxn) / Double(goalMxn) : 0 }
    var weekGoalRatio: Double { weekGoalMxn > 0 ? Double(weekEarningsMxn) / Double(weekGoalMxn) : 0 }
    var attendanceRatio: Double { onShiftDrivers > 0 ? Double(presentDrivers) / Double(onShiftDrivers) : 0 }
    var utilizationRatio: Double { fleetSize > 0 ? Double(operatingVehicles) / Double(fleetSize) : 0 }
}

/// A single day of the regional billing series.
nonisolated struct RegionDayPoint: Identifiable, Sendable {
    let date: Date
    let amountMxn: Int
    let goalMxn: Int
    let isToday: Bool
    let isFuture: Bool

    var id: Date { date }
    var ratio: Double { goalMxn > 0 ? Double(amountMxn) / Double(goalMxn) : 0 }
}

// MARK: - Rules

/// Management rules: the manager's split shift, thresholds and the alert engine.
nonisolated enum RegionalRules {
    /// The regional manager covers two blocks so both station shifts are seen live.
    static let morningBlock = (start: 8 * 60, end: 12 * 60)
    static let eveningBlock = (start: 16 * 60, end: 20 * 60)

    static let blockLabel = "08:00 — 12:00 · 16:00 — 20:00"

    /// Below this ratio of the daily goal a station is flagged.
    static let goalFloor: Double = 0.85
    /// Above this share of absent drivers the shift is at risk.
    static let absenteeismCeiling: Double = 0.06
    /// Below this share of usable units the station cannot cover its shifts.
    static let availabilityFloor: Double = 0.88
    static let maintenanceBacklogCeiling = 8

    enum DutyBlock: Sendable {
        case morning
        case evening
        case off

        var label: String {
            switch self {
            case .morning: "Bloque matutino"
            case .evening: "Bloque vespertino"
            case .off: "Fuera de bloque"
            }
        }

        var rangeLabel: String {
            switch self {
            case .morning: "08:00 — 12:00"
            case .evening: "16:00 — 20:00"
            case .off: blockLabel
            }
        }
    }

    static func dutyBlock(now: Date) -> DutyBlock {
        let current = ShiftRules.minutesOfDay(now)
        if current >= morningBlock.start && current <= morningBlock.end { return .morning }
        if current >= eveningBlock.start && current <= eveningBlock.end { return .evening }
        return .off
    }

    /// Progress inside the current block, used by the header bar.
    static func blockProgress(now: Date) -> Double {
        let current = Double(ShiftRules.minutesOfDay(now))
        switch dutyBlock(now: now) {
        case .morning:
            return (current - Double(morningBlock.start)) / Double(morningBlock.end - morningBlock.start)
        case .evening:
            return (current - Double(eveningBlock.start)) / Double(eveningBlock.end - eveningBlock.start)
        case .off:
            return 0
        }
    }

    /// Station shift the manager is looking at, following their own block.
    static func observedSlot(now: Date) -> ShiftSlot {
        ShiftRules.minutesOfDay(now) < ShiftRules.window(for: .evening).start ? .morning : .evening
    }

    /// Region-wide totals from the station cards.
    static func metrics(
        scorecards: [StationScorecard],
        requests: [RegionalRequest],
        now: Date
    ) -> RegionMetrics {
        let pending = requests.filter { $0.status == .pending }
        return RegionMetrics(
            stations: scorecards.count,
            fleetSize: scorecards.reduce(0) { $0 + $1.fleetSize },
            operatingVehicles: scorecards.reduce(0) { $0 + $1.operatingVehicles },
            idleVehicles: scorecards.reduce(0) { $0 + $1.inMaintenance + $1.outOfService },
            payrollSize: scorecards.reduce(0) { $0 + $1.payrollSize },
            onShiftDrivers: scorecards.reduce(0) { $0 + $1.rosterSize },
            presentDrivers: scorecards.reduce(0) { $0 + $1.presentDrivers },
            absentDrivers: scorecards.reduce(0) { $0 + $1.absentDrivers },
            lateDrivers: scorecards.reduce(0) { $0 + $1.lateDrivers },
            earningsMxn: scorecards.reduce(0) { $0 + $1.earningsMxn },
            goalMxn: scorecards.reduce(0) { $0 + $1.goalMxn },
            weekEarningsMxn: scorecards.reduce(0) { $0 + $1.weekEarningsMxn },
            weekGoalMxn: scorecards.reduce(0) { $0 + $1.weekGoalMxn },
            tripsToday: scorecards.reduce(0) { $0 + $1.tripsToday },
            pendingRequests: pending.count,
            agingRequests: pending.filter { $0.isAging(now: now) }.count,
            openIncidents: scorecards.reduce(0) { $0 + $1.openIncidents },
            criticalIncidents: scorecards.reduce(0) { $0 + $1.criticalIncidents },
            creditPortfolio: scorecards.reduce(0) { $0 + $1.creditPortfolio },
            creditBehind: scorecards.reduce(0) { $0 + $1.creditBehind },
            bonusAtRisk: scorecards.reduce(0) { $0 + $1.bonusAtRisk }
        )
    }

    /// The regional board is generated, never typed: every card comes from a threshold.
    static func alerts(
        scorecards: [StationScorecard],
        supervisors: [SupervisorScorecard],
        requests: [RegionalRequest],
        now: Date
    ) -> [RegionalAlert] {
        var alerts: [RegionalAlert] = []

        for station in scorecards where station.goalRatio < goalFloor {
            let missing = max(0, station.goalMxn - station.earningsMxn)
            alerts.append(
                RegionalAlert(
                    id: "ralr-goal-\(station.id)",
                    kind: .belowGoal,
                    severity: station.goalRatio < 0.7 ? .high : .medium,
                    title: "\(station.name) al \(Int(station.goalRatio * 100))% de su meta del día",
                    detail: "Faltan \(Fmt.mxn(missing)) para el objetivo de \(Fmt.mxn(station.goalMxn)) del turno \(station.slot.label.lowercased()).",
                    stationId: station.id,
                    requestId: nil,
                    createdAt: now
                )
            )
        }

        for station in scorecards {
            let ratio = station.rosterSize > 0 ? Double(station.absentDrivers) / Double(station.rosterSize) : 0
            guard ratio > absenteeismCeiling else { continue }
            alerts.append(
                RegionalAlert(
                    id: "ralr-abs-\(station.id)",
                    kind: .absenteeism,
                    severity: ratio > 0.1 ? .high : .medium,
                    title: "\(station.name) con \(station.absentDrivers) conductores ausentes",
                    detail: "\(Int(ratio * 100))% del turno sin registro de entrada. \(station.lateDrivers) más llegaron con atraso.",
                    stationId: station.id,
                    requestId: nil,
                    createdAt: now
                )
            )
        }

        for station in scorecards where station.availabilityRatio < availabilityFloor {
            alerts.append(
                RegionalAlert(
                    id: "ralr-fleet-\(station.id)",
                    kind: .fleetIdle,
                    severity: station.availabilityRatio < 0.8 ? .high : .medium,
                    title: "\(station.name) con \(station.inMaintenance + station.outOfService) unidades detenidas",
                    detail: "Solo \(Int(station.availabilityRatio * 100))% de la flotilla puede salir a turno.",
                    stationId: station.id,
                    requestId: nil,
                    createdAt: now
                )
            )
        }

        for station in scorecards where station.inMaintenance >= maintenanceBacklogCeiling {
            alerts.append(
                RegionalAlert(
                    id: "ralr-mto-\(station.id)",
                    kind: .maintenanceBacklog,
                    severity: .medium,
                    title: "Taller de \(station.name) con \(station.inMaintenance) unidades",
                    detail: "Revisa la carga del personal de mantenimiento asignado a la estación.",
                    stationId: station.id,
                    requestId: nil,
                    createdAt: now
                )
            )
        }

        for station in scorecards where station.criticalIncidents > 0 {
            alerts.append(
                RegionalAlert(
                    id: "ralr-inc-\(station.id)",
                    kind: .criticalIncident,
                    severity: .critical,
                    title: "\(station.criticalIncidents) incidente(s) crítico(s) en \(station.name)",
                    detail: "Requieren seguimiento de gerencia y pueden derivar en baja de unidad.",
                    stationId: station.id,
                    requestId: nil,
                    createdAt: now
                )
            )
        }

        for request in requests where request.isAging(now: now) {
            alerts.append(
                RegionalAlert(
                    id: "ralr-req-\(request.id)",
                    kind: .agingRequest,
                    severity: request.ageHours(now: now) >= 48 ? .high : .medium,
                    title: "\(request.kind.label) detenida \(request.ageHours(now: now)) h",
                    detail: "\(request.subject) · \(request.stationCode) · solicitada por \(request.requestedBy).",
                    stationId: request.stationId,
                    requestId: request.id,
                    createdAt: request.createdAt
                )
            )
        }

        for supervisor in supervisors where supervisor.isBacklogged {
            alerts.append(
                RegionalAlert(
                    id: "ralr-sup-\(supervisor.id)",
                    kind: .supervisorBacklog,
                    severity: .medium,
                    title: "\(supervisor.name) con \(supervisor.pendingHandovers) trámites en fila",
                    detail: "Tiempo de respuesta promedio de \(supervisor.avgResponseMinutes) min en \(supervisor.stationCode).",
                    stationId: supervisor.stationId,
                    requestId: nil,
                    createdAt: now
                )
            )
        }

        return alerts.sorted { lhs, rhs in
            lhs.severity.weight == rhs.severity.weight
                ? lhs.createdAt > rhs.createdAt
                : lhs.severity.weight > rhs.severity.weight
        }
    }
}
