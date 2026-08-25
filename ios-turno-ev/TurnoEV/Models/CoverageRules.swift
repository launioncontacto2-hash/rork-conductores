import Foundation

/// The engine behind cobertura de turnos: who is allowed to take a seat, in what order
/// they are offered it, and what the station's calendar looks like ahead.
///
/// Nothing here reads a preference, a friendship or a request from the titular. A seat is
/// offered by rule and ranked by workload and history.
nonisolated enum CoverageRules {
    // MARK: - Roster

    /// Everyone the engine may consider, taken from whatever environment is active. In
    /// test mode this is exactly what the laboratory created; in production, the seeded
    /// network. The module never keeps a roster of its own.
    static func roster(flags: [String: CoverageDriverFlags]) -> [CoverageDriverProfile] {
        let stations = StaffDirectory.stations
        return StaffDirectory.accounts
            .filter { $0.role == .driver && $0.status == .active }
            .compactMap { account in
                guard let stationId = account.stationId,
                      let station = stations.first(where: { $0.id == stationId }) else { return nil }
                let driverId = account.driverId ?? account.id
                let slot = account.slot ?? .morning
                return CoverageDriverProfile(
                    id: driverId,
                    name: account.name,
                    employeeNumber: account.employeeNumber,
                    stationId: stationId,
                    stationCode: station.code,
                    slot: slot,
                    group: LabRuntime.driver(id: account.driverId)?.group ?? .weekday,
                    flags: flags[driverId] ?? .clear
                )
            }
    }

    // MARK: - Regular schedule

    /// A driver holds their own block on the days of their group: weekday people run
    /// Monday to Friday, weekend people Saturday and Sunday.
    static func worksRegularly(_ profile: CoverageDriverProfile, on day: Date) -> Bool {
        ShiftRules.group(for: day) == profile.group
    }

    /// The block the person holds on a given day, if any.
    static func regularSlot(_ profile: CoverageDriverProfile, on day: Date) -> ShiftSlot? {
        worksRegularly(profile, on: day) ? profile.slot : nil
    }

    // MARK: - Eligibility

    /// Everything the engine needs to judge one person for one seat, gathered by the store.
    ///
    /// **Deliberately timeless.** Not one of the thirteen rules asks what time it is: every
    /// threshold is measured against the seat's own `scheduledStartAt` / `scheduledEndAt`
    /// and against stored facts — licence and vacation dates, held guards, weekly counters,
    /// flags. Whether the seat is next Tuesday or was yesterday changes nothing about
    /// *whether this person is allowed to take it*.
    ///
    /// It used to carry a `now` that no rule ever read. That dead field was load-bearing in
    /// the worst way: building it made the store read `CoverageStore.now` → `FleetStore.now`
    /// → `ClockSignal.generation`, so every caller of `evaluate` — including a tab badge —
    /// registered a dependency on the global clock and was invalidated by a hour it did not
    /// use. The urgency of a seat *is* time-dependent, and that lives where it belongs:
    /// `isEmergency(startAt:now:policy:)`, called by the store when a seat is opened.
    nonisolated struct EligibilityContext: Sendable {
        let policy: CoveragePolicy
        /// Guards the person already holds (reserved, approved or confirmed).
        let heldVacancies: [CoverageVacancy]
        /// Absences of this person already approved or in process.
        let openAbsences: [AbsenceRequest]
        /// Guards taken inside the same week as the seat.
        let guardsThisWeek: Int
        /// Own shifts plus guards inside the same week as the seat.
        let shiftsThisWeek: Int
        let reliability: CoverageReliability?
    }

    /// Runs the thirteen rules in the order the supervisor reads them.
    static func evaluate(
        profile: CoverageDriverProfile,
        vacancy: CoverageVacancy,
        context: EligibilityContext
    ) -> EligibilityVerdict {
        var checks: [EligibilityCheck] = []
        let policy = context.policy
        let start = vacancy.scheduledStartAt
        let end = vacancy.scheduledEndAt

        // Station
        let sameStation = profile.stationId == vacancy.stationId
        checks.append(
            EligibilityCheck(
                rule: .station,
                passed: sameStation || policy.allowsCrossStation,
                detail: sameStation
                    ? "Pertenece a \(vacancy.stationCode)"
                    : policy.allowsCrossStation
                        ? "Estación \(profile.stationCode), autorizada por política"
                        : "Pertenece a \(profile.stationCode), no a \(vacancy.stationCode)"
            )
        )

        // Employment / suspension
        checks.append(
            EligibilityCheck(
                rule: .employment,
                passed: true,
                detail: "Credencial activa en \(profile.stationCode)"
            )
        )
        checks.append(
            EligibilityCheck(
                rule: .notSuspended,
                passed: !profile.flags.isSuspended,
                detail: profile.flags.isSuspended ? "Suspendido por la estación" : "Sin suspensión vigente"
            )
        )

        // License
        let licenseOk = profile.flags.licenseValidUntil.map { $0 >= end } ?? true
        checks.append(
            EligibilityCheck(
                rule: .license,
                passed: licenseOk,
                detail: profile.flags.licenseValidUntil.map {
                    licenseOk
                        ? "Vigente hasta \(Fmt.dateShort($0))"
                        : "Vencida el \(Fmt.dateShort($0))"
                } ?? "Sin fecha de vencimiento registrada"
            )
        )

        // Documents
        checks.append(
            EligibilityCheck(
                rule: .documents,
                passed: profile.flags.documentsValid,
                detail: profile.flags.documentsValid ? "Expediente completo" : "Documentación vencida o incompleta"
            )
        )

        // Vacation
        let onVacation = profile.flags.vacationUntil.map { $0 >= start } ?? false
        checks.append(
            EligibilityCheck(
                rule: .notOnVacation,
                passed: !onVacation,
                detail: onVacation
                    ? "De vacaciones hasta \(Fmt.dateShort(profile.flags.vacationUntil ?? start))"
                    : "Sin vacaciones en esa fecha"
            )
        )

        // Incapacity
        let incapacitated = profile.flags.incapacityUntil.map { $0 >= start } ?? false
        checks.append(
            EligibilityCheck(
                rule: .notIncapacitated,
                passed: !incapacitated,
                detail: incapacitated
                    ? "Incapacidad hasta \(Fmt.dateShort(profile.flags.incapacityUntil ?? start))"
                    : "Sin incapacidad registrada"
            )
        )

        // Slot compatibility: the person may not be the titular of the same seat, and if
        // they already hold their own block that day it has to be the other one.
        let ownSlotThatDay = regularSlot(profile, on: vacancy.date)
        let isTitular = profile.id == vacancy.titularDriverId
        let slotCompatible = !isTitular && ownSlotThatDay != vacancy.slot
        checks.append(
            EligibilityCheck(
                rule: .slotCompatibility,
                passed: slotCompatible,
                detail: isTitular
                    ? "Es el titular del turno"
                    : ownSlotThatDay == vacancy.slot
                        ? "Ya tiene su propio turno \(vacancy.slot.label.lowercased()) ese día"
                        : "Turno \(vacancy.slot.label.lowercased()) compatible con su bloque"
            )
        )

        // No simultaneous shift: own block or another guard overlapping the window.
        let overlappingGuard = context.heldVacancies.first { held in
            held.id != vacancy.id && held.scheduledStartAt < end && start < held.scheduledEndAt
        }
        let ownBlockOverlaps: Bool = {
            guard let ownSlot = ownSlotThatDay else { return false }
            let ownStart = ShiftRules.scheduledStart(slot: ownSlot, on: vacancy.date)
            let ownEnd = ShiftRules.scheduledEnd(slot: ownSlot, on: vacancy.date)
            return ownStart < end && start < ownEnd
        }()
        checks.append(
            EligibilityCheck(
                rule: .noOverlap,
                passed: overlappingGuard == nil && !ownBlockOverlaps,
                detail: overlappingGuard != nil
                    ? "Ya tiene una guardia en ese horario"
                    : ownBlockOverlaps
                        ? "Su turno propio se encima con este horario"
                        : "El horario queda libre"
            )
        )

        // Rest between shifts
        let restHours = minimumRestGap(
            profile: profile,
            vacancy: vacancy,
            heldVacancies: context.heldVacancies
        )
        let restOk = restHours >= Double(policy.minimumRestHours)
        checks.append(
            EligibilityCheck(
                rule: .rest,
                passed: restOk,
                detail: restHours >= 999
                    ? "Sin jornada contigua"
                    : restOk
                        ? "\(Int(restHours)) h de descanso, mínimo \(policy.minimumRestHours) h"
                        : "Solo \(Int(restHours)) h entre jornadas, mínimo \(policy.minimumRestHours) h"
            )
        )

        // Weekly workload
        let loadOk = context.shiftsThisWeek < policy.maxShiftsPerWeek
        checks.append(
            EligibilityCheck(
                rule: .weeklyLoad,
                passed: loadOk,
                detail: "\(context.shiftsThisWeek) de \(policy.maxShiftsPerWeek) jornadas esa semana"
            )
        )

        // Guard load
        let guardOk = context.guardsThisWeek < policy.maxGuardsPerWeek
        checks.append(
            EligibilityCheck(
                rule: .guardLoad,
                passed: guardOk,
                detail: "\(context.guardsThisWeek) de \(policy.maxGuardsPerWeek) guardias esa semana"
            )
        )

        // No conflicting guard on the same day
        let sameDayGuard = context.heldVacancies.contains {
            $0.id != vacancy.id && ShiftRules.isSameDay($0.date, vacancy.date)
        }
        checks.append(
            EligibilityCheck(
                rule: .noConflictingGuard,
                passed: !sameDayGuard,
                detail: sameDayGuard ? "Ya tomó otra guardia ese día" : "Sin otra guardia ese día"
            )
        )

        let ranking = rank(
            profile: profile,
            vacancy: vacancy,
            guardsThisWeek: context.guardsThisWeek,
            reliability: context.reliability
        )

        return EligibilityVerdict(
            driverId: profile.id,
            driverName: profile.name,
            employeeNumber: profile.employeeNumber,
            checks: checks,
            score: ranking.score,
            priorityReason: ranking.reason
        )
    }

    /// Smallest gap in hours between this seat and any adjacent commitment.
    private static func minimumRestGap(
        profile: CoverageDriverProfile,
        vacancy: CoverageVacancy,
        heldVacancies: [CoverageVacancy]
    ) -> Double {
        let calendar = ShiftRules.calendar
        let start = vacancy.scheduledStartAt
        let end = vacancy.scheduledEndAt
        var windows: [(start: Date, end: Date)] = heldVacancies
            .filter { $0.id != vacancy.id }
            .map { ($0.scheduledStartAt, $0.scheduledEndAt) }

        // Own block the day before, that day and the day after.
        for offset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: vacancy.date),
                  let ownSlot = regularSlot(profile, on: day) else { continue }
            windows.append(
                (
                    ShiftRules.scheduledStart(slot: ownSlot, on: day),
                    ShiftRules.scheduledEnd(slot: ownSlot, on: day)
                )
            )
        }

        var gap = Double(999)
        for window in windows {
            if window.end <= start {
                gap = min(gap, start.timeIntervalSince(window.end) / 3600)
            } else if window.start >= end {
                gap = min(gap, window.start.timeIntervalSince(end) / 3600)
            } else {
                return 0
            }
        }
        return gap
    }

    // MARK: - Ranking

    /// Priority is built from four objective signals, in the order the network fixed:
    /// complementary group first, then declared availability, then who carries fewer
    /// guards, and last the completion history.
    private static func rank(
        profile: CoverageDriverProfile,
        vacancy: CoverageVacancy,
        guardsThisWeek: Int,
        reliability: CoverageReliability?
    ) -> (score: Double, reason: String) {
        var score: Double = 0
        var reasons: [String] = []

        if profile.group != vacancy.group {
            score += 40
            reasons.append("grupo complementario")
        }
        if profile.flags.acceptsExtraordinary {
            score += 25
            reasons.append("disponibilidad declarada")
        }
        let loadBonus = max(0, 20 - Double(guardsThisWeek) * 7)
        score += loadBonus
        if guardsThisWeek == 0 { reasons.append("sin guardias esta semana") }

        if let reliability, reliability.accepted > 0 {
            score += Double(reliability.score) * 0.15
            if reliability.score >= 85 { reasons.append("historial de cumplimiento") }
        }

        let reason = reasons.isEmpty ? "elegible" : reasons.joined(separator: " · ")
        return (score, reason)
    }

    // MARK: - Urgency

    /// An absence this close to the start is an emergency, whatever the driver picked.
    static func isEmergency(startAt: Date, now: Date, policy: CoveragePolicy) -> Bool {
        startAt.timeIntervalSince(now) / 3600 <= Double(policy.emergencyThresholdHours)
    }

    /// Text the station reads on a critical seat.
    static func urgencyLabel(hoursUntilStart: Double) -> String {
        if hoursUntilStart <= 0 { return "El turno ya empezó" }
        if hoursUntilStart < 1 { return "Faltan \(Int(hoursUntilStart * 60)) minutos" }
        if hoursUntilStart < 24 { return "Faltan \(Int(hoursUntilStart)) horas" }
        return "Faltan \(Int(hoursUntilStart / 24)) días"
    }

    // MARK: - Identifiers

    static func newId(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    /// Human label of a seat, reused across every screen and the audit trail.
    static func shiftLabel(date: Date, slot: ShiftSlot) -> String {
        "\(Fmt.dateShort(date)) · \(slot.label) \(slot.rangeLabel)"
    }
}
