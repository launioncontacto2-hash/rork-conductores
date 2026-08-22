import Foundation

/// The test world. Everything the administrator creates lives here and nowhere else.
/// It starts completely empty: zero stations, zero users, zero units, zero money.
nonisolated struct LabWorld: Codable, Sendable {
    var mode: LabMode = .production

    var regions: [Region] = []
    var stations: [LabStation] = []
    var users: [LabUser] = []
    var vehicles: [LabVehicle] = []

    var employeeFiles: [EmployeeFile] = []
    var prospects: [Prospect] = []
    var campaigns: [RecruitCampaign] = []
    var appointments: [Appointment] = []

    var assets: [StationAsset] = []
    var orders: [WorkOrder] = []
    var incidents: [StationIncident] = []

    var credits: [LabCredit] = []
    var bonuses: [LabBonus] = []
    var goals: [LabGoal] = []
    var settlements: [WeeklySettlement] = []
    var bankAccounts: [LabBankAccount] = []
    var transfers: [LabTransfer] = []

    var documents: [LabDocument] = []
    var alerts: [LabAlert] = []
    var faults: [LabFault] = []
    var audit: [LabAuditEntry] = []

    var uberFeeds: [LabUberFeed] = []
    var telemetry: [LabTelemetryReading] = []
    var customScenarios: [LabScenario] = []

    var shiftConfig: LabShiftConfig = .standard
    var clockOffsetMinutes: Int = 0
    var lastResetAt: Date?

    /// A brand new environment: nothing but the rules.
    static let empty = LabWorld()

    // MARK: - Counters used by the dashboard

    var operationalStations: [LabStation] { stations.filter { $0.lifecycle.isOperational } }

    var installedVehicles: [LabVehicle] { vehicles.filter { $0.stage.isInstalled } }

    var incomingVehicles: [LabVehicle] { vehicles.filter { $0.stage.isIncoming } }

    var driverUsers: [LabUser] { users.filter { $0.role == .driver } }

    var activeDriverUsers: [LabUser] {
        users.filter { $0.role == .driver && $0.status == .active && $0.employment.canOperate }
    }

    var requiredDrivers: Int { installedVehicles.count * max(1, shiftConfig.driversPerVehicle) }

    var driverDeficit: Int { max(0, requiredDrivers - activeDriverUsers.count) }

    var coveragePct: Int {
        requiredDrivers > 0
            ? Int((Double(activeDriverUsers.count) / Double(requiredDrivers) * 100).rounded())
            : 100
    }

    var isEmpty: Bool {
        stations.isEmpty && users.isEmpty && vehicles.isEmpty && prospects.isEmpty
            && credits.isEmpty && orders.isEmpty && documents.isEmpty
    }

    var totalRecords: Int {
        let core: Int = stations.count + users.count + vehicles.count + employeeFiles.count + prospects.count
        let operations: Int = campaigns.count + appointments.count + assets.count + orders.count + incidents.count
        let finance: Int = credits.count + bonuses.count + goals.count + settlements.count + bankAccounts.count
        let paperwork: Int = transfers.count + documents.count + alerts.count + faults.count
        let feeds: Int = uberFeeds.count + telemetry.count
        return core + operations + finance + paperwork + feeds
    }

    func station(id: String?) -> LabStation? {
        guard let id else { return nil }
        return stations.first { $0.id == id }
    }

    func vehicle(id: String?) -> LabVehicle? {
        guard let id else { return nil }
        return vehicles.first { $0.id == id }
    }

    func user(id: String?) -> LabUser? {
        guard let id else { return nil }
        return users.first { $0.id == id }
    }

    func vehicles(at stationId: String) -> [LabVehicle] {
        vehicles.filter { $0.stationId == stationId }
    }

    func users(at stationId: String, role: StaffRole) -> [LabUser] {
        users.filter { $0.stationId == stationId && $0.role == role }
    }

    func installedCount(at stationId: String) -> Int {
        vehicles.filter { $0.stationId == stationId && $0.stage.isInstalled }.count
    }

    // MARK: - Bridge projection

    /// What the rest of the app is allowed to see. Only operational stations and active
    /// credentials cross the border.
    var bridge: LabBridge {
        guard mode == .test else { return .production }
        let domainStations = stations.map { $0.station(installedVehicles: installedCount(at: $0.id)) }
        return LabBridge(
            mode: .test,
            regions: regions,
            stations: domainStations,
            accounts: users.map(\.account),
            vehicles: installedVehicles.map { unit in
                unit.vehicle(stationName: station(id: unit.stationId)?.displayName ?? "—")
            },
            drivers: driverUsers.compactMap { driver(from: $0) },
            driversPerVehicle: max(1, shiftConfig.driversPerVehicle)
        )
    }

    func driver(from user: LabUser) -> Driver? {
        guard user.role == .driver, let driverId = user.driverId, let stationId = user.stationId else { return nil }
        let block = user.block ?? .weekdayMorning
        return Driver(
            id: driverId,
            name: user.name,
            employeeNumber: user.employeeNumber,
            email: user.email.lowercased(),
            password: user.password,
            photoAsset: "rideshare_driver_portrait",
            stationId: stationId,
            station: station(id: stationId)?.displayName ?? "—",
            group: block.group,
            slot: block.slot,
            authorizedVehicleIds: vehicles(at: stationId).filter { $0.stage.isInstalled }.map(\.id)
        )
    }
}

// MARK: - Persistence

/// The test world is stored apart from the operational state so wiping one never touches
/// the other.
nonisolated enum LabPersistence {
    static let storageKey = "turnoev.lab.v1"

    static func load() -> LabWorld {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return .empty }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(LabWorld.self, from: data)
        } catch {
            print("No se pudo leer el entorno de pruebas: \(error.localizedDescription)")
            return .empty
        }
    }

    static func save(_ world: LabWorld) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(world)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("No se pudo guardar el entorno de pruebas: \(error.localizedDescription)")
        }
    }

    static func wipe() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Feeding the operational modules

/// Translates the test world into the snapshots every operational module already knows how
/// to read. In production mode none of this runs.
nonisolated enum LabSeed {
    // MARK: Supervision

    static func supervisionSnapshot(
        world: LabWorld,
        station: Station,
        slot: ShiftSlot,
        now: Date
    ) -> SupervisionMockData.Snapshot {
        let units = world.vehicles(at: station.id).filter { $0.stage.isInstalled }
        let vehicles: [StationVehicle] = units.enumerated().map { index, unit in
            StationVehicle(
                id: unit.id,
                internalNumber: unit.internalNumber,
                model: unit.fullModel,
                plates: unit.plates,
                stationId: station.id,
                bay: index + 1,
                state: fleetState(for: unit),
                batteryPct: unit.batteryPct,
                odometerKm: unit.odometerKm,
                assignedDriverId: unit.occupiedBy,
                assignedDriverName: world.users.first { $0.driverId == unit.occupiedBy }?.name,
                maintenance: unit.stage == .maintenance ? .inWorkshop : .ok,
                nextServiceKm: unit.odometerKm + 10_000,
                lastServiceAt: unit.incorporatedAt,
                qrScanned: false,
                photoAsset: "electric_sedan_charging"
            )
        }

        let roster = world.users.filter {
            $0.stationId == station.id && $0.role == .driver && ($0.block?.slot ?? .morning) == slot
        }
        let scheduled = ShiftRules.scheduledStart(slot: slot, on: now)
        let drivers: [StationDriver] = roster.map { user in
            StationDriver(
                id: user.driverId ?? user.id,
                name: user.name,
                employeeNumber: user.employeeNumber,
                photoAsset: nil,
                stationId: station.id,
                slot: slot,
                group: user.block?.group ?? .weekday,
                phone: user.phone,
                vehicleId: nil,
                vehicleNumber: nil,
                scheduledStartAt: scheduled,
                checkInAt: nil,
                lateMinutes: 0,
                state: user.employment.canOperate ? .awaitingHandover : .absent,
                earningsMxn: 0,
                trips: 0,
                creditState: creditState(world: world, driverId: user.driverId),
                openIncidents: 0,
                platformRating: 0,
                isLiveSession: false
            )
        }

        return SupervisionMockData.Snapshot(
            vehicles: vehicles,
            drivers: drivers,
            tickets: [],
            incidents: world.incidents.filter { $0.stationId == station.id }
        )
    }

    private static func fleetState(for unit: LabVehicle) -> FleetVehicleState {
        switch unit.stage {
        case .operating: .operating
        case .maintenance: .maintenance
        case .outOfService: .outOfService
        default: .available
        }
    }

    private static func creditState(world: LabWorld, driverId: String?) -> DriverCreditState {
        guard let driverId, let credit = world.credits.first(where: { $0.driverId == driverId }) else {
            return .none
        }
        switch credit.state {
        case .late, .suspended: return .behind
        case .settled: return .delivered
        case .cancelled: return .none
        case .active, .current: return .current
        }
    }

    // MARK: Station office

    static func stationOfficeSnapshot(
        world: LabWorld,
        station: Station,
        now: Date
    ) -> StationOfficeMockData.Snapshot {
        let incoming = world.vehicles(at: station.id).filter { $0.stage.isIncoming }
        let incorporations: [VehicleIncorporation] = Dictionary(grouping: incoming, by: { $0.stage })
            .map { stage, units in
                VehicleIncorporation(
                    id: "labinc-\(station.id)-\(stage.rawValue)",
                    stationId: station.id,
                    model: units.first?.fullModel ?? "Unidad",
                    units: units.count,
                    stage: incorporationStage(for: stage),
                    arrivalAt: units.map(\.incorporatedAt).min() ?? now,
                    operationStartAt: units.map(\.operationStartAt).min() ?? now,
                    note: "Alta generada desde el laboratorio de pruebas."
                )
            }
            .sorted { $0.arrivalAt < $1.arrivalAt }

        return StationOfficeMockData.Snapshot(
            activeVehicles: world.installedCount(at: station.id),
            files: world.employeeFiles.filter { $0.stationId == station.id },
            candidates: [],
            incorporations: incorporations,
            bankRequests: [],
            assets: world.assets.filter { $0.stationId == station.id },
            orders: world.orders.filter { $0.stationId == station.id },
            hiringDurations: [],
            audit: []
        )
    }

    private static func incorporationStage(for stage: LabVehicleStage) -> IncorporationStage {
        switch stage {
        case .purchase: .purchasing
        case .transit: .inTransit
        case .preparation: .preparing
        default: .active
        }
    }

    // MARK: Recruitment

    static func recruitmentSnapshot(world: LabWorld, stations: [Station]) -> RecruitmentMockData.Snapshot {
        let ids = Set(stations.map(\.id))
        return RecruitmentMockData.Snapshot(
            prospects: world.prospects.filter { ids.contains($0.stationId) },
            campaigns: world.campaigns.filter { ids.contains($0.stationId) },
            appointments: world.appointments.filter { ids.contains($0.stationId) }
        )
    }

    // MARK: Station management

    /// The manager's desk in test mode starts empty: the laboratory is what fills a
    /// station, so nothing is invented here.
    static func regionalSnapshot(world: LabWorld, station: Station) -> RegionalMockData.Snapshot {
        _ = world
        _ = station
        return RegionalMockData.Snapshot(scorecards: [], supervisors: [], requests: [])
    }
}
