package com.rork.turnoevandroid.domain

import kotlinx.serialization.Serializable

/**
 * Domain model for the fleet driver app. Everything is fed by mock data today and
 * shaped for future Uber, GPS, OCR and telemetry integrations.
 * Timestamps are epoch milliseconds so the whole state serializes cleanly.
 */

@Serializable
enum class ShiftGroup {
    WEEKDAY,
    WEEKEND;

    val label: String
        get() = when (this) {
            WEEKDAY -> "Entre semana"
            WEEKEND -> "Fin de semana"
        }
}

@Serializable
enum class ShiftSlot {
    MORNING,
    EVENING;

    val label: String
        get() = when (this) {
            MORNING -> "Matutino"
            EVENING -> "Vespertino"
        }

    val rangeLabel: String
        get() = when (this) {
            MORNING -> "05:00 — 14:00"
            EVENING -> "14:30 — 23:30"
        }

    val paybackWindowLabel: String
        get() = when (this) {
            MORNING -> "04:00 — 05:00"
            EVENING -> "23:30 — 00:30"
        }
}

@Serializable
data class Driver(
    val id: String,
    val name: String,
    val employeeNumber: String,
    val email: String,
    val password: String,
    val photoAsset: String,
    /** Station the driver belongs to; work can only start in this station. */
    val stationId: String,
    val station: String,
    val group: ShiftGroup,
    val slot: ShiftSlot,
    val authorizedVehicleIds: List<String>,
)

@Serializable
enum class VehicleStatus {
    AVAILABLE,
    OCCUPIED,
    MAINTENANCE;

    val label: String
        get() = when (this) {
            AVAILABLE -> "Disponible"
            OCCUPIED -> "Ocupado"
            MAINTENANCE -> "En mantenimiento"
        }
}

@Serializable
data class Vehicle(
    val id: String,
    val qrCode: String,
    val internalNumber: String,
    val model: String,
    val plates: String,
    val odometerKm: Int,
    val batteryPct: Int,
    val stationId: String,
    val station: String,
    val status: VehicleStatus,
    val occupiedBy: String? = null,
    val photoAsset: String,
)

@Serializable
enum class InspectionSlot {
    ODOMETER,
    BATTERY,
    FRONT,
    LEFT,
    RIGHT,
    REAR;

    val title: String
        get() = when (this) {
            ODOMETER -> "Odómetro"
            BATTERY -> "Nivel de batería"
            FRONT -> "Frente"
            LEFT -> "Lateral izquierdo"
            RIGHT -> "Lateral derecho"
            REAR -> "Trasera"
        }

    val hint: String
        get() = when (this) {
            ODOMETER -> "Lectura legible"
            BATTERY -> "Tablero encendido"
            FRONT -> "Placa visible"
            LEFT -> "Cuerpo completo"
            RIGHT -> "Cuerpo completo"
            REAR -> "Cajuela y micas"
        }
}

@Serializable
data class ActiveShift(
    val id: String,
    val driverId: String,
    val vehicleId: String,
    val group: ShiftGroup,
    val slot: ShiftSlot,
    val scheduledStartAt: Long,
    val startedAt: Long,
    val lateMinutes: Int,
    val startOdometerKm: Int,
    val startBatteryPct: Int,
    /** Evidence keyed by the inspection slot name. */
    val photos: Map<String, String> = emptyMap(),
    val trips: Int = 0,
    val earningsMxn: Int = 0,
)

@Serializable
data class ShiftRecord(
    val id: String,
    val driverId: String,
    val vehicleId: String,
    val vehicleInternalNumber: String,
    val group: ShiftGroup,
    val slot: ShiftSlot,
    val scheduledStartAt: Long,
    val startedAt: Long,
    val endedAt: Long,
    val lateMinutes: Int,
    val paidBackMinutes: Int,
    val startOdometerKm: Int,
    val endOdometerKm: Int,
    val startBatteryPct: Int,
    val endBatteryPct: Int,
    val trips: Int,
    val earningsMxn: Int,
) {
    val kmDriven: Int get() = (endOdometerKm - startOdometerKm).coerceAtLeast(0)
    val durationMinutes: Int get() = ((endedAt - startedAt) / 60_000L).toInt().coerceAtLeast(0)
    val pendingLateMinutes: Int get() = (lateMinutes - paidBackMinutes).coerceAtLeast(0)
}

@Serializable
enum class IncomePlatform {
    UBER,
    DIDI,
    CASH,
    OTHER;

    val label: String
        get() = when (this) {
            UBER -> "Uber"
            DIDI -> "DiDi"
            CASH -> "Efectivo"
            OTHER -> "Otro"
        }
}

@Serializable
data class IncomeEntry(
    val id: String,
    val driverId: String,
    val shiftId: String? = null,
    val date: Long,
    val amountMxn: Int,
    val trips: Int,
    val platform: IncomePlatform,
    val hasEvidence: Boolean = false,
    val note: String? = null,
)

@Serializable
enum class IncidentKind {
    ACCIDENT,
    DAMAGE,
    MECHANICAL;

    val label: String
        get() = when (this) {
            ACCIDENT -> "Accidente"
            DAMAGE -> "Daño"
            MECHANICAL -> "Falla mecánica"
        }

    val hint: String
        get() = when (this) {
            ACCIDENT -> "Con terceros o daños mayores"
            DAMAGE -> "Golpes, rayones, cristales"
            MECHANICAL -> "Frenos, carga, suspensión"
        }
}

@Serializable
enum class IncidentStatus {
    OPEN,
    REVIEW,
    CLOSED;

    val label: String
        get() = when (this) {
            OPEN -> "Abierta"
            REVIEW -> "En revisión"
            CLOSED -> "Cerrada"
        }
}

@Serializable
data class Incident(
    val id: String,
    val driverId: String,
    val vehicleId: String,
    val vehicleInternalNumber: String,
    val kind: IncidentKind,
    val createdAt: Long,
    val description: String,
    val photoCount: Int = 0,
    val status: IncidentStatus,
)

@Serializable
enum class NoticeKind {
    MAINTENANCE,
    CREDIT,
    STATION,
    REMINDER;

    val label: String
        get() = when (this) {
            MAINTENANCE -> "Mantenimiento"
            CREDIT -> "Crédito"
            STATION -> "Estación"
            REMINDER -> "Recordatorio"
        }
}

@Serializable
data class Notice(
    val id: String,
    val kind: NoticeKind,
    val title: String,
    val body: String,
    val createdAt: Long,
    val read: Boolean = false,
)

@Serializable
enum class CreditStatus {
    PAID,
    DUE,
    LATE;

    val label: String
        get() = when (this) {
            PAID -> "Pagado"
            DUE -> "Por pagar"
            LATE -> "Vencido"
        }
}

@Serializable
data class CreditPayment(
    val id: String,
    val concept: String,
    val dueDate: Long,
    val amountMxn: Int,
    val status: CreditStatus,
)

@Serializable
data class CreditAccount(
    val contractId: String,
    val vehicleTarget: String,
    /** Contract signature date; the delivery month and the term are measured from here. */
    val startedAt: Long,
    val totalMxn: Int,
    val paidMxn: Int,
    val weeklyMxn: Int,
    val weeksPaid: Int,
    val onTimePayments: Int,
    val latePayments: Int,
    /** Odometer of the unit reserved for this contract; it leaves the fleet at 110,000-120,000 km. */
    val assignedVehicleOdometerKm: Int,
    val payments: List<CreditPayment>,
)

enum class AssignmentIssueCode {
    OTHER_STATION,
    VEHICLE_OCCUPIED,
    INVALID_SHIFT,
    NOT_AUTHORIZED,
    LOW_BATTERY,
    ODOMETER_MISMATCH,
}

data class AssignmentIssue(
    val code: AssignmentIssueCode,
    val message: String,
)

data class ShiftSummary(
    val kmDriven: Int,
    val durationMinutes: Int,
    val earningsMxn: Int,
    val trips: Int,
    val dailyGoalMxn: Int,
    val missingMxn: Int,
    val missingTrips: Int,
    val lateMinutes: Int,
)
