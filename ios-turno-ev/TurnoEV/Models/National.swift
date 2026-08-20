import Foundation

/// National direction domain. Direction never operates a station and never signs a
/// station-level document: it reads the country consolidated, opens stations, creates
/// the credentials of managers, supervisors and technicians, and sets the rules every
/// region inherits. Its unit of work is the network, not the shift.

// MARK: - Region rollup

/// A region as direction reads it: the sum of its stations plus the manager that answers
/// for them. Computed, never stored, so it can never drift from the station cards.
nonisolated struct RegionRollup: Identifiable, Sendable {
    let id: String
    let name: String
    let stations: [StationScorecard]
    let pendingApprovals: Int
    let agingApprovals: Int
    /// Stations of this region that are missing their own manager. A region has no
    /// manager of its own: every station runs itself, so this is a count of holes.
    let stationsWithoutManager: [String]

    var stationCount: Int { stations.count }
    var fleetSize: Int { stations.reduce(0) { $0 + $1.fleetSize } }
    var operatingVehicles: Int { stations.reduce(0) { $0 + $1.operatingVehicles } }
    var idleVehicles: Int { stations.reduce(0) { $0 + $1.inMaintenance + $1.outOfService } }
    var payrollSize: Int { stations.reduce(0) { $0 + $1.payrollSize } }
    var rosterSize: Int { stations.reduce(0) { $0 + $1.rosterSize } }
    var presentDrivers: Int { stations.reduce(0) { $0 + $1.presentDrivers } }
    var absentDrivers: Int { stations.reduce(0) { $0 + $1.absentDrivers } }
    var earningsMxn: Int { stations.reduce(0) { $0 + $1.earningsMxn } }
    var goalMxn: Int { stations.reduce(0) { $0 + $1.goalMxn } }
    var weekEarningsMxn: Int { stations.reduce(0) { $0 + $1.weekEarningsMxn } }
    var weekGoalMxn: Int { stations.reduce(0) { $0 + $1.weekGoalMxn } }
    var tripsToday: Int { stations.reduce(0) { $0 + $1.tripsToday } }
    var openIncidents: Int { stations.reduce(0) { $0 + $1.openIncidents } }
    var criticalIncidents: Int { stations.reduce(0) { $0 + $1.criticalIncidents } }
    var creditPortfolio: Int { stations.reduce(0) { $0 + $1.creditPortfolio } }
    var creditBehind: Int { stations.reduce(0) { $0 + $1.creditBehind } }
    var bonusAtRisk: Int { stations.reduce(0) { $0 + $1.bonusAtRisk } }
    var hasLiveStation: Bool { stations.contains { $0.isLive } }
    /// True when every station of the region has someone who can authorize.
    var isFullyManaged: Bool { stationsWithoutManager.isEmpty }
    /// Short line naming who runs the region's stations, for the rollup card.
    var managementLabel: String {
        isFullyManaged
            ? "\(stationCount) estaciones con gerente"
            : "\(stationsWithoutManager.count) sin gerente de \(stationCount)"
    }

    /// Drivers the installed fleet demands: every unit needs four.
    var requiredDrivers: Int { HRRules.requiredDrivers(activeVehicles: fleetSize) }
    var driverDeficit: Int { max(0, requiredDrivers - payrollSize) }
    var staffingRatio: Double { requiredDrivers > 0 ? Double(payrollSize) / Double(requiredDrivers) : 1 }

    var goalRatio: Double { goalMxn > 0 ? Double(earningsMxn) / Double(goalMxn) : 0 }
    var weekGoalRatio: Double { weekGoalMxn > 0 ? Double(weekEarningsMxn) / Double(weekGoalMxn) : 0 }
    var attendanceRatio: Double { rosterSize > 0 ? Double(presentDrivers) / Double(rosterSize) : 0 }
    var utilizationRatio: Double { fleetSize > 0 ? Double(operatingVehicles) / Double(fleetSize) : 0 }

    /// Weighted by fleet: a big station moves the region more than a small one.
    var healthScore: Double {
        guard fleetSize > 0 else { return 0 }
        let weighted = stations.reduce(0.0) { $0 + $1.healthScore * Double($1.fleetSize) }
        return weighted / Double(fleetSize)
    }

    var health: StationHealth {
        if criticalIncidents > 2 || healthScore < 0.55 { return .critical }
        if healthScore < 0.68 { return .watch }
        if healthScore < 0.82 { return .steady }
        return .strong
    }

    /// Monday to Sunday of the region, day by day.
    var weekSeries: [Int] {
        (0..<7).map { offset in
            stations.reduce(0) { total, card in
                total + (card.weekEarnings.indices.contains(offset) ? card.weekEarnings[offset] : 0)
            }
        }
    }

    var stationsNeedingAttention: [StationScorecard] {
        stations.filter { $0.health == .watch || $0.health == .critical }
            .sorted { $0.healthScore < $1.healthScore }
    }

    /// A region is "covered" only when every one of its stations has its own manager.
    var hasManager: Bool { isFullyManaged }
}

// MARK: - Network metrics

/// The country in one struct. Everything direction decides starts from these numbers.
nonisolated struct NetworkMetrics: Sendable {
    let regions: Int
    let stations: Int
    let fleetSize: Int
    let operatingVehicles: Int
    let idleVehicles: Int
    let payrollSize: Int
    let requiredDrivers: Int
    let presentDrivers: Int
    let absentDrivers: Int
    let earningsMxn: Int
    let goalMxn: Int
    let weekEarningsMxn: Int
    let weekGoalMxn: Int
    let tripsToday: Int
    let openIncidents: Int
    let criticalIncidents: Int
    let pendingApprovals: Int
    let agingApprovals: Int
    let creditPortfolio: Int
    let creditBehind: Int
    let bonusAtRisk: Int
    /// Units already approved that are not operating yet.
    let incomingVehicles: Int
    /// Drivers those units will demand once installed.
    let incomingDriverDemand: Int

    var goalRatio: Double { goalMxn > 0 ? Double(earningsMxn) / Double(goalMxn) : 0 }
    var weekGoalRatio: Double { weekGoalMxn > 0 ? Double(weekEarningsMxn) / Double(weekGoalMxn) : 0 }
    var utilizationRatio: Double { fleetSize > 0 ? Double(operatingVehicles) / Double(fleetSize) : 0 }
    var staffingRatio: Double { requiredDrivers > 0 ? Double(payrollSize) / Double(requiredDrivers) : 1 }
    var driverDeficit: Int { max(0, requiredDrivers - payrollSize) }
    /// Money each unit of the network produced today.
    var earningsPerVehicleMxn: Int { fleetSize > 0 ? earningsMxn / fleetSize : 0 }
    /// Fleet the network will run once every approved project is operating.
    var projectedFleet: Int { fleetSize + incomingVehicles }
}

// MARK: - Expansion

/// Stages of opening a station. Direction is the only role that can advance them.
nonisolated enum ProjectStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case study
    case approved
    case site
    case fleet
    case hiring
    case launch
    case operating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .study: "En estudio"
        case .approved: "Autorizada"
        case .site: "Acondicionamiento"
        case .fleet: "Compra de unidades"
        case .hiring: "Contratación"
        case .launch: "Apertura"
        case .operating: "Operando"
        }
    }

    var symbol: String {
        switch self {
        case .study: "doc.text.magnifyingglass"
        case .approved: "checkmark.seal.fill"
        case .site: "hammer.fill"
        case .fleet: "car.2.fill"
        case .hiring: "person.badge.plus.fill"
        case .launch: "flag.checkered"
        case .operating: "bolt.fill"
        }
    }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var next: ProjectStage? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// From here on the station is committed: units were paid for.
    var isCommitted: Bool { order >= ProjectStage.fleet.order }
}

/// A station that does not exist yet. Direction approves it, funds its fleet and follows
/// the hiring it triggers — because every unit purchased demands four drivers.
nonisolated struct StationProject: Codable, Identifiable, Sendable {
    let id: String
    var code: String
    var name: String
    var city: String
    var regionId: String
    /// Units the station opens with.
    var targetVehicles: Int
    var launchDate: Date
    var stage: ProjectStage
    /// Drivers already signed for the new station.
    var hiredDrivers: Int
    var candidatesStarted: Int
    var investmentMxn: Int
    var note: String
    let createdAt: Date
    let createdBy: String

    var requiredDrivers: Int { HRRules.requiredDrivers(activeVehicles: targetVehicles) }
    var driverDeficit: Int { max(0, requiredDrivers - hiredDrivers) }
    var hiringRatio: Double { requiredDrivers > 0 ? Double(hiredDrivers) / Double(requiredDrivers) : 0 }

    func daysToLaunch(now: Date) -> Int {
        let days = ShiftRules.calendar.dateComponents([.day], from: now, to: launchDate).day ?? 0
        return days
    }

    /// Risk of opening without drivers: the only way a station fails on day one.
    func risk(now: Date, averageHiringDays: Int) -> OpsAlertLevel {
        guard stage != .operating else { return .informative }
        return HRRules.hiringRisk(
            daysAvailable: max(0, daysToLaunch(now: now)),
            averageHiringDays: averageHiringDays,
            deficit: driverDeficit
        )
    }

    var stageProgress: Double {
        Double(stage.order) / Double(max(1, ProjectStage.allCases.count - 1))
    }
}

// MARK: - Policy book

/// The rules of the whole network. Stations do not negotiate them: they inherit them.
/// Direction is the only role that can move a number here, and every move is versioned.
nonisolated struct PolicyBook: Codable, Sendable {
    var weekdayHourlyMxn: Int
    var weekdayDailyMxn: Int
    var weekendHourlyMxn: Int
    var weekendDailyMxn: Int
    var tripsPerDay: Int
    var graceMinutes: Int
    var minimumBatteryPct: Int
    var inspectionPhotos: Int
    var driversPerVehicle: Int
    var maxVehiclesPerStation: Int
    var bonusPunctualityMxn: Int
    var bonusBillingMxn: Int
    var bonusCareMxn: Int
    var creditWeeklyMxn: Int
    var creditTermWeeks: Int
    var creditDeliveryMonth: Int
    var version: Int
    var updatedAt: Date
    var updatedBy: String

    /// Values the product ships with, read from the operational rules already in force.
    static func networkDefault(now: Date) -> PolicyBook {
        let weekday = ShiftRules.goals(for: .weekday)
        let weekend = ShiftRules.goals(for: .weekend)
        return PolicyBook(
            weekdayHourlyMxn: weekday.hourlyMxn,
            weekdayDailyMxn: weekday.dailyMxn,
            weekendHourlyMxn: weekend.hourlyMxn,
            weekendDailyMxn: weekend.dailyMxn,
            tripsPerDay: weekday.tripsPerDay,
            graceMinutes: ShiftRules.graceMinutes,
            minimumBatteryPct: ShiftRules.minBatteryPct,
            inspectionPhotos: 6,
            driversPerVehicle: HRRules.driversPerVehicle,
            maxVehiclesPerStation: HRRules.maxVehiclesPerStation,
            bonusPunctualityMxn: BonusSchedule.networkDefault.punctualityMxn,
            bonusBillingMxn: BonusSchedule.networkDefault.billingMxn,
            bonusCareMxn: BonusSchedule.networkDefault.careMxn,
            creditWeeklyMxn: CreditProgram.weeklyMxn,
            creditTermWeeks: CreditProgram.termWeeks,
            creditDeliveryMonth: CreditProgram.deliveryMonth,
            version: 1,
            updatedAt: now,
            updatedBy: "Configuración de origen"
        )
    }

    /// Monthly bonus a driver can reach with the current policy.
    var monthlyBonusCeilingMxn: Int { bonusPunctualityMxn + bonusBillingMxn + bonusCareMxn }

    /// The bonus part of the book, in the shape the rest of the app consumes.
    var bonusSchedule: BonusSchedule {
        BonusSchedule(
            punctualityMxn: bonusPunctualityMxn,
            billingMxn: bonusBillingMxn,
            careMxn: bonusCareMxn,
            version: version,
            updatedAt: updatedAt,
            updatedBy: updatedBy
        )
    }
}

/// One movement of the policy book. Nothing is edited silently.
nonisolated struct PolicyChange: Codable, Identifiable, Sendable {
    let id: String
    let field: String
    let previousValue: String
    let newValue: String
    let changedAt: Date
    let changedBy: String
    let note: String
}

// MARK: - Credentials

/// A credential direction created. Managers, supervisors and technicians are born here;
/// drivers never are — those belong to the station that hires them.
nonisolated struct NetworkCredential: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var employeeNumber: String
    var email: String
    var role: StaffRole
    var stationId: String?
    var regionId: String?
    var slot: ShiftSlot?
    var status: StaffStatus
    let createdAt: Date
    let createdBy: String
    /// Temporary password handed to the person on their first day.
    let temporaryPassword: String

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var scopeLabel: String {
        switch role {
        case .manager, .supervisor, .maintenance, .recruiter:
            StaffDirectory.station(id: stationId)?.displayName ?? "Sin estación"
        default:
            role.scopeLabel
        }
    }
}

/// Result of trying to create a credential; direction sees exactly why it was blocked.
nonisolated enum CredentialOutcome: Sendable {
    case created(NetworkCredential)
    case duplicateEmail
    case duplicateEmployeeNumber
    case missingScope
    case slotTaken(String)
    case notAllowed

    var message: String? {
        switch self {
        case .created: nil
        case .duplicateEmail: "Ese correo ya pertenece a una credencial de la red."
        case .duplicateEmployeeNumber: "Ese número de empleado ya está asignado."
        case .missingScope: "Asigna la estación antes de generar la credencial."
        case .slotTaken(let name): "Ese puesto ya lo cubre \(name). Suspende esa credencial primero."
        case .notAllowed: "Dirección solo genera gerentes, supervisores, mantenimiento y reclutamiento."
        }
    }
}

// MARK: - National alerts

nonisolated enum NationalAlertKind: String, Codable, CaseIterable, Sendable {
    case regionBelowGoal
    case stationCritical
    case staffingGap
    case managerVacancy
    case agingApproval
    case creditRisk
    case projectAtRisk
    case fleetIdle

    var label: String {
        switch self {
        case .regionBelowGoal: "Región por debajo de meta"
        case .stationCritical: "Estación crítica"
        case .staffingGap: "Plantilla incompleta"
        case .managerVacancy: "Estación sin gerente"
        case .agingApproval: "Autorización detenida"
        case .creditRisk: "Cartera de crédito en riesgo"
        case .projectAtRisk: "Apertura en riesgo"
        case .fleetIdle: "Flotilla detenida"
        }
    }

    var symbol: String {
        switch self {
        case .regionBelowGoal: "chart.line.downtrend.xyaxis"
        case .stationCritical: "exclamationmark.octagon.fill"
        case .staffingGap: "person.badge.minus"
        case .managerVacancy: "person.crop.circle.badge.questionmark"
        case .agingApproval: "hourglass.badge.plus"
        case .creditRisk: "creditcard.trianglebadge.exclamationmark"
        case .projectAtRisk: "flag.slash.fill"
        case .fleetIdle: "car.badge.xmark"
        }
    }

    /// Where direction should land when it opens the card.
    var destination: NationalDestination {
        switch self {
        case .regionBelowGoal, .stationCritical, .fleetIdle, .agingApproval: .regions
        case .staffingGap, .managerVacancy: .directory
        case .projectAtRisk: .expansion
        case .creditRisk: .policy
        }
    }
}

nonisolated enum NationalDestination: String, Sendable {
    case regions
    case directory
    case expansion
    case policy
}

nonisolated struct NationalAlert: Identifiable, Sendable {
    let id: String
    let kind: NationalAlertKind
    let level: OpsAlertLevel
    let title: String
    let detail: String
    let regionId: String?
    let createdAt: Date
}

// MARK: - Rules

/// Consolidation and the national alert engine. Direction reads a board, not a list.
nonisolated enum NationalRules {
    /// Below this share of the daily goal a whole region is flagged.
    static let regionGoalFloor: Double = 0.88
    /// Below this share of the required payroll the network cannot cover its blocks.
    static let staffingFloor: Double = 0.92
    /// Above this share of late credit the portfolio is reviewed.
    static let creditRiskCeiling: Double = 0.08
    /// Average days from candidate to contract used for national planning.
    static let averageHiringDays = 12

    static func rollups(
        scorecards: [StationScorecard],
        requests: [RegionalRequest],
        now: Date
    ) -> [RegionRollup] {
        StaffDirectory.regions.map { region in
            let regionStations = StaffDirectory.stations(inRegion: region.id)
            let stationIds = Set(regionStations.map(\.id))
            let stations = scorecards.filter { stationIds.contains($0.id) }
            let regionRequests = requests.filter { stationIds.contains($0.stationId) && $0.status == .pending }
            let unmanaged = regionStations
                .filter { StaffDirectory.manager(ofStation: $0.id)?.status != .active }
                .map(\.code)
            return RegionRollup(
                id: region.id,
                name: region.name,
                stations: stations,
                pendingApprovals: regionRequests.count,
                agingApprovals: regionRequests.filter { $0.isAging(now: now) }.count,
                stationsWithoutManager: unmanaged
            )
        }
    }

    static func metrics(rollups: [RegionRollup], projects: [StationProject]) -> NetworkMetrics {
        let incoming = projects.filter { $0.stage != .operating }
        return NetworkMetrics(
            regions: rollups.count,
            stations: rollups.reduce(0) { $0 + $1.stationCount },
            fleetSize: rollups.reduce(0) { $0 + $1.fleetSize },
            operatingVehicles: rollups.reduce(0) { $0 + $1.operatingVehicles },
            idleVehicles: rollups.reduce(0) { $0 + $1.idleVehicles },
            payrollSize: rollups.reduce(0) { $0 + $1.payrollSize },
            requiredDrivers: rollups.reduce(0) { $0 + $1.requiredDrivers },
            presentDrivers: rollups.reduce(0) { $0 + $1.presentDrivers },
            absentDrivers: rollups.reduce(0) { $0 + $1.absentDrivers },
            earningsMxn: rollups.reduce(0) { $0 + $1.earningsMxn },
            goalMxn: rollups.reduce(0) { $0 + $1.goalMxn },
            weekEarningsMxn: rollups.reduce(0) { $0 + $1.weekEarningsMxn },
            weekGoalMxn: rollups.reduce(0) { $0 + $1.weekGoalMxn },
            tripsToday: rollups.reduce(0) { $0 + $1.tripsToday },
            openIncidents: rollups.reduce(0) { $0 + $1.openIncidents },
            criticalIncidents: rollups.reduce(0) { $0 + $1.criticalIncidents },
            pendingApprovals: rollups.reduce(0) { $0 + $1.pendingApprovals },
            agingApprovals: rollups.reduce(0) { $0 + $1.agingApprovals },
            creditPortfolio: rollups.reduce(0) { $0 + $1.creditPortfolio },
            creditBehind: rollups.reduce(0) { $0 + $1.creditBehind },
            bonusAtRisk: rollups.reduce(0) { $0 + $1.bonusAtRisk },
            incomingVehicles: incoming.reduce(0) { $0 + $1.targetVehicles },
            incomingDriverDemand: incoming.reduce(0) { $0 + $1.driverDeficit }
        )
    }

    /// Every card is generated from a threshold. Direction never writes its own list.
    static func alerts(
        rollups: [RegionRollup],
        projects: [StationProject],
        now: Date
    ) -> [NationalAlert] {
        var alerts: [NationalAlert] = []

        for region in rollups where region.goalRatio < regionGoalFloor {
            let missing = max(0, region.goalMxn - region.earningsMxn)
            alerts.append(
                NationalAlert(
                    id: "nalr-goal-\(region.id)",
                    kind: .regionBelowGoal,
                    level: region.goalRatio < 0.75 ? .critical : .important,
                    title: "\(region.name) al \(Int(region.goalRatio * 100))% de su meta del día",
                    detail: "Faltan \(Fmt.mxn(missing)) en \(region.stationCount) estaciones. Cada gerente responde por la suya.",
                    regionId: region.id,
                    createdAt: now
                )
            )
        }

        for region in rollups where !region.isFullyManaged {
            let codes = region.stationsWithoutManager.joined(separator: ", ")
            alerts.append(
                NationalAlert(
                    id: "nalr-mgr-\(region.id)",
                    kind: .managerVacancy,
                    level: .critical,
                    title: "\(region.stationsWithoutManager.count) estación(es) sin gerente en \(region.name)",
                    detail: "\(codes) opera sin quien autorice altas, bonos y créditos. Genera la credencial de gerencia.",
                    regionId: region.id,
                    createdAt: now
                )
            )
        }

        for region in rollups where region.staffingRatio < staffingFloor {
            alerts.append(
                NationalAlert(
                    id: "nalr-staff-\(region.id)",
                    kind: .staffingGap,
                    level: region.staffingRatio < 0.85 ? .critical : .important,
                    title: "\(region.name) necesita \(region.driverDeficit) conductores más",
                    detail: "\(region.fleetSize) unidades × \(HRRules.driversPerVehicle) turnos = \(region.requiredDrivers) de plantilla; hay \(region.payrollSize).",
                    regionId: region.id,
                    createdAt: now
                )
            )
        }

        for region in rollups {
            for station in region.stations where station.health == .critical {
                alerts.append(
                    NationalAlert(
                        id: "nalr-sta-\(station.id)",
                        kind: .stationCritical,
                        level: .critical,
                        title: "\(station.name) en estado crítico",
                        detail: "\(Int(station.goalRatio * 100))% de meta, \(station.absentDrivers) ausencias y \(station.criticalIncidents) incidentes críticos.",
                        regionId: region.id,
                        createdAt: now
                    )
                )
            }
        }

        for region in rollups where region.utilizationRatio < 0.6 && region.fleetSize > 0 {
            alerts.append(
                NationalAlert(
                    id: "nalr-fleet-\(region.id)",
                    kind: .fleetIdle,
                    level: .preventive,
                    title: "\(region.name) con \(region.idleVehicles) unidades detenidas",
                    detail: "Solo \(Int(region.utilizationRatio * 100))% de la flotilla está en la calle en este bloque.",
                    regionId: region.id,
                    createdAt: now
                )
            )
        }

        for region in rollups where region.agingApprovals > 0 {
            alerts.append(
                NationalAlert(
                    id: "nalr-apr-\(region.id)",
                    kind: .agingApproval,
                    level: .important,
                    title: "\(region.agingApprovals) autorizaciones detenidas en \(region.name)",
                    detail: "Gerencias de \(region.name) con trámites de más de 24 h sin firmar.",
                    regionId: region.id,
                    createdAt: now
                )
            )
        }

        for region in rollups where region.creditPortfolio > 0 {
            let ratio = Double(region.creditBehind) / Double(region.creditPortfolio)
            guard ratio > creditRiskCeiling else { continue }
            alerts.append(
                NationalAlert(
                    id: "nalr-cre-\(region.id)",
                    kind: .creditRisk,
                    level: ratio > 0.15 ? .critical : .important,
                    title: "\(region.creditBehind) créditos atrasados en \(region.name)",
                    detail: "\(Int(ratio * 100))% de una cartera de \(region.creditPortfolio) contratos con abono vía nómina.",
                    regionId: region.id,
                    createdAt: now
                )
            )
        }

        for project in projects where project.stage != .operating {
            let level = project.risk(now: now, averageHiringDays: averageHiringDays)
            guard level.demandsAction else { continue }
            let days = project.daysToLaunch(now: now)
            alerts.append(
                NationalAlert(
                    id: "nalr-prj-\(project.id)",
                    kind: .projectAtRisk,
                    level: level,
                    title: "\(project.name) abre en \(days) días con \(project.driverDeficit) conductores faltantes",
                    detail: "\(project.targetVehicles) unidades exigen \(project.requiredDrivers) conductores y contratar toma \(averageHiringDays) días en promedio.",
                    regionId: project.regionId,
                    createdAt: now
                )
            )
        }

        return alerts.sorted { lhs, rhs in
            lhs.level.weight == rhs.level.weight
                ? lhs.title < rhs.title
                : lhs.level.weight > rhs.level.weight
        }
    }

    /// Candidates the network must start today to open every committed project on time.
    static func nationalRecruitmentNeed(projects: [StationProject], deficit: Int) -> Int {
        let projectNeed = projects.filter { $0.stage != .operating }.reduce(0) { $0 + $1.driverDeficit }
        return HRRules.recommendedCandidates(needed: projectNeed + deficit, conversionRate: 0.42)
    }
}
