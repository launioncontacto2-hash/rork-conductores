package com.rork.turnoevandroid.domain

import com.rork.turnoevandroid.util.Fmt
import com.rork.turnoevandroid.util.plusDays
import com.rork.turnoevandroid.util.startOfDay
import java.util.Calendar

/**
 * Every operational rule of the fleet: shift windows, goals, late time and
 * vehicle assignment validation.
 */
object ShiftRules {
    /** A correct start is accepted up to 10 minutes after the scheduled time. */
    const val GRACE_MINUTES = 10
    const val TRIPS_GOAL_PER_DAY = 14
    const val MIN_BATTERY_PCT = 70

    /** The unit may be scanned this early before the scheduled start. */
    const val EARLY_ASSIGNMENT_MINUTES = 30

    data class Window(val start: Int, val end: Int)

    data class Goals(
        val hourlyMxn: Int,
        val dailyMxn: Int,
        val weeklyMxn: Int,
        val tripsPerDay: Int,
    )

    /** Start/end minute of day for each slot (8 worked hours + 1 hour meal break). */
    fun window(slot: ShiftSlot): Window = when (slot) {
        ShiftSlot.MORNING -> Window(5 * 60, 14 * 60)
        ShiftSlot.EVENING -> Window(14 * 60 + 30, 23 * 60 + 30)
    }

    fun group(millis: Long): ShiftGroup {
        val weekday = Fmt.calendar(millis).get(Calendar.DAY_OF_WEEK)
        return if (weekday == Calendar.SUNDAY || weekday == Calendar.SATURDAY) {
            ShiftGroup.WEEKEND
        } else {
            ShiftGroup.WEEKDAY
        }
    }

    fun minutesOfDay(millis: Long): Int {
        val calendar = Fmt.calendar(millis)
        return calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
    }

    fun at(minutes: Int, day: Long): Long = day.startOfDay() + minutes * 60_000L

    fun scheduledStart(slot: ShiftSlot, day: Long): Long = at(window(slot).start, day)

    fun scheduledEnd(slot: ShiftSlot, day: Long): Long = at(window(slot).end, day)

    fun lateMinutes(scheduled: Long, actual: Long): Int {
        val diff = ((actual - scheduled) / 60_000L).toInt()
        return if (diff > GRACE_MINUTES) diff else 0
    }

    /** The calendar day matches the driver's group and the clock is inside the slot. */
    fun isCorrectShiftMoment(driver: Driver, now: Long): Boolean {
        if (group(now) != driver.group) return false
        val current = minutesOfDay(now)
        val bounds = window(driver.slot)
        return current >= bounds.start - EARLY_ASSIGNMENT_MINUTES && current <= bounds.end
    }

    /** Morning shift pays back the hour before its start, evening the hour after it ends. */
    fun isPaybackWindow(driver: Driver, now: Long): Boolean {
        val current = minutesOfDay(now)
        return when (driver.slot) {
            ShiftSlot.MORNING -> current in (4 * 60) until (5 * 60)
            ShiftSlot.EVENING -> current >= 23 * 60 + 30 || current < 30
        }
    }

    fun goals(group: ShiftGroup): Goals = when (group) {
        ShiftGroup.WEEKDAY -> Goals(190, 1_520, 7_600, TRIPS_GOAL_PER_DAY)
        ShiftGroup.WEEKEND -> Goals(250, 2_000, 4_000, TRIPS_GOAL_PER_DAY)
    }

    /** Money the driver should already have made at this point of the shift. */
    fun paceTargetMxn(group: ShiftGroup, elapsedMinutes: Double): Int {
        val workedHours = (elapsedMinutes / 60).coerceIn(0.0, 8.0)
        return Math.round(goals(group).hourlyMxn * workedHours).toInt()
    }

    /** Monday 00:00 of the week containing [millis]. */
    fun weekStart(millis: Long): Long {
        val weekday = Fmt.calendar(millis).get(Calendar.DAY_OF_WEEK)
        val offset = (weekday + 5) % 7
        return millis.startOfDay().plusDays(-offset)
    }

    fun isSameDay(lhs: Long, rhs: Long): Boolean = lhs.startOfDay() == rhs.startOfDay()

    fun isInSameWeek(millis: Long, reference: Long): Boolean {
        val start = weekStart(reference)
        val end = start.plusDays(7)
        return millis >= start && millis < end
    }

    /** Blocking rules evaluated in priority order. Empty means the unit can be taken. */
    fun validateAssignment(
        driver: Driver,
        vehicle: Vehicle,
        now: Long,
        odometerKm: Int,
        batteryPct: Int,
    ): List<AssignmentIssue> {
        val issues = mutableListOf<AssignmentIssue>()

        if (vehicle.stationId != driver.stationId) {
            issues += AssignmentIssue(
                AssignmentIssueCode.OTHER_STATION,
                "Unidad de otra estación, no puedes iniciar labores aquí",
            )
        }

        val takenByOther = vehicle.occupiedBy != null && vehicle.occupiedBy != driver.id
        if (vehicle.status == VehicleStatus.OCCUPIED || takenByOther) {
            issues += AssignmentIssue(
                AssignmentIssueCode.VEHICLE_OCCUPIED,
                "Vehículo ocupado, notificar a supervisor",
            )
        }

        if (!isCorrectShiftMoment(driver, now)) {
            issues += AssignmentIssue(
                AssignmentIssueCode.INVALID_SHIFT,
                "Turno inválido, notificar a supervisor",
            )
        }

        if (!driver.authorizedVehicleIds.contains(vehicle.id)) {
            issues += AssignmentIssue(
                AssignmentIssueCode.NOT_AUTHORIZED,
                "No tienes autorizado usar esta unidad, notificar a supervisor",
            )
        }

        if (batteryPct <= MIN_BATTERY_PCT) {
            issues += AssignmentIssue(
                AssignmentIssueCode.LOW_BATTERY,
                "Batería insuficiente para iniciar turno, notificar a supervisor",
            )
        }

        if (odometerKm != vehicle.odometerKm) {
            issues += AssignmentIssue(
                AssignmentIssueCode.ODOMETER_MISMATCH,
                "Discrepancia con el kilometraje registrado, notificar a supervisor",
            )
        }

        return issues
    }
}
