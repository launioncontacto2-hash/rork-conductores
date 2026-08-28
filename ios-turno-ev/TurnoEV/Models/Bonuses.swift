import Foundation

/// Monthly bonuses paid at month end but evaluated week by week: the driver must
/// hit the target on all four weeks of the month to collect.
///
/// Nobody authorizes a bonus driver by driver. The goal engine releases it when the
/// four weeks close in green and cancels it the moment one week fails. The only hand
/// that can move a bonus is the national administration, and it does so by changing
/// the amounts of the whole network in the policy book — never one driver at a time.

nonisolated enum BonusKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case punctuality
    case billing
    case care
    case service

    var id: String { rawValue }

    var title: String {
        switch self {
        case .punctuality: "Puntualidad y asistencia"
        case .billing: "Facturación"
        case .care: "Limpieza y cuidado"
        case .service: "Calidad en el servicio"
        }
    }

    /// Short name used inside notifications: "has perdido el bono de puntualidad".
    var shortName: String {
        switch self {
        case .punctuality: "puntualidad"
        case .billing: "facturación"
        case .care: "limpieza"
        case .service: "calidad"
        }
    }

    /// Quality comes from the Uber API, so the amount is defined by the platform.
    var isExternal: Bool { self == .service }

    var symbol: String {
        switch self {
        case .punctuality: "alarm.waves.left.and.right.fill"
        case .billing: "banknote.fill"
        case .care: "sparkles"
        case .service: "star.fill"
        }
    }

    var howToWin: String {
        switch self {
        case .punctuality: "Inicia turno a tiempo todos los días del mes."
        case .billing: "Llega a la meta semanal de facturación las 4 semanas."
        case .care: "Termina el mes sin reportes de daño ni de limpieza."
        case .service: "Mantén tu calificación de plataforma en verde."
        }
    }

    var howToLose: String {
        switch self {
        case .punctuality: "Se pierde con una falta o si cierras el mes con tiempo adeudado."
        case .billing: "Se pierde en la semana que no alcanzas la meta."
        case .care: "Se pierde si el supervisor genera un reporte en tu contra."
        case .service: "Se integra con la API de Uber; en pruebas se muestra positiva."
        }
    }
}

// MARK: - Amounts in force

/// Bonus amounts of the whole network. Written only by the national administration;
/// every station, supervisor and driver reads it.
nonisolated struct BonusSchedule: Codable, Sendable, Equatable {
    var punctualityMxn: Int
    var billingMxn: Int
    var careMxn: Int
    /// Version of the policy book that produced these amounts.
    var version: Int
    var updatedAt: Date
    var updatedBy: String

    static let networkDefault = BonusSchedule(
        punctualityMxn: 1_500,
        billingMxn: 1_500,
        careMxn: 1_000,
        version: 1,
        updatedAt: .distantPast,
        updatedBy: "Administración nacional"
    )

    func amountMxn(for kind: BonusKind) -> Int {
        switch kind {
        case .punctuality: punctualityMxn
        case .billing: billingMxn
        case .care: careMxn
        case .service: 0
        }
    }

    /// Everything a driver can collect in a perfect month.
    var ceilingMxn: Int { punctualityMxn + billingMxn + careMxn }
}

/// Single place where the bonus amounts live for the whole app. The national policy
/// book publishes here; nothing else writes.
enum NationalBonusBoard {
    private static let storageKey = "turnoev.bonus.schedule.v1"
    private static var cache: BonusSchedule?

    static var current: BonusSchedule {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(BonusSchedule.self, from: data) else {
            cache = .networkDefault
            return .networkDefault
        }
        cache = decoded
        return decoded
    }

    /// Called by the national board when direction moves an amount.
    static func publish(_ schedule: BonusSchedule) {
        cache = schedule
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func reset() {
        cache = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

/// What the engine already decided about a bonus of the month.
///
/// `notEvaluable` is not a fourth flavour of "running": it is the month the engine
/// refuses to judge because no week in it carried enough evidence. A bonus nobody can
/// evaluate is neither released nor cancelled, and saying so out loud is the whole
/// point — the alternative is a screen that congratulates or punishes a driver for a
/// month they never worked.
nonisolated enum BonusDecision: String, Sendable {
    case running
    case authorized
    case cancelled
    case notEvaluable

    var label: String {
        switch self {
        case .running: "En evaluación"
        case .authorized: "Autorizado automáticamente"
        case .cancelled: "Cancelado automáticamente"
        case .notEvaluable: "Sin evaluar"
        }
    }

    var symbol: String {
        switch self {
        case .running: "circle.dotted"
        case .authorized: "checkmark.seal.fill"
        case .cancelled: "xmark.seal.fill"
        case .notEvaluable: "circle.dashed"
        }
    }

    var detail: String {
        switch self {
        case .running: "Se libera solo si cierras las 4 semanas en verde."
        case .authorized: "Cumpliste las 4 semanas. Entra en el corte del mes sin que nadie lo firme."
        case .cancelled: "Una semana incumplida lo cancela. Nadie puede reactivarlo en la estación."
        case .notEvaluable: "Todavía no hay operación registrada que permita evaluar este bono."
        }
    }
}

nonisolated enum BonusWeekStatus: String, Codable, Sendable {
    case achieved
    case lost
    case inProgress
    case upcoming
    /// The week closed — or is running — without evidence of operation, so there is
    /// nothing to judge. Distinct from `upcoming`, which is a week that has not started.
    case notEvaluated

    var label: String {
        switch self {
        case .achieved: "Cumplida"
        case .lost: "Perdida"
        case .inProgress: "En curso"
        case .upcoming: "Por evaluar"
        case .notEvaluated: "Sin actividad"
        }
    }

    var symbol: String {
        switch self {
        case .achieved: "checkmark"
        case .lost: "xmark"
        case .inProgress: "circle.dotted"
        case .upcoming: "minus"
        case .notEvaluated: "questionmark"
        }
    }

    /// Whether this week produced a verdict the month can be built on. Only these weeks
    /// can move a bonus, raise an alert or open the recovery program.
    var isVerdict: Bool {
        switch self {
        case .achieved, .lost, .inProgress: true
        case .upcoming, .notEvaluated: false
        }
    }
}

/// Monday → Sunday evaluation window, numbered 1 to 4 inside the month.
nonisolated struct BonusWeekRange: Identifiable, Sendable {
    let index: Int
    let start: Date
    let end: Date

    var id: Int { index }
    var shortLabel: String { "S\(index)" }
    var rangeLabel: String { "\(Fmt.dayNumber(start)) — \(Fmt.dayNumber(end.addingTimeInterval(-86_400)))" }

    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

nonisolated struct BonusWeekResult: Identifiable, Sendable {
    let week: BonusWeekRange
    let status: BonusWeekStatus
    let detail: String

    var id: Int { week.index }
}

nonisolated struct BonusEvaluation: Identifiable, Sendable {
    let kind: BonusKind
    let weeks: [BonusWeekResult]
    /// Amounts in force when the evaluation ran, straight from the national policy book.
    let schedule: BonusSchedule

    var id: String { kind.rawValue }

    var lostWeeks: [Int] { weeks.filter { $0.status == .lost }.map(\.week.index) }
    var achievedCount: Int { weeks.filter { $0.status == .achieved }.count }
    var isLost: Bool { !lostWeeks.isEmpty }
    var isSecured: Bool { achievedCount == weeks.count && !weeks.isEmpty }

    /// Weeks that actually produced a verdict. A month made only of weeks without
    /// evidence has none, and cannot be secured or cancelled by any of them.
    var verdictCount: Int { weeks.filter { $0.status.isVerdict }.count }

    /// Nothing in this month can be judged yet.
    var isNotEvaluable: Bool { verdictCount == 0 }

    /// Amount of this bonus with the amounts the national administration has in force.
    var monthlyMxn: Int { schedule.amountMxn(for: kind) }

    /// Money actually payable at month end with the current evaluation.
    ///
    /// A month with no evaluable week pays nothing rather than projecting the full
    /// amount: the driver has not earned it, and promising it on the goals screen would
    /// be the same mistake as the green check, only with money attached.
    var payableMxn: Int { (isLost || isNotEvaluable) ? 0 : monthlyMxn }

    /// The engine's own verdict. No signature exists anywhere in this flow.
    var decision: BonusDecision {
        if isLost { return .cancelled }
        if isSecured { return .authorized }
        if isNotEvaluable { return .notEvaluable }
        return .running
    }

    var statusText: String {
        if isLost { return "Perdido · semana \(lostWeeks.map(String.init).joined(separator: ", "))" }
        if isSecured { return "Asegurado" }
        if isNotEvaluable { return "Sin actividad para evaluar" }
        return "En camino · \(achievedCount) de \(weeks.count) semanas"
    }
}

nonisolated enum SupervisorReportKind: String, Codable, CaseIterable, Sendable {
    case damage
    case cleanliness

    var label: String {
        switch self {
        case .damage: "Reporte de daño"
        case .cleanliness: "Reporte de limpieza"
        }
    }
}

/// Report generated by the station supervisor against the driver.
nonisolated struct SupervisorReport: Codable, Identifiable, Sendable {
    let id: String
    let kind: SupervisorReportKind
    let createdAt: Date
    let vehicleInternalNumber: String
    let note: String
}

/// Reserved day inside the bonus recovery program, always on the opposite group.
nonisolated struct RecoveryBooking: Codable, Identifiable, Sendable {
    let id: String
    let date: Date
    let slot: ShiftSlot
    let bonus: BonusKind
    let createdAt: Date
}

nonisolated struct BonusAlert: Identifiable, Sendable {
    let id: String
    let kind: BonusKind
    let weekIndex: Int
    let message: String
}

nonisolated enum BonusRules {
    /// The month is evaluated in four Monday → Sunday windows.
    static let weeksPerMonth = 4

    static func monthStart(for date: Date) -> Date {
        let calendar = ShiftRules.calendar
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }

    static func weeks(reference: Date) -> [BonusWeekRange] {
        let calendar = ShiftRules.calendar
        var start = ShiftRules.weekStart(for: monthStart(for: reference))
        var result: [BonusWeekRange] = []
        for index in 1...weeksPerMonth {
            guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { break }
            result.append(BonusWeekRange(index: index, start: start, end: end))
            start = end
        }
        return result
    }

    struct EvaluationInput: Sendable {
        let driver: Driver
        let goals: ShiftRules.Goals
        let history: [ShiftRecord]
        let incomes: [IncomeEntry]
        let reports: [SupervisorReport]
        /// The shift open right now, when it belongs to this driver. A week can be
        /// evaluable before its first shift closes.
        let activeShift: ActiveShift?
        /// Platform quality score of **this** driver, or `nil` when no source answers
        /// for them. There is no default: an absent score is an absent score.
        let qualityScore: Double?
        let schedule: BonusSchedule
        let now: Date
    }

    // MARK: - Evidence

    /// Did this driver operate during this week?
    ///
    /// The single gate that separates "did not comply" from "there is nothing to judge".
    /// The calendar advancing is **not** evidence of work: a week only becomes evaluable
    /// when the driver left a trace of operation inside it — a shift they closed, the
    /// shift they have open right now, or income they registered.
    ///
    /// Every source is matched against `driver.id` here as well as upstream. Evidence
    /// that cannot name its owner does not count.
    static func hasOperationalActivity(week: BonusWeekRange, input: EvaluationInput) -> Bool {
        let driverId = input.driver.id
        if input.history.contains(where: { $0.driverId == driverId && week.contains($0.startedAt) }) {
            return true
        }
        if let shift = input.activeShift, shift.driverId == driverId, week.contains(shift.startedAt) {
            return true
        }
        return input.incomes.contains {
            $0.driverId == driverId && week.contains($0.date) && ($0.shiftId != nil || $0.amountMxn > 0)
        }
    }

    static func evaluateAll(_ input: EvaluationInput) -> [BonusEvaluation] {
        let ranges = weeks(reference: input.now)
        return BonusKind.allCases.map { kind in
            BonusEvaluation(
                kind: kind,
                weeks: ranges.map { week in evaluate(kind: kind, week: week, input: input) },
                schedule: input.schedule
            )
        }
    }

    static func evaluate(kind: BonusKind, week: BonusWeekRange, input: EvaluationInput) -> BonusWeekResult {
        if week.start > input.now {
            return BonusWeekResult(week: week, status: .upcoming, detail: "Aún no inicia")
        }

        // Nothing operated, nothing to judge. This is what stops a driver with an empty
        // record from being charged five absences they never incurred, missing a billing
        // target nobody set them, and collecting a cleanliness check for a unit they were
        // never handed.
        guard hasOperationalActivity(week: week, input: input) else {
            return BonusWeekResult(week: week, status: .notEvaluated, detail: "Sin actividad registrada")
        }

        let isRunning = week.contains(input.now)
        let driverId = input.driver.id

        switch kind {
        case .punctuality:
            // An absence is an obligation the driver failed to meet, so it needs the
            // obligation first. This rule used to derive it by subtraction —
            // `expectedWorkDays - records.count` — which is not a measurement of anything:
            // the minuend is a calendar count of the days their group *would* rotate,
            // owed by nobody, assigned by nobody. A driver who joined on Thursday and
            // worked their one shift came out with four faults for the Monday, Tuesday
            // and Wednesday when they were not yet employed here.
            //
            // There is no roster in the model today that can prove which days a given
            // driver was scheduled to work in a past week, so this bonus judges only what
            // the operation actually recorded: the shifts they ran and the lateness those
            // shifts carry. A day with no `ShiftRecord` is a day with no evidence, not a
            // fault. When a real assignment calendar exists, an absence becomes
            // "scheduled shift that was not run" and belongs right here.
            let records = input.history.filter { $0.driverId == driverId && week.contains($0.startedAt) }
            let pending = records.reduce(0) { $0 + $1.pendingLateMinutes }

            if pending > 0 {
                return BonusWeekResult(week: week, status: .lost, detail: "Adeudo \(Fmt.lateText(pending)) sin pagar")
            }
            let lateTotal = records.reduce(0) { $0 + $1.lateMinutes }
            let detail = lateTotal > 0 ? "Atraso pagado \(Fmt.lateText(lateTotal))" : "Sin atrasos registrados"
            return BonusWeekResult(week: week, status: isRunning ? .inProgress : .achieved, detail: detail)

        case .billing:
            let earned = input.incomes
                .filter { $0.driverId == driverId && week.contains($0.date) }
                .reduce(0) { $0 + $1.amountMxn }
            let target = input.goals.weeklyMxn
            let detail = "\(Fmt.mxn(earned)) de \(Fmt.mxn(target))"
            if earned >= target {
                return BonusWeekResult(week: week, status: .achieved, detail: detail)
            }
            return BonusWeekResult(week: week, status: isRunning ? .inProgress : .lost, detail: detail)

        case .care:
            // A report is the only positive fact here, and it always loses the week.
            // Its absence clears the week only because the guard above already proved
            // there was an operation a supervisor could have reported on.
            let reports = input.reports.filter { week.contains($0.createdAt) }
            if let first = reports.first {
                return BonusWeekResult(week: week, status: .lost, detail: first.kind.label)
            }
            return BonusWeekResult(
                week: week,
                status: isRunning ? .inProgress : .achieved,
                detail: "Sin reportes del supervisor"
            )

        case .service:
            // No score, no verdict. Never substitute 0, 5.0 or the demonstration figure.
            guard let score = input.qualityScore else {
                return BonusWeekResult(week: week, status: .notEvaluated, detail: "Sin calificación de plataforma")
            }
            return BonusWeekResult(
                week: week,
                status: isRunning ? .inProgress : .achieved,
                detail: "Calificación \(Fmt.rating(score)) · API Uber"
            )
        }
    }

    // MARK: - Recovery program

    /// A weekday driver recovers on the weekend and the other way around.
    static func recoveryGroup(for driver: Driver) -> ShiftGroup {
        driver.group == .weekday ? .weekend : .weekday
    }

    static func recoveryDaysLabel(for driver: Driver) -> String {
        driver.group == .weekday ? "Sábado y domingo" : "Lunes a viernes"
    }

    static func isRecoveryDay(driver: Driver, date: Date) -> Bool {
        ShiftRules.group(for: date) == recoveryGroup(for: driver)
    }

    /// Bookable when it belongs to the opposite group and has not happened yet.
    static func canBook(driver: Driver, date: Date, now: Date) -> Bool {
        guard isRecoveryDay(driver: driver, date: date) else { return false }
        let calendar = ShiftRules.calendar
        return calendar.startOfDay(for: date) >= calendar.startOfDay(for: now)
    }
}
