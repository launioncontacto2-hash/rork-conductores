package com.rork.turnoevandroid.domain

import com.rork.turnoevandroid.util.plusDays

/** Simulated backend. Replace these builders with API calls when the fleet backend lands. */
object MockData {
    val driver = Driver(
        id = "drv-1042",
        name = "Carlos Méndez Rivas",
        employeeNumber = "EV-1042",
        email = "launion.contacto2@gmail.com",
        password = "Kymyly14",
        photoAsset = "driver_portrait",
        stationId = "est-nte-cdmx",
        station = "Estación Norte · CDMX",
        group = ShiftGroup.WEEKDAY,
        slot = ShiftSlot.MORNING,
        authorizedVehicleIds = listOf("veh-014", "veh-027", "veh-055"),
    )

    private const val VEHICLE_PHOTO_ASSET = "vehicle_photo"

    val vehicles: List<Vehicle>
        get() = listOf(
            Vehicle(
                id = "veh-014",
                qrCode = "TEV-014",
                internalNumber = "TEV-014",
                model = "BYD Dolphin Mini 2025",
                plates = "NXP-482-C",
                odometerKm = 42_180,
                batteryPct = 96,
                stationId = "est-nte-cdmx",
                station = "Estación Norte · CDMX",
                status = VehicleStatus.AVAILABLE,
                photoAsset = VEHICLE_PHOTO_ASSET,
            ),
            Vehicle(
                id = "veh-027",
                qrCode = "TEV-027",
                internalNumber = "TEV-027",
                model = "Nissan Leaf 2024",
                plates = "PLC-733-B",
                odometerKm = 61_540,
                batteryPct = 88,
                stationId = "est-nte-cdmx",
                station = "Estación Norte · CDMX",
                status = VehicleStatus.AVAILABLE,
                photoAsset = VEHICLE_PHOTO_ASSET,
            ),
            Vehicle(
                id = "veh-031",
                qrCode = "TEV-031",
                internalNumber = "TEV-031",
                model = "BYD Dolphin 2025",
                plates = "MRK-118-A",
                odometerKm = 30_210,
                batteryPct = 79,
                stationId = "est-nte-cdmx",
                station = "Estación Norte · CDMX",
                status = VehicleStatus.OCCUPIED,
                occupiedBy = "drv-2210",
                photoAsset = VEHICLE_PHOTO_ASSET,
            ),
            Vehicle(
                id = "veh-042",
                qrCode = "TEV-042",
                internalNumber = "TEV-042",
                model = "JAC E10X 2024",
                plates = "TQD-905-D",
                odometerKm = 25_780,
                batteryPct = 62,
                stationId = "est-sur-cdmx",
                station = "Estación Sur · CDMX",
                status = VehicleStatus.AVAILABLE,
                photoAsset = VEHICLE_PHOTO_ASSET,
            ),
            Vehicle(
                id = "veh-055",
                qrCode = "TEV-055",
                internalNumber = "TEV-055",
                model = "BYD Yuan Plus 2025",
                plates = "VZR-260-E",
                odometerKm = 18_940,
                batteryPct = 91,
                stationId = "est-nte-cdmx",
                station = "Estación Norte · CDMX",
                status = VehicleStatus.AVAILABLE,
                photoAsset = VEHICLE_PHOTO_ASSET,
            ),
            Vehicle(
                id = "veh-063",
                qrCode = "TEV-063",
                internalNumber = "TEV-063",
                model = "BYD Dolphin Mini 2025",
                plates = "WBN-347-F",
                odometerKm = 12_360,
                batteryPct = 45,
                stationId = "est-nte-cdmx",
                station = "Estación Norte · CDMX",
                status = VehicleStatus.MAINTENANCE,
                photoAsset = VEHICLE_PHOTO_ASSET,
            ),
        )

    private val latePattern = listOf(15, 0, 10, 0, 0, 20, 0, 5, 0, 12, 0, 0, 18, 0)
    private val earningsFactor =
        listOf(1.04, 0.92, 1.0, 1.12, 0.88, 0.97, 1.06, 0.91, 1.08, 0.95, 1.01, 0.86, 1.1, 0.99)
    private val tripsPattern = listOf(15, 12, 14, 16, 11, 14, 15, 13, 14, 12, 14, 10, 16, 14)

    /** Closed shifts covering the last 45 days, honoring the driver's shift group. */
    fun shiftHistory(driver: Driver, now: Long): List<ShiftRecord> {
        val records = mutableListOf<ShiftRecord>()
        var odometer = 42_180
        var index = 0
        val goals = ShiftRules.goals(driver.group)

        for (back in 45 downTo 1) {
            val day = now.plusDays(-back)
            if (ShiftRules.group(day) != driver.group) continue

            val late = latePattern[index % latePattern.size]
            val trips = tripsPattern[index % tripsPattern.size]
            val earnings =
                Math.round(goals.dailyMxn * earningsFactor[index % earningsFactor.size]).toInt()
            val scheduled = ShiftRules.scheduledStart(driver.slot, day)
            val started = scheduled + late * 60_000L
            val ended = started + (9 * 60 - minOf(late, 30)) * 60_000L
            val kmDriven = 150 + ((index * 17) % 60)
            val startOdometer = odometer
            odometer += kmDriven

            records += ShiftRecord(
                id = "shift-h-$back",
                driverId = driver.id,
                vehicleId = "veh-014",
                vehicleInternalNumber = "TEV-014",
                group = driver.group,
                slot = driver.slot,
                scheduledStartAt = scheduled,
                startedAt = started,
                endedAt = ended,
                lateMinutes = late,
                paidBackMinutes = if (index % 5 == 0) minOf(late, 10) else 0,
                startOdometerKm = startOdometer,
                endOdometerKm = startOdometer + kmDriven,
                startBatteryPct = 92 - (index % 4) * 3,
                endBatteryPct = 24 + (index % 5) * 4,
                trips = trips,
                earningsMxn = earnings,
            )
            index += 1
        }

        return records.reversed()
    }

    /** The odometer of the most recent closed shift becomes the expected reading. */
    fun syncOdometers(vehicles: List<Vehicle>, history: List<ShiftRecord>): List<Vehicle> =
        vehicles.map { vehicle ->
            val last = history.firstOrNull { it.vehicleId == vehicle.id } ?: return@map vehicle
            vehicle.copy(odometerKm = last.endOdometerKm)
        }

    fun incomeHistory(driver: Driver, history: List<ShiftRecord>): List<IncomeEntry> =
        history.mapIndexed { index, record ->
            IncomeEntry(
                id = "inc-${record.id}",
                driverId = driver.id,
                shiftId = record.id,
                date = record.endedAt,
                amountMxn = record.earningsMxn,
                trips = record.trips,
                platform = if (index % 3 == 0) IncomePlatform.DIDI else IncomePlatform.UBER,
                note = if (record.trips < ShiftRules.TRIPS_GOAL_PER_DAY) "Día con baja demanda" else null,
            )
        }

    fun incidents(driver: Driver, now: Long): List<Incident> = listOf(
        Incident(
            id = "inci-002",
            driverId = driver.id,
            vehicleId = "veh-014",
            vehicleInternalNumber = "TEV-014",
            kind = IncidentKind.DAMAGE,
            createdAt = now.plusDays(-3),
            description = "Rayón en salpicadera trasera derecha al salir del estacionamiento de la estación.",
            status = IncidentStatus.REVIEW,
        ),
        Incident(
            id = "inci-001",
            driverId = driver.id,
            vehicleId = "veh-027",
            vehicleInternalNumber = "TEV-027",
            kind = IncidentKind.MECHANICAL,
            createdAt = now.plusDays(-9),
            description = "Sensor de proximidad trasero intermitente, la alarma se activa sin obstáculos.",
            status = IncidentStatus.CLOSED,
        ),
    )

    fun notices(now: Long): List<Notice> {
        fun hoursAgo(hours: Double): Long = now - (hours * 3_600_000L).toLong()
        return listOf(
            Notice(
                id = "not-005",
                kind = NoticeKind.REMINDER,
                title = "Recuerda cargar al 100% antes de entregar",
                body = "La unidad debe quedar conectada al cargador de la bahía asignada al terminar tu turno.",
                createdAt = hoursAgo(1.0),
            ),
            Notice(
                id = "not-004",
                kind = NoticeKind.MAINTENANCE,
                title = "Mantenimiento programado · TEV-014",
                body = "Servicio de 40,000 km el viernes a las 15:00 en Estación Norte. Entrega la unidad 30 min antes.",
                createdAt = hoursAgo(6.0),
            ),
            Notice(
                id = "not-003",
                kind = NoticeKind.CREDIT,
                title = "Pago de crédito por vencer",
                body = "Tu abono semanal de $2,031 se aplica el domingo vía nómina.",
                createdAt = hoursAgo(20.0),
            ),
            Notice(
                id = "not-002",
                kind = NoticeKind.STATION,
                title = "Aviso de estación · Bahía 4 cerrada",
                body = "La bahía 4 estará fuera de servicio por instalación de cargador rápido. Usa bahías 1 a 3.",
                createdAt = hoursAgo(30.0),
                read = true,
            ),
            Notice(
                id = "not-001",
                kind = NoticeKind.REMINDER,
                title = "Revisión de llantas quincenal",
                body = "Reporta presión y desgaste en el reporte de incidencias si detectas algo fuera de rango.",
                createdAt = hoursAgo(52.0),
                read = true,
            ),
        )
    }

    /** Supervisor reports drive the cleanliness / vehicle-care bonus. */
    fun supervisorReports(now: Long): List<SupervisorReport> = listOf(
        SupervisorReport(
            id = "sup-001",
            kind = SupervisorReportKind.CLEANLINESS,
            createdAt = now.plusDays(-41),
            vehicleInternalNumber = "TEV-014",
            note = "Interiores con basura al entregar la unidad. Se descontó el bono del mes anterior.",
        ),
    )

    /** Mid-term contract (week 14 of 192) used to show every metric of the credit panel. */
    fun credit(now: Long): CreditAccount {
        val weekly = CreditProgram.WEEKLY_MXN
        val weeksPaid = 14
        return CreditAccount(
            contractId = "CR-10428",
            vehicleTarget = "${CreditProgram.VEHICLE_MODEL} · TEV-014",
            startedAt = now.plusDays(-98),
            totalMxn = CreditProgram.PRICE_MXN,
            paidMxn = weekly * weeksPaid,
            weeklyMxn = weekly,
            weeksPaid = weeksPaid,
            onTimePayments = 13,
            latePayments = 1,
            assignedVehicleOdometerKm = 96_480,
            payments = listOf(
                CreditPayment("cp-15", "Abono semanal 15", now.plusDays(4), weekly, CreditStatus.DUE),
                CreditPayment("cp-14", "Abono semanal 14", now.plusDays(-3), weekly, CreditStatus.PAID),
                CreditPayment("cp-13", "Abono semanal 13", now.plusDays(-10), weekly, CreditStatus.PAID),
                CreditPayment("cp-12", "Abono semanal 12", now.plusDays(-17), weekly, CreditStatus.PAID),
                CreditPayment("cp-11", "Abono semanal 11", now.plusDays(-24), weekly, CreditStatus.LATE),
                CreditPayment("cp-10", "Abono semanal 10", now.plusDays(-31), weekly, CreditStatus.PAID),
            ),
        )
    }
}
