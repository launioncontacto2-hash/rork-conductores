import Foundation
import Observation

/// Station-scoped source of truth for a supervisor session. It reads the same fleet
/// database the drivers write to (`FleetStore`) and expands it with the rest of the
/// station roster. Nothing outside the supervisor's station and shift is ever loaded.
@Observable
final class SupervisionStore {
    // MARK: - Persisted shape

    nonisolated private struct PersistedState: Codable, Sendable {
        var seedKey: String
        var vehicles: [StationVehicle]
        var peers: [StationDriver]
        var tickets: [HandoverTicket]
        var incidents: [StationIncident]
        var resolvedAlertIds: [String]
    }

    // MARK: - Identity

    let account: StaffAccount
    let station: Station
    private let fleet: FleetStore

    /// Shift the supervisor covers; every roster and ticket belongs to it.
    var slot: ShiftSlot { account.slot ?? .morning }
    var now: Date { fleet.now }

    // MARK: - State

    var vehicles: [StationVehicle] = []
    /// Simulated peers of the shift; the live driver session is merged on read.
    var peers: [StationDriver] = []
    var tickets: [HandoverTicket] = []
    var incidents: [StationIncident] = []
    var resolvedAlertIds: [String] = []
    private var seedKey: String = ""

    private var storageKey: String { "turnoev.supervision.v1.\(account.id)" }

    init(account: StaffAccount, fleet: FleetStore) {
        self.account = account
        self.fleet = fleet
        station = StaffDirectory.station(id: account.stationId) ?? StaffDirectory.stations[0]
        load()
    }

    // MARK: - Lifecycle

    /// Rebuilds the station when the operating day or shift changed, then pulls the
    /// latest driver-app activity into the supervision board.
    func refresh() {
        if seedKey != currentSeedKey { rebuild() }
        syncSharedFleet()
        syncLiveTickets()
        seedAssignmentsFromRoster()
        fleet.reloadAssignment()
        recordDayBilling()
    }

    /// Archives what the station has billed today.
    ///
    /// This write used to live inside `goalProgress(now:)`, a derived read — which meant
    /// drawing a screen mutated stored state, and after Fase 12 that read runs inside a
    /// `TimeScope(.day)`. A cadence boundary is not an event, and it must never be the thing
    /// that decides the ledger.
    ///
    /// Here it sits on the two real mutations instead: `refresh()`, which pulls the driver
    /// app's activity into the board, and `regenerateStation()`, which reseeds the peers'
    /// earnings. `StationGoalLedger.record` is idempotent by station and day — it compares
    /// before storing — so calling it on every sync costs nothing when nothing moved.
    private func recordDayBilling() {
        let today = now
        let billed = allDrivers(now: today).reduce(0) { $0 + $1.earningsMxn }
        StationGoalLedger.record(stationId: station.id, day: today, earningsMxn: billed)
    }

    private var currentSeedKey: String {
        let day = ShiftRules.calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        return "\(station.id)|\(slot.rawValue)|\(day)"
    }

    private func rebuild() {
        let snapshot = SupervisionMockData.snapshot(
            station: station,
            slot: slot,
            supervisorName: account.name,
            baseVehicles: fleet.vehicles,
            liveDriver: liveDriverProfile,
            now: now
        )
        vehicles = snapshot.vehicles
        peers = snapshot.drivers
        tickets = snapshot.tickets
        incidents = snapshot.incidents
        resolvedAlertIds = []
        seedKey = currentSeedKey
        persist()
    }

    /// Regenerates the simulated station without touching the drivers' records.
    func regenerateStation() {
        rebuild()
        syncLiveTickets()
        recordDayBilling()
    }

    // MARK: - Live driver bridge

    /// The driver profile of this station running the driver app on this device.
    private var liveDriverProfile: Driver? {
        let driver = fleet.driver
        guard driver.stationId == station.id, driver.slot == slot else { return nil }
        return driver
    }

    private func liveDeliveryTicket(now: Date) -> HandoverTicket? {
        guard let driver = liveDriverProfile else { return nil }
        return tickets.first { $0.driverId == driver.id && $0.kind == .delivery && ShiftRules.isSameDay($0.createdAt, now) }
    }

    /// Row built live from the driver app: same database, supervisor's reading.
    ///
    /// **Minute.** This is the root of every temporal dependency in this store. A driver who
    /// has not checked in is `.awaitingHandover` until the grace period runs out and then
    /// becomes `.absent` — a change decided by nothing but the clock advancing. Everything
    /// downstream (`allDrivers`, `alerts`, `metrics`, `attentionItems`) inherits that.
    func liveDriver(now: Date) -> StationDriver? {
        guard let driver = liveDriverProfile else { return nil }
        let scheduled = ShiftRules.scheduledStart(slot: slot, on: now)
        let todayRecord = fleet.history.first { ShiftRules.isSameDay($0.startedAt, now) }

        var state: StationDriverState
        var checkIn: Date?
        var late = 0
        var vehicleId: String?
        var vehicleNumber: String?

        if let shift = fleet.activeShift {
            checkIn = shift.startedAt
            late = shift.lateMinutes
            vehicleId = shift.vehicleId
            vehicleNumber = fleet.activeVehicle?.internalNumber
            if let ticket = liveDeliveryTicket(now: now), ticket.status == .pending {
                state = .awaitingHandover
            } else {
                state = late > 0 ? .late : .operating
            }
        } else if let record = todayRecord {
            state = .finished
            checkIn = record.startedAt
            late = record.lateMinutes
            vehicleId = record.vehicleId
            vehicleNumber = record.vehicleInternalNumber
        } else {
            let elapsed = Int(now.timeIntervalSince(scheduled) / 60)
            state = elapsed > ShiftRules.graceMinutes ? .absent : .awaitingHandover
        }

        let credit: DriverCreditState = {
            guard let credit = fleet.credit else { return .none }
            return credit.payments.contains { $0.status == .late } ? .behind : .current
        }()

        return StationDriver(
            id: driver.id,
            name: driver.name,
            employeeNumber: driver.employeeNumber,
            photoAsset: driver.photoAsset,
            stationId: driver.stationId,
            slot: driver.slot,
            group: driver.group,
            phone: "55 4821 9077",
            vehicleId: vehicleId,
            vehicleNumber: vehicleNumber,
            scheduledStartAt: scheduled,
            checkInAt: checkIn,
            lateMinutes: late,
            state: state,
            earningsMxn: fleet.earnedToday(reference: now),
            trips: fleet.tripsToday(reference: now),
            creditState: credit,
            openIncidents: fleet.incidents.filter { $0.status != .closed }.count,
            platformRating: 4.86,
            isLiveSession: true
        )
    }

    /// Incidents the driver app pushed into the shared database.
    private var liveIncidents: [StationIncident] {
        guard let driver = liveDriverProfile else { return [] }
        return fleet.incidents.map { incident in
            StationIncident(
                id: "live-\(incident.id)",
                stationId: station.id,
                driverId: driver.id,
                driverName: Fmt.firstName(driver.name) + " " + (driver.name.split(separator: " ").dropFirst().first.map(String.init) ?? ""),
                vehicleNumber: incident.vehicleInternalNumber,
                kind: incident.kind,
                severity: Self.severity(for: incident.kind),
                createdAt: incident.createdAt,
                detail: incident.description,
                photos: incident.photos,
                status: incident.status,
                reportedBy: "Conductor"
            )
        }
    }

    private static func severity(for kind: IncidentKind) -> IncidentSeverity {
        switch kind {
        case .accident: .critical
        case .mechanical: .high
        case .damage: .medium
        }
    }

    /// Mirrors the units of the shared database into the station fleet board.
    private func syncSharedFleet() {
        for vehicle in fleet.vehicles where vehicle.stationId == station.id {
            guard let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) else { continue }
            vehicles[index].batteryPct = vehicle.batteryPct
            vehicles[index].odometerKm = vehicle.odometerKm
            switch vehicle.status {
            case .maintenance:
                vehicles[index].state = .maintenance
            case .occupied:
                vehicles[index].state = .operating
                vehicles[index].assignedDriverId = vehicle.occupiedBy
                vehicles[index].assignedDriverName = vehicle.occupiedBy == fleet.driver.id ? fleet.driver.name : vehicles[index].assignedDriverName
                vehicles[index].qrScanned = true
            case .available:
                if vehicles[index].state == .operating {
                    vehicles[index].state = .available
                    vehicles[index].assignedDriverId = nil
                    vehicles[index].assignedDriverName = nil
                }
            }
        }
    }

    /// Opens the handover tickets the live driver generated with the driver app.
    private func syncLiveTickets() {
        guard let driver = liveDriverProfile else { return }

        if let shift = fleet.activeShift {
            let id = "hnd-live-d-\(shift.id)"
            if !tickets.contains(where: { $0.id == id }) {
                let vehicle = fleet.activeVehicle
                tickets.insert(
                    HandoverTicket(
                        id: id,
                        stationId: station.id,
                        kind: .delivery,
                        driverId: driver.id,
                        driverName: driver.name,
                        vehicleId: shift.vehicleId,
                        vehicleNumber: vehicle?.internalNumber ?? "—",
                        createdAt: shift.startedAt,
                        scheduledStartAt: shift.scheduledStartAt,
                        startOdometerKm: shift.startOdometerKm,
                        endOdometerKm: nil,
                        expectedOdometerKm: vehicle?.odometerKm ?? shift.startOdometerKm,
                        batteryPct: shift.startBatteryPct,
                        qrCodeRead: vehicle?.qrCode,
                        photosCaptured: shift.photos.count,
                        lateMinutes: shift.lateMinutes,
                        observations: shift.lateMinutes > 0
                            ? "Inicio con \(Fmt.lateText(shift.lateMinutes)) de atraso registrado en bitácora."
                            : "Inicio dentro de tolerancia.",
                        checks: [:],
                        status: .pending,
                        resolvedAt: nil,
                        rejectionReason: nil,
                        odometerPhotoAsset: nil,
                        isLiveSession: true
                    ),
                    at: 0
                )
                persist()
            } else if let index = tickets.firstIndex(where: { $0.id == id }), tickets[index].status == .pending {
                // The driver keeps adding evidence while the ticket waits for approval.
                tickets[index].photosCaptured = shift.photos.count
            }
        }

        if let record = fleet.history.first(where: { ShiftRules.isSameDay($0.startedAt, now) && $0.driverId == driver.id }) {
            let id = "hnd-live-r-\(record.id)"
            if !tickets.contains(where: { $0.id == id }) {
                tickets.insert(
                    HandoverTicket(
                        id: id,
                        stationId: station.id,
                        kind: .reception,
                        driverId: driver.id,
                        driverName: driver.name,
                        vehicleId: record.vehicleId,
                        vehicleNumber: record.vehicleInternalNumber,
                        createdAt: record.endedAt,
                        scheduledStartAt: record.scheduledStartAt,
                        startOdometerKm: record.startOdometerKm,
                        endOdometerKm: record.endOdometerKm,
                        expectedOdometerKm: record.endOdometerKm,
                        batteryPct: record.endBatteryPct,
                        qrCodeRead: record.vehicleInternalNumber,
                        photosCaptured: 6,
                        lateMinutes: record.lateMinutes,
                        observations: "Turno de \(Fmt.durationText(record.durationMinutes)) · \(record.trips) viajes.",
                        checks: [:],
                        status: .pending,
                        resolvedAt: nil,
                        rejectionReason: nil,
                        odometerPhotoAsset: nil,
                        isLiveSession: true
                    ),
                    at: 0
                )
                persist()
            }
        }
    }

    /// Evidence captured by the live driver, shown when reviewing his handover.
    func liveEvidence(for ticket: HandoverTicket) -> [(slot: InspectionSlot, data: Data)] {
        guard ticket.isLiveSession, let shift = fleet.activeShift else { return [] }
        return InspectionSlot.allCases.compactMap { slot in
            guard let data = shift.photos[slot.rawValue] else { return nil }
            return (slot, data)
        }
    }

    // MARK: - Reads

    /// **Minute**, inherited from `liveDriver`. The simulated peers carry stored states, so
    /// the only row that can change by itself is the live one — but that is enough to move
    /// any count built on top of this.
    func allDrivers(now: Date) -> [StationDriver] {
        let roster = liveDriver(now: now).map { [$0] + peers } ?? peers
        let book = AssignmentBook.assignments(stationId: station.id)
        return roster.map { row in
            guard let assignment = book.first(where: { $0.driverId == row.id }) else {
                var cleared = row
                // Nobody tied a unit to this driver: the roster must show the gap.
                if fleet.activeShift?.driverId != row.id {
                    cleared.vehicleId = nil
                    cleared.vehicleNumber = nil
                }
                return cleared
            }
            var updated = row
            updated.vehicleId = row.vehicleId ?? assignment.vehicleId
            updated.vehicleNumber = row.vehicleNumber ?? assignment.vehicleNumber
            return updated
        }
    }

    // MARK: - Unit assignment

    /// Every unit the station tied to a person, supervisor's own board.
    var assignments: [VehicleAssignment] { AssignmentBook.assignments(stationId: station.id) }

    func assignment(driverId: String) -> VehicleAssignment? {
        AssignmentBook.assignment(driverId: driverId)
    }

    /// Driver currently holding a unit, so one unit is never tied to two people.
    func holder(vehicleId: String) -> VehicleAssignment? {
        AssignmentBook.holder(vehicleId: vehicleId)
    }

    /// Units this supervisor can hand over: in the station, not broken, not in the workshop.
    func assignableVehicles(for driverId: String) -> [StationVehicle] {
        vehicles
            .filter { $0.state != .outOfService && $0.state != .maintenance }
            .filter { vehicle in
                guard let holder = holder(vehicleId: vehicle.id) else { return true }
                return holder.driverId == driverId
            }
            .sorted { $0.bay < $1.bay }
    }

    /// Ties a unit to a driver. `.substitute` keeps the titular unit on file so the
    /// driver goes back to it once it is released.
    @discardableResult
    func assignUnit(
        driverId: String,
        driverName: String,
        vehicleId: String,
        kind: AssignedUnitKind,
        note: String
    ) -> Bool {
        guard let vehicle = vehicles.first(where: { $0.id == vehicleId }) else { return false }
        let previous = assignment(driverId: driverId)
        let assignment = AssignmentBook.make(
            stationId: station.id,
            driverId: driverId,
            driverName: driverName,
            vehicleId: vehicle.id,
            vehicleNumber: vehicle.internalNumber,
            kind: kind,
            note: note,
            assignedBy: account.name,
            now: now,
            previous: previous
        )
        AssignmentBook.upsert(assignment)

        if let index = vehicles.firstIndex(where: { $0.id == vehicleId }) {
            vehicles[index].assignedDriverId = driverId
            vehicles[index].assignedDriverName = driverName
        }
        // The unit the driver leaves goes back to the free pool of the station.
        if let previous, previous.vehicleId != vehicleId,
           let index = vehicles.firstIndex(where: { $0.id == previous.vehicleId }),
           vehicles[index].state != .operating {
            vehicles[index].assignedDriverId = nil
            vehicles[index].assignedDriverName = nil
        }

        notifyDriver(
            driverId: driverId,
            title: kind == .substitute ? "Unidad sustituta asignada" : "Unidad asignada",
            body: "\(account.name) te asignó \(vehicle.internalNumber)\(note.isEmpty ? "." : ": \(note)")"
        )

        persist()
        return true
    }

    /// Removes the unit from a driver. The seat stays on the roster without a unit.
    func removeAssignment(driverId: String) {
        let previous = assignment(driverId: driverId)
        AssignmentBook.remove(driverId: driverId)
        if let previous, let index = vehicles.firstIndex(where: { $0.id == previous.vehicleId }),
           vehicles[index].state != .operating {
            vehicles[index].assignedDriverId = nil
            vehicles[index].assignedDriverName = nil
        }
        notifyDriver(
            driverId: driverId,
            title: "Unidad retirada",
            body: "\(account.name) retiró la asignación de \(previous?.vehicleNumber ?? "tu unidad"). No podrás iniciar turno hasta recibir otra."
        )
        persist()
    }

    /// Pushes the change to the driver app when the affected credential is the live one.
    private func notifyDriver(driverId: String, title: String, body: String) {
        fleet.reloadAssignment()
        guard fleet.driver.id == driverId else { return }
        fleet.pushNotice(kind: .station, title: title, body: body)
    }

    /// Turns the simulated roster into real assignment records so the board opens coherent.
    private func seedAssignmentsFromRoster() {
        for peer in peers {
            guard let vehicleId = peer.vehicleId, let vehicleNumber = peer.vehicleNumber else { continue }
            guard AssignmentBook.assignment(driverId: peer.id) == nil else { continue }
            guard AssignmentBook.holder(vehicleId: vehicleId) == nil else { continue }
            AssignmentBook.upsert(
                AssignmentBook.make(
                    stationId: station.id,
                    driverId: peer.id,
                    driverName: peer.name,
                    vehicleId: vehicleId,
                    vehicleNumber: vehicleNumber,
                    kind: .titular,
                    note: "Asignación de planta.",
                    assignedBy: account.name,
                    now: now,
                    previous: nil
                )
            )
        }
    }

    var allIncidents: [StationIncident] {
        (liveIncidents + incidents).sorted { $0.createdAt > $1.createdAt }
    }

    var pendingTickets: [HandoverTicket] {
        tickets.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt }
    }

    var resolvedTickets: [HandoverTicket] {
        tickets.filter { $0.status != .pending }.sorted { ($0.resolvedAt ?? $0.createdAt) > ($1.resolvedAt ?? $1.createdAt) }
    }

    /// **Minute.** Not because of the `now` handed to the rule set — that one only stamps
    /// `createdAt` on lines that have no better date — but because membership itself moves:
    /// the rules raise one alert per driver in `.late` and one per driver in `.absent`, and
    /// a driver crosses into `.absent` on the grace boundary with no event behind it.
    func alerts(now: Date) -> [StationAlert] {
        SupervisionRules.alerts(
            drivers: allDrivers(now: now),
            vehicles: vehicles,
            tickets: pendingTickets,
            incidents: allIncidents,
            now: now
        )
        .filter { !resolvedAlertIds.contains($0.id) }
    }

    func criticalAlerts(now: Date) -> [StationAlert] {
        alerts(now: now).filter { $0.severity == .critical || $0.severity == .high }
    }

    /// **Minute**, on two independent counts: the driver states come from `allDrivers`, and
    /// the shift goal is read from `ShiftRules.group(for:)`, which changes on block change.
    func metrics(now: Date) -> StationMetrics {
        let drivers = allDrivers(now: now)
        let openIncidents = allIncidents.filter(\.isOpen).count
        return StationMetrics(
            activeVehicles: vehicles.filter { $0.state == .operating }.count,
            pendingHandover: pendingTickets.count,
            outOfService: vehicles.filter { $0.state == .outOfService }.count,
            inMaintenance: vehicles.filter { $0.state == .maintenance }.count,
            presentDrivers: drivers.filter { $0.state.isPresent }.count,
            absentDrivers: drivers.filter { $0.state == .absent }.count,
            lateDrivers: drivers.filter { $0.state == .late }.count,
            openIncidents: openIncidents,
            criticalAlerts: criticalAlerts(now: now).count,
            capacity: station.vehicleCapacity,
            rosterSize: drivers.count,
            earningsMxn: drivers.reduce(0) { $0 + $1.earningsMxn },
            goalMxn: ShiftRules.stationShiftGoalMxn(
                capacity: station.vehicleCapacity,
                group: ShiftRules.group(for: now)
            ),
            tripsToday: drivers.reduce(0) { $0 + $1.trips },
            goalGroup: ShiftRules.group(for: now)
        )
    }

    /// The fixed number this shift has to reach and the arithmetic behind it: the same
    /// board the manager reads, cut to this supervisor's own block.
    /// **Minute**: the block the goal belongs to changes on the shift boundary.
    func goalBoard(now: Date) -> StationGoalBoard {
        let drivers = allDrivers(now: now)
        return StationGoalBoard(
            capacity: station.vehicleCapacity,
            group: ShiftRules.group(for: now),
            slot: slot,
            earningsMxn: drivers.reduce(0) { $0 + $1.earningsMxn },
            presentDrivers: drivers.filter { $0.state.isPresent }.count,
            weekEarningsMxn: StationGoalLedger.weekEarnings(stationId: station.id, reference: now)
        )
    }

    // MARK: - Operación summary

    /// Day, week and month against their own fixed goals. The week and the month add up
    /// only the days the station actually recorded, so nothing here is an estimate.
    ///
    /// **Day.** The three buckets are decided by the calendar date, not by the hour: nothing
    /// here moves at a shift boundary.
    ///
    /// **Pure.** It reads the ledger and never writes to it — see `recordDayBilling()`.
    ///
    /// Today is taken live and swapped in for whatever the archive holds for today, which is
    /// what keeps the observable behaviour identical to the version that wrote first and
    /// read second: the week and the month always contain the freshest figure of the day,
    /// while the days behind it come from the archive untouched.
    func goalProgress(now: Date) -> StationGoalProgress {
        let capacity = station.vehicleCapacity
        let billedToday = allDrivers(now: now).reduce(0) { $0 + $1.earningsMxn }
        let archivedToday = StationGoalLedger.earnings(stationId: station.id, day: now)
        let archivedWeek = StationGoalLedger.weekEarnings(stationId: station.id, reference: now)
        let archivedMonth = StationGoalLedger.monthEarnings(stationId: station.id, reference: now)

        return StationGoalProgress(
            dayEarningsMxn: billedToday,
            dayGoalMxn: ShiftRules.stationDayGoalMxn(capacity: capacity, on: now),
            weekEarningsMxn: archivedWeek - archivedToday + billedToday,
            weekGoalMxn: ShiftRules.stationWeekGoalMxn(capacity: capacity),
            monthEarningsMxn: archivedMonth - archivedToday + billedToday,
            monthGoalMxn: ShiftRules.stationMonthGoalMxn(capacity: capacity, on: now)
        )
    }

    /// Units the station holds back to cover an unexpected absence. They belong to nobody:
    /// a replacement shift can be tied to one of them later in the day.
    var configuredReplacementUnits: Int {
        StationReplacementPolicy.configuredUnits(stationId: station.id)
    }

    /// Of those, the ones parked and free right now.
    var availableReplacementUnits: Int {
        let idle = vehicles.filter { $0.state == .available && $0.assignedDriverId == nil }.count
        return min(configuredReplacementUnits, idle)
    }

    /// The short list of situations that need the supervisor. It is not a set of metrics:
    /// when a situation is resolved, its line disappears.
    /// **Minute**, inherited whole from `metrics`.
    func attentionItems(now: Date) -> [StationAttentionItem] {
        let numbers = metrics(now: now)
        var items: [StationAttentionItem] = []

        if numbers.absentDrivers > 0 {
            items.append(
                StationAttentionItem(
                    id: "absent",
                    title: numbers.absentDrivers == 1
                        ? "1 conductor ausente sin cobertura"
                        : "\(numbers.absentDrivers) conductores ausentes sin cobertura",
                    level: .problem,
                    symbol: "person.fill.xmark",
                    target: .drivers(.absent)
                )
            )
        }

        if numbers.outOfService > 0 {
            items.append(
                StationAttentionItem(
                    id: "outOfService",
                    title: numbers.outOfService == 1
                        ? "1 vehículo no disponible"
                        : "\(numbers.outOfService) vehículos no disponibles",
                    level: .problem,
                    symbol: "xmark.octagon.fill",
                    target: .vehicles(.outOfService)
                )
            )
        }

        if numbers.criticalAlerts > 0 {
            items.append(
                StationAttentionItem(
                    id: "critical",
                    title: numbers.criticalAlerts == 1
                        ? "1 alerta crítica abierta"
                        : "\(numbers.criticalAlerts) alertas críticas abiertas",
                    level: .problem,
                    symbol: "bell.badge.fill",
                    target: .alerts
                )
            )
        }

        if numbers.lateDrivers > 0 {
            items.append(
                StationAttentionItem(
                    id: "late",
                    title: numbers.lateDrivers == 1
                        ? "1 conductor demorado"
                        : "\(numbers.lateDrivers) conductores demorados",
                    level: .warning,
                    symbol: "clock.badge.exclamationmark.fill",
                    target: .drivers(.late)
                )
            )
        }

        if numbers.inMaintenance > 0 {
            items.append(
                StationAttentionItem(
                    id: "maintenance",
                    title: numbers.inMaintenance == 1
                        ? "1 vehículo en taller"
                        : "\(numbers.inMaintenance) vehículos en taller",
                    level: .warning,
                    symbol: "wrench.and.screwdriver.fill",
                    target: .vehicles(.maintenance)
                )
            )
        }

        if numbers.pendingHandover > 0 {
            items.append(
                StationAttentionItem(
                    id: "handover",
                    title: numbers.pendingHandover == 1
                        ? "1 entrega pendiente de firma"
                        : "\(numbers.pendingHandover) entregas pendientes de firma",
                    level: .warning,
                    symbol: "hand.raised.fill",
                    target: .vehicles(.available)
                )
            )
        }

        // A free replacement unit is not a problem: it is the way out of one.
        if numbers.absentDrivers > 0, availableReplacementUnits > 0 {
            items.append(
                StationAttentionItem(
                    id: "replacement",
                    title: availableReplacementUnits == 1
                        ? "1 turno de reemplazo disponible"
                        : "\(availableReplacementUnits) turnos de reemplazo disponibles",
                    level: .info,
                    symbol: "arrow.triangle.2.circlepath",
                    target: .coverage
                )
            )
        }

        return items
    }

    /// **Minute** whenever the filter names a state — `.late`, `.absent`, `.active` are all
    /// membership decided by the clock through `allDrivers`.
    func drivers(matching filter: DriverFilter, search: String = "", now: Date) -> [StationDriver] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return allDrivers(now: now)
            .filter { driver in
                switch filter {
                case .all: true
                case .active: driver.state == .operating || driver.state == .late
                case .withoutUnit: assignment(driverId: driver.id) == nil
                case .late: driver.state == .late
                case .absent: driver.state == .absent
                case .withIncidents: driver.openIncidents > 0
                }
            }
            .filter { driver in
                guard !cleaned.isEmpty else { return true }
                return driver.name.localizedStandardContains(cleaned)
                    || driver.employeeNumber.localizedStandardContains(cleaned)
                    || (driver.vehicleNumber ?? "").localizedStandardContains(cleaned)
            }
            .sorted { lhs, rhs in
                if lhs.isLiveSession != rhs.isLiveSession { return lhs.isLiveSession }
                return statePriority(lhs.state) == statePriority(rhs.state)
                    ? lhs.name < rhs.name
                    : statePriority(lhs.state) < statePriority(rhs.state)
            }
    }

    private func statePriority(_ state: StationDriverState) -> Int {
        switch state {
        case .late: 0
        case .awaitingHandover: 1
        case .absent: 2
        case .operating: 3
        case .finished: 4
        }
    }

    func vehicles(matching state: FleetVehicleState?, search: String = "") -> [StationVehicle] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return vehicles
            .filter { state == nil || $0.state == state }
            .filter { vehicle in
                guard !cleaned.isEmpty else { return true }
                return vehicle.internalNumber.localizedStandardContains(cleaned)
                    || vehicle.plates.localizedStandardContains(cleaned)
                    || (vehicle.assignedDriverName ?? "").localizedStandardContains(cleaned)
            }
            .sorted { $0.bay < $1.bay }
    }

    func driver(id: String?, now: Date) -> StationDriver? {
        guard let id else { return nil }
        return allDrivers(now: now).first { $0.id == id }
    }

    func vehicle(id: String?) -> StationVehicle? {
        guard let id else { return nil }
        return vehicles.first { $0.id == id }
    }

    func ticket(id: String?) -> HandoverTicket? {
        guard let id else { return nil }
        return tickets.first { $0.id == id }
    }

    func ticket(forDriver driverId: String) -> HandoverTicket? {
        pendingTickets.first { $0.driverId == driverId }
    }

    // MARK: - Handover decisions

    func setCheck(_ check: HandoverCheck, on ticketId: String, value: Bool) {
        guard let index = tickets.firstIndex(where: { $0.id == ticketId }) else { return }
        tickets[index].checks[check.rawValue] = value
        persist()
    }

    /// Validates a scanned sticker against the unit of the ticket.
    @discardableResult
    func validateScan(code: String, on ticketId: String) -> Bool {
        guard let index = tickets.firstIndex(where: { $0.id == ticketId }) else { return false }
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let expected = tickets[index].vehicleNumber.uppercased()
        guard cleaned == expected else { return false }
        tickets[index].qrCodeRead = cleaned
        tickets[index].checks[HandoverCheck.qr.rawValue] = true
        if let vehicleIndex = vehicles.firstIndex(where: { $0.id == tickets[index].vehicleId }) {
            vehicles[vehicleIndex].qrScanned = true
        }
        persist()
        return true
    }

    @discardableResult
    func approve(ticketId: String) -> Bool {
        guard let index = tickets.firstIndex(where: { $0.id == ticketId }), tickets[index].isReadyToApprove else {
            return false
        }
        tickets[index].status = .approved
        tickets[index].resolvedAt = now
        let ticket = tickets[index]

        switch ticket.kind {
        case .delivery:
            if let driverIndex = peers.firstIndex(where: { $0.id == ticket.driverId }) {
                peers[driverIndex].state = peers[driverIndex].lateMinutes > 0 ? .late : .operating
                peers[driverIndex].checkInAt = peers[driverIndex].checkInAt ?? now
            }
            if let vehicleIndex = vehicles.firstIndex(where: { $0.id == ticket.vehicleId }) {
                vehicles[vehicleIndex].state = .operating
                vehicles[vehicleIndex].assignedDriverId = ticket.driverId
                vehicles[vehicleIndex].assignedDriverName = ticket.driverName
                vehicles[vehicleIndex].odometerKm = ticket.startOdometerKm
                vehicles[vehicleIndex].qrScanned = true
            }
            if ticket.isLiveSession {
                fleet.pushNotice(
                    kind: .station,
                    title: "Inicio de turno aprobado",
                    body: "\(account.name) validó tu entrega de \(ticket.vehicleNumber). Buen turno."
                )
            }
        case .reception:
            if let driverIndex = peers.firstIndex(where: { $0.id == ticket.driverId }) {
                peers[driverIndex].state = .finished
            }
            if let vehicleIndex = vehicles.firstIndex(where: { $0.id == ticket.vehicleId }) {
                vehicles[vehicleIndex].state = .available
                vehicles[vehicleIndex].assignedDriverId = nil
                vehicles[vehicleIndex].assignedDriverName = nil
                vehicles[vehicleIndex].batteryPct = ticket.batteryPct
                vehicles[vehicleIndex].odometerKm = ticket.endOdometerKm ?? vehicles[vehicleIndex].odometerKm
                vehicles[vehicleIndex].qrScanned = false
            }
            if ticket.isLiveSession {
                fleet.pushNotice(
                    kind: .station,
                    title: "Recepción de unidad aprobada",
                    body: "\(account.name) recibió \(ticket.vehicleNumber) con \(Fmt.km(ticket.endOdometerKm ?? 0))."
                )
            }
        }

        persist()
        return true
    }

    func reject(ticketId: String, reason: String) {
        guard let index = tickets.firstIndex(where: { $0.id == ticketId }) else { return }
        tickets[index].status = .rejected
        tickets[index].resolvedAt = now
        tickets[index].rejectionReason = reason
        let ticket = tickets[index]

        if let vehicleIndex = vehicles.firstIndex(where: { $0.id == ticket.vehicleId }) {
            vehicles[vehicleIndex].state = .available
            vehicles[vehicleIndex].assignedDriverId = nil
            vehicles[vehicleIndex].assignedDriverName = nil
        }
        if ticket.isLiveSession {
            fleet.pushNotice(
                kind: .station,
                title: "\(ticket.kind.label) rechazada",
                body: "\(account.name): \(reason)"
            )
        }
        persist()
    }

    // MARK: - Incidents

    func report(
        kind: IncidentKind,
        severity: IncidentSeverity,
        driverId: String?,
        vehicleNumber: String,
        detail: String,
        photos: [Data]
    ) {
        // Action path: the roster is read at the instant the report is filed, and the same
        // instant stamps the incident. Nothing here is a live reading.
        let filedAt = now
        let driver = driver(id: driverId, now: filedAt)
        let incident = StationIncident(
            id: "sinc-\(UUID().uuidString.prefix(8))",
            stationId: station.id,
            driverId: driverId,
            driverName: driver?.shortName ?? "Sin conductor",
            vehicleNumber: vehicleNumber,
            kind: kind,
            severity: severity,
            createdAt: filedAt,
            detail: detail,
            photos: Array(photos.prefix(4)),
            status: .open,
            reportedBy: account.name
        )
        incidents.insert(incident, at: 0)

        if severity == .high || severity == .critical,
           let index = vehicles.firstIndex(where: { $0.internalNumber == vehicleNumber }) {
            vehicles[index].state = .outOfService
            vehicles[index].assignedDriverId = nil
            vehicles[index].assignedDriverName = nil
        }

        if let driverId, driverId == fleet.driver.id {
            fleet.pushNotice(
                kind: .station,
                title: "Reporte de \(kind.label.lowercased()) levantado",
                body: "\(account.name) registró un reporte de gravedad \(severity.label.lowercased()) en \(vehicleNumber)."
            )
        }
        persist()
    }

    func setIncidentStatus(id: String, status: IncidentStatus) {
        guard let index = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[index].status = status
        if status == .closed, let vehicleIndex = vehicles.firstIndex(where: { $0.internalNumber == incidents[index].vehicleNumber }),
           vehicles[vehicleIndex].state == .outOfService {
            vehicles[vehicleIndex].state = .available
        }
        persist()
    }

    // MARK: - Fleet actions

    func setVehicleState(id: String, state: FleetVehicleState) {
        guard let index = vehicles.firstIndex(where: { $0.id == id }) else { return }
        vehicles[index].state = state
        if state != .operating {
            vehicles[index].assignedDriverId = nil
            vehicles[index].assignedDriverName = nil
        }
        if state == .maintenance {
            vehicles[index].maintenance = .inWorkshop
        }
        persist()
    }

    func sendToWorkshop(id: String, note: String) {
        setVehicleState(id: id, state: .maintenance)
        guard let vehicle = vehicle(id: id) else { return }
        incidents.insert(
            StationIncident(
                id: "sinc-\(UUID().uuidString.prefix(8))",
                stationId: station.id,
                driverId: nil,
                driverName: "Estación",
                vehicleNumber: vehicle.internalNumber,
                kind: .mechanical,
                severity: .medium,
                createdAt: now,
                detail: note.isEmpty ? "Envío a taller programado por supervisión." : note,
                photos: [],
                status: .review,
                reportedBy: account.name
            ),
            at: 0
        )
        persist()
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
            vehicles = state.vehicles
            peers = state.peers
            tickets = state.tickets
            incidents = state.incidents
            resolvedAlertIds = state.resolvedAlertIds
            if seedKey != currentSeedKey { rebuild() }
        } catch {
            print("No se pudo leer el tablero de supervisión: \(error.localizedDescription)")
            rebuild()
        }
    }

    private func persist() {
        let state = PersistedState(
            seedKey: seedKey,
            vehicles: vehicles,
            peers: peers,
            tickets: tickets,
            incidents: incidents,
            resolvedAlertIds: resolvedAlertIds
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("No se pudo guardar el tablero de supervisión: \(error.localizedDescription)")
        }
    }
}
