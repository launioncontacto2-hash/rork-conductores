import Foundation

/// Deterministic station simulator. It expands the shared fleet database into a full
/// station: up to 100 units and 100 drivers per shift, plus the handovers, incidents
/// and readings a supervisor works with. Replace with API calls when the backend lands.
nonisolated enum SupervisionMockData {
    /// Everything the supervision store starts from.
    struct Snapshot: Sendable {
        var vehicles: [StationVehicle]
        var drivers: [StationDriver]
        var tickets: [HandoverTicket]
        var incidents: [StationIncident]
    }

    /// Where the supervised shift is standing right now.
    enum ShiftPhase: Sendable {
        case beforeStart
        case open
        case closed
    }

    private static let firstNames = [
        "Alejandro", "Brenda", "Cristian", "Daniela", "Emiliano", "Fernanda", "Gerardo", "Hilda",
        "Ismael", "Jazmín", "Kevin", "Lucía", "Marcos", "Nadia", "Osvaldo", "Paola",
        "Quetzal", "Rodrigo", "Samantha", "Tadeo", "Ulises", "Verónica", "Wendy", "Ximena",
        "Yahir", "Zoe", "Bruno", "Citlali", "Diego", "Elisa",
    ]

    private static let lastNames = [
        "Hernández", "García", "Martínez", "López", "Sánchez", "Ramírez", "Torres", "Flores",
        "Rivera", "Gómez", "Díaz", "Cruz", "Morales", "Reyes", "Gutiérrez", "Ortiz",
        "Chávez", "Ruiz", "Mendoza", "Aguilar", "Vázquez", "Castillo", "Jiménez", "Romero",
        "Alvarado", "Bautista", "Cabrera", "Delgado", "Escobar", "Fuentes",
    ]

    private static let models = [
        "BYD Dolphin Mini 2025",
        "BYD Dolphin 2025",
        "BYD Yuan Plus 2025",
        "Nissan Leaf 2024",
        "JAC E10X 2024",
        "Chevrolet Bolt 2023",
    ]

    private static let plateLetters = ["NXP", "PLC", "MRK", "TQD", "VZR", "WBN", "KLR", "JHD", "RSA", "BTX"]

    private static let observations = [
        "Interiores limpios, sin objetos olvidados.",
        "Llanta trasera derecha con presión baja, se calibró en bahía.",
        "Pantalla de infoentretenimiento se reinició una vez.",
        "Cargador de la bahía 3 tardó en enganchar.",
        "Unidad entregada con cinturón trasero desabrochado.",
        "Sin observaciones.",
    ]

    private static let incidentDetails: [(IncidentKind, IncidentSeverity, String, IncidentStatus)] = [
        (.damage, .medium, "Golpe en puerta trasera izquierda al maniobrar en estacionamiento comercial.", .open),
        (.mechanical, .high, "Freno de servicio con recorrido largo, se retira de operación para revisión.", .open),
        (.accident, .critical, "Alcance con tercero en Circuito Interior, con parte de tránsito levantado.", .review),
        (.damage, .low, "Rayón superficial en salpicadera delantera derecha.", .closed),
        (.mechanical, .medium, "Sensor de proximidad trasero intermitente, se reprogramó módulo.", .closed),
    ]

    // MARK: - Snapshot

    static func snapshot(
        station: Station,
        slot: ShiftSlot,
        supervisorName: String,
        baseVehicles: [Vehicle],
        liveDriver: Driver?,
        now: Date
    ) -> Snapshot {
        if LabRuntime.isTest {
            return LabSeed.supervisionSnapshot(world: LabRuntime.world, station: station, slot: slot, now: now)
        }
        var random = SeededGenerator(seed: seed(station: station, slot: slot, now: now))
        let phase = phase(slot: slot, now: now)
        let scheduled = ShiftRules.scheduledStart(slot: slot, on: now)
        let group = ShiftRules.group(for: now)

        var vehicles = fleet(station: station, baseVehicles: baseVehicles, now: now, random: &random)
        var drivers: [StationDriver] = []
        var tickets: [HandoverTicket] = []

        // One driver per installed unit per block: the roster follows the fleet, never a
        // fixed number.
        let rosterSize = max(0, station.vehicleCapacity - (liveDriver == nil ? 0 : 1))
        let counts = distribution(phase: phase, roster: rosterSize)
        var states: [StationDriverState] = []
        states.append(contentsOf: Array(repeating: .operating, count: counts.operating))
        states.append(contentsOf: Array(repeating: .late, count: counts.late))
        states.append(contentsOf: Array(repeating: .awaitingHandover, count: counts.awaiting))
        states.append(contentsOf: Array(repeating: .finished, count: counts.finished))
        states.append(contentsOf: Array(repeating: .absent, count: counts.absent))

        // Units that can be handed over today, in bay order.
        var assignable = vehicles.indices.filter {
            vehicles[$0].state != .maintenance && vehicles[$0].state != .outOfService
        }

        for index in 0..<rosterSize {
            let state = index < states.count ? states[index] : .operating
            let first = firstNames[(index * 7 + 3) % firstNames.count]
            let middle = lastNames[(index * 11 + 5) % lastNames.count]
            let last = lastNames[(index * 5 + 17) % lastNames.count]
            let name = "\(first) \(middle) \(last)"
            let driverId = "drv-s\(String(format: "%03d", 200 + index))"
            let late = state == .late ? random.int(11...52) : 0
            let checkIn: Date? = {
                switch state {
                case .absent: return nil
                case .late: return scheduled.addingTimeInterval(TimeInterval(late * 60))
                case .awaitingHandover: return now.addingTimeInterval(TimeInterval(-random.int(2...18) * 60))
                default: return scheduled.addingTimeInterval(TimeInterval(-random.int(0...9) * 60))
                }
            }()

            var vehicleId: String?
            var vehicleNumber: String?
            let needsUnit = state == .operating || state == .late || state == .awaitingHandover || state == .finished
            if needsUnit, let slotIndex = assignable.first {
                assignable.removeFirst()
                vehicleId = vehicles[slotIndex].id
                vehicleNumber = vehicles[slotIndex].internalNumber
                if state == .operating || state == .late {
                    vehicles[slotIndex].state = .operating
                    vehicles[slotIndex].assignedDriverId = driverId
                    vehicles[slotIndex].assignedDriverName = name
                    vehicles[slotIndex].qrScanned = true
                    vehicles[slotIndex].batteryPct = random.int(28...88)
                } else {
                    vehicles[slotIndex].state = .available
                    vehicles[slotIndex].assignedDriverId = nil
                    vehicles[slotIndex].assignedDriverName = nil
                    vehicles[slotIndex].qrScanned = state == .awaitingHandover ? random.chance(0.78) : true
                }
            }

            let goals = ShiftRules.goals(for: group)
            let progress = SupervisionRules.shiftProgress(slot: slot, now: now)
            let earnings: Int = {
                switch state {
                case .absent: return 0
                case .awaitingHandover: return 0
                case .finished: return Int(Double(goals.dailyMxn) * random.double(0.72...1.18))
                default: return Int(Double(goals.dailyMxn) * progress * random.double(0.62...1.24))
                }
            }()
            let trips = earnings > 0 ? max(1, Int(Double(earnings) / 108.0)) : 0

            drivers.append(
                StationDriver(
                    id: driverId,
                    name: name,
                    employeeNumber: "EV-\(1100 + index * 3)",
                    photoAsset: nil,
                    stationId: station.id,
                    slot: slot,
                    group: group,
                    phone: "55 \(random.int(1000...9999)) \(random.int(1000...9999))",
                    vehicleId: vehicleId,
                    vehicleNumber: vehicleNumber,
                    scheduledStartAt: scheduled,
                    checkInAt: checkIn,
                    lateMinutes: late,
                    state: state,
                    earningsMxn: earnings,
                    trips: trips,
                    creditState: creditState(index: index, random: &random),
                    openIncidents: 0,
                    platformRating: 4.5 + random.double(0...0.49),
                    isLiveSession: false
                )
            )

            // Pending handovers: units waiting to leave and units coming back.
            if state == .awaitingHandover, let vehicleId, let vehicleNumber,
               let vehicle = vehicles.first(where: { $0.id == vehicleId }) {
                tickets.append(
                    HandoverTicket(
                        id: "hnd-d-\(driverId)",
                        stationId: station.id,
                        kind: .delivery,
                        driverId: driverId,
                        driverName: name,
                        vehicleId: vehicleId,
                        vehicleNumber: vehicleNumber,
                        createdAt: checkIn ?? now,
                        scheduledStartAt: scheduled,
                        startOdometerKm: vehicle.odometerKm + (random.chance(0.2) ? random.int(3...45) : 0),
                        endOdometerKm: nil,
                        expectedOdometerKm: vehicle.odometerKm,
                        batteryPct: vehicle.batteryPct,
                        qrCodeRead: vehicle.qrScanned ? vehicle.internalNumber : nil,
                        photosCaptured: random.int(4...6),
                        lateMinutes: 0,
                        observations: random.pick(observations),
                        checks: [:],
                        status: .pending,
                        resolvedAt: nil,
                        rejectionReason: nil,
                        odometerPhotoAsset: "electric_hatchback_charging",
                        isLiveSession: false
                    )
                )
            }

            if state == .finished, let vehicleId, let vehicleNumber,
               let vehicle = vehicles.first(where: { $0.id == vehicleId }) {
                let driven = random.int(120...220)
                tickets.append(
                    HandoverTicket(
                        id: "hnd-r-\(driverId)",
                        stationId: station.id,
                        kind: .reception,
                        driverId: driverId,
                        driverName: name,
                        vehicleId: vehicleId,
                        vehicleNumber: vehicleNumber,
                        createdAt: now.addingTimeInterval(TimeInterval(-random.int(5...50) * 60)),
                        scheduledStartAt: scheduled,
                        startOdometerKm: vehicle.odometerKm,
                        endOdometerKm: vehicle.odometerKm + driven + (random.chance(0.25) ? random.int(6...60) : 0),
                        expectedOdometerKm: vehicle.odometerKm + driven,
                        batteryPct: random.int(18...42),
                        qrCodeRead: vehicle.internalNumber,
                        photosCaptured: 6,
                        lateMinutes: 0,
                        observations: random.pick(observations),
                        checks: [:],
                        status: .pending,
                        resolvedAt: nil,
                        rejectionReason: nil,
                        odometerPhotoAsset: "electric_sedan_charging",
                        isLiveSession: false
                    )
                )
            }
        }

        var incidents = self.incidents(station: station, drivers: drivers, supervisorName: supervisorName, now: now)

        // Incident counters feed the "con incidencias" filter.
        for index in drivers.indices {
            let open = incidents.filter { $0.driverId == drivers[index].id && $0.isOpen }.count
            drivers[index].openIncidents = open
        }

        // Units tied to an open incident leave operation.
        for incident in incidents where incident.isOpen {
            guard let index = vehicles.firstIndex(where: { $0.internalNumber == incident.vehicleNumber }) else { continue }
            if incident.severity == .critical || incident.severity == .high {
                vehicles[index].state = .outOfService
            }
        }
        incidents.sort { $0.createdAt > $1.createdAt }

        return Snapshot(vehicles: vehicles, drivers: drivers, tickets: tickets, incidents: incidents)
    }

    // MARK: - Phase

    static func phase(slot: ShiftSlot, now: Date) -> ShiftPhase {
        let bounds = ShiftRules.window(for: slot)
        let current = ShiftRules.minutesOfDay(now)
        if current < bounds.start { return .beforeStart }
        if current > bounds.end { return .closed }
        return .open
    }

    /// Shape of the shift as percentages of the roster, so any station size works.
    private static func distribution(
        phase: ShiftPhase,
        roster: Int
    ) -> (operating: Int, late: Int, awaiting: Int, finished: Int, absent: Int) {
        let mix: (Double, Double, Double, Double, Double) = switch phase {
        case .beforeStart: (0, 0, 0.62, 0.20, 0.14)
        case .open: (0.76, 0.09, 0.06, 0.04, 0.05)
        case .closed: (0.07, 0.03, 0.02, 0.83, 0.05)
        }
        func share(_ ratio: Double) -> Int { Int((Double(roster) * ratio).rounded()) }
        return (share(mix.0), share(mix.1), share(mix.2), share(mix.3), share(mix.4))
    }

    private static func creditState(index: Int, random: inout SeededGenerator) -> DriverCreditState {
        switch index % 7 {
        case 0, 3: .current
        case 1: random.chance(0.4) ? .behind : .current
        case 5: .delivered
        default: .none
        }
    }

    // MARK: - Fleet

    private static func fleet(
        station: Station,
        baseVehicles: [Vehicle],
        now: Date,
        random: inout SeededGenerator
    ) -> [StationVehicle] {
        var result: [StationVehicle] = []

        // Units already living in the shared database.
        for (index, vehicle) in baseVehicles.enumerated() where vehicle.stationId == station.id {
            result.append(
                StationVehicle(
                    id: vehicle.id,
                    internalNumber: vehicle.internalNumber,
                    model: vehicle.model,
                    plates: vehicle.plates,
                    stationId: station.id,
                    bay: index + 1,
                    state: vehicle.status == .maintenance ? .maintenance : (vehicle.status == .occupied ? .operating : .available),
                    batteryPct: vehicle.batteryPct,
                    odometerKm: vehicle.odometerKm,
                    assignedDriverId: vehicle.occupiedBy,
                    assignedDriverName: nil,
                    maintenance: maintenanceState(odometer: vehicle.odometerKm, isWorkshop: vehicle.status == .maintenance),
                    nextServiceKm: nextService(for: vehicle.odometerKm),
                    lastServiceAt: now.addingTimeInterval(TimeInterval(-Double(random.int(8...60)) * 86400)),
                    qrScanned: vehicle.status == .occupied,
                    photoAsset: vehicle.photoAsset
                )
            )
        }

        let missing = max(0, station.vehicleCapacity - result.count)
        for index in 0..<missing {
            let number = 101 + index
            let odometer = 8_000 + ((index * 2_137) % 104_000)
            let inWorkshop = index % 17 == 3
            let isOut = index % 29 == 7
            result.append(
                StationVehicle(
                    id: "veh-\(station.code.lowercased())-\(number)",
                    internalNumber: "TEV-\(number)",
                    model: models[index % models.count],
                    plates: "\(plateLetters[index % plateLetters.count])-\(String(format: "%03d", (index * 37) % 999))-\(Character(UnicodeScalar(65 + index % 26)!))",
                    stationId: station.id,
                    bay: result.count + 1,
                    state: inWorkshop ? .maintenance : (isOut ? .outOfService : .available),
                    batteryPct: inWorkshop ? random.int(20...60) : random.int(62...100),
                    odometerKm: odometer,
                    assignedDriverId: nil,
                    assignedDriverName: nil,
                    maintenance: maintenanceState(odometer: odometer, isWorkshop: inWorkshop),
                    nextServiceKm: nextService(for: odometer),
                    lastServiceAt: now.addingTimeInterval(TimeInterval(-Double(random.int(4...80)) * 86400)),
                    qrScanned: false,
                    photoAsset: index % 2 == 0 ? "electric_sedan_charging" : "electric_hatchback_charging"
                )
            )
        }

        return result
    }

    /// Services are programmed every 10,000 km.
    private static func nextService(for odometer: Int) -> Int {
        ((odometer / 10_000) + 1) * 10_000
    }

    private static func maintenanceState(odometer: Int, isWorkshop: Bool) -> MaintenanceState {
        if isWorkshop { return .inWorkshop }
        let toService = nextService(for: odometer) - odometer
        if toService < 250 { return .overdue }
        if toService < 1_200 { return .dueSoon }
        return .ok
    }

    // MARK: - Incidents

    private static func incidents(
        station: Station,
        drivers: [StationDriver],
        supervisorName: String,
        now: Date
    ) -> [StationIncident] {
        incidentDetails.enumerated().map { index, item in
            let driver = drivers.indices.contains(index * 7) ? drivers[index * 7] : drivers.first
            return StationIncident(
                id: "sinc-\(String(format: "%03d", index + 1))",
                stationId: station.id,
                driverId: driver?.id,
                driverName: driver?.shortName ?? "Sin conductor",
                vehicleNumber: driver?.vehicleNumber ?? "TEV-1\(index)2",
                kind: item.0,
                severity: item.1,
                createdAt: now.addingTimeInterval(TimeInterval(-Double(index * 9 + 2) * 3_600)),
                detail: item.2,
                photos: [],
                status: item.3,
                reportedBy: index % 2 == 0 ? "Conductor" : supervisorName
            )
        }
    }

    // MARK: - Seed

    private static func seed(station: Station, slot: ShiftSlot, now: Date) -> UInt64 {
        let day = ShiftRules.calendar.ordinality(of: .day, in: .era, for: now) ?? 1
        var value: UInt64 = UInt64(day) * 2_654_435_761
        for byte in station.id.utf8 { value = value &* 31 &+ UInt64(byte) }
        value = value &* 31 &+ (slot == .morning ? 7 : 13)
        return value
    }
}

/// Small xorshift generator so every relaunch rebuilds the same station.
nonisolated struct SeededGenerator: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    mutating func double(_ range: ClosedRange<Double> = 0...1) -> Double {
        let unit = Double(next() % 10_000) / 10_000
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func chance(_ probability: Double) -> Bool {
        double() < probability
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[int(0...(items.count - 1))]
    }
}
