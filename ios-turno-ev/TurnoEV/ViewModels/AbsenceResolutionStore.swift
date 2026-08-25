import Foundation
import Observation

/// The engine behind Resolver ausencias.
///
/// It watches attendance, waits out the tolerance, declares the absence and recovers the
/// capacity by itself. The supervisor is informed, not consulted — unless the rules leave
/// no valid answer, and then the case is escalated to him.
///
/// It owns no roster, no fleet and no candidate list: attendance comes from the station,
/// units from the fleet board, and eligibility and offers from Guardias.
@Observable
final class AbsenceResolutionStore {
    nonisolated private struct PersistedState: Codable, Sendable {
        var cases: [AbsenceResolutionCase]
    }

    private(set) var cases: [AbsenceResolutionCase] = []

    private var supervision: SupervisionStore?
    private var coverage: CoverageStore?

    private let stationId: String
    private var storageKey: String { "turnoev.absence.cases.\(stationId)" }

    var policy: AbsencePolicy { AbsenceResolutionConfig.policy }
    var reservePolicy: ReservePolicy { AbsenceResolutionConfig.reservePolicy(stationId: stationId) }

    /// Logical time as the engine reads it, with no SwiftUI dependency attached.
    ///
    /// This used to hop to `SupervisionStore.now` and from there to `FleetStore.now`, which
    /// reads `ClockSignal.generation` — so a store whose `now` is almost entirely write
    /// timestamps (`detectedAt`, `acceptedAt`, `assignedAt`, `closedAt`, the sweep) was
    /// quietly subscribing its readers to every adopted clock state. The screens that show
    /// live minutes now register that dependency themselves, one case card at a time.
    private var now: Date { AppClock.now() }

    init(stationId: String) {
        self.stationId = stationId
        load()
    }

    /// Wires the module to the two systems it reads from. It never writes to them except
    /// through the guard engine, which is the single source of candidates.
    func configure(supervision: SupervisionStore, coverage: CoverageStore) {
        self.supervision = supervision
        self.coverage = coverage
    }

    // MARK: - Reads

    var openCases: [AbsenceResolutionCase] {
        cases.filter(\.isOpen).sorted { $0.metrics.detectedAt > $1.metrics.detectedAt }
    }

    var todayCases: [AbsenceResolutionCase] {
        cases
            .filter { ShiftRules.isSameDay($0.date, now) }
            .sorted { $0.metrics.detectedAt > $1.metrics.detectedAt }
    }

    var escalatedCases: [AbsenceResolutionCase] { todayCases.filter(\.needsSupervisor) }
    var resolvingCases: [AbsenceResolutionCase] { todayCases.filter { $0.status == .resolving || $0.status == .detected } }
    var resolvedCases: [AbsenceResolutionCase] {
        todayCases.filter { $0.status == .resolved || $0.status == .partiallyResolved }
    }

    func resolutionCase(id: String) -> AbsenceResolutionCase? {
        cases.first { $0.id == id }
    }

    /// Reserve as the station actually stands right now.
    var reserveStatus: ReserveStatus {
        let fleet = supervision?.vehicles ?? []
        let approved = fleet.filter { ReserveFleetRegistry.isApproved(vehicleId: $0.id) }
        let committed = Set(
            cases
                .filter(\.isOpen)
                .flatMap(\.opportunities)
                .filter { $0.kind == .extraordinary && ($0.status.isOpen || $0.status.isResolved) }
                .compactMap(\.vehicleId)
        )

        let available = approved.filter {
            $0.state == .available && $0.assignedDriverId == nil && !committed.contains($0.id)
        }.count

        return ReserveStatus(
            configured: reservePolicy.targetUnits,
            approved: approved.count,
            available: available,
            inUse: committed.count,
            inMaintenance: approved.filter { $0.state == .maintenance || $0.state == .outOfService }.count,
            policy: reservePolicy
        )
    }

    /// The single line the Operación card prints.
    var headline: ResolutionHeadline {
        let today = todayCases
        let escalated = today.filter(\.needsSupervisor).count
        let resolving = today.filter { $0.status == .resolving || $0.status == .detected }.count
        let resolved = today.filter { $0.status == .resolved || $0.status == .partiallyResolved }.count

        if escalated > 0 { return .escalated(count: escalated) }
        if resolving > 0 {
            return .resolving(
                absences: resolving,
                reserves: reserveStatus.available,
                resolved: resolved
            )
        }
        if resolved > 0 {
            let latest = today.first { $0.status == .resolved || $0.status == .partiallyResolved }
            return .resolved(
                count: resolved,
                substitute: latest?.opportunities.compactMap(\.assignedDriverName).first,
                eta: latest?.earliestEta
            )
        }
        return .clear
    }

    // MARK: - Detection

    /// Runs on every refresh of the supervisor interface. It is the only place an absence
    /// is declared, and it declares it strictly by the tolerance.
    func refresh() {
        guard let supervision else { return }
        let current = policy

        for driver in supervision.allDrivers {
            let verdict = AttendanceRules.verdict(
                scheduledStart: driver.scheduledStartAt,
                checkIn: driver.checkInAt,
                now: now,
                policy: current
            )

            switch verdict {
            case .absent:
                if !hasOpenCase(driverId: driver.id, on: driver.scheduledStartAt) {
                    declareAbsence(driver: driver)
                }
            case .onTime, .late:
                // Only a real check-in closes what was opened. Rewinding the test clock
                // also produces a "late" verdict, and that must never erase an absence
                // that already happened.
                if driver.checkInAt != nil {
                    closeCaseIfTitularArrived(driverId: driver.id, on: driver.scheduledStartAt)
                }
            case .pending:
                break
            }
        }

        advanceOpenCases()
        persist()
    }

    private func hasOpenCase(driverId: String, on day: Date) -> Bool {
        cases.contains {
            $0.absentDriverId == driverId
                && ShiftRules.isSameDay($0.date, day)
                && $0.status != .closed
        }
    }

    /// Registers the absence, frees the position and opens whatever the station can fill.
    /// No supervisor takes part in any of this.
    private func declareAbsence(driver: StationDriver) {
        guard let supervision else { return }
        let station = supervision.station
        let scheduledEnd = ShiftRules.scheduledEnd(slot: driver.slot, on: driver.scheduledStartAt)

        var opportunities: [CoverageOpportunity] = []

        // A · the unit the absent driver left parked, until its return hour.
        let vehicleNumber = driver.vehicleNumber
            ?? supervision.vehicles.first { $0.id == driver.vehicleId }?.internalNumber
        if let vehicleNumber {
            let usableMinutes = max(0, Int(scheduledEnd.timeIntervalSince(now) / 60))
            if usableMinutes >= policy.minimumProductiveMinutes {
                opportunities.append(
                    CoverageOpportunity(
                        id: CoverageRules.newId("opp"),
                        kind: .ordinary,
                        vehicleId: driver.vehicleId,
                        vehicleNumber: vehicleNumber,
                        opensAt: now,
                        returnBy: scheduledEnd,
                        isFlexible: false,
                        status: .searching,
                        offers: [],
                        heldByDriverId: nil,
                        heldUntil: nil,
                        assignedDriverId: nil,
                        assignedDriverName: nil,
                        assignedEta: nil,
                        checkInAt: nil,
                        checkOutAt: nil,
                        earningsMxn: 0,
                        vacancyId: nil,
                        escalationReason: nil
                    )
                )
            }
        }

        // B · an approved reserve unit, if the protection limits allow committing one.
        if let reserve = nextUsableReserve() {
            opportunities.append(
                CoverageOpportunity(
                    id: CoverageRules.newId("opp"),
                    kind: .extraordinary,
                    vehicleId: reserve.id,
                    vehicleNumber: reserve.internalNumber,
                    opensAt: now,
                    returnBy: scheduledEnd,
                    isFlexible: true,
                    status: .searching,
                    offers: [],
                    heldByDriverId: nil,
                    heldUntil: nil,
                    assignedDriverId: nil,
                    assignedDriverName: nil,
                    assignedEta: nil,
                    checkInAt: nil,
                    checkOutAt: nil,
                    earningsMxn: 0,
                    vacancyId: nil,
                    escalationReason: nil
                )
            )
        }

        var record = AbsenceResolutionCase(
            id: CoverageRules.newId("res"),
            stationId: station.id,
            stationCode: station.code,
            date: ShiftRules.calendar.startOfDay(for: driver.scheduledStartAt),
            slot: driver.slot,
            group: ShiftRules.group(for: driver.scheduledStartAt),
            absentDriverId: driver.id,
            absentDriverName: driver.name,
            scheduledStart: driver.scheduledStartAt,
            scheduledEnd: scheduledEnd,
            status: opportunities.isEmpty ? .escalated : .resolving,
            opportunities: opportunities,
            metrics: ResolutionMetrics(detectedAt: now),
            closedAt: nil
        )

        if opportunities.isEmpty {
            // Nothing productive can be recovered: that is exactly a supervisor matter.
            record.metrics.escalatedAt = now
        }

        cases.insert(record, at: 0)

        if opportunities.isEmpty {
            notifySupervisor(
                title: "Ausencia sin cobertura posible",
                body: "\(driver.name) no se presentó y no queda tiempo productivo ni unidad de reserva disponible."
            )
        } else {
            for index in record.opportunities.indices {
                openSeat(caseId: record.id, opportunityId: record.opportunities[index].id)
            }
        }
        persist()
    }

    /// The first approved reserve the policy allows to commit.
    private func nextUsableReserve() -> StationVehicle? {
        let status = reserveStatus
        guard status.usable > 0 else { return nil }
        let committed = Set(
            cases
                .filter(\.isOpen)
                .flatMap(\.opportunities)
                .filter { $0.kind == .extraordinary }
                .compactMap(\.vehicleId)
        )
        return supervision?.vehicles.first {
            ReserveFleetRegistry.isApproved(vehicleId: $0.id)
                && $0.state == .available
                && $0.assignedDriverId == nil
                && !committed.contains($0.id)
        }
    }

    /// Opens the seat inside Guardias, which is what actually reaches the drivers.
    private func openSeat(caseId: String, opportunityId: String) {
        guard let coverage,
              let supervision,
              let caseIndex = cases.firstIndex(where: { $0.id == caseId }),
              let oppIndex = cases[caseIndex].opportunities.firstIndex(where: { $0.id == opportunityId })
        else { return }

        let record = cases[caseIndex]
        let opportunity = record.opportunities[oppIndex]

        let created = coverage.createExtraordinaryVacancy(
            station: supervision.station,
            date: record.date,
            slot: record.slot,
            seats: 1,
            bonusMode: .variable,
            bonusMxn: policy.shiftPayMxn,
            reason: opportunity.kind == .ordinary
                ? "Cobertura ordinaria por ausencia de \(record.absentDriverName) · unidad \(opportunity.vehicleNumber)"
                : "Guardia extraordinaria en unidad de reserva \(opportunity.vehicleNumber)",
            by: supervision.account
        )

        cases[caseIndex].opportunities[oppIndex].vacancyId = created.first?.id
        cases[caseIndex].opportunities[oppIndex].status = .offered

        let contacted = created.first.map { coverage.eligibleCandidates(for: $0).count } ?? 0
        cases[caseIndex].metrics.candidatesContacted += contacted

        if contacted == 0 {
            escalate(
                caseId: caseId,
                opportunityId: opportunityId,
                reason: "Ningún conductor elegible para \(opportunity.kind.label.lowercased())."
            )
        }
    }

    // MARK: - Offers

    /// A driver accepted and said when he can be at the station. The ETA selects him; it
    /// never starts his pay.
    @discardableResult
    func acceptOpportunity(
        caseId: String,
        opportunityId: String,
        driver: CoverageDriverProfile,
        eta: Date
    ) -> Bool {
        guard let caseIndex = cases.firstIndex(where: { $0.id == caseId }),
              let oppIndex = cases[caseIndex].opportunities.firstIndex(where: { $0.id == opportunityId })
        else { return false }

        let opportunity = cases[caseIndex].opportunities[oppIndex]
        guard opportunity.status.isOpen else { return false }

        // Nobody may hold two opportunities of the same absence.
        let alreadyEngaged = cases[caseIndex].opportunities.contains {
            $0.id != opportunityId && ($0.assignedDriverId == driver.id || $0.heldByDriverId == driver.id)
        }
        guard !alreadyEngaged else { return false }

        // The window has to be worth the trip.
        let productive = max(0, Int(opportunity.returnBy.timeIntervalSince(eta) / 60))
        guard opportunity.isFlexible || productive >= policy.minimumProductiveMinutes else { return false }

        let offer = OpportunityOffer(
            id: CoverageRules.newId("off"),
            driverId: driver.id,
            driverName: driver.name,
            employeeNumber: driver.employeeNumber,
            eta: eta,
            acceptedAt: now,
            accumulatedGuards: coverage?.guards(driverId: driver.id).count ?? 0,
            reliabilityScore: coverage?.reliability(driverId: driver.id)?.score ?? 0
        )

        cases[caseIndex].opportunities[oppIndex].offers.append(offer)
        if cases[caseIndex].metrics.firstAcceptanceAt == nil {
            cases[caseIndex].metrics.firstAcceptanceAt = now
        }

        selectCandidate(caseId: caseId, opportunityId: opportunityId)
        persist()
        return true
    }

    /// Picks between the drivers who accepted. Order: soonest arrival, then most
    /// productive time, then fewest guards already taken, then best record. Historic
    /// earnings never decide who gets an opportunity.
    private func selectCandidate(caseId: String, opportunityId: String) {
        guard let caseIndex = cases.firstIndex(where: { $0.id == caseId }),
              let oppIndex = cases[caseIndex].opportunities.firstIndex(where: { $0.id == opportunityId })
        else { return }

        let opportunity = cases[caseIndex].opportunities[oppIndex]
        guard opportunity.status.isOpen else { return }
        guard opportunity.heldByDriverId == nil else { return }

        let taken = Set(cases[caseIndex].opportunities.compactMap(\.assignedDriverId))
        let candidates = opportunity.offers.filter { !$0.declined && !taken.contains($0.driverId) }
        guard let best = candidates.sorted(by: Self.isBetter).first else { return }

        cases[caseIndex].opportunities[oppIndex].status = .held
        cases[caseIndex].opportunities[oppIndex].heldByDriverId = best.driverId
        cases[caseIndex].opportunities[oppIndex].heldUntil = now
            .addingTimeInterval(TimeInterval(policy.confirmationWindowMinutes * 60))
    }

    /// The four criteria, in order.
    nonisolated private static func isBetter(_ lhs: OpportunityOffer, _ rhs: OpportunityOffer) -> Bool {
        if lhs.eta != rhs.eta { return lhs.eta < rhs.eta }
        if lhs.accumulatedGuards != rhs.accumulatedGuards { return lhs.accumulatedGuards < rhs.accumulatedGuards }
        if lhs.reliabilityScore != rhs.reliabilityScore { return lhs.reliabilityScore > rhs.reliabilityScore }
        return lhs.acceptedAt < rhs.acceptedAt
    }

    /// The held candidate confirms. From here the opportunity is his.
    @discardableResult
    func confirmHold(caseId: String, opportunityId: String) -> Bool {
        guard let caseIndex = cases.firstIndex(where: { $0.id == caseId }),
              let oppIndex = cases[caseIndex].opportunities.firstIndex(where: { $0.id == opportunityId }),
              let holderId = cases[caseIndex].opportunities[oppIndex].heldByDriverId,
              let offer = cases[caseIndex].opportunities[oppIndex].offers.first(where: { $0.driverId == holderId })
        else { return false }

        cases[caseIndex].opportunities[oppIndex].status = .assigned
        cases[caseIndex].opportunities[oppIndex].assignedDriverId = offer.driverId
        cases[caseIndex].opportunities[oppIndex].assignedDriverName = offer.driverName
        cases[caseIndex].opportunities[oppIndex].assignedEta = offer.eta
        cases[caseIndex].opportunities[oppIndex].heldByDriverId = nil
        cases[caseIndex].opportunities[oppIndex].heldUntil = nil

        if cases[caseIndex].metrics.assignedAt == nil {
            cases[caseIndex].metrics.assignedAt = now
        }

        let record = cases[caseIndex]
        notifySupervisor(
            title: "Ausencia resuelta automáticamente",
            body: "\(offer.driverName) cubre a \(record.absentDriverName) en \(record.opportunities[oppIndex].vehicleNumber). ETA \(Fmt.clock(offer.eta))."
        )

        refreshStatus(caseIndex: caseIndex)
        persist()
        return true
    }

    /// The held candidate let the window pass. The opportunity moves to the next one by
    /// itself; nobody has to notice.
    private func releaseHold(caseId: String, opportunityId: String, declined: Bool) {
        guard let caseIndex = cases.firstIndex(where: { $0.id == caseId }),
              let oppIndex = cases[caseIndex].opportunities.firstIndex(where: { $0.id == opportunityId }),
              let holderId = cases[caseIndex].opportunities[oppIndex].heldByDriverId
        else { return }

        if let offerIndex = cases[caseIndex].opportunities[oppIndex].offers.firstIndex(where: { $0.driverId == holderId }) {
            cases[caseIndex].opportunities[oppIndex].offers[offerIndex].declined = true
        }
        cases[caseIndex].opportunities[oppIndex].heldByDriverId = nil
        cases[caseIndex].opportunities[oppIndex].heldUntil = nil
        cases[caseIndex].opportunities[oppIndex].status = .searching
        cases[caseIndex].metrics.rejections += 1
        if declined { cases[caseIndex].metrics.reassignments += 1 }

        selectCandidate(caseId: caseId, opportunityId: opportunityId)

        // Nobody left to try: this is the moment the supervisor is needed.
        if cases[caseIndex].opportunities[oppIndex].heldByDriverId == nil,
           cases[caseIndex].opportunities[oppIndex].offers.allSatisfy(\.declined) {
            escalate(
                caseId: caseId,
                opportunityId: opportunityId,
                reason: "Todos los candidatos rechazaron o no confirmaron."
            )
        }
    }

    /// The driver gives the opportunity back after having confirmed it. The search reopens.
    func cancelAssignment(caseId: String, opportunityId: String, reason: String) {
        guard let caseIndex = cases.firstIndex(where: { $0.id == caseId }),
              let oppIndex = cases[caseIndex].opportunities.firstIndex(where: { $0.id == opportunityId }),
              let driverId = cases[caseIndex].opportunities[oppIndex].assignedDriverId
        else { return }

        if let offerIndex = cases[caseIndex].opportunities[oppIndex].offers.firstIndex(where: { $0.driverId == driverId }) {
            cases[caseIndex].opportunities[oppIndex].offers[offerIndex].declined = true
        }
        cases[caseIndex].opportunities[oppIndex].assignedDriverId = nil
        cases[caseIndex].opportunities[oppIndex].assignedDriverName = nil
        cases[caseIndex].opportunities[oppIndex].assignedEta = nil
        cases[caseIndex].opportunities[oppIndex].status = .searching
        cases[caseIndex].metrics.reassignments += 1

        selectCandidate(caseId: caseId, opportunityId: opportunityId)

        if cases[caseIndex].opportunities[oppIndex].heldByDriverId == nil {
            escalate(
                caseId: caseId,
                opportunityId: opportunityId,
                reason: "El sustituto canceló y no hay alternativas: \(reason)."
            )
        } else {
            refreshStatus(caseIndex: caseIndex)
        }
        persist()
    }

    // MARK: - Work

    /// Pay starts here and nowhere else: a validated check-in with the clock of the
    /// station, not the one of the phone.
    func registerCheckIn(caseId: String, opportunityId: String) {
        guard let caseIndex = cases.firstIndex(where: { $0.id == caseId }),
              let oppIndex = cases[caseIndex].opportunities.firstIndex(where: { $0.id == opportunityId })
        else { return }
        guard cases[caseIndex].opportunities[oppIndex].checkInAt == nil else { return }

        cases[caseIndex].opportunities[oppIndex].checkInAt = now
        cases[caseIndex].opportunities[oppIndex].status = .working
        refreshStatus(caseIndex: caseIndex)
        persist()
    }

    /// Closes the coverage and writes it into the weekly cut, by effective minute.
    func registerCheckOut(caseId: String, opportunityId: String, earningsMxn: Int) {
        guard let caseIndex = cases.firstIndex(where: { $0.id == caseId }),
              let oppIndex = cases[caseIndex].opportunities.firstIndex(where: { $0.id == opportunityId }),
              let checkIn = cases[caseIndex].opportunities[oppIndex].checkInAt
        else { return }

        cases[caseIndex].opportunities[oppIndex].checkOutAt = now
        cases[caseIndex].opportunities[oppIndex].earningsMxn = earningsMxn
        cases[caseIndex].opportunities[oppIndex].status = .completed

        let record = cases[caseIndex]
        let opportunity = record.opportunities[oppIndex]
        let minutes = max(0, Int(now.timeIntervalSince(checkIn) / 60))

        if let driverId = opportunity.assignedDriverId {
            CoverageEarningLedger.record(
                CoverageEarning(
                    id: opportunity.id,
                    driverId: driverId,
                    driverName: opportunity.assignedDriverName ?? "—",
                    stationId: record.stationId,
                    date: record.date,
                    kind: opportunity.kind,
                    vehicleNumber: opportunity.vehicleNumber,
                    substitutedDriverName: record.absentDriverName,
                    declaredEta: opportunity.assignedEta ?? checkIn,
                    checkInAt: checkIn,
                    checkOutAt: now,
                    effectiveMinutes: minutes,
                    ratePerMinuteMxn: policy.ratePerMinuteMxn(shiftMinutes: record.shiftMinutes),
                    earningsMxn: earningsMxn,
                    goalPerMinuteMxn: policy.goalPerMinuteMxn
                )
            )
        }

        refreshStatus(caseIndex: caseIndex)
        persist()
    }

    /// Live objective of a running coverage: it grows with the minutes actually worked.
    func productivity(caseId: String, opportunityId: String) -> CoverageProductivity? {
        guard let record = resolutionCase(id: caseId),
              let opportunity = record.opportunities.first(where: { $0.id == opportunityId })
        else { return nil }
        return CoverageProductivity(
            effectiveMinutes: opportunity.liveMinutes(now: now),
            earningsMxn: opportunity.earningsMxn,
            goalPerMinuteMxn: policy.goalPerMinuteMxn
        )
    }

    // MARK: - Escalation

    /// Automation is conservative: if the rules allow a solution it runs, and if anything
    /// is in conflict or unknown it stops and calls the supervisor.
    func escalate(caseId: String, opportunityId: String?, reason: String) {
        guard let caseIndex = cases.firstIndex(where: { $0.id == caseId }) else { return }

        if let opportunityId,
           let oppIndex = cases[caseIndex].opportunities.firstIndex(where: { $0.id == opportunityId }) {
            cases[caseIndex].opportunities[oppIndex].status = .escalated
            cases[caseIndex].opportunities[oppIndex].escalationReason = reason
        }

        // A case only escalates when nothing else is still producing a solution.
        let stillWorking = cases[caseIndex].opportunities.contains { $0.status.isOpen || $0.status.isResolved }
        if !stillWorking {
            cases[caseIndex].status = .escalated
            if cases[caseIndex].metrics.escalatedAt == nil {
                cases[caseIndex].metrics.escalatedAt = now
            }
            notifySupervisor(
                title: "Intervención requerida",
                body: "\(cases[caseIndex].absentDriverName): \(reason)"
            )
        } else {
            refreshStatus(caseIndex: caseIndex)
        }
        persist()
    }

    /// The supervisor took over. The case stops asking for him.
    func acknowledgeEscalation(caseId: String, note: String) {
        guard let index = cases.firstIndex(where: { $0.id == caseId }) else { return }
        cases[index].status = .closed
        cases[index].closedAt = now
        persist()
    }

    // MARK: - Engine tick

    /// Moves every open case forward: expired holds and searches that ran out of time.
    ///
    /// The engine only ever moves forward. Going back on the test clock is a legitimate
    /// way to replay a sequence, but it must not silently undo an absence, a search, an
    /// offer or an assignment that already happened — those stay until the scenario is
    /// reset from the laboratory.
    private func advanceOpenCases() {
        for index in cases.indices where cases[index].isOpen {
            let record = cases[index]
            guard now >= record.metrics.detectedAt else { continue }

            for opportunity in record.opportunities {
                if let heldUntil = opportunity.heldUntil, now >= heldUntil {
                    releaseHold(caseId: record.id, opportunityId: opportunity.id, declined: true)
                    continue
                }
                // An opportunity that ran out of useful time is no longer worth filling.
                if opportunity.status.isOpen,
                   !opportunity.isFlexible,
                   Int(opportunity.returnBy.timeIntervalSince(now) / 60) < policy.minimumProductiveMinutes {
                    if let oppIndex = cases[index].opportunities.firstIndex(where: { $0.id == opportunity.id }) {
                        cases[index].opportunities[oppIndex].status = .closed
                        cases[index].opportunities[oppIndex].escalationReason =
                            "Ya no queda el tiempo productivo mínimo configurado."
                    }
                }
            }
            refreshStatus(caseIndex: index)
        }
    }

    /// The state of the case is the sum of its opportunities, never a separate flag.
    private func refreshStatus(caseIndex: Int) {
        let opportunities = cases[caseIndex].opportunities
        guard !opportunities.isEmpty else { return }

        let resolved = opportunities.filter { $0.status.isResolved }.count
        let open = opportunities.filter { $0.status.isOpen }.count
        let escalated = opportunities.filter { $0.status == .escalated }.count

        if open > 0 {
            cases[caseIndex].status = .resolving
        } else if resolved == opportunities.count {
            cases[caseIndex].status = .resolved
        } else if resolved > 0 {
            cases[caseIndex].status = .partiallyResolved
        } else if escalated > 0 {
            cases[caseIndex].status = .escalated
        } else {
            cases[caseIndex].status = .closed
            cases[caseIndex].closedAt = now
        }
    }

    /// The titular turned up after the tolerance. Whatever was still searching closes;
    /// what was already assigned stands, because somebody was called for it.
    private func closeCaseIfTitularArrived(driverId: String, on day: Date) {
        guard let index = cases.firstIndex(where: {
            $0.absentDriverId == driverId && ShiftRules.isSameDay($0.date, day) && $0.isOpen
        }) else { return }

        for oppIndex in cases[index].opportunities.indices where cases[index].opportunities[oppIndex].status.isOpen {
            cases[index].opportunities[oppIndex].status = .closed
            cases[index].opportunities[oppIndex].escalationReason = "El titular se presentó."
        }
        refreshStatus(caseIndex: index)
    }

    private func notifySupervisor(title: String, body: String) {
        guard let coverage, let supervision else { return }
        coverage.notifySupervisors(
            stationId: supervision.station.id,
            kind: .criticalCoverage,
            title: title,
            body: body
        )
    }

    // MARK: - Laboratory hooks

    /// Wipes everything this module produced. Used by the laboratory reset.
    func clearAll() {
        cases = []
        CoverageEarningLedger.clear()
        persist()
    }

    /// Lets the laboratory drive the engine end to end without waiting for real drivers.
    @discardableResult
    func simulateAcceptance(caseId: String, opportunityId: String, driverId: String, eta: Date) -> Bool {
        guard let coverage, let profile = coverage.profile(id: driverId) else { return false }
        return acceptOpportunity(caseId: caseId, opportunityId: opportunityId, driver: profile, eta: eta)
    }

    func simulateHoldExpiry(caseId: String, opportunityId: String) {
        releaseHold(caseId: caseId, opportunityId: opportunityId, declined: true)
        persist()
    }

    /// Forces the input condition of the engine — a driver who crossed the tolerance — so
    /// a scenario does not have to wait for the real clock. Everything after this point is
    /// the production path.
    @discardableResult
    func simulateAbsence(driverId: String) -> AbsenceResolutionCase? {
        guard let supervision,
              let driver = supervision.allDrivers.first(where: { $0.id == driverId })
        else { return nil }
        guard !hasOpenCase(driverId: driver.id, on: driver.scheduledStartAt) else {
            return cases.first { $0.absentDriverId == driver.id && $0.isOpen }
        }
        declareAbsence(driver: driver)
        persist()
        return cases.first { $0.absentDriverId == driver.id }
    }

    /// Runs a whole coverage from check-in to check-out so the per-minute pay and the
    /// proportional objective can be verified.
    func simulateWork(caseId: String, opportunityId: String, minutes: Int, earningsMxn: Int) {
        guard let caseIndex = cases.firstIndex(where: { $0.id == caseId }),
              let oppIndex = cases[caseIndex].opportunities.firstIndex(where: { $0.id == opportunityId })
        else { return }

        // Pay only ever starts at a validated check-in, never at the declared ETA.
        let checkIn = now.addingTimeInterval(TimeInterval(-minutes * 60))
        cases[caseIndex].opportunities[oppIndex].checkInAt = checkIn
        cases[caseIndex].opportunities[oppIndex].status = .working
        registerCheckOut(caseId: caseId, opportunityId: opportunityId, earningsMxn: earningsMxn)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cases = try decoder.decode(PersistedState.self, from: data).cases
        } catch {
            print("No se pudo leer resolver ausencias: \(error.localizedDescription)")
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(PersistedState(cases: cases))
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("No se pudo guardar resolver ausencias: \(error.localizedDescription)")
        }
    }
}

/// The single line the Operación card shows.
nonisolated enum ResolutionHeadline: Sendable {
    case clear
    case resolving(absences: Int, reserves: Int, resolved: Int)
    case resolved(count: Int, substitute: String?, eta: Date?)
    case escalated(count: Int)
}
