import Foundation
import Observation

/// Country-scoped source of truth for a national direction session. It consolidates the
/// very same regional snapshots the managers read, so direction and gerencia can never
/// see different numbers, and adds what only direction owns: credentials, station
/// projects and the policy book every region inherits.
@Observable
final class NationalStore {
    // MARK: - Persisted shape

    nonisolated private struct PersistedState: Codable, Sendable {
        var credentials: [NetworkCredential]
        var projects: [StationProject]
        var policy: PolicyBook
        var policyLog: [PolicyChange]
        var reviewedAlertIds: [String]
    }

    // MARK: - Identity

    let account: StaffAccount
    private let fleet: FleetStore

    var now: Date { fleet.now }

    // MARK: - State

    /// Live consolidation of every region; rebuilt from the regional snapshots.
    private(set) var scorecards: [StationScorecard] = []
    private(set) var supervisors: [SupervisorScorecard] = []
    private(set) var requests: [RegionalRequest] = []

    var credentials: [NetworkCredential] = []
    var projects: [StationProject] = []
    /// The policy in force. Deliberately **not** a temporal read: it is stored state,
    /// seeded once at init and replaced only when direction authorises a change. The hour
    /// it was written with is already baked into the record, so no consumer of this needs a
    /// cadence — it moves on an event, never on the clock.
    var policy: PolicyBook
    var policyLog: [PolicyChange] = []
    var reviewedAlertIds: [String] = []

    private var seedKey: String = ""
    private var storageKey: String { "turnoev.national.v1.\(account.id)" }

    init(account: StaffAccount, fleet: FleetStore) {
        self.account = account
        self.fleet = fleet
        policy = PolicyBook.networkDefault(now: fleet.now)
        load()
        publishBonusSchedule()
        rebuildNetwork()
    }

    // MARK: - Lifecycle

    func refresh() {
        if seedKey != currentSeedKey { rebuildNetwork() }
    }

    private var currentSeedKey: String {
        let day = ShiftRules.calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        return "nac|\(RegionalRules.observedSlot(now: now).rawValue)|\(day)|\(fleet.clockOffsetMinutes / 60)"
    }

    /// Direction reads the country by asking every station for its own board. The
    /// station is the unit of the company, so the roll-up into regions happens after.
    private func rebuildNetwork() {
        var cards: [StationScorecard] = []
        var sups: [SupervisorScorecard] = []
        var reqs: [RegionalRequest] = []

        for station in StaffDirectory.stations {
            let manager = StaffDirectory.manager(ofStation: station.id) ?? account
            let snapshot = RegionalMockData.snapshot(
                station: station,
                manager: manager,
                isLive: fleet.driver.stationId == station.id,
                now: now
            )
            cards.append(contentsOf: snapshot.scorecards)
            sups.append(contentsOf: snapshot.supervisors)
            reqs.append(contentsOf: snapshot.requests)
        }

        scorecards = cards
        supervisors = sups
        requests = reqs
        seedKey = currentSeedKey
        foldLiveStation()
    }

    func regenerateNetwork() {
        rebuildNetwork()
    }

    /// The driver running on this device is counted once, in their own station.
    private func foldLiveStation() {
        let stationId = fleet.driver.stationId
        guard let index = scorecards.firstIndex(where: { $0.id == stationId }) else { return }
        var card = scorecards[index]
        card.earningsMxn += fleet.earnedToday(reference: now)
        card.tripsToday += fleet.tripsToday(reference: now)
        card.isLive = true
        scorecards[index] = card
    }

    // MARK: - Reads

    // MARK: - Reads that answer differently depending on the hour
    //
    // All of these used to read `self.now`, which meant the badge of a tab and the cards of
    // a screen shared one invisible dependency on the global clock. They now take the
    // instant explicitly, so whoever reads them has to say at what cadence they care.

    /// `.minute`: the roll-up counts requests that have gone stale, and a request crosses
    /// its twenty-four hours at an arbitrary hour.
    func rollups(now: Date) -> [RegionRollup] {
        NationalRules.rollups(scorecards: scorecards, requests: requests, now: now)
    }

    func metrics(now: Date) -> NetworkMetrics {
        NationalRules.metrics(rollups: rollups(now: now), projects: projects)
    }

    /// The exception board of the country, and the source of a tab badge.
    ///
    /// `.minute`, because the *set* changes with time: an alert appears when a region's
    /// backlog goes stale and when a project's launch risk turns. Whoever shows the count
    /// must invalidate at the same cadence as whoever shows the cards, or the badge will
    /// disagree with the screen behind it.
    func alerts(now: Date) -> [NationalAlert] {
        NationalRules.alerts(rollups: rollups(now: now), projects: projects, now: now)
            .filter { !reviewedAlertIds.contains($0.id) }
    }

    func criticalAlerts(now: Date) -> [NationalAlert] {
        alerts(now: now).filter { $0.level.demandsAction }
    }

    /// Regions ordered by health: the one that needs direction comes first.
    func rollupsByRisk(now: Date) -> [RegionRollup] {
        rollups(now: now).sorted { $0.healthScore < $1.healthScore }
    }

    func rollupsByPerformance(now: Date) -> [RegionRollup] {
        rollups(now: now).sorted { $0.goalRatio > $1.goalRatio }
    }

    var allStations: [StationScorecard] {
        scorecards.sorted { $0.healthScore > $1.healthScore }
    }

    func rollup(id: String?, now: Date) -> RegionRollup? {
        guard let id else { return nil }
        return rollups(now: now).first { $0.id == id }
    }

    func station(id: String?) -> StationScorecard? {
        guard let id else { return nil }
        return scorecards.first { $0.id == id }
    }

    func supervisors(stationId: String) -> [SupervisorScorecard] {
        supervisors.filter { $0.stationId == stationId }
    }

    /// Monday to Sunday of the whole country against the goal of each day.
    ///
    /// `.day`: the week it covers and the day it marks as today are calendar facts.
    func weekSeries(now: Date) -> [RegionDayPoint] {
        let weekStart = ShiftRules.weekStart(for: now)
        let boards = rollups(now: now)
        return (0..<7).compactMap { offset in
            guard let day = ShiftRules.calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let amount = boards.reduce(0) { total, region in
                let series = region.weekSeries
                return total + (series.indices.contains(offset) ? series[offset] : 0)
            }
            let goal = scorecards.reduce(0) {
                $0 + ShiftRules.stationDayGoalMxn(capacity: $1.vehicleCapacity, on: day)
            }
            return RegionDayPoint(
                date: day,
                amountMxn: amount,
                goalMxn: goal,
                isToday: ShiftRules.isSameDay(day, now),
                isFuture: day > now && !ShiftRules.isSameDay(day, now)
            )
        }
    }

    // MARK: - Directory

    /// Everyone with a credential above driver level: the directory seeded with the
    /// product plus everything direction has generated in this session.
    var networkStaff: [NetworkCredential] {
        let seeded: [NetworkCredential] = StaffDirectory.accounts
            .filter { $0.role != .driver }
            .map { account in
                NetworkCredential(
                    id: account.id,
                    name: account.name,
                    employeeNumber: account.employeeNumber,
                    email: account.email,
                    role: account.role,
                    stationId: account.stationId,
                    regionId: account.regionId,
                    slot: account.slot,
                    status: suspendedIds.contains(account.id) ? .suspended : account.status,
                    createdAt: account.createdById == nil ? Date(timeIntervalSince1970: 1_700_000_000) : Date(timeIntervalSince1970: 1_705_000_000),
                    createdBy: StaffDirectory.account(id: account.createdById)?.name ?? "Origen de la red",
                    temporaryPassword: ""
                )
            }
        return (seeded + credentials).sorted { lhs, rhs in
            lhs.role.rawValue == rhs.role.rawValue ? lhs.name < rhs.name : roleOrder(lhs.role) < roleOrder(rhs.role)
        }
    }

    private var suspendedIds: Set<String> {
        Set(credentials.filter { $0.status == .suspended }.map(\.id))
    }

    private func roleOrder(_ role: StaffRole) -> Int {
        switch role {
        case .national: 0
        case .manager: 1
        case .supervisor: 2
        case .recruiter: 3
        case .maintenance: 4
        case .driver: 5
        case .lab: 6
        }
    }

    func staff(role: StaffRole?) -> [NetworkCredential] {
        guard let role else { return networkStaff }
        return networkStaff.filter { $0.role == role }
    }

    func staff(search: String, role: StaffRole?) -> [NetworkCredential] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return staff(role: role).filter { credential in
            guard !cleaned.isEmpty else { return true }
            return credential.name.localizedStandardContains(cleaned)
                || credential.employeeNumber.localizedStandardContains(cleaned)
                || credential.email.localizedStandardContains(cleaned)
                || credential.scopeLabel.localizedStandardContains(cleaned)
        }
    }

    /// Stations that have nobody covering one of the two supervision shifts.
    var supervisionGaps: [(station: Station, slot: ShiftSlot)] {
        var gaps: [(Station, ShiftSlot)] = []
        let active = networkStaff.filter { $0.role == .supervisor && $0.status == .active }
        for station in StaffDirectory.stations {
            for slot in ShiftSlot.allCases {
                let covered = active.contains { $0.stationId == station.id && $0.slot == slot }
                if !covered { gaps.append((station, slot)) }
            }
        }
        return gaps.map { (station: $0.0, slot: $0.1) }
    }

    /// Stations running without a manager. Every station must have exactly one, so this
    /// is one of the few things direction has to fix itself.
    var stationsWithoutManager: [Station] {
        let managed = Set(
            networkStaff.filter { $0.role == .manager && $0.status == .active }.compactMap(\.stationId)
        )
        return StaffDirectory.stations.filter { !managed.contains($0.id) }
    }

    /// Stations running without their own recruitment desk: their vacancies have nobody
    /// working them.
    var stationsWithoutRecruiter: [Station] {
        let covered = Set(
            networkStaff.filter { $0.role == .recruiter && $0.status == .active }.compactMap(\.stationId)
        )
        return StaffDirectory.stations.filter { !covered.contains($0.id) }
    }

    // MARK: - Credentials

    /// Generates a credential. Direction only creates management, supervision and
    /// workshop: a driver is always born in the station that hires them.
    func createCredential(
        name: String,
        employeeNumber: String,
        email: String,
        role: StaffRole,
        stationId: String?,
        regionId: String?,
        slot: ShiftSlot?
    ) -> CredentialOutcome {
        guard account.role.canRegister.contains(role) else { return .notAllowed }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanNumber = employeeNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if networkStaff.contains(where: { $0.email.lowercased() == cleanEmail })
            || StaffDirectory.accounts.contains(where: { $0.email == cleanEmail }) {
            return .duplicateEmail
        }
        if networkStaff.contains(where: { $0.employeeNumber.uppercased() == cleanNumber })
            || StaffDirectory.accounts.contains(where: { $0.employeeNumber == cleanNumber }) {
            return .duplicateEmployeeNumber
        }

        switch role {
        case .manager, .recruiter:
            // One station, one manager and one recruitment desk. Both are station staff.
            guard stationId != nil else { return .missingScope }
            if let taken = networkStaff.first(where: {
                $0.role == role && $0.stationId == stationId && $0.status == .active
            }) {
                return .slotTaken(taken.name)
            }
        case .supervisor:
            guard stationId != nil, let slot else { return .missingScope }
            if let taken = networkStaff.first(where: {
                $0.role == .supervisor && $0.stationId == stationId && $0.slot == slot && $0.status == .active
            }) {
                return .slotTaken(taken.name)
            }
        case .maintenance:
            guard stationId != nil else { return .missingScope }
        default:
            return .notAllowed
        }

        _ = regionId
        let credential = NetworkCredential(
            id: "cred-\(role.rawValue)-\(UUID().uuidString.prefix(6))",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            employeeNumber: cleanNumber,
            email: cleanEmail,
            role: role,
            stationId: stationId,
            regionId: StaffDirectory.station(id: stationId)?.regionId,
            slot: role == .maintenance ? (slot ?? .morning) : slot,
            status: .active,
            createdAt: now,
            createdBy: account.name,
            temporaryPassword: Self.temporaryPassword(for: role)
        )
        credentials.append(credential)
        persist()
        return .created(credential)
    }

    /// First-day password: the person changes it after their first sign-in.
    private static func temporaryPassword(for role: StaffRole) -> String {
        let prefix: String
        switch role {
        case .manager: prefix = "Gerencia"
        case .supervisor: prefix = "Supervisor"
        case .maintenance: prefix = "Taller"
        case .recruiter: prefix = "Reclutamiento"
        default: prefix = "Turno"
        }
        return "\(prefix)\(Int.random(in: 20...99))"
    }

    func setStatus(_ status: StaffStatus, for credentialId: String) {
        if let index = credentials.firstIndex(where: { $0.id == credentialId }) {
            credentials[index].status = status
            persist()
            return
        }
        // Seeded credential: keep an override so the directory reflects the decision.
        guard let seeded = networkStaff.first(where: { $0.id == credentialId }) else { return }
        var copy = seeded
        copy.status = status
        credentials.append(copy)
        persist()
    }

    func isGenerated(_ credential: NetworkCredential) -> Bool {
        credentials.contains { $0.id == credential.id }
    }

    // MARK: - Expansion

    func addProject(
        name: String,
        code: String,
        city: String,
        regionId: String,
        targetVehicles: Int,
        launchDate: Date,
        note: String
    ) {
        let project = StationProject(
            id: "prj-\(UUID().uuidString.prefix(6))",
            code: code.uppercased(),
            name: name,
            city: city,
            regionId: regionId,
            targetVehicles: max(1, min(HRRules.maxVehiclesPerStation, targetVehicles)),
            launchDate: launchDate,
            stage: .study,
            hiredDrivers: 0,
            candidatesStarted: 0,
            investmentMxn: targetVehicles * CreditProgram.priceMxn,
            note: note,
            createdAt: now,
            createdBy: account.name
        )
        projects.insert(project, at: 0)
        persist()
    }

    func advance(projectId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }),
              let next = projects[index].stage.next else { return }
        projects[index].stage = next
        if next == .operating {
            projects[index].hiredDrivers = projects[index].requiredDrivers
        }
        persist()
    }

    func setStage(_ stage: ProjectStage, for projectId: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].stage = stage
        persist()
    }

    func updateHiring(projectId: String, hired: Int, candidates: Int) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].hiredDrivers = max(0, min(projects[index].requiredDrivers, hired))
        projects[index].candidatesStarted = max(0, candidates)
        persist()
    }

    func removeProject(id: String) {
        projects.removeAll { $0.id == id }
        persist()
    }

    func project(id: String?) -> StationProject? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    var projectsByLaunch: [StationProject] {
        projects.sorted { $0.launchDate < $1.launchDate }
    }

    /// Committed investment of everything that is not operating yet.
    var committedInvestmentMxn: Int {
        projects.filter { $0.stage != .operating }.reduce(0) { $0 + $1.investmentMxn }
    }

    // MARK: - Policy

    /// Moves one rule of the network. The previous value is kept in the log forever.
    func updatePolicy(field: String, note: String, apply: (inout PolicyBook) -> Void) {
        var updated = policy
        apply(&updated)
        guard let before = Self.describe(policy, field: field),
              let after = Self.describe(updated, field: field),
              before != after else { return }

        updated.version = policy.version + 1
        updated.updatedAt = now
        updated.updatedBy = account.name
        policy = updated
        publishBonusSchedule()

        policyLog.insert(
            PolicyChange(
                id: "pol-\(UUID().uuidString.prefix(6))",
                field: field,
                previousValue: before,
                newValue: after,
                changedAt: now,
                changedBy: account.name,
                note: note
            ),
            at: 0
        )
        persist()
    }

    /// Sends the bonus amounts to the rest of the app. Bonuses are resolved by the goal
    /// engine, so this is the only hand that can change what a driver collects, and it
    /// moves the whole network at once instead of one driver at a time.
    private func publishBonusSchedule() {
        NationalBonusBoard.publish(policy.bonusSchedule)
    }

    // MARK: - Cash deposits

    /// The account every driver sees when he has to deposit cash he could not charge by
    /// card. Only direction writes it, and it is the same one for the whole network.
    var cashAccount: CashDepositAccount { NationalCashBoard.current }

    func publishCashAccount(_ account: CashDepositAccount, note: String) {
        let previous = NationalCashBoard.current
        var updated = account
        updated.version = previous.version + 1
        updated.updatedAt = now
        updated.updatedBy = self.account.name
        NationalCashBoard.publish(updated)

        policyLog.insert(
            PolicyChange(
                id: "pol-\(UUID().uuidString.prefix(6))",
                field: "cashDepositAccount",
                previousValue: "\(previous.bank) · \(previous.clabe)",
                newValue: "\(updated.bank) · \(updated.clabe)",
                changedAt: now,
                changedBy: self.account.name,
                note: note.isEmpty ? "Cuenta para depósitos en efectivo actualizada para toda la red." : note
            ),
            at: 0
        )
        persist()
    }

    /// Current value of a rule, used to build the change log without duplicating strings.
    private static func describe(_ book: PolicyBook, field: String) -> String? {
        switch field {
        case "weekdayHourlyMxn": Fmt.mxn(book.weekdayHourlyMxn)
        case "weekdayDailyMxn": Fmt.mxn(book.weekdayDailyMxn)
        case "weekendHourlyMxn": Fmt.mxn(book.weekendHourlyMxn)
        case "weekendDailyMxn": Fmt.mxn(book.weekendDailyMxn)
        case "tripsPerDay": "\(book.tripsPerDay) viajes"
        case "graceMinutes": "\(book.graceMinutes) min"
        case "minimumBatteryPct": "\(book.minimumBatteryPct)%"
        case "inspectionPhotos": "\(book.inspectionPhotos) fotos"
        case "maxVehiclesPerStation": "\(book.maxVehiclesPerStation) unidades"
        case "bonusPunctualityMxn": Fmt.mxn(book.bonusPunctualityMxn)
        case "bonusBillingMxn": Fmt.mxn(book.bonusBillingMxn)
        case "bonusCareMxn": Fmt.mxn(book.bonusCareMxn)
        case "creditWeeklyMxn": Fmt.mxn(book.creditWeeklyMxn)
        default: nil
        }
    }

    func restorePolicyDefaults() {
        let fresh = PolicyBook.networkDefault(now: now)
        policy = PolicyBook(
            weekdayHourlyMxn: fresh.weekdayHourlyMxn,
            weekdayDailyMxn: fresh.weekdayDailyMxn,
            weekendHourlyMxn: fresh.weekendHourlyMxn,
            weekendDailyMxn: fresh.weekendDailyMxn,
            tripsPerDay: fresh.tripsPerDay,
            graceMinutes: fresh.graceMinutes,
            minimumBatteryPct: fresh.minimumBatteryPct,
            inspectionPhotos: fresh.inspectionPhotos,
            driversPerVehicle: fresh.driversPerVehicle,
            maxVehiclesPerStation: fresh.maxVehiclesPerStation,
            bonusPunctualityMxn: fresh.bonusPunctualityMxn,
            bonusBillingMxn: fresh.bonusBillingMxn,
            bonusCareMxn: fresh.bonusCareMxn,
            creditWeeklyMxn: fresh.creditWeeklyMxn,
            creditTermWeeks: fresh.creditTermWeeks,
            creditDeliveryMonth: fresh.creditDeliveryMonth,
            version: policy.version + 1,
            updatedAt: now,
            updatedBy: account.name
        )
        policyLog.insert(
            PolicyChange(
                id: "pol-\(UUID().uuidString.prefix(6))",
                field: "Libro completo",
                previousValue: "Versión \(policy.version - 1)",
                newValue: "Valores de origen",
                changedAt: now,
                changedBy: account.name,
                note: "Restauración de las reglas con las que opera la red."
            ),
            at: 0
        )
        publishBonusSchedule()
        persist()
    }

    // MARK: - Alerts

    func reviewAlert(id: String) {
        guard !reviewedAlertIds.contains(id) else { return }
        reviewedAlertIds.append(id)
        persist()
    }

    func restoreAlerts() {
        reviewedAlertIds = []
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            projects = NationalMockData.projects(now: fleet.now, author: account.name)
            persist()
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            credentials = state.credentials
            projects = state.projects
            policy = state.policy
            policyLog = state.policyLog
            reviewedAlertIds = state.reviewedAlertIds
        } catch {
            print("No se pudo leer el tablero nacional: \(error.localizedDescription)")
            projects = NationalMockData.projects(now: fleet.now, author: account.name)
            persist()
        }
    }

    private func persist() {
        let state = PersistedState(
            credentials: credentials,
            projects: projects,
            policy: policy,
            policyLog: policyLog,
            reviewedAlertIds: reviewedAlertIds
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("No se pudo guardar el tablero nacional: \(error.localizedDescription)")
        }
    }
}
