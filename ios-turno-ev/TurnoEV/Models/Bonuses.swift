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

/// What the engine already decided about a bonus of the month. There is no pending
/// state on purpose: a bonus is either running, released or cancelled.
nonisolated enum BonusDecision: String, Sendable {
    case running
    case authorized
    case cancelled

    var label: String {
        switch self {
        case .running: "En evaluación"
        case .authorized: "Autorizado automáticamente"
        case .cancelled: "Cancelado automáticamente"
        }
    }

    var symbol: String {
        switch self {
        case .running: "circle.dotted"
        case .authorized: "checkmark.seal.fill"
        case .cancelled: "xmark.seal.fill"
        }
    }

    var detail: String {
        switch self {
        case .running: "Se libera solo si cierras las 4 semanas en verde."
        case .authorized: "Cumpliste las 4 semanas. Entra en el corte del mes sin que nadie lo firme."
        case .cancelled: "Una semana incumplida lo cancela. Nadie puede reactivarlo en la estación."
        }
    }
}

nonisolated enum BonusWeekStatus: String, Codable, Sendable {
    case achieved
    case lost
    case inProgress
    case upcoming

    var label: String {
        switch self {
        case .achieved: "Cumplida"
        case .lost: "Perdida"
        case .inProgress: "En curso"
        case .upcoming: "Por evaluar"
        }
    }

    var symbol: String {
        switch self {
        case .achieved: "checkmark"
        case .lost: "xmark"
        case .inProgress: "circle.dotted"
        case .upcoming: "minus"
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

    /// Amount of this bonus with the amounts the national administration has in force.
    var monthlyMxn: Int { schedule.amountMxn(for: kind) }

    /// Money actually payable at month end with the current evaluation.
    var payableMxn: Int { isLost ? 0 : monthlyMxn }

    /// The engine's own verdict. No signature exists anywhere in this flow.
    var decision: BonusDecision {
        if isLost { return .cancelled }
        if isSecured { return .authorized }
        return .running
    }

    var statusText: String {
        if isLost { return "Perdido · semana \(lostWeeks.map(String.init).joined(separator: ", "))" }
        if isSecured { return "Asegurado" }
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

    /// Uber quality score is mocked as positive until the API is connected.
    static let mockQualityScore = 4.91

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

    /// Days of the week the driver was scheduled to work and that already finished.
    static func expectedWorkDays(driver: Driver, week: BonusWeekRange, now: Date) -> Int {
        let calendar = ShiftRules.calendar
        var count = 0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { continue }
            guard ShiftRules.group(for: day) == driver.group else { continue }
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day), dayEnd <= now else { continue }
            count += 1
        }
        return count
    }

    struct EvaluationInput: Sendable {
        let driver: Driver
        let goals: ShiftRules.Goals
        let history: [ShiftRecord]
        let incomes: [IncomeEntry]
        let reports: [SupervisorReport]
        let schedule: BonusSchedule
        let now: Date
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

        let isRunning = week.contains(input.now)

        switch kind {
        case .punctuality:
            let records = input.history.filter { week.contains($0.startedAt) }
            let pending = records.reduce(0) { $0 + $1.pendingLateMinutes }
            let expected = expectedWorkDays(driver: input.driver, week: week, now: input.now)
            let absences = max(0, expected - records.count)

            if absences > 0 {
                let text = absences == 1 ? "1 falta registrada" : "\(absences) faltas registradas"
                return BonusWeekResult(week: week, status: .lost, detail: text)
            }
            if pending > 0 {
                return BonusWeekResult(week: week, status: .lost, detail: "Adeudo \(Fmt.lateText(pending)) sin pagar")
            }
            let lateTotal = records.reduce(0) { $0 + $1.lateMinutes }
            let detail = lateTotal > 0 ? "Atraso pagado \(Fmt.lateText(lateTotal))" : "Sin atrasos"
            return BonusWeekResult(week: week, status: isRunning ? .inProgress : .achieved, detail: detail)

        case .billing:
            let earned = input.incomes.filter { week.contains($0.date) }.reduce(0) { $0 + $1.amountMxn }
            let target = input.goals.weeklyMxn
            let detail = "\(Fmt.mxn(earned)) de \(Fmt.mxn(target))"
            if earned >= target {
                return BonusWeekResult(week: week, status: .achieved, detail: detail)
            }
            return BonusWeekResult(week: week, status: isRunning ? .inProgress : .lost, detail: detail)

        case .care:
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
            // Mocked positive until the Uber quality API is available.
            return BonusWeekResult(
                week: week,
                status: isRunning ? .inProgress : .achieved,
                detail: "Calificación \(Fmt.rating(mockQualityScore)) · API Uber"
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
