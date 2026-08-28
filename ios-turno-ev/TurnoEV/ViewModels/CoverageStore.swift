import Foundation
import Observation

/// Shared source of truth for cobertura de turnos. Every role reads and writes the same
/// board: the driver asks for an absence, the engine opens the seat, other drivers claim
/// it, the supervisor signs, and Human Resources reads the trace.
///
/// The module starts completely empty on purpose. It never seeds itself — data arrives
/// from the laboratory or from real use, and the test and production worlds stay apart.
@Observable
final class CoverageStore {
    // MARK: - Persisted shape

    nonisolated private struct PersistedState: Codable, Sendable {
        var policy: CoveragePolicy
        var flags: [String: CoverageDriverFlags]
        var absences: [AbsenceRequest]
        var vacancies: [CoverageVacancy]
        var swaps: [ShiftSwapRequest]
        var audit: [CoverageAuditEntry]
        var notifications: [CoverageNotification]
    }

    private static let storageKey = "turnoev.coverage.v1"

    // MARK: - State

    var policy: CoveragePolicy = .standard
    /// Status of each person that can block a guard, written by the laboratory.
    var flags: [String: CoverageDriverFlags] = [:]
    var absences: [AbsenceRequest] = []
    var vacancies: [CoverageVacancy] = []
    var swaps: [ShiftSwapRequest] = []
    /// Append-only. Nothing in the app rewrites or removes an entry.
    private(set) var audit: [CoverageAuditEntry] = []
    var notifications: [CoverageNotification] = []

    private var fleet: FleetStore?

    /// Capability fixed at construction, used by tests to exercise a session state
    /// without standing up a whole `FleetStore`. `nil` means "ask the attached session",
    /// which is what the app always does.
    private let pinnedCapability: CoordinationCapability?

    /// Where the board is stored. The app passes `.standard` and writes the one key it
    /// has always written; an isolated suite keeps a test from touching a real board.
    private let defaults: UserDefaults

    init(capability: CoordinationCapability? = nil, defaults: UserDefaults = .standard) {
        self.pinnedCapability = capability
        self.defaults = defaults
        load()
    }

    /// Links the driver app so a decision here can raise a notice there.
    func attach(fleet: FleetStore) {
        self.fleet = fleet
    }

    // MARK: - Coordination boundary

    /// What this session may do with the shared board.
    ///
    /// Resolved through the session on every read rather than cached at `attach`: the
    /// session changes when somebody signs in or out, and a snapshot taken at launch
    /// would answer for whoever happened to be there first.
    ///
    /// An unattached store answers `.localWorkflow`. That is the laboratory and the
    /// previews, where there is no proved identity to protect — the app itself always
    /// attaches, in `TurnoEVApp`.
    var coordination: CoordinationCapability {
        if let pinnedCapability { return pinnedCapability }
        guard let fleet else { return .localWorkflow }
        return fleet.coordinationCapability
    }

    var canCoordinateLocally: Bool { coordination.allowsLocalWorkflow }

    var now: Date { fleet?.now ?? Date() }

    var isEmpty: Bool {
        absences.isEmpty && vacancies.isEmpty && swaps.isEmpty
    }

    // MARK: - Roster

    var roster: [CoverageDriverProfile] { CoverageRules.roster(flags: flags) }

    func roster(stationId: String?) -> [CoverageDriverProfile] {
        guard let stationId else { return roster }
        return roster.filter { $0.stationId == stationId }
    }

    func profile(id: String?) -> CoverageDriverProfile? {
        guard let id else { return nil }
        return roster.first { $0.id == id }
    }

    /// Reads the profile of the driver holding the current session, even when the
    /// environment has not registered them in the roster yet.
    ///
    /// A session the station cannot reach never adopts a directory entry, even when the
    /// identifiers line up. The roster is the demonstration directory; matching an id
    /// against it would hand a proved identity somebody else's declared block — the same
    /// mistake as trusting a driver id alone to decide whose money a ledger holds.
    func profile(for driver: Driver) -> CoverageDriverProfile {
        if canCoordinateLocally, let known = profile(id: driver.id) { return known }
        return CoverageDriverProfile(
            id: driver.id,
            name: driver.name,
            employeeNumber: driver.employeeNumber,
            stationId: driver.stationId,
            stationCode: StaffDirectory.station(id: driver.stationId)?.code ?? driver.station,
            slot: driver.slot,
            group: driver.group,
            scheduleKnowledge: canCoordinateLocally ? .declaredBlock : .unpublished,
            flags: flags[driver.id] ?? .clear
        )
    }

    // MARK: - Reads

    /// Requests this session may read as its own.
    ///
    /// Everything on this board was written by this device. For a session the station
    /// cannot reach, none of it belongs to the person holding it, however the ids line
    /// up — so the answer is empty rather than somebody else's paperwork relabelled.
    func absences(driverId: String) -> [AbsenceRequest] {
        guard canCoordinateLocally else { return [] }
        return absences.filter { $0.driverId == driverId }.sorted { $0.createdAt > $1.createdAt }
    }

    func absences(stationId: String) -> [AbsenceRequest] {
        absences.filter { $0.stationId == stationId }.sorted { $0.date < $1.date }
    }

    func absence(id: String?) -> AbsenceRequest? {
        guard let id else { return nil }
        return absences.first { $0.id == id }
    }

    func vacancy(id: String?) -> CoverageVacancy? {
        guard let id else { return nil }
        return vacancies.first { $0.id == id }
    }

    func vacancies(stationId: String) -> [CoverageVacancy] {
        vacancies.filter { $0.stationId == stationId }.sorted { $0.scheduledStartAt < $1.scheduledStartAt }
    }

    func openVacancies(stationId: String) -> [CoverageVacancy] {
        vacancies(stationId: stationId).filter { $0.status == .searching }
    }

    /// Seats with a candidate waiting for the supervisor's signature.
    func vacanciesAwaitingApproval(stationId: String) -> [CoverageVacancy] {
        vacancies(stationId: stationId).filter { $0.status == .reserved }
    }

    func confirmedVacancies(stationId: String) -> [CoverageVacancy] {
        vacancies(stationId: stationId).filter { $0.status == .confirmed }
    }

    func criticalVacancies(stationId: String) -> [CoverageVacancy] {
        vacancies(stationId: stationId).filter { $0.isCritical && $0.status.isOpen }
    }

    func history(stationId: String) -> [CoverageVacancy] {
        vacancies.filter { $0.stationId == stationId && !$0.status.isOpen }
            .sorted { $0.scheduledStartAt > $1.scheduledStartAt }
    }

    /// Guards this person holds, whatever their state.
    func guards(driverId: String) -> [CoverageVacancy] {
        guard canCoordinateLocally else { return [] }
        return vacancies
            .filter { vacancy in vacancy.claims.contains { $0.driverId == driverId } }
            .sorted { $0.scheduledStartAt > $1.scheduledStartAt }
    }

    /// Guards this person is currently committed to.
    func activeGuards(driverId: String) -> [CoverageVacancy] {
        guard canCoordinateLocally else { return [] }
        return vacancies.filter { vacancy in
            (vacancy.status == .reserved || vacancy.status == .confirmed)
                && vacancy.holder?.driverId == driverId
        }
    }

    func swaps(driverId: String) -> [ShiftSwapRequest] {
        guard canCoordinateLocally else { return [] }
        return swaps.filter { $0.fromDriverId == driverId || $0.toDriverId == driverId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func swaps(stationId: String) -> [ShiftSwapRequest] {
        swaps.filter { $0.stationId == stationId }.sorted { $0.createdAt > $1.createdAt }
    }

    func auditTrail(stationCode: String? = nil) -> [CoverageAuditEntry] {
        let entries = audit.sorted { $0.createdAt > $1.createdAt }
        guard let stationCode else { return entries }
        return entries.filter { $0.stationCode == stationCode }
    }

    func notifications(for recipientId: String) -> [CoverageNotification] {
        notifications.filter { $0.recipientId == recipientId }.sorted { $0.createdAt > $1.createdAt }
    }

    func unreadCount(for recipientId: String) -> Int {
        notifications.filter { $0.recipientId == recipientId && !$0.isRead }.count
    }

    // MARK: - Guards offered to one person

    /// Seats this person may actually take. Nothing that fails a rule is ever shown, so
    /// nobody is offered work they cannot legally accept.
    func availableGuards(for profile: CoverageDriverProfile) -> [(vacancy: CoverageVacancy, verdict: EligibilityVerdict)] {
        // Every seat here was opened on this phone. Offering one as work a proved driver
        // may take — with a bonus figure attached — would be inventing an assignment the
        // station never published, and the take would refuse anyway.
        guard canCoordinateLocally else { return [] }
        return vacancies
            .filter { $0.status == .searching }
            .filter { !$0.isClaimed(by: profile.id) }
            .map { (vacancy: $0, verdict: evaluate(profile: profile, vacancy: $0)) }
            .filter(\.verdict.isEligible)
            .sorted { lhs, rhs in
                if lhs.vacancy.isCritical != rhs.vacancy.isCritical { return lhs.vacancy.isCritical }
                return lhs.vacancy.scheduledStartAt < rhs.vacancy.scheduledStartAt
            }
    }

    /// Ranked candidate list of a seat, used by the supervisor and by the search itself.
    func candidates(for vacancy: CoverageVacancy) -> [EligibilityVerdict] {
        let pool = policy.allowsCrossStation ? roster : roster(stationId: vacancy.stationId)
        return pool
            .map { evaluate(profile: $0, vacancy: vacancy) }
            .sorted { lhs, rhs in
                if lhs.isEligible != rhs.isEligible { return lhs.isEligible }
                return lhs.score > rhs.score
            }
    }

    func eligibleCandidates(for vacancy: CoverageVacancy) -> [EligibilityVerdict] {
        candidates(for: vacancy).filter(\.isEligible)
    }

    /// Runs the whole rule set for one person against one seat.
    func evaluate(profile: CoverageDriverProfile, vacancy: CoverageVacancy) -> EligibilityVerdict {
        CoverageRules.evaluate(profile: profile, vacancy: vacancy, context: context(for: profile, vacancy: vacancy))
    }

    /// Gathers the facts one verdict needs.
    ///
    /// Reads only observable collections — `vacancies`, `absences`, `policy`, `flags` — and
    /// never `now`. That is what keeps `evaluate` off the clock: see the note on
    /// `EligibilityContext`.
    private func context(for profile: CoverageDriverProfile, vacancy: CoverageVacancy) -> CoverageRules.EligibilityContext {
        let held = vacancies.filter { candidate in
            (candidate.status == .reserved || candidate.status == .confirmed)
                && candidate.holder?.driverId == profile.id
        }
        let guardsThisWeek = held.filter { ShiftRules.isInSameWeek($0.date, as: vacancy.date) }.count

        let calendar = ShiftRules.calendar
        let weekStart = ShiftRules.weekStart(for: vacancy.date)
        let regularDays = (0..<7).compactMap { offset -> Date? in
            calendar.date(byAdding: .day, value: offset, to: weekStart)
        }
        .filter { CoverageRules.worksRegularly(profile, on: $0) }
        .filter { day in
            !absences.contains {
                $0.driverId == profile.id && $0.status == .approved && ShiftRules.isSameDay($0.date, day)
            }
        }
        .count

        return CoverageRules.EligibilityContext(
            policy: policy,
            heldVacancies: held,
            openAbsences: absences.filter { $0.driverId == profile.id && $0.status.isOpen },
            guardsThisWeek: guardsThisWeek,
            shiftsThisWeek: regularDays + guardsThisWeek,
            reliability: reliability(driverId: profile.id)
        )
    }

    // MARK: - Reliability

    func reliability(driverId: String) -> CoverageReliability? {
        let taken = vacancies.filter { vacancy in
            vacancy.claims.contains { $0.driverId == driverId && $0.status != .waitlisted }
        }
        guard !taken.isEmpty else { return nil }
        let name = profile(id: driverId)?.name ?? taken.first?.substituteName ?? "—"
        return CoverageReliability(
            driverId: driverId,
            driverName: name,
            accepted: taken.count,
            completed: taken.filter { $0.status == .completed }.count,
            cancelled: taken.filter { vacancy in
                vacancy.claims.contains { $0.driverId == driverId && $0.status == .cancelled }
            }.count,
            noShows: taken.filter { $0.status == .noShow && $0.claims.contains { $0.driverId == driverId } }.count,
            lateStarts: 0
        )
    }

    func reliabilityBoard(stationId: String) -> [CoverageReliability] {
        roster(stationId: stationId).compactMap { reliability(driverId: $0.id) }
            .sorted { $0.score > $1.score }
    }

    // MARK: - Absences

    /// The driver asks. Nothing is authorized by this call: it opens the request and, if
    /// the seat needs somebody, the vacancy that will look for a substitute.
    ///
    /// The refusal comes first, before the request, the vacancy, the audit line, the
    /// supervisor alert and the driver's own notice bell. A request that stops halfway
    /// through that sequence is worse than one that never started.
    @discardableResult
    func requestAbsence(
        driver: CoverageDriverProfile,
        date: Date,
        slot: ShiftSlot,
        kind: AbsenceKind,
        reason: String,
        comments: String,
        evidence: Data?,
        vehicleNumber: String? = nil
    ) throws -> AbsenceRequest {
        guard canCoordinateLocally else { throw CoordinationMutationError.stationRequired }

        let day = ShiftRules.calendar.startOfDay(for: date)
        let start = ShiftRules.scheduledStart(slot: slot, on: day)
        let isUrgent = kind.isUrgent || CoverageRules.isEmergency(startAt: start, now: now, policy: policy)

        var request = AbsenceRequest(
            id: CoverageRules.newId("aus"),
            driverId: driver.id,
            driverName: driver.name,
            employeeNumber: driver.employeeNumber,
            stationId: driver.stationId,
            stationCode: driver.stationCode,
            date: day,
            slot: slot,
            kind: isUrgent && kind == .scheduled ? .emergency : kind,
            reason: reason,
            comments: comments,
            evidence: evidence,
            status: .requested,
            createdAt: now,
            vacancyId: nil,
            decidedAt: nil,
            decidedBy: nil,
            decisionNote: nil
        )

        // The gap is detected on its own: station, date, window, titular and unit.
        let vacancy = CoverageVacancy(
            id: CoverageRules.newId("vac"),
            stationId: driver.stationId,
            stationCode: driver.stationCode,
            date: day,
            slot: slot,
            origin: .absence,
            titularDriverId: driver.id,
            titularName: driver.name,
            vehicleId: nil,
            vehicleNumber: vehicleNumber,
            bonusMode: .fixed,
            bonusMxn: policy.defaultBonusMxn,
            reason: reason.isEmpty ? request.kind.label : reason,
            status: .searching,
            absenceRequestId: request.id,
            claims: [],
            approvedBy: nil,
            approvedAt: nil,
            rejectionNote: nil,
            isCritical: isUrgent,
            createdAt: now,
            createdBy: driver.name
        )

        request.vacancyId = vacancy.id
        request.status = .searching
        absences.insert(request, at: 0)
        vacancies.insert(vacancy, at: 0)

        record(
            actor: "\(driver.name) · \(driver.employeeNumber)",
            role: .driver,
            action: isUrgent ? "Ausencia de emergencia" : "Solicitud de ausencia",
            stationCode: driver.stationCode,
            shift: CoverageRules.shiftLabel(date: day, slot: slot),
            from: "—",
            to: AbsenceStatus.searching.label,
            detail: "\(request.kind.label). Motivo: \(reason.isEmpty ? "sin especificar" : reason)."
        )

        offerGuard(vacancy: vacancy, urgent: isUrgent)

        if isUrgent {
            notifySupervisors(
                stationId: driver.stationId,
                kind: .criticalCoverage,
                title: "Alerta crítica de cobertura",
                body: "\(driver.name) no puede cubrir \(CoverageRules.shiftLabel(date: day, slot: slot)). \(CoverageRules.urgencyLabel(hoursUntilStart: start.timeIntervalSince(now) / 3600)).",
                vacancyId: vacancy.id
            )
        }

        persist()
        return request
    }

    /// The driver withdraws their own request while it is still open.
    func cancelAbsence(id: String, by actor: String) throws {
        guard canCoordinateLocally else { throw CoordinationMutationError.stationRequired }
        guard let index = absences.firstIndex(where: { $0.id == id }), absences[index].status.isOpen else { return }
        let previous = absences[index].status
        absences[index].status = .cancelled
        absences[index].decidedAt = now
        absences[index].decidedBy = actor

        if let vacancyId = absences[index].vacancyId,
           let vIndex = vacancies.firstIndex(where: { $0.id == vacancyId }),
           vacancies[vIndex].status.isOpen {
            vacancies[vIndex].status = .cancelled
            let vacancy = vacancies[vIndex]
            // Whoever had already taken the seat has to know it no longer exists.
            for claim in vacancy.claims where claim.status == .reserved || claim.status == .approved || claim.status == .waitlisted {
                push(
                    to: claim.driverId,
                    kind: .guardCancelled,
                    title: "Guardia cancelada",
                    body: "El titular retiró su solicitud para \(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot))."
                )
            }
        }

        record(
            actor: actor,
            role: .driver,
            action: "Cancelación de solicitud",
            stationCode: absences[index].stationCode,
            shift: CoverageRules.shiftLabel(date: absences[index].date, slot: absences[index].slot),
            from: previous.label,
            to: AbsenceStatus.cancelled.label,
            detail: "El titular retiró la solicitud antes de la resolución."
        )
        persist()
    }

    /// Coverage and authorization are separate: this is the second decision, taken by a
    /// supervisor over the absence itself, never by finding a substitute.
    func decideAbsence(id: String, approved: Bool, note: String, by actor: StaffAccount) {
        guard let index = absences.firstIndex(where: { $0.id == id }) else { return }
        let previous = absences[index].status
        absences[index].status = approved ? .approved : .rejected
        absences[index].decidedAt = now
        absences[index].decidedBy = "\(actor.name) · \(actor.employeeNumber)"
        absences[index].decisionNote = note

        let request = absences[index]
        record(
            actor: "\(actor.name) · \(actor.employeeNumber)",
            role: actor.role,
            action: approved ? "Autorización de ausencia" : "Ausencia no autorizada",
            stationCode: request.stationCode,
            shift: CoverageRules.shiftLabel(date: request.date, slot: request.slot),
            from: previous.label,
            to: request.status.label,
            detail: note.isEmpty ? "Sin nota." : note
        )

        push(
            to: request.driverId,
            kind: approved ? .absenceApproved : .absenceRejected,
            title: approved ? "Ausencia aprobada" : "Ausencia no autorizada",
            body: approved
                ? "Tu ausencia del \(Fmt.dateShort(request.date)) quedó autorizada."
                : "Tu ausencia del \(Fmt.dateShort(request.date)) no fue autorizada. \(note)"
        )
        persist()
    }

    // MARK: - Vacancies

    /// A seat opened by the station with no absence behind it: extra demand, an event, an
    /// additional unit or preventive cover.
    @discardableResult
    func createExtraordinaryVacancy(
        station: Station,
        date: Date,
        slot: ShiftSlot,
        seats: Int,
        bonusMode: GuardBonusMode,
        bonusMxn: Int,
        reason: String,
        by actor: StaffAccount
    ) -> [CoverageVacancy] {
        let day = ShiftRules.calendar.startOfDay(for: date)
        var created: [CoverageVacancy] = []

        for _ in 0..<max(1, seats) {
            let vacancy = CoverageVacancy(
                id: CoverageRules.newId("vac"),
                stationId: station.id,
                stationCode: station.code,
                date: day,
                slot: slot,
                origin: .extraordinary,
                titularDriverId: nil,
                titularName: nil,
                vehicleId: nil,
                vehicleNumber: nil,
                bonusMode: bonusMode,
                bonusMxn: bonusMode == .none ? 0 : bonusMxn,
                reason: reason,
                status: .searching,
                absenceRequestId: nil,
                claims: [],
                approvedBy: nil,
                approvedAt: nil,
                rejectionNote: nil,
                isCritical: CoverageRules.isEmergency(startAt: ShiftRules.scheduledStart(slot: slot, on: day), now: now, policy: policy),
                createdAt: now,
                createdBy: actor.name
            )
            vacancies.insert(vacancy, at: 0)
            created.append(vacancy)
            offerGuard(vacancy: vacancy, urgent: vacancy.isCritical)
        }

        record(
            actor: "\(actor.name) · \(actor.employeeNumber)",
            role: actor.role,
            action: "Cobertura extraordinaria",
            stationCode: station.code,
            shift: CoverageRules.shiftLabel(date: day, slot: slot),
            from: "—",
            to: VacancyStatus.searching.label,
            detail: "\(max(1, seats)) plaza(s). Motivo: \(reason). \(bonusMode.label)\(bonusMode == .none ? "" : " de \(Fmt.mxn(bonusMxn))")."
        )
        persist()
        return created
    }

    /// Offers the seat to everyone eligible, in priority order. Nobody is assigned here:
    /// the offer is an invitation, the reservation happens when somebody takes it.
    private func offerGuard(vacancy: CoverageVacancy, urgent: Bool) {
        let eligible = eligibleCandidates(for: vacancy)
        guard !eligible.isEmpty else {
            markUncovered(vacancyId: vacancy.id, reason: "El motor no encontró conductores elegibles.")
            return
        }

        for candidate in eligible {
            push(
                to: candidate.driverId,
                kind: .guardAvailable,
                title: urgent ? "Guardia urgente disponible" : "Guardia disponible",
                body: "\(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot)) en \(vacancy.stationCode). \(vacancy.bonusMode == .none ? "Sin bono." : "Bono \(Fmt.mxn(vacancy.bonusMxn)).")",
                vacancyId: vacancy.id
            )
        }
    }

    /// Closes a seat nobody eligible can take. The absence stays without coverage, which
    /// is exactly what the station needs to see.
    func markUncovered(vacancyId: String, reason: String) {
        guard let index = vacancies.firstIndex(where: { $0.id == vacancyId }) else { return }
        let previous = vacancies[index].status
        vacancies[index].status = .uncovered
        let vacancy = vacancies[index]

        if let absenceId = vacancy.absenceRequestId,
           let aIndex = absences.firstIndex(where: { $0.id == absenceId }) {
            absences[aIndex].status = .uncovered
            push(
                to: absences[aIndex].driverId,
                kind: .absenceUncovered,
                title: "Tu turno sigue sin cobertura",
                body: "Ningún conductor elegible tomó \(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot)). Tu ausencia no está autorizada."
            )
        }

        notifySupervisors(
            stationId: vacancy.stationId,
            kind: .absenceUncovered,
            title: "Turno sin candidatos",
            body: "\(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot)) en \(vacancy.stationCode). \(reason)",
            vacancyId: vacancy.id
        )

        record(
            actor: "Sistema de cobertura",
            role: .supervisor,
            action: "Sin candidatos elegibles",
            stationCode: vacancy.stationCode,
            shift: CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot),
            from: previous.label,
            to: VacancyStatus.uncovered.label,
            detail: reason
        )
        persist()
    }

    // MARK: - Claims

    nonisolated enum ClaimOutcome: Sendable {
        case reserved
        case waitlisted(position: Int)
        case notEligible([EligibilityCheck])
        case unavailable(String)
        /// The seat cannot be held from here at all: taking it is an agreement with a
        /// station, and this session has no way to reach one. Kept apart from
        /// `notEligible`, which says the person fails a rule — nobody fails anything here.
        case stationRequired

        var isSuccess: Bool {
            switch self {
            case .reserved, .waitlisted: true
            case .notEligible, .unavailable, .stationRequired: false
            }
        }
    }

    /// Taking a guard re-runs the whole rule set: the person's situation may have changed
    /// since the offer went out. Two people can never end up holding the same seat.
    @discardableResult
    func claimGuard(vacancyId: String, by profile: CoverageDriverProfile) -> ClaimOutcome {
        guard canCoordinateLocally else { return .stationRequired }
        guard let index = vacancies.firstIndex(where: { $0.id == vacancyId }) else {
            return .unavailable("Esta guardia ya no existe.")
        }
        let vacancy = vacancies[index]
        guard vacancy.status == .searching || vacancy.status == .reserved else {
            return .unavailable("Esta guardia ya no está disponible.")
        }
        guard !vacancy.isClaimed(by: profile.id) else {
            return .unavailable("Ya estás anotado en esta guardia.")
        }

        let verdict = evaluate(profile: profile, vacancy: vacancy)
        guard verdict.isEligible else {
            record(
                actor: "\(profile.name) · \(profile.employeeNumber)",
                role: .driver,
                action: "Intento de tomar guardia rechazado",
                stationCode: vacancy.stationCode,
                shift: CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot),
                from: vacancy.status.label,
                to: vacancy.status.label,
                detail: "No cumple: \(verdict.blockerSummary)."
            )
            persist()
            return .notEligible(verdict.blockers)
        }

        // The seat is held by whoever arrives first; the rest queue in order.
        let alreadyHeld = vacancies[index].holder != nil
        let claim = CoverageClaim(
            id: CoverageRules.newId("cl"),
            driverId: profile.id,
            driverName: profile.name,
            employeeNumber: profile.employeeNumber,
            claimedAt: now,
            status: alreadyHeld ? .waitlisted : .reserved,
            note: nil
        )
        vacancies[index].claims.append(claim)

        if !alreadyHeld {
            vacancies[index].status = .reserved
            if let absenceId = vacancy.absenceRequestId,
               let aIndex = absences.firstIndex(where: { $0.id == absenceId }) {
                absences[aIndex].status = .covered
            }
            notifySupervisors(
                stationId: vacancy.stationId,
                kind: .guardAvailable,
                title: "Reemplazo propuesto",
                body: "\(profile.name) tomó \(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot)). Falta tu aprobación.",
                vacancyId: vacancy.id
            )
        }

        record(
            actor: "\(profile.name) · \(profile.employeeNumber)",
            role: .driver,
            action: alreadyHeld ? "Anotado en lista de espera" : "Guardia reservada",
            stationCode: vacancy.stationCode,
            shift: CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot),
            from: vacancy.status.label,
            to: alreadyHeld ? ClaimStatus.waitlisted.label : VacancyStatus.reserved.label,
            detail: alreadyHeld
                ? "La plaza ya estaba reservada; queda en espera por si se libera."
                : "Elegibilidad revalidada al momento de tomarla."
        )
        persist()

        if alreadyHeld {
            let position = vacancies[index].waitlist.firstIndex { $0.driverId == profile.id }.map { $0 + 1 } ?? 1
            return .waitlisted(position: position)
        }
        return .reserved
    }

    /// The person who took the guard gives it back. A confirmed seat reopens immediately
    /// and, if somebody is waiting, it goes straight to them.
    func cancelClaim(vacancyId: String, driverId: String, reason: String) throws {
        guard canCoordinateLocally else { throw CoordinationMutationError.stationRequired }
        guard let index = vacancies.firstIndex(where: { $0.id == vacancyId }) else { return }
        guard let claimIndex = vacancies[index].claims.firstIndex(where: {
            $0.driverId == driverId && ($0.status == .reserved || $0.status == .approved || $0.status == .waitlisted)
        }) else { return }

        let wasHolder = vacancies[index].claims[claimIndex].status != .waitlisted
        let previousStatus = vacancies[index].status
        let hoursAhead = vacancies[index].hoursUntilStart(now: now)
        vacancies[index].claims[claimIndex].status = .cancelled
        vacancies[index].claims[claimIndex].note = reason

        let vacancy = vacancies[index]
        record(
            actor: "\(vacancy.claims[claimIndex].driverName) · \(vacancy.claims[claimIndex].employeeNumber)",
            role: .driver,
            action: "Cancelación de guardia",
            stationCode: vacancy.stationCode,
            shift: CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot),
            from: previousStatus.label,
            to: wasHolder ? VacancyStatus.searching.label : ClaimStatus.cancelled.label,
            detail: "Anticipación de \(CoverageRules.urgencyLabel(hoursUntilStart: hoursAhead)). Motivo: \(reason.isEmpty ? "sin especificar" : reason)."
        )

        guard wasHolder else {
            persist()
            return
        }

        notifySupervisors(
            stationId: vacancy.stationId,
            kind: .guardCancelled,
            title: "Guardia cancelada",
            body: "\(vacancy.claims[claimIndex].driverName) canceló \(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot)). \(CoverageRules.urgencyLabel(hoursUntilStart: hoursAhead)).",
            vacancyId: vacancy.id
        )

        // The waiting list is the point: offer it to the next one instead of restarting.
        if let nextIndex = vacancies[index].claims.firstIndex(where: { $0.status == .waitlisted }) {
            vacancies[index].claims[nextIndex].status = .reserved
            vacancies[index].status = .reserved
            let next = vacancies[index].claims[nextIndex]
            push(
                to: next.driverId,
                kind: .guardAvailable,
                title: "La guardia pasó a ti",
                body: "Se liberó \(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot)). Queda reservada a tu nombre, pendiente de aprobación.",
                vacancyId: vacancy.id
            )
        } else {
            vacancies[index].status = .searching
            vacancies[index].approvedBy = nil
            vacancies[index].approvedAt = nil
            if let absenceId = vacancy.absenceRequestId,
               let aIndex = absences.firstIndex(where: { $0.id == absenceId }),
               absences[aIndex].status.isOpen {
                absences[aIndex].status = .searching
            }
            offerGuard(vacancy: vacancies[index], urgent: vacancies[index].isCritical)
        }
        persist()
    }

    // MARK: - Supervisor decisions

    /// The signature that turns a reservation into a commitment. Both calendars, the
    /// station board and the bonus follow from here.
    @discardableResult
    func approveVacancy(id: String, by actor: StaffAccount, note: String = "") -> Bool {
        guard let index = vacancies.firstIndex(where: { $0.id == id }),
              vacancies[index].status == .reserved,
              let holderIndex = vacancies[index].claims.firstIndex(where: { $0.status == .reserved })
        else { return false }

        vacancies[index].claims[holderIndex].status = .approved
        vacancies[index].status = .confirmed
        vacancies[index].approvedBy = "\(actor.name) · \(actor.employeeNumber)"
        vacancies[index].approvedAt = now
        let vacancy = vacancies[index]
        let substitute = vacancy.claims[holderIndex]

        // The absence advances only up to "pending authorization": covering the seat is
        // never the same as excusing the person.
        if let absenceId = vacancy.absenceRequestId,
           let aIndex = absences.firstIndex(where: { $0.id == absenceId }) {
            absences[aIndex].status = policy.absenceRequiresAuthorization ? .awaitingAuthorization : .approved
            push(
                to: absences[aIndex].driverId,
                kind: .absenceProcessed,
                title: "Tu solicitud fue procesada",
                body: "Tu solicitud para el \(Fmt.dateShort(vacancy.date)) fue procesada. La cobertura fue asignada a \(substitute.driverName)."
            )
        }

        push(
            to: substitute.driverId,
            kind: .guardConfirmed,
            title: "Guardia confirmada",
            body: "\(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot)) en \(vacancy.stationCode).",
            vacancyId: vacancy.id
        )

        record(
            actor: "\(actor.name) · \(actor.employeeNumber)",
            role: actor.role,
            action: "Aprobación de reemplazo",
            stationCode: vacancy.stationCode,
            shift: CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot),
            from: VacancyStatus.reserved.label,
            to: VacancyStatus.confirmed.label,
            detail: "Sustituto \(substitute.driverName) · \(substitute.employeeNumber). \(vacancy.bonusMode == .none ? "Sin bono." : "Bono \(Fmt.mxn(vacancy.bonusMxn)) al completar el turno.") \(note)"
        )
        persist()
        return true
    }

    /// The supervisor turns down the proposed substitute. The seat returns to the pool.
    func rejectSubstitute(vacancyId: String, by actor: StaffAccount, reason: String) {
        guard let index = vacancies.firstIndex(where: { $0.id == vacancyId }),
              let holderIndex = vacancies[index].claims.firstIndex(where: { $0.status == .reserved })
        else { return }

        let rejected = vacancies[index].claims[holderIndex]
        vacancies[index].claims[holderIndex].status = .rejected
        vacancies[index].claims[holderIndex].note = reason
        vacancies[index].rejectionNote = reason
        let vacancy = vacancies[index]

        push(
            to: rejected.driverId,
            kind: .guardRejected,
            title: "Guardia rechazada",
            body: "El supervisor no aprobó tu guardia del \(Fmt.dateShort(vacancy.date)). \(reason)"
        )

        record(
            actor: "\(actor.name) · \(actor.employeeNumber)",
            role: actor.role,
            action: "Reemplazo rechazado",
            stationCode: vacancy.stationCode,
            shift: CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot),
            from: VacancyStatus.reserved.label,
            to: VacancyStatus.searching.label,
            detail: "Sustituto \(rejected.driverName) rechazado. Motivo: \(reason.isEmpty ? "sin especificar" : reason)."
        )

        if let nextIndex = vacancies[index].claims.firstIndex(where: { $0.status == .waitlisted }) {
            vacancies[index].claims[nextIndex].status = .reserved
            vacancies[index].status = .reserved
            let next = vacancies[index].claims[nextIndex]
            push(
                to: next.driverId,
                kind: .guardAvailable,
                title: "La guardia pasó a ti",
                body: "\(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot)) quedó reservada a tu nombre.",
                vacancyId: vacancy.id
            )
        } else {
            vacancies[index].status = .searching
            if let absenceId = vacancy.absenceRequestId,
               let aIndex = absences.firstIndex(where: { $0.id == absenceId }) {
                absences[aIndex].status = .searching
            }
            offerGuard(vacancy: vacancies[index], urgent: vacancies[index].isCritical)
        }
        persist()
    }

    /// The turn was actually worked. Only now does the bonus exist.
    func markCompleted(vacancyId: String, by actor: StaffAccount) {
        guard let index = vacancies.firstIndex(where: { $0.id == vacancyId }),
              vacancies[index].status == .confirmed else { return }
        vacancies[index].status = .completed
        let vacancy = vacancies[index]

        record(
            actor: "\(actor.name) · \(actor.employeeNumber)",
            role: actor.role,
            action: "Guardia completada",
            stationCode: vacancy.stationCode,
            shift: CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot),
            from: VacancyStatus.confirmed.label,
            to: VacancyStatus.completed.label,
            detail: vacancy.bonusMode == .none
                ? "Sin bono asociado."
                : "Bono por guardia de \(Fmt.mxn(vacancy.bonusMxn)) aplicado a la liquidación de \(vacancy.substituteName ?? "—")."
        )

        if let substituteId = vacancy.substituteId, vacancy.payableBonusMxn > 0 {
            push(
                to: substituteId,
                kind: .guardConfirmed,
                title: "Bono por guardia \(Fmt.mxn(vacancy.payableBonusMxn))",
                body: "Completaste \(CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot)). El bono entra a tu liquidación."
            )
        }
        persist()
    }

    /// Accepted the guard and did not show up. It costs the station the whole seat and it
    /// is written down, but the app never turns it into a sanction by itself.
    func markNoShow(vacancyId: String, by actor: StaffAccount, note: String) {
        guard let index = vacancies.firstIndex(where: { $0.id == vacancyId }) else { return }
        let previous = vacancies[index].status
        vacancies[index].status = .noShow
        let vacancy = vacancies[index]

        record(
            actor: "\(actor.name) · \(actor.employeeNumber)",
            role: actor.role,
            action: "No presentación en guardia",
            stationCode: vacancy.stationCode,
            shift: CoverageRules.shiftLabel(date: vacancy.date, slot: vacancy.slot),
            from: previous.label,
            to: VacancyStatus.noShow.label,
            detail: "\(vacancy.substituteName ?? "—") no se presentó. Sin bono. \(note)"
        )
        persist()
    }

    // MARK: - Swaps

    /// A driver proposes trading their turn. Nothing moves yet: the other person answers,
    /// then the engine re-checks both, then the supervisor signs.
    @discardableResult
    func proposeSwap(
        from profile: CoverageDriverProfile,
        fromDate: Date,
        fromSlot: ShiftSlot,
        to partner: CoverageDriverProfile,
        toDate: Date,
        toSlot: ShiftSlot,
        note: String
    ) throws -> ShiftSwapRequest {
        guard canCoordinateLocally else { throw CoordinationMutationError.stationRequired }

        let request = ShiftSwapRequest(
            id: CoverageRules.newId("swp"),
            stationId: profile.stationId,
            stationCode: profile.stationCode,
            fromDriverId: profile.id,
            fromDriverName: profile.name,
            fromDate: ShiftRules.calendar.startOfDay(for: fromDate),
            fromSlot: fromSlot,
            toDriverId: partner.id,
            toDriverName: partner.name,
            toDate: ShiftRules.calendar.startOfDay(for: toDate),
            toSlot: toSlot,
            status: .proposed,
            note: note,
            createdAt: now,
            respondedAt: nil,
            resolvedAt: nil,
            resolvedBy: nil,
            decisionNote: nil,
            blockers: []
        )
        swaps.insert(request, at: 0)

        push(
            to: partner.id,
            kind: .swapProposed,
            title: "Intercambio propuesto",
            body: "\(profile.name) te propone cambiar \(request.summary).",
            swapId: request.id
        )
        record(
            actor: "\(profile.name) · \(profile.employeeNumber)",
            role: .driver,
            action: "Intercambio propuesto",
            stationCode: profile.stationCode,
            shift: request.summary,
            from: "—",
            to: SwapStatus.proposed.label,
            detail: "Contraparte \(partner.name). \(note)"
        )
        persist()
        return request
    }

    /// The partner answers. Accepting only sends it to the supervisor.
    func respondToSwap(id: String, accepted: Bool, by profile: CoverageDriverProfile) throws {
        guard canCoordinateLocally else { throw CoordinationMutationError.stationRequired }
        guard let index = swaps.firstIndex(where: { $0.id == id }), swaps[index].status == .proposed else { return }
        swaps[index].respondedAt = now

        guard accepted else {
            swaps[index].status = .declined
            push(
                to: swaps[index].fromDriverId,
                kind: .swapResolved,
                title: "Intercambio rechazado",
                body: "\(profile.name) no aceptó el cambio de \(swaps[index].summary)."
            )
            record(
                actor: "\(profile.name) · \(profile.employeeNumber)",
                role: .driver,
                action: "Intercambio rechazado por el compañero",
                stationCode: swaps[index].stationCode,
                shift: swaps[index].summary,
                from: SwapStatus.proposed.label,
                to: SwapStatus.declined.label,
                detail: "La contraparte no aceptó."
            )
            persist()
            return
        }

        // Both sides are re-checked before the supervisor ever sees it.
        swaps[index].blockers = swapBlockers(for: swaps[index])
        swaps[index].status = .awaitingSupervisor
        let swap = swaps[index]

        notifySupervisors(
            stationId: swap.stationId,
            kind: .swapProposed,
            title: "Intercambio por aprobar",
            body: "\(swap.fromDriverName) ⇄ \(swap.toDriverName): \(swap.summary).",
            swapId: swap.id
        )
        record(
            actor: "\(profile.name) · \(profile.employeeNumber)",
            role: .driver,
            action: "Intercambio aceptado",
            stationCode: swap.stationCode,
            shift: swap.summary,
            from: SwapStatus.proposed.label,
            to: SwapStatus.awaitingSupervisor.label,
            detail: swap.blockers.isEmpty
                ? "Ambos conductores cumplen las reglas configuradas."
                : "Con observaciones: \(swap.blockers.joined(separator: " · "))."
        )
        persist()
    }

    /// Findings that make a swap questionable. They do not block the supervisor, they
    /// inform the signature.
    private func swapBlockers(for swap: ShiftSwapRequest) -> [String] {
        var result: [String] = []
        guard let from = profile(id: swap.fromDriverId), let to = profile(id: swap.toDriverId) else {
            return ["No se pudo leer el perfil de alguno de los conductores."]
        }
        if from.stationId != to.stationId && !policy.allowsCrossStation {
            result.append("Pertenecen a estaciones distintas")
        }
        if !to.flags.documentsValid { result.append("\(to.shortName): documentación vencida") }
        if !from.flags.documentsValid { result.append("\(from.shortName): documentación vencida") }
        if to.flags.isSuspended { result.append("\(to.shortName): suspendido") }
        if from.flags.isSuspended { result.append("\(from.shortName): suspendido") }
        if let until = to.flags.licenseValidUntil, until < swap.fromDate {
            result.append("\(to.shortName): licencia vencida")
        }
        if swap.fromSlot != swap.toSlot,
           ShiftRules.isSameDay(swap.fromDate, swap.toDate) {
            result.append("Ambos turnos caen el mismo día")
        }
        return result
    }

    /// The supervisor signs. Only now do the calendars change.
    func decideSwap(id: String, approved: Bool, by actor: StaffAccount, note: String) {
        guard let index = swaps.firstIndex(where: { $0.id == id }) else { return }
        let previous = swaps[index].status
        swaps[index].status = approved ? .approved : .rejected
        swaps[index].resolvedAt = now
        swaps[index].resolvedBy = "\(actor.name) · \(actor.employeeNumber)"
        swaps[index].decisionNote = note
        let swap = swaps[index]

        for driverId in [swap.fromDriverId, swap.toDriverId] {
            push(
                to: driverId,
                kind: .swapResolved,
                title: approved ? "Intercambio aprobado" : "Intercambio rechazado",
                body: approved
                    ? "Tu calendario ya refleja el cambio: \(swap.summary)."
                    : "El supervisor no aprobó el cambio. \(note)"
            )
        }

        record(
            actor: "\(actor.name) · \(actor.employeeNumber)",
            role: actor.role,
            action: approved ? "Intercambio aprobado" : "Intercambio rechazado",
            stationCode: swap.stationCode,
            shift: swap.summary,
            from: previous.label,
            to: swap.status.label,
            detail: note.isEmpty ? "Sin nota." : note
        )
        persist()
    }

    // MARK: - Calendar

    /// The driver's month: their own block, their guards, their absences and their swaps,
    /// each one with a different reading.
    func calendar(for profile: CoverageDriverProfile, month: Date) -> [CoverageCalendarDay] {
        let calendar = ShiftRules.calendar
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30

        return (0..<dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            return self.day(for: profile, on: day)
        }
    }

    /// What a single date means for this person.
    func day(for profile: CoverageDriverProfile, on date: Date) -> CoverageCalendarDay {
        let day = ShiftRules.calendar.startOfDay(for: date)

        // Nothing on this board was written for a session the station cannot reach, so
        // none of the readings below — a guard, an absence, an approved swap — can be
        // this person's. The month says what is actually known: the block, and no day.
        guard canCoordinateLocally else { return unpublishedDay(for: profile, on: day) }

        if let guardVacancy = vacancies.first(where: {
            ShiftRules.isSameDay($0.date, day)
                && $0.holder?.driverId == profile.id
                && ($0.status == .reserved || $0.status == .confirmed || $0.status == .completed || $0.status == .noShow)
        }) {
            let kind: CoverageDayKind = switch guardVacancy.status {
            case .reserved: .guardReserved
            case .noShow: .noShow
            default: guardVacancy.origin == .extraordinary ? .extraordinary : .guardConfirmed
            }
            return CoverageCalendarDay(
                date: day,
                kind: kind,
                slot: guardVacancy.slot,
                stationCode: guardVacancy.stationCode,
                vehicleNumber: guardVacancy.vehicleNumber,
                statusLabel: guardVacancy.status.label,
                detail: guardVacancy.origin.label,
                bonusMxn: guardVacancy.bonusMode == .none ? nil : guardVacancy.bonusMxn,
                vacancyId: guardVacancy.id,
                absenceId: nil
            )
        }

        if let absence = absences.first(where: {
            $0.driverId == profile.id && ShiftRules.isSameDay($0.date, day)
                && $0.status != .cancelled && $0.status != .rejected
        }) {
            return CoverageCalendarDay(
                date: day,
                kind: absence.status == .approved ? .absenceApproved : .absenceRequested,
                slot: absence.slot,
                stationCode: absence.stationCode,
                vehicleNumber: nil,
                statusLabel: absence.status.label,
                detail: absence.kind.label,
                bonusMxn: nil,
                vacancyId: absence.vacancyId,
                absenceId: absence.id
            )
        }

        if let swap = swaps.first(where: {
            $0.status == .approved
                && (($0.fromDriverId == profile.id && ShiftRules.isSameDay($0.toDate, day))
                    || ($0.toDriverId == profile.id && ShiftRules.isSameDay($0.fromDate, day)))
        }) {
            let isOrigin = swap.fromDriverId == profile.id
            return CoverageCalendarDay(
                date: day,
                kind: .swap,
                slot: isOrigin ? swap.toSlot : swap.fromSlot,
                stationCode: swap.stationCode,
                vehicleNumber: nil,
                statusLabel: "Intercambio aprobado",
                detail: "Con \(isOrigin ? swap.toDriverName : swap.fromDriverName)",
                bonusMxn: nil,
                vacancyId: nil,
                absenceId: nil
            )
        }

        // A published block is what makes the next two readings possible. Without one,
        // "Programado" and "Día libre" are both inventions: group plus slot says which
        // rotation somebody belongs to, never that they were assigned this Tuesday.
        guard profile.scheduleKnowledge == .declaredBlock else {
            return unpublishedDay(for: profile, on: day)
        }

        if let slot = CoverageRules.regularSlot(profile, on: day) {
            return CoverageCalendarDay(
                date: day,
                kind: .regular,
                slot: slot,
                stationCode: profile.stationCode,
                vehicleNumber: nil,
                statusLabel: "Programado",
                detail: "Turno normal de tu bloque",
                bonusMxn: nil,
                vacancyId: nil,
                absenceId: nil
            )
        }

        return CoverageCalendarDay(
            date: day,
            kind: .rest,
            slot: nil,
            stationCode: profile.stationCode,
            vehicleNumber: nil,
            statusLabel: "Día libre",
            detail: "Fuera de tu bloque",
            bonusMxn: nil,
            vacancyId: nil,
            absenceId: nil
        )
    }

    /// A day the app knows nothing about, said plainly instead of guessed.
    private func unpublishedDay(for profile: CoverageDriverProfile, on day: Date) -> CoverageCalendarDay {
        CoverageCalendarDay(
            date: day,
            kind: .unpublished,
            slot: nil,
            stationCode: profile.stationCode,
            vehicleNumber: nil,
            statusLabel: "Sin asignación publicada",
            detail: "Tu bloque es \(profile.slot.label) · \(profile.group.label). La estación aún no publica el calendario diario.",
            bonusMxn: nil,
            vacancyId: nil,
            absenceId: nil
        )
    }

    // MARK: - Station boards

    /// Coverage of today per block: seats required by the authorized fleet against the
    /// people actually scheduled plus the guards already confirmed.
    func slotBoards(station: Station, on date: Date) -> [CoverageSlotBoard] {
        let group = ShiftRules.group(for: date)
        let stationRoster = roster(stationId: station.id)

        return ShiftSlot.allCases.map { slot in
            let scheduled = stationRoster.filter { profile in
                CoverageRules.regularSlot(profile, on: date) == slot
                    && !absences.contains {
                        $0.driverId == profile.id
                            && ShiftRules.isSameDay($0.date, date)
                            && $0.slot == slot
                            && ($0.status == .approved || $0.status == .awaitingAuthorization || $0.status == .covered)
                    }
            }.count

            let stationVacancies = vacancies.filter {
                $0.stationId == station.id && ShiftRules.isSameDay($0.date, date) && $0.slot == slot
            }

            return CoverageSlotBoard(
                slot: slot,
                group: group,
                required: station.vehicleCapacity,
                scheduled: scheduled,
                openVacancies: stationVacancies.filter { $0.status.isOpen }.count,
                confirmedGuards: stationVacancies.filter { $0.status == .confirmed || $0.status == .completed }.count
            )
        }
    }

    /// Days ahead where the station will not be able to staff its units. Detecting this
    /// early is the whole point: a deficit found on the day is already a lost shift.
    func forecast(station: Station, days: Int, from date: Date) -> [CoverageForecastDay] {
        let calendar = ShiftRules.calendar
        let stationRoster = roster(stationId: station.id)
        let start = calendar.startOfDay(for: date)

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let required = station.vehicleCapacity * ShiftRules.slotsPerDay
            let scheduled = ShiftSlot.allCases.reduce(0) { total, slot in
                total + stationRoster.filter { profile in
                    CoverageRules.regularSlot(profile, on: day) == slot
                        && !absences.contains {
                            $0.driverId == profile.id
                                && ShiftRules.isSameDay($0.date, day)
                                && ($0.status == .approved || $0.status == .awaitingAuthorization || $0.status == .covered || $0.status == .searching)
                        }
                }.count
            }
            let confirmed = vacancies.filter {
                $0.stationId == station.id && ShiftRules.isSameDay($0.date, day) && $0.status == .confirmed
            }.count
            let open = vacancies.filter {
                $0.stationId == station.id && ShiftRules.isSameDay($0.date, day) && $0.status.isOpen
            }.count

            return CoverageForecastDay(
                date: day,
                required: required,
                scheduled: scheduled + confirmed,
                openVacancies: open
            )
        }
    }

    // MARK: - Human Resources feed

    /// Read-only summary handed to Human Resources. The station never edits what is here:
    /// it is the trace, not a working document.
    nonisolated struct HRDigest: Sendable {
        var absences: Int
        var leaves: Int
        var emergencies: Int
        var cancellations: Int
        var noShows: Int
        var completedGuards: Int
        var uncovered: Int
        var bonusPayableMxn: Int
    }

    func hrDigest(stationId: String) -> HRDigest {
        let stationAbsences = absences.filter { $0.stationId == stationId }
        let stationVacancies = vacancies.filter { $0.stationId == stationId }
        return HRDigest(
            absences: stationAbsences.filter { $0.kind == .scheduled }.count,
            leaves: stationAbsences.filter { $0.kind == .leave }.count,
            emergencies: stationAbsences.filter { $0.kind == .emergency }.count,
            cancellations: stationVacancies.reduce(0) { total, vacancy in
                total + vacancy.claims.filter { $0.status == .cancelled }.count
            },
            noShows: stationVacancies.filter { $0.status == .noShow }.count,
            completedGuards: stationVacancies.filter { $0.status == .completed }.count,
            uncovered: stationVacancies.filter { $0.status == .uncovered }.count,
            bonusPayableMxn: stationVacancies.reduce(0) { $0 + $1.payableBonusMxn }
        )
    }

    /// Guard bonuses already earned by a driver: only turns actually completed count.
    ///
    /// This is a peso figure on the driver's own screen, so it obeys the same rule as the
    /// rest of the board: a locally minted guard never becomes somebody's earnings.
    func earnedGuardBonusMxn(driverId: String) -> Int {
        guard canCoordinateLocally else { return 0 }
        return vacancies
            .filter { $0.status == .completed && $0.substituteId == driverId }
            .reduce(0) { $0 + $1.payableBonusMxn }
    }

    func completedGuards(driverId: String) -> [CoverageVacancy] {
        guard canCoordinateLocally else { return [] }
        return vacancies.filter { $0.status == .completed && $0.substituteId == driverId }
            .sorted { $0.scheduledStartAt > $1.scheduledStartAt }
    }

    // MARK: - Notifications

    func markNotificationRead(id: String) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[index].isRead = true
        persist()
    }

    func markAllNotificationsRead(for recipientId: String) {
        for index in notifications.indices where notifications[index].recipientId == recipientId {
            notifications[index].isRead = true
        }
        persist()
    }

    private func push(
        to recipientId: String,
        kind: CoverageNoticeKind,
        title: String,
        body: String,
        vacancyId: String? = nil,
        swapId: String? = nil
    ) {
        notifications.insert(
            CoverageNotification(
                id: CoverageRules.newId("cnot"),
                recipientId: recipientId,
                kind: kind,
                title: title,
                body: body,
                createdAt: now,
                vacancyId: vacancyId,
                swapId: swapId,
                isRead: false
            ),
            at: 0
        )

        // The driver holding the session also gets it in their own notice bell.
        if let fleet, fleet.driver.id == recipientId {
            fleet.pushNotice(kind: .station, title: title, body: body)
        }
    }

    /// Reachable by the absence resolution engine, which reports its results through the
    /// same notification channel instead of opening a second one.
    func notifySupervisors(
        stationId: String,
        kind: CoverageNoticeKind,
        title: String,
        body: String,
        vacancyId: String? = nil,
        swapId: String? = nil
    ) {
        let supervisors = StaffDirectory.accounts.filter {
            $0.role == .supervisor && $0.stationId == stationId && $0.status == .active
        }
        for supervisor in supervisors {
            push(to: supervisor.id, kind: kind, title: title, body: body, vacancyId: vacancyId, swapId: swapId)
        }
    }

    // MARK: - Audit

    private func record(
        actor: String,
        role: StaffRole,
        action: String,
        stationCode: String,
        shift: String,
        from: String,
        to: String,
        detail: String
    ) {
        audit.insert(
            CoverageAuditEntry(
                id: CoverageRules.newId("aud"),
                createdAt: now,
                actor: actor,
                actorRole: role,
                action: action,
                stationCode: stationCode,
                shiftLabel: shift,
                previousState: from,
                newState: to,
                detail: detail,
                device: nil
            ),
            at: 0
        )
    }

    /// Entry point for the laboratory, which is the only place allowed to write the trace
    /// directly — and even there it only appends.
    func recordFromLab(action: String, stationCode: String, shift: String, detail: String) {
        record(
            actor: "Laboratorio de pruebas",
            role: .lab,
            action: action,
            stationCode: stationCode,
            shift: shift,
            from: "—",
            to: "—",
            detail: detail
        )
        persist()
    }

    // MARK: - Flags

    func setFlags(_ newFlags: CoverageDriverFlags, for driverId: String) {
        flags[driverId] = newFlags
        persist()
    }

    func updatePolicy(_ newPolicy: CoveragePolicy) {
        policy = newPolicy
        persist()
    }

    // MARK: - Reset

    /// Returns the module to zero. Used by the laboratory reset and when the environment
    /// changes, so the test world never leaks into production.
    func clear() {
        absences = []
        vacancies = []
        swaps = []
        notifications = []
        flags = [:]
        persist()
    }

    /// Wipes the trace too. Kept apart from `clear()` because the audit is meant to
    /// survive an ordinary cleanup.
    func clearIncludingAudit() {
        audit = []
        clear()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            policy = state.policy
            flags = state.flags
            absences = state.absences
            vacancies = state.vacancies
            swaps = state.swaps
            audit = state.audit
            notifications = state.notifications
        } catch {
            print("No se pudo leer la cobertura de turnos: \(error.localizedDescription)")
        }
    }

    private func persist() {
        let state = PersistedState(
            policy: policy,
            flags: flags,
            absences: absences,
            vacancies: vacancies,
            swaps: swaps,
            audit: audit,
            notifications: notifications
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            print("No se pudo guardar la cobertura de turnos: \(error.localizedDescription)")
        }
    }
}
