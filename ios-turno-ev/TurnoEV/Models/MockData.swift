import Foundation

/// Simulated backend. Replace these builders with API calls when the fleet backend lands.
nonisolated enum MockData {
    /// Driver profile the app opens with. In test mode there is no seeded driver: the
    /// profile is whatever the laboratory created, and a blank placeholder while nothing
    /// exists yet.
    static var driver: Driver {
        LabRuntime.isTest ? (LabRuntime.driver ?? blankDriver) : seededDriver
    }

    /// Empty driver used while the test environment has no drivers registered.
    static let blankDriver = Driver(
        id: "drv-none",
        name: "Sin conductor registrado",
        employeeNumber: "—",
        email: "—",
        password: "—",
        photoAsset: "rideshare_driver_portrait",
        stationId: "—",
        station: "Sin estación",
        group: .weekday,
        slot: .morning,
        authorizedVehicleIds: []
    )

    static let seededDriver = Driver(
        id: "drv-1042",
        name: "Carlos Méndez Rivas",
        employeeNumber: "EV-1042",
        email: "launion.contacto2@gmail.com",
        password: "Kymyly14",
        photoAsset: "rideshare_driver_portrait",
        stationId: "est-nte-cdmx",
        station: "Estación Norte · CDMX",
        group: .weekday,
        slot: .morning,
        authorizedVehicleIds: ["veh-014", "veh-027", "veh-055"]
    )

    static let vehiclePhotoAsset = "electric_sedan_charging"

    static var vehicles: [Vehicle] {
        LabRuntime.isTest ? LabRuntime.vehicles : seededVehicles
    }

    static var seededVehicles: [Vehicle] {
        [
            Vehicle(
                id: "veh-014",
                qrCode: "TEV-014",
                internalNumber: "TEV-014",
                model: "BYD Dolphin Mini 2025",
                plates: "NXP-482-C",
                odometerKm: 42180,
                batteryPct: 96,
                stationId: "est-nte-cdmx",
                station: "Estación Norte · CDMX",
                status: .available,
                occupiedBy: nil,
                photoAsset: vehiclePhotoAsset
            ),
            Vehicle(
                id: "veh-027",
                qrCode: "TEV-027",
                internalNumber: "TEV-027",
                model: "Nissan Leaf 2024",
                plates: "PLC-733-B",
                odometerKm: 61540,
                batteryPct: 88,
                stationId: "est-nte-cdmx",
                station: "Estación Norte · CDMX",
                status: .available,
                occupiedBy: nil,
                photoAsset: vehiclePhotoAsset
            ),
            Vehicle(
                id: "veh-031",
                qrCode: "TEV-031",
                internalNumber: "TEV-031",
                model: "BYD Dolphin 2025",
                plates: "MRK-118-A",
                odometerKm: 30210,
                batteryPct: 79,
                stationId: "est-nte-cdmx",
                station: "Estación Norte · CDMX",
                status: .occupied,
                occupiedBy: "drv-2210",
                photoAsset: vehiclePhotoAsset
            ),
            Vehicle(
                id: "veh-042",
                qrCode: "TEV-042",
                internalNumber: "TEV-042",
                model: "JAC E10X 2024",
                plates: "TQD-905-D",
                odometerKm: 25780,
                batteryPct: 62,
                stationId: "est-sur-cdmx",
                station: "Estación Sur · CDMX",
                status: .available,
                occupiedBy: nil,
                photoAsset: vehiclePhotoAsset
            ),
            Vehicle(
                id: "veh-055",
                qrCode: "TEV-055",
                internalNumber: "TEV-055",
                model: "BYD Yuan Plus 2025",
                plates: "VZR-260-E",
                odometerKm: 18940,
                batteryPct: 91,
                stationId: "est-nte-cdmx",
                station: "Estación Norte · CDMX",
                status: .available,
                occupiedBy: nil,
                photoAsset: vehiclePhotoAsset
            ),
            Vehicle(
                id: "veh-063",
                qrCode: "TEV-063",
                internalNumber: "TEV-063",
                model: "BYD Dolphin Mini 2025",
                plates: "WBN-347-F",
                odometerKm: 12360,
                batteryPct: 45,
                stationId: "est-nte-cdmx",
                station: "Estación Norte · CDMX",
                status: .maintenance,
                occupiedBy: nil,
                photoAsset: vehiclePhotoAsset
            ),
        ]
    }

    private static let latePattern = [15, 0, 10, 0, 0, 20, 0, 5, 0, 12, 0, 0, 18, 0]
    private static let earningsFactor = [1.04, 0.92, 1.0, 1.12, 0.88, 0.97, 1.06, 0.91, 1.08, 0.95, 1.01, 0.86, 1.1, 0.99]
    private static let tripsPattern = [15, 12, 14, 16, 11, 14, 15, 13, 14, 12, 14, 10, 16, 14]

    /// Closed shifts covering the whole current month, honoring the driver's shift group.
    static func shiftHistory(driver: Driver, now: Date) -> [ShiftRecord] {
        guard !LabRuntime.isTest else { return [] }
        var records: [ShiftRecord] = []
        var odometer = 42180
        var index = 0
        let calendar = ShiftRules.calendar
        let goals = ShiftRules.goals(for: driver.group)

        for back in stride(from: 45, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            guard ShiftRules.group(for: day) == driver.group else { continue }

            let late = latePattern[index % latePattern.count]
            let trips = tripsPattern[index % tripsPattern.count]
            let earnings = Int((Double(goals.dailyMxn) * earningsFactor[index % earningsFactor.count]).rounded())
            let scheduled = ShiftRules.scheduledStart(slot: driver.slot, on: day)
            let started = scheduled.addingTimeInterval(TimeInterval(late * 60))
            let ended = started.addingTimeInterval(TimeInterval((9 * 60 - min(late, 30)) * 60))
            let kmDriven = 150 + ((index * 17) % 60)
            let startOdometer = odometer
            odometer += kmDriven

            records.append(
                ShiftRecord(
                    id: "shift-h-\(back)",
                    driverId: driver.id,
                    vehicleId: "veh-014",
                    vehicleInternalNumber: "TEV-014",
                    group: driver.group,
                    slot: driver.slot,
                    scheduledStartAt: scheduled,
                    startedAt: started,
                    endedAt: ended,
                    lateMinutes: late,
                    paidBackMinutes: index % 5 == 0 ? min(late, 10) : 0,
                    startOdometerKm: startOdometer,
                    endOdometerKm: startOdometer + kmDriven,
                    startBatteryPct: 92 - (index % 4) * 3,
                    endBatteryPct: 24 + (index % 5) * 4,
                    trips: trips,
                    earningsMxn: earnings
                )
            )
            index += 1
        }

        return records.reversed()
    }

    /// The odometer of the most recent closed shift becomes the expected reading.
    static func syncOdometers(vehicles: [Vehicle], history: [ShiftRecord]) -> [Vehicle] {
        vehicles.map { vehicle in
            guard let last = history.first(where: { $0.vehicleId == vehicle.id }) else { return vehicle }
            var updated = vehicle
            updated.odometerKm = last.endOdometerKm
            return updated
        }
    }

    static func incomeHistory(driver: Driver, history: [ShiftRecord]) -> [IncomeEntry] {
        guard !LabRuntime.isTest else { return [] }
        return history.enumerated().map { index, record in
            IncomeEntry(
                id: "inc-\(record.id)",
                driverId: driver.id,
                shiftId: record.id,
                date: record.endedAt,
                amountMxn: record.earningsMxn,
                trips: record.trips,
                platform: index % 3 == 0 ? .didi : .uber,
                evidence: nil,
                note: record.trips < ShiftRules.tripsGoalPerDay ? "Día con baja demanda" : nil
            )
        }
    }

    static func incidents(driver: Driver, now: Date) -> [Incident] {
        guard !LabRuntime.isTest else { return [] }
        return [
            Incident(
                id: "inci-002",
                driverId: driver.id,
                vehicleId: "veh-014",
                vehicleInternalNumber: "TEV-014",
                kind: .damage,
                createdAt: now.addingTimeInterval(-3 * 86400),
                description: "Rayón en salpicadera trasera derecha al salir del estacionamiento de la estación.",
                photos: [],
                status: .review
            ),
            Incident(
                id: "inci-001",
                driverId: driver.id,
                vehicleId: "veh-027",
                vehicleInternalNumber: "TEV-027",
                kind: .mechanical,
                createdAt: now.addingTimeInterval(-9 * 86400),
                description: "Sensor de proximidad trasero intermitente, la alarma se activa sin obstáculos.",
                photos: [],
                status: .closed
            ),
        ]
    }

    static func notices(now: Date) -> [Notice] {
        guard !LabRuntime.isTest else { return [] }
        func hoursAgo(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        return [
            Notice(
                id: "not-005",
                kind: .reminder,
                title: "Recuerda cargar al 100% antes de entregar",
                body: "La unidad debe quedar conectada al cargador de la bahía asignada al terminar tu turno.",
                createdAt: hoursAgo(1),
                read: false
            ),
            Notice(
                id: "not-004",
                kind: .maintenance,
                title: "Mantenimiento programado · TEV-014",
                body: "Servicio de 40,000 km el viernes a las 15:00 en Estación Norte. Entrega la unidad 30 min antes.",
                createdAt: hoursAgo(6),
                read: false
            ),
            Notice(
                id: "not-003",
                kind: .credit,
                title: "Pago de crédito por vencer",
                body: "Tu abono semanal de $1,200 se aplica el domingo. Saldo restante $46,800.",
                createdAt: hoursAgo(20),
                read: false
            ),
            Notice(
                id: "not-002",
                kind: .station,
                title: "Aviso de estación · Bahía 4 cerrada",
                body: "La bahía 4 estará fuera de servicio por instalación de cargador rápido. Usa bahías 1 a 3.",
                createdAt: hoursAgo(30),
                read: true
            ),
            Notice(
                id: "not-001",
                kind: .reminder,
                title: "Revisión de llantas quincenal",
                body: "Reporta presión y desgaste en el reporte de incidencias si detectas algo fuera de rango.",
                createdAt: hoursAgo(52),
                read: true
            ),
        ]
    }

    /// Supervisor reports drive the cleanliness / vehicle-care bonus.
    static func supervisorReports(now: Date) -> [SupervisorReport] {
        guard !LabRuntime.isTest else { return [] }
        return [
            SupervisorReport(
                id: "sup-001",
                kind: .cleanliness,
                createdAt: now.addingTimeInterval(-41 * 86400),
                vehicleInternalNumber: "TEV-014",
                note: "Interiores con basura al entregar la unidad. Se descontó el bono del mes anterior."
            ),
        ]
    }

    /// Mid-term contract (week 14 of 192) used to show every metric of the credit panel.
    static func credit(now: Date) -> CreditAccount {
        func dayIn(_ days: Double) -> Date { now.addingTimeInterval(days * 86400) }
        let weekly = CreditProgram.weeklyMxn
        let weeksPaid = 14
        return CreditAccount(
            contractId: "CR-10428",
            vehicleTarget: "\(CreditProgram.vehicleModel) · TEV-014",
            startedAt: dayIn(-98),
            totalMxn: CreditProgram.priceMxn,
            paidMxn: weekly * weeksPaid,
            weeklyMxn: weekly,
            weeksPaid: weeksPaid,
            onTimePayments: 13,
            latePayments: 1,
            assignedVehicleOdometerKm: 96_480,
            payments: [
                CreditPayment(id: "cp-15", concept: "Abono semanal 15", dueDate: dayIn(4), amountMxn: weekly, status: .due),
                CreditPayment(id: "cp-14", concept: "Abono semanal 14", dueDate: dayIn(-3), amountMxn: weekly, status: .paid),
                CreditPayment(id: "cp-13", concept: "Abono semanal 13", dueDate: dayIn(-10), amountMxn: weekly, status: .paid),
                CreditPayment(id: "cp-12", concept: "Abono semanal 12", dueDate: dayIn(-17), amountMxn: weekly, status: .paid),
                CreditPayment(id: "cp-11", concept: "Abono semanal 11", dueDate: dayIn(-24), amountMxn: weekly, status: .late),
                CreditPayment(id: "cp-10", concept: "Abono semanal 10", dueDate: dayIn(-31), amountMxn: weekly, status: .paid),
            ]
        )
    }
}
