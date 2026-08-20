import Foundation

/// Every operational rule of the fleet: shift windows, goals, late time and
/// vehicle assignment validation.
nonisolated enum ShiftRules {
    /// A correct start is accepted up to 10 minutes after the scheduled time.
    static let graceMinutes = 10
    static let tripsGoalPerDay = 14
    static let minBatteryPct = 70
    /// The unit may be scanned this early before the scheduled start.
    static let earlyAssignmentMinutes = 30
    /// Difference accepted between the captured odometer and the registered one.
    static let odometerToleranceKm = 5

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Fmt.locale
        return calendar
    }

    // MARK: - Windows

    /// Start/end minute of day for each slot (8 worked hours + 1 hour meal break).
    static func window(for slot: ShiftSlot) -> (start: Int, end: Int) {
        switch slot {
        case .morning: (5 * 60, 14 * 60)
        case .evening: (14 * 60 + 30, 23 * 60 + 30)
        }
    }

    static func group(for date: Date) -> ShiftGroup {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday == 1 || weekday == 7) ? .weekend : .weekday
    }

    static func minutesOfDay(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func at(minutes: Int, on day: Date) -> Date {
        let midnight = calendar.startOfDay(for: day)
        return midnight.addingTimeInterval(TimeInterval(minutes * 60))
    }

    static func scheduledStart(slot: ShiftSlot, on day: Date) -> Date {
        at(minutes: window(for: slot).start, on: day)
    }

    static func scheduledEnd(slot: ShiftSlot, on day: Date) -> Date {
        at(minutes: window(for: slot).end, on: day)
    }

    // MARK: - Start window

    /// How early the block can be opened. The morning shift may start one hour before
    /// its scheduled time; the evening one, thirty minutes before.
    static func earlyStartMinutes(for slot: ShiftSlot) -> Int {
        switch slot {
        case .morning: 60
        case .evening: 30
        }
    }

    /// Extra time the block may run past its scheduled end. The morning shift always
    /// closes at its established hour; the evening one may stretch one hour.
    static func overtimeMinutes(for slot: ShiftSlot) -> Int {
        switch slot {
        case .morning: 0
        case .evening: 60
        }
    }

    /// The evening block crosses midnight: between 00:00 and 00:30 the driver is still
    /// inside the workday that started the previous calendar day.
    static func operatingDay(slot: ShiftSlot, now: Date) -> Date {
        let midnight = calendar.startOfDay(for: now)
        guard slot == .evening, minutesOfDay(now) < overtimeMinutes(for: slot) else { return midnight }
        return calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight
    }

    /// Absolute instants when the block opens for starting and when it is force-closed.
    static func startWindow(slot: ShiftSlot, now: Date) -> (opensAt: Date, closesAt: Date) {
        let day = operatingDay(slot: slot, now: now)
        let bounds = window(for: slot)
        return (
            at(minutes: bounds.start - earlyStartMinutes(for: slot), on: day),
            at(minutes: bounds.end + overtimeMinutes(for: slot), on: day)
        )
    }

    /// Where the clock stands against the block the driver belongs to.
    nonisolated enum WindowState: Sendable, Equatable {
        case open
        case early(opensAt: Date)
        case closed(closedAt: Date)
        case wrongDay

        var isOpen: Bool { self == .open }
    }

    static func windowState(driver: Driver, now: Date) -> WindowState {
        let bounds = startWindow(slot: driver.slot, now: now)
        if group(for: operatingDay(slot: driver.slot, now: now)) != driver.group { return .wrongDay }
        if now < bounds.opensAt { return .early(opensAt: bounds.opensAt) }
        if now > bounds.closesAt { return .closed(closedAt: bounds.closesAt) }
        return .open
    }

    /// The workday of a running shift is over and the unit must be handed back.
    static func isPastClose(slot: ShiftSlot, now: Date) -> Bool {
        now > startWindow(slot: slot, now: now).closesAt
    }

    /// Human sentence for the blocking alert.
    static func windowMessage(driver: Driver, now: Date) -> String? {
        switch windowState(driver: driver, now: now) {
        case .open:
            return nil
        case .early(let opensAt):
            return "Aún no abre tu ventana de inicio. Podrás tomar tu unidad a partir de las \(Fmt.clock(opensAt))."
        case .closed(let closedAt):
            return "Tu jornada cerró a las \(Fmt.clock(closedAt)). Ya no puedes iniciar turno, notificar a supervisor."
        case .wrongDay:
            return "Hoy no corresponde a tu grupo de \(driver.group.label.lowercased()). Notificar a supervisor."
        }
    }

    // MARK: - Late time

    static func lateMinutes(scheduled: Date, actual: Date) -> Int {
        let diff = Int(actual.timeIntervalSince(scheduled) / 60)
        return diff > graceMinutes ? diff : 0
    }

    /// The calendar day matches the driver's group and the clock is inside the block,
    /// counting the early opening and the overtime of the slot.
    static func isCorrectShiftMoment(driver: Driver, now: Date) -> Bool {
        windowState(driver: driver, now: now).isOpen
    }

    /// Morning shift pays back the hour before its start, evening the hour after it ends.
    static func isPaybackWindow(driver: Driver, now: Date) -> Bool {
        let current = minutesOfDay(now)
        switch driver.slot {
        case .morning: return current >= 4 * 60 && current < 5 * 60
        case .evening: return current >= 23 * 60 + 30 || current < 30
        }
    }

    // MARK: - Goals

    struct Goals: Sendable {
        let hourlyMxn: Int
        let dailyMxn: Int
        let weeklyMxn: Int
        let tripsPerDay: Int
    }

    static func goals(for group: ShiftGroup) -> Goals {
        switch group {
        case .weekday: Goals(hourlyMxn: 190, dailyMxn: 1520, weeklyMxn: 7600, tripsPerDay: tripsGoalPerDay)
        case .weekend: Goals(hourlyMxn: 250, dailyMxn: 2000, weeklyMxn: 4000, tripsPerDay: tripsGoalPerDay)
        }
    }

    // MARK: - Station goal

    /// Blocks a station runs in one calendar day: matutino and vespertino.
    static var slotsPerDay: Int { ShiftSlot.allCases.count }

    /// The fixed billing goal of a station for one shift. It is the authorized fleet —
    /// not the covered seats — times the driver goal of the group, so an empty unit
    /// never lowers the number the station has to reach.
    static func stationShiftGoalMxn(capacity: Int, group: ShiftGroup) -> Int {
        goals(for: group).dailyMxn * max(0, capacity)
    }

    /// Both blocks of the day added up.
    static func stationDayGoalMxn(capacity: Int, group: ShiftGroup) -> Int {
        stationShiftGoalMxn(capacity: capacity, group: group) * slotsPerDay
    }

    /// Monday to Sunday: five weekday days plus two weekend days, both blocks each.
    static func stationWeekGoalMxn(capacity: Int) -> Int {
        stationDayGoalMxn(capacity: capacity, group: .weekday) * 5
            + stationDayGoalMxn(capacity: capacity, group: .weekend) * 2
    }

    /// The goal of a station on a specific date, for the week series.
    static func stationDayGoalMxn(capacity: Int, on day: Date) -> Int {
        stationDayGoalMxn(capacity: capacity, group: group(for: day))
    }

    /// Every day of the calendar month, each one counted by its own group.
    static func stationMonthGoalMxn(capacity: Int, on day: Date) -> Int {
        let calendar = calendar
        guard let range = calendar.range(of: .day, in: .month, for: day) else { return 0 }
        var components = calendar.dateComponents([.year, .month], from: day)
        return range.reduce(0) { total, dayNumber in
            components.day = dayNumber
            guard let date = calendar.date(from: components) else { return total }
            return total + stationDayGoalMxn(capacity: capacity, on: date)
        }
    }

    /// What each present driver has to bill so the shift closes its fixed goal. When
    /// seats are empty the same money is split between fewer people.
    static func shareOfShiftGoalMxn(capacity: Int, group: ShiftGroup, presentDrivers: Int) -> Int {
        let total = stationShiftGoalMxn(capacity: capacity, group: group)
        guard presentDrivers > 0 else { return total }
        return Int((Double(total) / Double(presentDrivers)).rounded())
    }

    /// Money the driver should already have made at this point of the shift.
    static func paceTargetMxn(group: ShiftGroup, elapsedMinutes: Double) -> Int {
        let workedHours = min(8, max(0, elapsedMinutes / 60))
        return Int((Double(goals(for: group).hourlyMxn) * workedHours).rounded())
    }

    // MARK: - Weeks

    /// Monday 00:00 of the week containing `date`.
    static func weekStart(for date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let offset = (weekday + 5) % 7
        let midnight = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -offset, to: midnight) ?? midnight
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func isInSameWeek(_ date: Date, as reference: Date) -> Bool {
        let start = weekStart(for: reference)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return false }
        return date >= start && date < end
    }

    // MARK: - Assignment validation

    /// Step 1 of the start flow: the sticker read must be the unit the supervisor tied
    /// to this driver, in this station, free, and inside the start window.
    static func validateUnit(
        driver: Driver,
        vehicle: Vehicle,
        assignedVehicleId: String?,
        now: Date
    ) -> [AssignmentIssue] {
        var issues: [AssignmentIssue] = []

        guard let assignedVehicleId else {
            return [
                AssignmentIssue(
                    code: .notAssigned,
                    message: "No tienes unidad asignada. Tu supervisor debe asignarte una antes de iniciar turno."
                )
            ]
        }

        if vehicle.id != assignedVehicleId {
            issues.append(
                AssignmentIssue(
                    code: .wrongVehicle,
                    message: "La unidad \(vehicle.internalNumber) no es la que tienes asignada, notificar a supervisor"
                )
            )
        }

        if vehicle.stationId != driver.stationId {
            issues.append(
                AssignmentIssue(
                    code: .otherStation,
                    message: "Unidad de otra estación, no puedes iniciar labores aquí"
                )
            )
        }

        let takenByOther = vehicle.occupiedBy != nil && vehicle.occupiedBy != driver.id
        if vehicle.status == .occupied || takenByOther {
            issues.append(AssignmentIssue(code: .vehicleOccupied, message: "Vehículo ocupado, notificar a supervisor"))
        }

        if vehicle.status == .maintenance {
            issues.append(
                AssignmentIssue(
                    code: .vehicleOccupied,
                    message: "Unidad en mantenimiento, solicita una sustituta a tu supervisor"
                )
            )
        }

        if let message = windowMessage(driver: driver, now: now) {
            issues.append(AssignmentIssue(code: .outsideWindow, message: message))
        }

        return issues
    }

    /// Step 2: the photographed odometer against the registered one, ±5 km.
    static func validateOdometer(vehicle: Vehicle, reading: Int) -> AssignmentIssue? {
        let drift = abs(reading - vehicle.odometerKm)
        guard drift > odometerToleranceKm else { return nil }
        return AssignmentIssue(
            code: .odometerMismatch,
            message: "Diferencia de \(Fmt.km(drift)) contra el registro de \(Fmt.km(vehicle.odometerKm)). La tolerancia es de \(odometerToleranceKm) km, notificar a supervisor"
        )
    }

    /// Step 3: the photographed charge against the minimum the fleet demands.
    static func validateBattery(reading: Int) -> AssignmentIssue? {
        guard reading <= minBatteryPct else { return nil }
        return AssignmentIssue(
            code: .lowBattery,
            message: "Batería al \(reading)%. Se requiere más de \(minBatteryPct)% para iniciar turno, notificar a supervisor"
        )
    }

    /// Blocking rules evaluated in priority order. Empty means the unit can be taken.
    static func validateAssignment(
        driver: Driver,
        vehicle: Vehicle,
        now: Date,
        odometerKm: Int,
        batteryPct: Int
    ) -> [AssignmentIssue] {
        var issues: [AssignmentIssue] = []

        if vehicle.stationId != driver.stationId {
            issues.append(
                AssignmentIssue(
                    code: .otherStation,
                    message: "Unidad de otra estación, no puedes iniciar labores aquí"
                )
            )
        }

        let takenByOther = vehicle.occupiedBy != nil && vehicle.occupiedBy != driver.id
        if vehicle.status == .occupied || takenByOther {
            issues.append(AssignmentIssue(code: .vehicleOccupied, message: "Vehículo ocupado, notificar a supervisor"))
        }

        if !isCorrectShiftMoment(driver: driver, now: now) {
            issues.append(AssignmentIssue(code: .invalidShift, message: "Turno inválido, notificar a supervisor"))
        }

        if !driver.authorizedVehicleIds.contains(vehicle.id) {
            issues.append(
                AssignmentIssue(
                    code: .notAuthorized,
                    message: "No tienes autorizado usar esta unidad, notificar a supervisor"
                )
            )
        }

        if let issue = validateBattery(reading: batteryPct) {
            issues.append(issue)
        }

        if let issue = validateOdometer(vehicle: vehicle, reading: odometerKm) {
            issues.append(issue)
        }

        return issues
    }
}

// MARK: - Station goal board

/// The fixed number every role of a station chases. Management, supervision and the
/// drivers all read the same arithmetic: authorized units × the driver goal of the day.
/// Nothing here is captured by hand — change the station's capacity and the goal moves.
nonisolated struct StationGoalBoard: Sendable {
    /// Units the network authorized for the station.
    let capacity: Int
    let group: ShiftGroup
    let slot: ShiftSlot
    /// Money billed so far in the observed shift.
    let earningsMxn: Int
    /// Drivers who actually took a unit this shift.
    let presentDrivers: Int
    let weekEarningsMxn: Int

    /// Goal per driver of the day: $1,520 entre semana, $2,000 en fin de semana.
    var driverGoalMxn: Int { ShiftRules.goals(for: group).dailyMxn }
    var driverHourlyMxn: Int { ShiftRules.goals(for: group).hourlyMxn }

    /// The headline: capacity × driver goal. Fixed for the whole shift.
    var shiftGoalMxn: Int { ShiftRules.stationShiftGoalMxn(capacity: capacity, group: group) }
    /// Both blocks of the day.
    var dayGoalMxn: Int { ShiftRules.stationDayGoalMxn(capacity: capacity, group: group) }
    var weekGoalMxn: Int { ShiftRules.stationWeekGoalMxn(capacity: capacity) }

    var weekdayShiftGoalMxn: Int { ShiftRules.stationShiftGoalMxn(capacity: capacity, group: .weekday) }
    var weekendShiftGoalMxn: Int { ShiftRules.stationShiftGoalMxn(capacity: capacity, group: .weekend) }

    var ratio: Double { shiftGoalMxn > 0 ? Double(earningsMxn) / Double(shiftGoalMxn) : 0 }
    var gapMxn: Int { max(0, shiftGoalMxn - earningsMxn) }
    var weekRatio: Double { weekGoalMxn > 0 ? Double(weekEarningsMxn) / Double(weekGoalMxn) : 0 }

    /// Seats of the shift nobody covered: each one is a whole driver goal missing.
    var uncoveredSeats: Int { max(0, capacity - presentDrivers) }
    var uncoveredGoalMxn: Int { uncoveredSeats * driverGoalMxn }

    /// What each driver on the floor must bill for the fixed goal to close anyway.
    var shareMxn: Int {
        ShiftRules.shareOfShiftGoalMxn(capacity: capacity, group: group, presentDrivers: presentDrivers)
    }

    /// Extra money each present driver absorbs because of the empty seats.
    var overloadMxn: Int { max(0, shareMxn - driverGoalMxn) }

    /// Formula spelled out the way the network states it.
    var formulaLabel: String {
        "\(capacity) unidades × \(Fmt.mxn(driverGoalMxn))"
    }

    var groupLabel: String { group == .weekend ? "fin de semana" : "entre semana" }
}
