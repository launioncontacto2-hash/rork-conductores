import Foundation
import Observation

/// Station-scoped source of truth for a manager session. A manager runs exactly one
/// station, so this store loads that station and nothing else: it reads the same
/// database the station writes to (`FleetStore`) and completes what the simulated
/// roster contributes. No other station is ever loaded, not even to compare.
@Observable
final class RegionalStore {
    // MARK: - Persisted shape

    nonisolated private struct PersistedState: Codable, Sendable {
        var seedKey: String
        var scorecards: [StationScorecard]
        var supervisors: [SupervisorScorecard]
        var requests: [RegionalRequest]
        var resolvedAlertIds: [String]
    }

    // MARK: - Identity

    let account: StaffAccount
    /// The one station this manager answers for.
    let station: Station
    /// Region the station belongs to. Kept for reporting labels only — the manager has
    /// no authority outside their own station.
    var region: Region? { StaffDirectory.region(id: station.regionId) }
    private let fleet: FleetStore

    var now: Date { fleet.now }

    /// Station shift the manager is watching, following their own split block.
    ///
    /// A shift boundary falls on a minute, not on a date, so a consumer of this has to
    /// listen by the minute. It takes `now` explicitly for the same reason every read in
    /// this section does: a property that answers differently depending on the hour must
    /// not hide the hour.
    func observedSlot(now: Date) -> ShiftSlot { RegionalRules.observedSlot(now: now) }

    func dutyBlock(now: Date) -> RegionalRules.DutyBlock { RegionalRules.dutyBlock(now: now) }

    // MARK: - State

    var scorecards: [StationScorecard] = []
    var supervisors: [SupervisorScorecard] = []
    var requests: [RegionalRequest] = []
    var resolvedAlertIds: [String] = []
    private var seedKey: String = ""

    private var storageKey: String { "turnoev.regional.v1.\(account.id)" }

    init(account: StaffAccount, fleet: FleetStore) {
        self.account = account
        self.fleet = fleet
        station = StaffDirectory.station(id: account.stationId)
            ?? StaffDirectory.stations.first
            ?? Station(
                id: "est-sin-asignar",
                code: "S/A",
                name: "Sin estación",
                city: "—",
                regionId: "—",
                vehicleCapacity: 0
            )
        load()
    }

    // MARK: - Lifecycle

    func refresh() {
        if seedKey != currentSeedKey { rebuild() }
        syncLiveStation()
        syncLiveRequests()
    }

    private var currentSeedKey: String {
        let day = ShiftRules.calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        return "\(station.id)|\(observedSlot(now: now).rawValue)|\(day)"
    }

    private func rebuild() {
        let snapshot = RegionalMockData.snapshot(
            station: station,
            manager: account,
            isLive: liveStationId != nil,
            now: now
        )
        scorecards = snapshot.scorecards
        supervisors = snapshot.supervisors
        requests = snapshot.requests
        resolvedAlertIds = []
        seedKey = currentSeedKey
        persist()
    }

    /// Rebuilds the simulated station without touching the drivers' own records.
    func regenerateRegion() {
        rebuild()
        syncLiveStation()
        syncLiveRequests()
    }

    // MARK: - Live bridge

    /// Non-nil when the driver operating this device belongs to the manager's station,
    /// which is when the board stops being simulated and starts being real.
    private var liveStationId: String? {
        fleet.driver.stationId == station.id ? station.id : nil
    }

    /// Folds the real numbers of the live station into its scorecard: the driver app's
    /// billing, trips, incidents and fleet status are counted here too.
    private func syncLiveStation() {
        guard let liveStationId,
              let index = scorecards.firstIndex(where: { $0.id == liveStationId }) else { return }

        let stationVehicles = fleet.vehicles.filter { $0.stationId == liveStationId }
        guard !stationVehicles.isEmpty else { return }

        let sharedMaintenance = stationVehicles.filter { $0.status == .maintenance }.count
        let sharedOperating = stationVehicles.filter { $0.status == .occupied }.count
        let liveEarnings = fleet.earnedToday(reference: now)
        let liveTrips = fleet.tripsToday(reference: now)
        let liveIncidents = fleet.incidents.filter { $0.status != .closed }.count

        // The simulated roster already covers 100 drivers; the live driver replaces one
        // of them so the totals stay honest instead of double counting.
        var card = scorecards[index]
        card.operatingVehicles = max(card.operatingVehicles, sharedOperating)
        card.inMaintenance = max(1, sharedMaintenance + card.inMaintenance - 1)
        card.earningsMxn += liveEarnings
        card.tripsToday += liveTrips
        card.openIncidents = max(card.openIncidents, liveIncidents)
        if fleet.credit != nil {
            let isBehind = fleet.credit?.payments.contains { $0.status == .late } ?? false
            if isBehind { card.creditBehind += 1 } else { card.creditCurrent += 1 }
        }
        card.isLive = true
        scorecards[index] = card
    }

    /// Opens the regional decisions the driver app generated: a credit application of
    /// the live driver needs the manager's signature before payroll starts the discount.
    private func syncLiveRequests() {
        guard let liveStationId,
              let station = StaffDirectory.station(id: liveStationId) else { return }

        let driver = fleet.driver
        let id = "req-cre-live-\(driver.id)"

        guard fleet.credit != nil else {
            requests.removeAll { $0.id == id && $0.status == .pending }
            return
        }
        guard !requests.contains(where: { $0.id == id }) else { return }

        let supervisorName = supervisors.first { $0.stationId == liveStationId && $0.slot == driver.slot }?.name
            ?? "Supervisión de estación"

        requests.insert(
            RegionalRequest(
                id: id,
                kind: .credit,
                stationId: station.id,
                stationCode: station.code,
                subject: driver.name,
                subjectDetail: "\(driver.employeeNumber) · turno \(driver.slot.label.lowercased())",
                amountMxn: CreditProgram.weeklyMxn,
                detail: "Contrato del \(CreditProgram.vehicleModel) a \(CreditProgram.termMonths) meses, \(CreditProgram.termWeeks) abonos semanales vía nómina y entrega de unidad en el mes \(CreditProgram.deliveryMonth). El conductor ya firmó en la estación y opera con la app.",
                createdAt: fleet.credit?.startedAt ?? now,
                requestedBy: supervisorName,
                requestedByRole: .supervisor,
                priority: .high,
                checks: [:],
                status: .pending,
                resolvedAt: nil,
                decisionNote: nil,
                photoAsset: CreditProgram.imageAssetName,
                isLiveSession: true
            ),
            at: 0
        )
        persist()
    }

    // MARK: - Reads

    /// Counts of the region, including `agingRequests`.
    ///
    /// `.minute`: a request goes stale twenty-four hours after it was created, and it was
    /// created at an arbitrary hour. A date cadence would report the backlog late.
    func metrics(now: Date) -> RegionMetrics {
        RegionalRules.metrics(scorecards: scorecards, requests: requests, now: now)
    }

    /// `.minute`, for the same reason as `metrics`: the set itself grows when a request
    /// crosses its twenty-four hours.
    func alerts(now: Date) -> [RegionalAlert] {
        RegionalRules.alerts(
            scorecards: scorecards,
            supervisors: supervisors,
            requests: requests,
            now: now
        )
        .filter { !resolvedAlertIds.contains($0.id) }
    }

    func criticalAlerts(now: Date) -> [RegionalAlert] {
        alerts(now: now).filter { $0.severity == .critical || $0.severity == .high }
    }

    /// Stations ordered by health, so the card that needs the manager comes first.
    var ranking: [StationScorecard] {
        scorecards.sorted { $0.healthScore > $1.healthScore }
    }

    var stationsNeedingAttention: [StationScorecard] {
        scorecards.filter { $0.health == .watch || $0.health == .critical }
            .sorted { $0.healthScore < $1.healthScore }
    }

    var pendingRequests: [RegionalRequest] {
        requests.filter { $0.status == .pending }
            .sorted { lhs, rhs in
                lhs.priority.weight == rhs.priority.weight
                    ? lhs.createdAt < rhs.createdAt
                    : lhs.priority.weight > rhs.priority.weight
            }
    }

    var resolvedRequests: [RegionalRequest] {
        requests.filter { $0.status != .pending }
            .sorted { ($0.resolvedAt ?? $0.createdAt) > ($1.resolvedAt ?? $1.createdAt) }
    }

    func pendingCount(for filter: RequestFilter) -> Int {
        guard let kind = filter.kind else { return pendingRequests.count }
        return pendingRequests.filter { $0.kind == kind }.count
    }

    func requests(matching filter: RequestFilter, search: String = "") -> [RegionalRequest] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return pendingRequests
            .filter { filter.kind == nil || $0.kind == filter.kind }
            .filter { request in
                guard !cleaned.isEmpty else { return true }
                return request.subject.localizedStandardContains(cleaned)
                    || request.stationCode.localizedStandardContains(cleaned)
                    || request.requestedBy.localizedStandardContains(cleaned)
            }
    }

    func request(id: String?) -> RegionalRequest? {
        guard let id else { return nil }
        return requests.first { $0.id == id }
    }

    func station(id: String?) -> StationScorecard? {
        guard let id else { return nil }
        return scorecards.first { $0.id == id }
    }

    func supervisors(stationId: String) -> [SupervisorScorecard] {
        supervisors.filter { $0.stationId == stationId }.sorted { $0.slot == .morning && $1.slot != .morning }
    }

    func maintenance(stationId: String) -> [(id: String, name: String, slot: ShiftSlot)] {
        guard let station = StaffDirectory.station(id: stationId) else { return [] }
        return RegionalMockData.maintenanceStaff(station: station, index: 0)
    }

    /// The station's own scorecard: the single card this whole interface is about.
    var card: StationScorecard? { scorecards.first { $0.id == station.id } ?? scorecards.first }

    /// Recruitment desk of this station, so the manager knows who fills their vacancies.
    var recruiter: StaffAccount? { StaffDirectory.recruiter(ofStation: station.id) }

    /// The plantilla of the station as a phone directory: supervision by shift, the
    /// workshop by shift and the recruitment desk. Registered accounts contribute their
    /// own line; simulated staff get a stable derived one.
    var staffDirectory: [StationContact] {
        var result: [StationContact] = []

        for supervisor in supervisors(stationId: station.id) {
            let account = StaffDirectory.account(id: supervisor.id)
            result.append(
                StationContact(
                    id: supervisor.id,
                    name: supervisor.name,
                    employeeNumber: supervisor.employeeNumber,
                    desk: .supervision,
                    duty: "Turno \(supervisor.slot.label.lowercased())",
                    phone: account?.phone ?? StationContact.derivedPhone(id: supervisor.id, city: station.city)
                )
            )
        }

        for technician in maintenance(stationId: station.id) {
            let account = StaffDirectory.account(id: technician.id)
            result.append(
                StationContact(
                    id: technician.id,
                    name: technician.name,
                    employeeNumber: account?.employeeNumber ?? "EV-MTO-\(technician.id.suffix(3).uppercased())",
                    desk: .workshop,
                    duty: "Turno \(technician.slot.label.lowercased())",
                    phone: account?.phone ?? StationContact.derivedPhone(id: technician.id, city: station.city)
                )
            )
        }

        if let recruiter {
            result.append(
                StationContact(
                    id: recruiter.id,
                    name: recruiter.name,
                    employeeNumber: recruiter.employeeNumber,
                    desk: .recruitment,
                    duty: "Cubre y firma las altas",
                    phone: recruiter.phone ?? StationContact.derivedPhone(id: recruiter.id, city: station.city)
                )
            )
        }

        return result
    }

    /// Station billing per day of the current week, against the fixed goal of each day.
    /// `.day`: the week it covers and the day it marks as today are both calendar facts.
    func weekSeries(now: Date) -> [RegionDayPoint] {
        let weekStart = ShiftRules.weekStart(for: now)
        return (0..<7).compactMap { offset in
            guard let day = ShiftRules.calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let amount = scorecards.reduce(0) { total, card in
                total + (card.weekEarnings.indices.contains(offset) ? card.weekEarnings[offset] : 0)
            }
            let goal = ShiftRules.stationDayGoalMxn(capacity: station.vehicleCapacity, on: day)
            return RegionDayPoint(
                date: day,
                amountMxn: amount,
                goalMxn: goal,
                isToday: ShiftRules.isSameDay(day, now),
                isFuture: day > now && !ShiftRules.isSameDay(day, now)
            )
        }
    }

    // MARK: - Fixed goal

    /// The number the whole station chases: authorized units × the driver goal of the
    /// day. It never moves with attendance, so every empty seat shows up as a gap.
    /// `.minute`: the goal of the day depends on the group in force and on the shift being
    /// observed, and both turn on a shift boundary.
    func goalBoard(now: Date) -> StationGoalBoard {
        StationGoalBoard(
            capacity: station.vehicleCapacity,
            group: ShiftRules.group(for: now),
            slot: observedSlot(now: now),
            earningsMxn: card?.earningsMxn ?? 0,
            presentDrivers: card?.presentDrivers ?? 0,
            weekEarningsMxn: card?.weekEarningsMxn ?? 0
        )
    }

    /// Money the goal engine will release at month end for this station. It is a
    /// reading, not a decision: nobody in the station authorizes a bonus.
    var bonusPayrollMxn: Int {
        scorecards.reduce(0) { $0 + $1.bonusEligible } * NationalBonusBoard.current.ceilingMxn
    }

    /// What the station stops paying if the drivers at risk do not recover their week.
    var bonusAtRiskMxn: Int {
        scorecards.reduce(0) { $0 + $1.bonusAtRisk } * NationalBonusBoard.current.ceilingMxn
    }

    // MARK: - Decisions

    func setCheck(_ check: RequestCheck, on requestId: String, value: Bool) {
        guard let index = requests.firstIndex(where: { $0.id == requestId }) else { return }
        requests[index].checks[check.id] = value
        persist()
    }

    /// Signs the request. Drivers of this device are notified through the shared database.
    @discardableResult
    func authorize(requestId: String, note: String) -> Bool {
        guard let index = requests.firstIndex(where: { $0.id == requestId }),
              requests[index].isReadyToAuthorize else { return false }

        requests[index].status = .authorized
        requests[index].resolvedAt = now
        requests[index].decisionNote = note.isEmpty ? "Autorizada por la gerencia de la estación." : note
        let request = requests[index]

        applySideEffects(of: request, authorized: true)
        persist()
        return true
    }

    func reject(requestId: String, reason: String) {
        guard let index = requests.firstIndex(where: { $0.id == requestId }) else { return }
        requests[index].status = .rejected
        requests[index].resolvedAt = now
        requests[index].decisionNote = reason
        let request = requests[index]

        applySideEffects(of: request, authorized: false)
        persist()
    }

    private func applySideEffects(of request: RegionalRequest, authorized: Bool) {
        guard let index = scorecards.firstIndex(where: { $0.id == request.stationId }) else { return }

        switch request.kind {
        case .hiring:
            if authorized { scorecards[index].payrollSize += 1 }
        case .credit:
            if authorized {
                scorecards[index].creditCurrent += 1
            }
        case .retirement:
            if authorized {
                scorecards[index].fleetSize = max(0, scorecards[index].fleetSize - 1)
                scorecards[index].outOfService = max(0, scorecards[index].outOfService - 1)
            }
        }

        guard request.isLiveSession else { return }
        switch request.kind {
        case .credit:
            fleet.pushNotice(
                kind: .credit,
                title: authorized ? "Crédito validado por gerencia" : "Crédito devuelto a revisión",
                body: authorized
                    ? "\(account.name) autorizó tu contrato del \(CreditProgram.vehicleModel). El descuento semanal se aplica vía nómina."
                    : "\(account.name): \(request.decisionNote ?? "Solicitud devuelta a la estación.")"
            )
        case .hiring, .retirement:
            break
        }
    }

    func resolveAlert(id: String) {
        guard !resolvedAlertIds.contains(id) else { return }
        resolvedAlertIds.append(id)
        persist()
    }

    func restoreAlerts() {
        resolvedAlertIds = []
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            rebuild()
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            seedKey = state.seedKey
            scorecards = state.scorecards
            supervisors = state.supervisors
            requests = state.requests
            resolvedAlertIds = state.resolvedAlertIds
            if seedKey != currentSeedKey { rebuild() }
        } catch {
            print("No se pudo leer el tablero de la estación: \(error.localizedDescription)")
            rebuild()
        }
    }

    private func persist() {
        let state = PersistedState(
            seedKey: seedKey,
            scorecards: scorecards,
            supervisors: supervisors,
            requests: requests,
            resolvedAlertIds: resolvedAlertIds
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("No se pudo guardar el tablero de la estación: \(error.localizedDescription)")
        }
    }
}
