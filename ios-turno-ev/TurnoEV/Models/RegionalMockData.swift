import Foundation

/// Deterministic station simulator for the manager's desk. A manager runs one station,
/// so this builds that station's scorecard, the supervisors that hold each shift and the
/// decisions waiting to be signed. Replace with API calls when the backend lands; the
/// shapes already match.
nonisolated enum RegionalMockData {
    struct Snapshot: Sendable {
        var scorecards: [StationScorecard]
        var supervisors: [SupervisorScorecard]
        var requests: [RegionalRequest]
    }

    private static let candidateNames = [
        "Ariadna Solís Beltrán", "Néstor Cabrera Luna", "Yolanda Prieto Sáenz", "Efraín Montiel Ávila",
        "Karime Duarte Lozano", "Bruno Estrada Vidal", "Perla Anguiano Ruiz", "Gonzalo Iriarte Peña",
    ]

    private static let driverNames = [
        "Marisol Aguirre Téllez", "Joaquín Serrano Ibarra", "Tania Bermúdez Rojo", "Ulises Carmona Nava",
        "Rebeca Villalobos Cano", "Damián Escutia Prado", "Norma Zepeda Rincón", "Aldo Trejo Meneses",
    ]

    private static let supervisorNames = [
        "Rocío Estrada Palma", "Héctor Quintanar Ríos", "Silvia Márquez Fonseca", "Omar Bañuelos Tapia",
    ]

    private static let maintenanceNames = [
        "Faustino Alcalá Vega", "Norberto Sandoval Ríos", "Ruth Villagómez Paz", "Isaac Delgadillo Mora",
    ]

    // MARK: - Snapshot

    static func snapshot(
        station: Station,
        manager: StaffAccount,
        isLive: Bool,
        now: Date
    ) -> Snapshot {
        if LabRuntime.isTest {
            return LabSeed.regionalSnapshot(world: LabRuntime.world, station: station)
        }
        var random = SeededGenerator(seed: seed(station: station, now: now))
        let slot = RegionalRules.observedSlot(now: now)

        let card = scorecard(
            station: station,
            slot: slot,
            index: 0,
            isLive: isLive,
            now: now,
            random: &random
        )
        let supervisors = staff(station: station, index: 0, card: card, now: now, random: &random)
        let requests = self.requests(
            station: station,
            supervisors: supervisors,
            manager: manager,
            now: now,
            random: &random
        )

        return Snapshot(scorecards: [card], supervisors: supervisors, requests: requests)
    }

    // MARK: - Station

    private static func scorecard(
        station: Station,
        slot: ShiftSlot,
        index: Int,
        isLive: Bool,
        now: Date,
        random: inout SeededGenerator
    ) -> StationScorecard {
        let progress = SupervisionRules.shiftProgress(slot: slot, now: now)
        let group = ShiftRules.group(for: now)
        let goals = ShiftRules.goals(for: group)

        let fleetSize = station.vehicleCapacity
        let inMaintenance = random.int(1...max(2, fleetSize / 8))
        let outOfService = random.int(0...max(1, fleetSize / 12))
        let usable = fleetSize - inMaintenance - outOfService

        // One driver per unit per block: the shift roster follows the installed fleet.
        let rosterSize = fleetSize
        let absent = random.int(0...max(1, rosterSize / 10))
        let late = random.int(0...max(1, rosterSize / 7))
        let present = rosterSize - absent
        let operating = min(usable, max(0, Int(Double(present) * (progress > 0 ? 0.9 : 0.15)) - random.int(0...6)))

        // The goal is fixed: authorized units × the driver goal of the day. It does not
        // move when someone does not show up — that is precisely what it measures.
        let shiftGoal = ShiftRules.stationShiftGoalMxn(capacity: station.vehicleCapacity, group: group)
        let performance = random.double(0.74...1.12)
        let earnings = Int(Double(shiftGoal) * progress * performance)

        let weekGoal = ShiftRules.stationWeekGoalMxn(capacity: station.vehicleCapacity)
        let weekEarnings = weekSeries(capacity: station.vehicleCapacity, now: now, random: &random)

        return StationScorecard(
            id: station.id,
            code: station.code,
            name: station.name,
            city: station.city,
            vehicleCapacity: station.vehicleCapacity,
            fleetSize: fleetSize,
            operatingVehicles: operating,
            availableVehicles: max(0, usable - operating),
            inMaintenance: inMaintenance,
            outOfService: outOfService,
            slot: slot,
            rosterSize: rosterSize,
            presentDrivers: present,
            lateDrivers: late,
            absentDrivers: absent,
            payrollSize: max(0, station.requiredDrivers - random.int(0...max(1, fleetSize / 5))),
            earningsMxn: earnings,
            goalMxn: shiftGoal,
            tripsToday: earnings > 0 ? earnings / 108 : 0,
            weekEarnings: weekEarnings,
            weekGoalMxn: weekGoal,
            goalGroup: group,
            punctualityPct: random.double(82...97),
            carePct: random.double(78...96),
            ratingAvg: 4.6 + random.double(0...0.35),
            pendingHandovers: random.int(0...max(2, rosterSize / 4)),
            openIncidents: random.int(1...max(2, fleetSize / 5)),
            criticalIncidents: index == 0 ? random.int(0...1) : random.int(0...2),
            creditCurrent: random.int(4...max(6, fleetSize / 2)),
            creditBehind: random.int(0...max(1, fleetSize / 10)),
            creditDelivered: random.int(0...max(1, fleetSize / 8)),
            bonusEligible: random.int(fleetSize...max(fleetSize + 1, station.requiredDrivers - 10)),
            bonusAtRisk: random.int(2...max(3, fleetSize / 2)),
            supervisorIds: [supervisorId(station: station, slot: .morning), supervisorId(station: station, slot: .evening)],
            maintenanceIds: [maintenanceId(station: station)],
            isLive: isLive
        )
    }

    /// Monday to Sunday series against the fixed goal of each day; days after today stay
    /// empty so the trend reads honestly.
    private static func weekSeries(capacity: Int, now: Date, random: inout SeededGenerator) -> [Int] {
        let weekStart = ShiftRules.weekStart(for: now)
        return (0..<7).map { offset in
            guard let day = ShiftRules.calendar.date(byAdding: .day, value: offset, to: weekStart) else { return 0 }
            if day > now && !ShiftRules.isSameDay(day, now) { return 0 }
            let base = Double(ShiftRules.stationDayGoalMxn(capacity: capacity, on: day))
            if ShiftRules.isSameDay(day, now) {
                return Int(base * SupervisionRules.shiftProgress(slot: .morning, now: now) * random.double(0.8...1.1))
            }
            return Int(base * random.double(0.82...1.06))
        }
    }

    // MARK: - Staff

    private static func supervisorId(station: Station, slot: ShiftSlot) -> String {
        if let account = StaffDirectory.accounts.first(where: {
            $0.role == .supervisor && $0.stationId == station.id && $0.slot == slot
        }) {
            return account.id
        }
        return "sup-\(station.code.lowercased())-\(slot.rawValue)"
    }

    private static func maintenanceId(station: Station) -> String {
        if let account = StaffDirectory.accounts.first(where: { $0.role == .maintenance && $0.stationId == station.id }) {
            return account.id
        }
        return "mto-\(station.code.lowercased())"
    }

    private static func staff(
        station: Station,
        index: Int,
        card: StationScorecard,
        now: Date,
        random: inout SeededGenerator
    ) -> [SupervisorScorecard] {
        ShiftSlot.allCases.enumerated().map { slotIndex, slot in
            let id = supervisorId(station: station, slot: slot)
            let account = StaffDirectory.account(id: id)
            let name = account?.name ?? supervisorNames[(index * 2 + slotIndex) % supervisorNames.count]
            let pending = slot == card.slot ? card.pendingHandovers : random.int(0...3)
            return SupervisorScorecard(
                id: id,
                name: name,
                employeeNumber: account?.employeeNumber ?? "EV-SUP-\(310 + index * 4 + slotIndex)",
                stationId: station.id,
                stationCode: station.code,
                slot: slot,
                driversManaged: station.vehicleCapacity,
                approvalsToday: slot == card.slot ? random.int(station.vehicleCapacity / 2...station.vehicleCapacity) : random.int(0...6),
                pendingHandovers: pending,
                avgResponseMinutes: random.int(3...17),
                punctualityPct: random.double(84...98),
                incidentsRaised: random.int(0...5),
                isLive: card.isLive && slot == card.slot
            )
        }
    }

    /// Maintenance technicians of a station, one per shift.
    static func maintenanceStaff(station: Station, index: Int) -> [(id: String, name: String, slot: ShiftSlot)] {
        ShiftSlot.allCases.enumerated().map { slotIndex, slot in
            let base = maintenanceId(station: station)
            let account = StaffDirectory.account(id: base)
            if slot == .morning, let account {
                return (account.id, account.name, slot)
            }
            return (
                "\(base)-\(slot.rawValue)",
                maintenanceNames[(index * 2 + slotIndex) % maintenanceNames.count],
                slot
            )
        }
    }

    // MARK: - Requests

    private static func requests(
        station: Station,
        supervisors: [SupervisorScorecard],
        manager: StaffAccount,
        now: Date,
        random: inout SeededGenerator
    ) -> [RegionalRequest] {
        var result: [RegionalRequest] = []
        let index = 0

        do {
            let stationSupervisors = supervisors.filter { $0.stationId == station.id }

            // Plazas above the authorized plantilla, asked for by the recruitment desk.
            // Ordinary hires never reach the manager: recruitment signs them itself.
            let recruiterName = StaffDirectory.recruiter(ofStation: station.id)?.name
                ?? "Reclutamiento \(station.code)"
            for offset in 0..<3 {
                let candidate = candidateNames[(index * 3 + offset) % candidateNames.count]
                result.append(
                    RegionalRequest(
                        id: "req-hir-\(station.code.lowercased())-\(offset)",
                        kind: .hiring,
                        stationId: station.id,
                        stationCode: station.code,
                        subject: candidate,
                        subjectDetail: "Plaza por encima de la plantilla autorizada",
                        amountMxn: nil,
                        detail: "Candidato con \(random.int(2...9)) años de experiencia, ya entrevistado y documentado por reclutamiento. La plaza excede unidades × 4, por eso pasa por ti antes de firmarse.",
                        createdAt: now.addingTimeInterval(TimeInterval(-random.int(3...58) * 3_600)),
                        requestedBy: recruiterName,
                        requestedByRole: .recruiter,
                        priority: offset == 0 ? .medium : .low,
                        checks: [:],
                        status: .pending,
                        resolvedAt: nil,
                        decisionNote: nil,
                        photoAsset: nil,
                        isLiveSession: false
                    )
                )
            }

            // Bonuses do not appear here on purpose: the goal engine resolves them
            // automatically and no manager signs them one by one.

            // Unit retirements coming from the workshop.
            let retiredKm = random.int(110_000...119_400)
            result.append(
                RegionalRequest(
                    id: "req-ret-\(station.code.lowercased())",
                    kind: .retirement,
                    stationId: station.id,
                    stationCode: station.code,
                    subject: "TEV-\(random.int(101...199))",
                    subjectDetail: "\(Fmt.km(retiredKm)) · BYD Dolphin Mini",
                    amountMxn: nil,
                    detail: "La unidad alcanzó el kilometraje de salida de flotilla. Taller propone retirarla y liberarla al programa de crédito.",
                    createdAt: now.addingTimeInterval(TimeInterval(-random.int(6...70) * 3_600)),
                    requestedBy: maintenanceStaff(station: station, index: index)[0].name,
                    requestedByRole: .maintenance,
                    priority: .medium,
                    checks: [:],
                    status: .pending,
                    resolvedAt: nil,
                    decisionNote: nil,
                    photoAsset: index % 2 == 0 ? "electric_sedan_charging" : "electric_hatchback_charging",
                    isLiveSession: false
                )
            )
        }

        // Already signed decisions, so the log is not empty on first open.
        for offset in 0..<3 {
            let kind: RegionalRequestKind = [.hiring, .credit, .retirement][offset % 3]
            result.append(
                RegionalRequest(
                    id: "req-log-\(offset)",
                    kind: kind,
                    stationId: station.id,
                    stationCode: station.code,
                    subject: kind == .retirement ? "TEV-\(random.int(101...199))" : driverNames[(offset * 3) % driverNames.count],
                    subjectDetail: kind == .retirement ? "Baja por kilometraje" : "EV-\(1400 + offset * 11)",
                    amountMxn: kind == .credit ? 1_500 : nil,
                    detail: "Resuelta en el bloque anterior de gerencia.",
                    createdAt: now.addingTimeInterval(TimeInterval(-Double(offset + 1) * 26 * 3_600)),
                    requestedBy: supervisors[offset % max(1, supervisors.count)].name,
                    requestedByRole: offset == 2 ? .maintenance : .supervisor,
                    priority: .low,
                    checks: Dictionary(uniqueKeysWithValues: kind.checks.map { ($0.id, true) }),
                    status: offset == 1 ? .rejected : .authorized,
                    resolvedAt: now.addingTimeInterval(TimeInterval(-Double(offset + 1) * 24 * 3_600)),
                    decisionNote: offset == 1
                        ? "Falta comprobante de vigencia de licencia; se regresa al supervisor."
                        : "Autorizada por la gerencia de la estación.",
                    photoAsset: nil,
                    isLiveSession: false
                )
            )
        }

        return result.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Seed

    private static func seed(station: Station, now: Date) -> UInt64 {
        let day = ShiftRules.calendar.ordinality(of: .day, in: .era, for: now) ?? 1
        var value: UInt64 = UInt64(day) * 6_364_136_223
        for byte in station.id.utf8 { value = value &* 31 &+ UInt64(byte) }
        return value
    }
}
