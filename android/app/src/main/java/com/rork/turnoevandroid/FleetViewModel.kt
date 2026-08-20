package com.rork.turnoevandroid

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.data.FleetStorage
import com.rork.turnoevandroid.domain.ActiveShift
import com.rork.turnoevandroid.domain.AssignmentIssue
import com.rork.turnoevandroid.domain.BonusAlert
import com.rork.turnoevandroid.domain.BonusEvaluation
import com.rork.turnoevandroid.domain.BonusKind
import com.rork.turnoevandroid.domain.BonusRules
import com.rork.turnoevandroid.domain.BonusWeekStatus
import com.rork.turnoevandroid.domain.CreditMetrics
import com.rork.turnoevandroid.domain.CreditProgram
import com.rork.turnoevandroid.domain.Driver
import com.rork.turnoevandroid.domain.Incident
import com.rork.turnoevandroid.domain.IncidentKind
import com.rork.turnoevandroid.domain.IncidentStatus
import com.rork.turnoevandroid.domain.IncomeEntry
import com.rork.turnoevandroid.domain.IncomePlatform
import com.rork.turnoevandroid.domain.InspectionSlot
import com.rork.turnoevandroid.domain.MockData
import com.rork.turnoevandroid.domain.Notice
import com.rork.turnoevandroid.domain.NoticeKind
import com.rork.turnoevandroid.domain.RecoveryBooking
import com.rork.turnoevandroid.domain.ShiftRecord
import com.rork.turnoevandroid.domain.ShiftRules
import com.rork.turnoevandroid.domain.ShiftSlot
import com.rork.turnoevandroid.domain.ShiftSummary
import com.rork.turnoevandroid.domain.SignInMethod
import com.rork.turnoevandroid.domain.StaffAccount
import com.rork.turnoevandroid.domain.StaffDirectory
import com.rork.turnoevandroid.domain.StaffRole
import com.rork.turnoevandroid.domain.StaffSession
import com.rork.turnoevandroid.domain.Station
import com.rork.turnoevandroid.domain.Vehicle
import com.rork.turnoevandroid.domain.VehicleStatus
import com.rork.turnoevandroid.util.Fmt
import com.rork.turnoevandroid.util.plusDays
import com.rork.turnoevandroid.util.startOfDay
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Single source of truth for the driver session, the active shift and every log.
 * Mirrors the iOS `FleetStore`: mock data in, local persistence out.
 */
class FleetViewModel(application: Application) : AndroidViewModel(application) {
    private val storage = FleetStorage(application)

    private val _state = MutableStateFlow(seedOrRestore())
    val state: StateFlow<FleetState> = _state.asStateFlow()

    /** Device clock shifted by the demo offset, refreshed every second. */
    private val _now = MutableStateFlow(nowMillis())
    val now: StateFlow<Long> = _now.asStateFlow()

    /** In-memory evidence thumbnails; only the capture marker is persisted. */
    private val _photoThumbnails = MutableStateFlow<Map<String, android.graphics.Bitmap>>(emptyMap())
    val photoThumbnails: StateFlow<Map<String, android.graphics.Bitmap>> = _photoThumbnails.asStateFlow()

    val driver: Driver = MockData.driver

    init {
        viewModelScope.launch {
            while (true) {
                _now.value = nowMillis()
                delay(1_000)
            }
        }
    }

    private fun nowMillis(): Long =
        System.currentTimeMillis() + _state.value.clockOffsetMinutes * 60_000L

    private fun seedOrRestore(): FleetState {
        storage.load()?.let { return it }
        val seedDate = System.currentTimeMillis()
        val seedHistory = MockData.shiftHistory(MockData.driver, seedDate)
        return FleetState(
            vehicles = MockData.syncOdometers(MockData.vehicles, seedHistory),
            history = seedHistory,
            incomes = MockData.incomeHistory(MockData.driver, seedHistory),
            incidents = MockData.incidents(MockData.driver, seedDate),
            notices = MockData.notices(seedDate),
            supervisorReports = MockData.supervisorReports(seedDate),
        )
    }

    private fun update(transform: (FleetState) -> FleetState) {
        val next = transform(_state.value)
        _state.value = next
        _now.value = System.currentTimeMillis() + next.clockOffsetMinutes * 60_000L
        storage.save(next)
    }

    // MARK: - Derived values

    val goals: ShiftRules.Goals get() = ShiftRules.goals(driver.group)

    fun activeVehicle(state: FleetState = _state.value): Vehicle? {
        val shift = state.activeShift ?: return null
        return state.vehicles.firstOrNull { it.id == shift.vehicleId }
    }

    fun creditMetrics(reference: Long = _now.value): CreditMetrics? {
        val credit = _state.value.credit ?: return null
        return CreditProgram.metrics(credit, reference)
    }

    fun elapsedSeconds(reference: Long): Int {
        val shift = _state.value.activeShift ?: return 0
        return ((reference - shift.startedAt) / 1000L).toInt().coerceAtLeast(0)
    }

    /** Average fleet speed used to estimate distance until real GPS/telemetry lands. */
    fun estimatedKmDriven(reference: Long): Int =
        Math.round(elapsedSeconds(reference) / 60.0 * SIMULATED_KM_PER_MINUTE).toInt()

    val capturedPhotoCount: Int get() = _state.value.activeShift?.photos?.size ?: 0

    val isInspectionComplete: Boolean get() = capturedPhotoCount >= InspectionSlot.entries.size

    /** Monday → Sunday late-minute log, the "bitácora" shown in Historial. */
    data class LateDay(
        val date: Long,
        val label: String,
        val minutes: Int,
        val paidBackMinutes: Int,
        val hasShift: Boolean,
    ) {
        val pendingMinutes: Int get() = (minutes - paidBackMinutes).coerceAtLeast(0)
    }

    fun weeklyLateBreakdown(reference: Long): List<LateDay> {
        val start = ShiftRules.weekStart(reference)
        return (0 until 7).map { offset ->
            val day = start.plusDays(offset)
            val record = _state.value.history.firstOrNull { ShiftRules.isSameDay(it.startedAt, day) }
            LateDay(
                date = day,
                label = Fmt.dayShort(day),
                minutes = record?.lateMinutes ?: 0,
                paidBackMinutes = record?.paidBackMinutes ?: 0,
                hasShift = record != null,
            )
        }
    }

    fun weeklyLateDebt(reference: Long): Int =
        weeklyLateBreakdown(reference).sumOf { it.pendingMinutes }

    fun earnedToday(reference: Long): Int {
        val state = _state.value
        val fromIncomes = state.incomes.filter { ShiftRules.isSameDay(it.date, reference) }
            .sumOf { it.amountMxn }
        val fromClosedShifts = state.history.filter { ShiftRules.isSameDay(it.startedAt, reference) }
            .sumOf { it.earningsMxn }
        return maxOf(fromIncomes, fromClosedShifts, state.activeShift?.earningsMxn ?: 0)
    }

    fun tripsToday(reference: Long): Int {
        val state = _state.value
        val fromIncomes = state.incomes.filter { ShiftRules.isSameDay(it.date, reference) }
            .sumOf { it.trips }
        return maxOf(fromIncomes, state.activeShift?.trips ?: 0)
    }

    fun earnedThisWeek(reference: Long): Int = _state.value.incomes
        .filter { ShiftRules.isInSameWeek(it.date, reference) }
        .sumOf { it.amountMxn }

    data class DayEarnings(val label: String, val amount: Int, val isToday: Boolean, val date: Long)

    fun weeklyEarningsByDay(reference: Long): List<DayEarnings> {
        val start = ShiftRules.weekStart(reference)
        return (0 until 7).map { offset ->
            val day = start.plusDays(offset)
            DayEarnings(
                label = Fmt.dayShort(day),
                amount = _state.value.incomes
                    .filter { ShiftRules.isSameDay(it.date, day) }
                    .sumOf { it.amountMxn },
                isToday = ShiftRules.isSameDay(day, reference),
                date = day,
            )
        }
    }

    // MARK: - Session

    /** Authenticated credential of the active session, or `null` when signed out. */
    val currentAccount: StaffAccount?
        get() = StaffDirectory.account(_state.value.session?.accountId)

    val currentRole: StaffRole?
        get() = _state.value.session?.role

    val currentStation: Station?
        get() = StaffDirectory.station(_state.value.session?.stationId)

    /** Credential allowed to unlock this device with biometrics. */
    val enrolledAccount: StaffAccount?
        get() = StaffDirectory.account(_state.value.enrolledAccountId)

    /** Interfaces open by role only: a driver can never render a supervisor screen. */
    fun hasAccess(role: StaffRole): Boolean = _state.value.session?.role == role

    /**
     * Opens the session for an already authenticated account and links the device so
     * future biometric unlocks resolve to this same credential.
     */
    fun signIn(account: StaffAccount, method: SignInMethod) = update { current ->
        current.copy(
            session = StaffSession(
                accountId = account.id,
                role = account.role,
                stationId = account.stationId,
                method = method,
                startedAt = System.currentTimeMillis(),
            ),
            enrolledAccountId = account.id,
        )
    }

    /**
     * Opens the session after a short delay so the login screen can confirm the
     * identified role before its interface is built.
     */
    fun scheduleSignIn(account: StaffAccount, method: SignInMethod, delayMillis: Long) {
        viewModelScope.launch {
            delay(delayMillis)
            signIn(account, method)
        }
    }

    fun signOut() = update { it.copy(session = null) }

    /** Removes the biometric link so the next access requires full credentials. */
    fun forgetDevice() = update { it.copy(session = null, enrolledAccountId = null) }

    fun setClockOffset(minutes: Int) = update { it.copy(clockOffsetMinutes = minutes) }

    /** Jumps the simulated clock to a given minute of the current day. */
    fun setSimulatedTime(minutesOfDay: Int?) {
        if (minutesOfDay == null) {
            setClockOffset(0)
            return
        }
        val real = System.currentTimeMillis()
        setClockOffset(minutesOfDay - ShiftRules.minutesOfDay(real))
    }

    fun resetDemoData() {
        val seedDate = System.currentTimeMillis()
        val seedHistory = MockData.shiftHistory(driver, seedDate)
        _photoThumbnails.value = emptyMap()
        update { current ->
            current.copy(
                vehicles = MockData.syncOdometers(MockData.vehicles, seedHistory),
                history = seedHistory,
                incomes = MockData.incomeHistory(driver, seedHistory),
                incidents = MockData.incidents(driver, seedDate),
                notices = MockData.notices(seedDate),
                credit = MockData.credit(seedDate),
                supervisorReports = MockData.supervisorReports(seedDate),
                recoveryBookings = emptyList(),
                notifiedBonusWeeks = emptyList(),
                activeShift = null,
                clockOffsetMinutes = 0,
            )
        }
    }

    // MARK: - Bonuses

    fun bonusEvaluations(reference: Long): List<BonusEvaluation> {
        val state = _state.value
        return BonusRules.evaluateAll(
            BonusRules.EvaluationInput(
                driver = driver,
                goals = goals,
                history = state.history,
                incomes = state.incomes,
                reports = state.supervisorReports,
                now = reference,
            ),
        )
    }

    /** Money still collectable at month end with the current weekly evaluation. */
    fun bonusPayableMxn(reference: Long): Int =
        bonusEvaluations(reference).sumOf { it.payableMxn }

    fun bonusTotalMxn(): Int = BonusKind.entries.sumOf { it.monthlyMxn }

    /** Raises the popup for the first closed week that broke a bonus, once only. */
    fun raiseBonusAlert(reference: Long): BonusAlert? {
        for (evaluation in bonusEvaluations(reference)) {
            for (result in evaluation.weeks) {
                if (result.status != BonusWeekStatus.LOST) continue
                val id = "${evaluation.kind.name}-${Fmt.monthKey(reference)}-${result.week.index}"
                if (_state.value.notifiedBonusWeeks.contains(id)) continue
                val message = "¡${Fmt.firstName(driver.name)} has perdido el bono de " +
                    "${evaluation.kind.shortName}! Agenda hoy tu lugar en el programa de recuperación de bonos"
                update { it.copy(notifiedBonusWeeks = it.notifiedBonusWeeks + id) }
                pushNotice(
                    NoticeKind.REMINDER,
                    message,
                    "Semana ${result.week.index} (${result.week.rangeLabel}): ${result.detail}.",
                )
                return BonusAlert(id, evaluation.kind, result.week.index, message)
            }
        }
        return null
    }

    // MARK: - Recovery program

    fun recoveryBooking(day: Long): RecoveryBooking? =
        _state.value.recoveryBookings.firstOrNull { ShiftRules.isSameDay(it.date, day) }

    val upcomingRecoveryBookings: List<RecoveryBooking>
        get() = _state.value.recoveryBookings.sortedBy { it.date }

    fun bookRecovery(date: Long, slot: ShiftSlot, bonus: BonusKind): Boolean {
        if (!BonusRules.canBook(driver, date, _now.value)) return false
        if (recoveryBooking(date) != null) return false

        val booking = RecoveryBooking(
            id = "rec-${UUID.randomUUID().toString().take(8)}",
            date = date.startOfDay(),
            slot = slot,
            bonus = bonus,
            createdAt = _now.value,
        )
        update { it.copy(recoveryBookings = it.recoveryBookings + booking) }
        pushNotice(
            NoticeKind.STATION,
            "Reserva confirmada en recuperación de bonos",
            "${Fmt.dateShort(booking.date)} · turno ${slot.label.lowercase()} ${slot.rangeLabel}. " +
                "Recuperas el bono de ${bonus.shortName}.",
        )
        return true
    }

    fun cancelRecovery(id: String) = update { state ->
        state.copy(recoveryBookings = state.recoveryBookings.filterNot { it.id == id })
    }

    // MARK: - Shift lifecycle

    fun validateAssignment(vehicle: Vehicle, odometerKm: Int, batteryPct: Int): List<AssignmentIssue> =
        ShiftRules.validateAssignment(driver, vehicle, _now.value, odometerKm, batteryPct)

    fun assign(vehicle: Vehicle, odometerKm: Int, batteryPct: Int) {
        val startedAt = _now.value
        val scheduled = ShiftRules.scheduledStart(driver.slot, startedAt)
        val lateMinutes = ShiftRules.lateMinutes(scheduled, startedAt)
        val shift = ActiveShift(
            id = "shift-${UUID.randomUUID().toString().take(8)}",
            driverId = driver.id,
            vehicleId = vehicle.id,
            group = ShiftRules.group(startedAt),
            slot = driver.slot,
            scheduledStartAt = scheduled,
            startedAt = startedAt,
            lateMinutes = lateMinutes,
            startOdometerKm = odometerKm,
            startBatteryPct = batteryPct,
        )

        _photoThumbnails.value = emptyMap()
        update { state ->
            state.copy(
                activeShift = shift,
                vehicles = state.vehicles.map { item ->
                    if (item.id == vehicle.id) {
                        item.copy(
                            status = VehicleStatus.OCCUPIED,
                            occupiedBy = driver.id,
                            odometerKm = odometerKm,
                            batteryPct = batteryPct,
                        )
                    } else {
                        item
                    }
                },
            )
        }

        if (lateMinutes > 0) {
            pushNotice(
                NoticeKind.REMINDER,
                "Inicio de turno con atraso",
                "Iniciaste $lateMinutes minutos después de la hora programada. Se registró en tu bitácora.",
            )
        }
    }

    fun saveInspectionPhoto(slot: InspectionSlot, thumbnail: android.graphics.Bitmap?) {
        val shift = _state.value.activeShift ?: return
        if (thumbnail != null) {
            _photoThumbnails.value = _photoThumbnails.value + (slot.name to thumbnail)
        }
        update {
            it.copy(
                activeShift = shift.copy(
                    photos = shift.photos + (slot.name to "captured-${_now.value}"),
                ),
            )
        }
    }

    fun registerIncome(amountMxn: Int, trips: Int, platform: IncomePlatform, hasEvidence: Boolean) {
        val entry = IncomeEntry(
            id = "inc-${UUID.randomUUID().toString().take(8)}",
            driverId = driver.id,
            shiftId = _state.value.activeShift?.id,
            date = _now.value,
            amountMxn = amountMxn,
            trips = trips,
            platform = platform,
            hasEvidence = hasEvidence,
        )
        update { state ->
            state.copy(
                incomes = listOf(entry) + state.incomes,
                activeShift = state.activeShift?.let { shift ->
                    shift.copy(
                        earningsMxn = shift.earningsMxn + amountMxn,
                        trips = shift.trips + trips,
                    )
                },
            )
        }
    }

    fun reportIncident(kind: IncidentKind, description: String, photoCount: Int) {
        val state = _state.value
        val vehicle = activeVehicle(state) ?: state.vehicles.firstOrNull()
        val incident = Incident(
            id = "inci-${UUID.randomUUID().toString().take(8)}",
            driverId = driver.id,
            vehicleId = vehicle?.id ?: "—",
            vehicleInternalNumber = vehicle?.internalNumber ?: "—",
            kind = kind,
            createdAt = _now.value,
            description = description,
            photoCount = photoCount,
            status = IncidentStatus.OPEN,
        )
        update { it.copy(incidents = listOf(incident) + it.incidents) }
        pushNotice(
            NoticeKind.STATION,
            "Incidencia enviada a la estación",
            "Tu reporte de ${kind.label.lowercase()} quedó en revisión.",
        )
    }

    fun finishShift(endOdometerKm: Int, endBatteryPct: Int, hasPhoto: Boolean): ShiftSummary {
        val state = _state.value
        val shift = state.activeShift ?: return ShiftSummary(
            kmDriven = 0,
            durationMinutes = 0,
            earningsMxn = 0,
            trips = 0,
            dailyGoalMxn = goals.dailyMxn,
            missingMxn = goals.dailyMxn,
            missingTrips = goals.tripsPerDay,
            lateMinutes = 0,
        )

        val record = ShiftRecord(
            id = shift.id,
            driverId = shift.driverId,
            vehicleId = shift.vehicleId,
            vehicleInternalNumber = activeVehicle(state)?.internalNumber ?: "—",
            group = shift.group,
            slot = shift.slot,
            scheduledStartAt = shift.scheduledStartAt,
            startedAt = shift.startedAt,
            endedAt = _now.value,
            lateMinutes = shift.lateMinutes,
            paidBackMinutes = 0,
            startOdometerKm = shift.startOdometerKm,
            endOdometerKm = endOdometerKm,
            startBatteryPct = shift.startBatteryPct,
            endBatteryPct = endBatteryPct,
            trips = shift.trips,
            earningsMxn = shift.earningsMxn,
        )

        _photoThumbnails.value = emptyMap()
        update { current ->
            current.copy(
                history = listOf(record) + current.history,
                activeShift = null,
                vehicles = current.vehicles.map { item ->
                    if (item.id == shift.vehicleId) {
                        item.copy(
                            status = VehicleStatus.AVAILABLE,
                            occupiedBy = null,
                            odometerKm = endOdometerKm,
                            batteryPct = endBatteryPct,
                        )
                    } else {
                        item
                    }
                },
            )
        }

        if (hasPhoto) {
            pushNotice(
                NoticeKind.STATION,
                "Turno cerrado",
                "Entregaste ${record.vehicleInternalNumber} con ${Fmt.km(endOdometerKm)}. " +
                    "Duración ${Fmt.durationText(record.durationMinutes)}.",
            )
        }

        return ShiftSummary(
            kmDriven = record.kmDriven,
            durationMinutes = record.durationMinutes,
            earningsMxn = record.earningsMxn,
            trips = record.trips,
            dailyGoalMxn = goals.dailyMxn,
            missingMxn = (goals.dailyMxn - record.earningsMxn).coerceAtLeast(0),
            missingTrips = (goals.tripsPerDay - record.trips).coerceAtLeast(0),
            lateMinutes = record.lateMinutes,
        )
    }

    /** Applies paid-back minutes to the oldest pending late day of the current week. */
    fun payLateTime(minutes: Int): Int {
        var remaining = minutes
        var applied = 0
        val pendingDates = weeklyLateBreakdown(_now.value)
            .filter { it.pendingMinutes > 0 }
            .map { it.date }

        val updatedHistory = _state.value.history.map { record ->
            if (remaining <= 0) return@map record
            if (pendingDates.none { ShiftRules.isSameDay(it, record.startedAt) }) return@map record
            val pending = record.pendingLateMinutes
            if (pending <= 0) return@map record
            val pay = minOf(pending, remaining)
            remaining -= pay
            applied += pay
            record.copy(paidBackMinutes = record.paidBackMinutes + pay)
        }

        if (applied > 0) update { it.copy(history = updatedHistory) }
        return applied
    }

    // MARK: - Credit

    /** Signs a new contract: no down payment, immediate approval, first instalment in a week. */
    fun requestCredit() {
        if (_state.value.credit != null) return
        val unit = _state.value.vehicles
            .firstOrNull { driver.authorizedVehicleIds.contains(it.id) }
            ?.internalNumber ?: "por asignar"
        update { it.copy(credit = CreditProgram.newAccount(_now.value, unit)) }
        pushNotice(
            NoticeKind.CREDIT,
            "Crédito aprobado",
            "Tu contrato del ${CreditProgram.VEHICLE_MODEL} quedó firmado. " +
                "El primer abono semanal se descuenta en 7 días.",
        )
    }

    /** Loads the seeded mid-term contract so every metric of the panel can be reviewed. */
    fun loadCreditDemoProgress() = update { it.copy(credit = MockData.credit(_now.value)) }

    /** Returns the driver to the promotional banner state. */
    fun cancelCredit() = update { it.copy(credit = null) }

    // MARK: - Notices

    fun markNoticeRead(id: String) = update { state ->
        state.copy(notices = state.notices.map { if (it.id == id) it.copy(read = true) else it })
    }

    fun markAllNoticesRead() = update { state ->
        state.copy(notices = state.notices.map { it.copy(read = true) })
    }

    fun pushNotice(kind: NoticeKind, title: String, body: String) = update { state ->
        state.copy(
            notices = listOf(
                Notice(
                    id = "not-${UUID.randomUUID().toString().take(8)}",
                    kind = kind,
                    title = title,
                    body = body,
                    createdAt = _now.value,
                ),
            ) + state.notices,
        )
    }

    private companion object {
        /** Average fleet speed used to estimate distance until real GPS/telemetry lands. */
        const val SIMULATED_KM_PER_MINUTE = 0.32
    }
}
