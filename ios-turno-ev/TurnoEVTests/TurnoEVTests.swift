//
//  TurnoEVTests.swift
//  TurnoEVTests
//
//  Created by Rork on August 16, 2026.
//

import Foundation
import Testing
@testable import TurnoEV

/// 15B.10 · the credit instalment is a deduction only when the contract can be verified.
///
/// These cover the rule itself, which is pure: given a contract and the week being
/// settled, it either charges the instalment or it does not. The session-level cases
/// (A and B) live in `FleetStore`, which is `@MainActor` and reads `UserDefaults`, and
/// are verified by running the app.
struct SettlementCreditTests {

    private static let weeklyMxn = CreditProgram.weeklyMxn

    private static func contract(
        driverId: String,
        origin: RecordOrigin,
        startedAt: Date
    ) -> CreditAccount {
        CreditAccount(
            driverId: driverId,
            origin: origin,
            contractId: "CR-TEST",
            vehicleTarget: "\(CreditProgram.vehicleModel) · TEV-001",
            startedAt: startedAt,
            totalMxn: CreditProgram.priceMxn,
            paidMxn: 0,
            weeklyMxn: weeklyMxn,
            weeksPaid: 0,
            onTimePayments: 0,
            latePayments: 0,
            assignedVehicleOdometerKm: 96_480,
            payments: []
        )
    }

    private static func settlement(
        driverId: String,
        credit: CreditAccount?,
        ledgerOrigin: RecordOrigin,
        weekStart: Date,
        now: Date
    ) -> WeeklySettlement {
        SettlementRules.build(
            driverId: driverId,
            records: [],
            activeEarningsMxn: 0,
            credit: credit,
            ledgerOrigin: ledgerOrigin,
            bonusMxn: 0,
            weekStart: weekStart,
            now: now
        )
    }

    /// C · a contract signed this week owes nothing for the weeks that closed before it
    /// was signed. This is the retroactive debt found in the audit: the same instalment
    /// was applied to the five previous, already frozen weeks.
    @Test func contractSignedThisWeekDoesNotChargePreviousWeeks() {
        let now = Date()
        let driverId = "drv-001"
        let credit = Self.contract(driverId: driverId, origin: .simulated, startedAt: now)
        let currentWeek = ShiftRules.weekStart(for: now)

        for offset in 1...5 {
            let past = ShiftRules.calendar.date(byAdding: .day, value: -7 * offset, to: currentWeek)
            let weekStart = try! #require(past)
            let previous = Self.settlement(
                driverId: driverId,
                credit: credit,
                ledgerOrigin: .simulated,
                weekStart: weekStart,
                now: now
            )
            #expect(previous.creditMxn == 0)
            #expect(previous.netMxn == 0)
        }

        let current = Self.settlement(
            driverId: driverId,
            credit: credit,
            ledgerOrigin: .simulated,
            weekStart: currentWeek,
            now: now
        )
        #expect(current.creditMxn == -Self.weeklyMxn)
    }

    /// D · a contract belonging to someone else never reaches this driver's pay.
    @Test func contractOfAnotherDriverIsNotDeducted() {
        let now = Date()
        let credit = Self.contract(
            driverId: "drv-other",
            origin: .simulated,
            startedAt: now.addingTimeInterval(-98 * 86400)
        )
        let result = Self.settlement(
            driverId: "drv-001",
            credit: credit,
            ledgerOrigin: .simulated,
            weekStart: ShiftRules.weekStart(for: now),
            now: now
        )
        #expect(result.creditMxn == 0)
        #expect(result.netMxn == 0)
    }

    /// A fixture cannot be charged against a ledger an authority produced, even when the
    /// owner string matches. This is what stops a locally minted contract from becoming
    /// the debt of a proved identity.
    @Test func simulatedContractIsNotDeductedFromABackendLedger() {
        let now = Date()
        let driverId = "drv-001"
        let credit = Self.contract(
            driverId: driverId,
            origin: .simulated,
            startedAt: now.addingTimeInterval(-98 * 86400)
        )
        let result = Self.settlement(
            driverId: driverId,
            credit: credit,
            ledgerOrigin: .backend,
            weekStart: ShiftRules.weekStart(for: now),
            now: now
        )
        #expect(result.creditMxn == 0)
    }

    /// E · the demonstration contract keeps being discounted exactly as before: same
    /// owner, same provenance as the ledger, signed long before the week being settled.
    @Test func demonstrationContractStillChargesItsWeeklyInstalment() {
        let now = Date()
        let driverId = MockData.driver.id
        let credit = MockData.credit(now: now, driverId: driverId)
        let result = Self.settlement(
            driverId: driverId,
            credit: credit,
            ledgerOrigin: .simulated,
            weekStart: ShiftRules.weekStart(for: now),
            now: now
        )
        #expect(credit.origin == .simulated)
        #expect(result.creditMxn == -Self.weeklyMxn)
    }
}

/// Contracts and incomes stored before 15B.10 carry no owner and no provenance.
struct RecordOriginCompatibilityTests {

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// A legacy contract decodes as unprovable: nobody's, and simulated. It must never
    /// be silently attributed to whoever happens to be signed in.
    @Test func legacyCreditDecodesAsUnattributedAndSimulated() throws {
        let json = """
        {
          "contractId": "CR-10428",
          "vehicleTarget": "BYD Dolphin Mini · TEV-014",
          "startedAt": "2026-05-01T00:00:00Z",
          "totalMxn": 390000,
          "paidMxn": 28434,
          "weeklyMxn": 2031,
          "weeksPaid": 14,
          "onTimePayments": 13,
          "latePayments": 1,
          "assignedVehicleOdometerKm": 96480,
          "payments": []
        }
        """
        let credit = try Self.decoder().decode(CreditAccount.self, from: Data(json.utf8))
        #expect(credit.origin == .simulated)
        #expect(credit.isAttributed == false)
        #expect(credit.driverId == CreditAccount.unattributedOwnerId)

        // Naming it for the demonstration driver never promotes it.
        let named = credit.attributed(to: "drv-001")
        #expect(named.driverId == "drv-001")
        #expect(named.origin == .simulated)
        #expect(named.weeklyMxn == credit.weeklyMxn)
    }

    /// An unattributed contract matches no driver, so it is deducted from nobody.
    @Test func unattributedCreditIsNeverDeducted() throws {
        let json = """
        {
          "contractId": "CR-10428",
          "vehicleTarget": "BYD Dolphin Mini · TEV-014",
          "startedAt": "2020-01-01T00:00:00Z",
          "totalMxn": 390000,
          "paidMxn": 0,
          "weeklyMxn": 2031,
          "weeksPaid": 0,
          "onTimePayments": 0,
          "latePayments": 0,
          "assignedVehicleOdometerKm": 96480,
          "payments": []
        }
        """
        let credit = try Self.decoder().decode(CreditAccount.self, from: Data(json.utf8))
        let now = Date()
        let result = SettlementRules.build(
            driverId: "drv-001",
            records: [],
            activeEarningsMxn: 0,
            credit: credit,
            ledgerOrigin: .simulated,
            bonusMxn: 0,
            weekStart: ShiftRules.weekStart(for: now),
            now: now
        )
        #expect(result.creditMxn == 0)
    }

    /// A legacy income decodes as simulated: no other kind of session could have written it.
    @Test func legacyIncomeDecodesAsSimulated() throws {
        let json = """
        {
          "id": "inc-001",
          "driverId": "drv-001",
          "date": "2026-05-01T00:00:00Z",
          "amountMxn": 1200,
          "trips": 14,
          "platform": "Uber"
        }
        """
        let income = try Self.decoder().decode(IncomeEntry.self, from: Data(json.utf8))
        #expect(income.origin == .simulated)
        #expect(income.driverId == "drv-001")
        #expect(income.shiftId == nil)
    }
}

/// 15B.12 · cash charges are recovered from a week only when the book agrees.
///
/// A cash charge is the one record in the app that turns into a deduction by doing
/// nothing at all: when its day ends without a deposit it becomes money taken off the
/// week. That makes it the cheapest way to charge a real identity for a fiction, and the
/// reason ownership alone was never enough — the fixture and the real record would carry
/// the same `driverId`.
struct CashRecoveryOriginTests {

    private static func charge(
        driverId: String,
        origin: RecordOrigin,
        amountMxn: Int,
        at date: Date
    ) -> CashCharge {
        CashCharge(
            id: "cash-test-\(origin.rawValue)-\(driverId)",
            origin: origin,
            driverId: driverId,
            stationId: "est-001",
            tripReference: "UBER-587507",
            amountMxn: amountMxn,
            generatedAt: date,
            depositedAt: nil,
            chargedBackAt: date
        )
    }

    private static func settlement(
        driverId: String,
        ledgerOrigin: RecordOrigin,
        recoveries: [CashCharge],
        now: Date
    ) -> WeeklySettlement {
        SettlementRules.build(
            driverId: driverId,
            records: [],
            activeEarningsMxn: 0,
            credit: nil,
            ledgerOrigin: ledgerOrigin,
            bonusMxn: 0,
            cashRecoveries: recoveries,
            weekStart: ShiftRules.weekStart(for: now),
            now: now
        )
    }

    /// The $140 trip. Minted on the device, it can never be recovered from a settlement
    /// built out of records an authority produced.
    @Test func simulatedChargeIsNotRecoveredFromABackendLedger() {
        let now = Date()
        let result = Self.settlement(
            driverId: "drv-001",
            ledgerOrigin: .backend,
            recoveries: [Self.charge(driverId: "drv-001", origin: .simulated, amountMxn: 140, at: now)],
            now: now
        )
        #expect(result.deductionMxn == 0)
    }

    /// The same charge, read by the session that produced it, still works.
    @Test func simulatedChargeIsRecoveredFromItsOwnLedger() {
        let now = Date()
        let result = Self.settlement(
            driverId: "drv-001",
            ledgerOrigin: .simulated,
            recoveries: [Self.charge(driverId: "drv-001", origin: .simulated, amountMxn: 140, at: now)],
            now: now
        )
        #expect(result.deductionMxn == -140)
    }

    /// A charge the platform really reported is recovered normally. The boundary refuses
    /// fictions, not cash.
    @Test func backendChargeIsRecoveredFromABackendLedger() {
        let now = Date()
        let result = Self.settlement(
            driverId: "drv-001",
            ledgerOrigin: .backend,
            recoveries: [Self.charge(driverId: "drv-001", origin: .backend, amountMxn: 140, at: now)],
            now: now
        )
        #expect(result.deductionMxn == -140)
    }

    /// Ownership is still checked: the right book does not make it the right driver.
    @Test func chargeOfAnotherDriverIsNotRecovered() {
        let now = Date()
        let result = Self.settlement(
            driverId: "drv-001",
            ledgerOrigin: .backend,
            recoveries: [Self.charge(driverId: "drv-999", origin: .backend, amountMxn: 140, at: now)],
            now: now
        )
        #expect(result.deductionMxn == 0)
    }
}

/// 15B.12 · cash records and wallet blobs stored before provenance existed.
struct CashOriginCompatibilityTests {

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The charge already sitting in `turnoev.cash.charges.v1`. It decodes, it keeps its
    /// folio and its amount, and it reads as simulated — which is what stops it from
    /// appearing under an identity the server proved.
    @Test func legacyCashChargeDecodesAsSimulated() throws {
        let json = """
        {
          "id": "cash-8f21ab3c",
          "driverId": "drv-001",
          "stationId": "est-001",
          "tripReference": "UBER-587507",
          "amountMxn": 140,
          "generatedAt": "2026-08-20T18:30:00Z"
        }
        """
        let charge = try Self.decoder().decode(CashCharge.self, from: Data(json.utf8))
        #expect(charge.origin == .simulated)
        #expect(charge.amountMxn == 140)
        #expect(charge.tripReference == "UBER-587507")
        #expect(charge.isOpen)
    }

    /// A slip filed before provenance existed is a demonstration slip.
    @Test func legacyCashDepositDecodesAsSimulated() throws {
        let json = """
        {
          "id": "dep-1120aa41",
          "stationId": "est-001",
          "driverId": "drv-001",
          "driverName": "Carlos Ramírez",
          "vehicleNumber": "TEV-014",
          "declaredMxn": 140,
          "match": "matched",
          "bank": "BBVA México",
          "clabe": "012180014877239104",
          "createdAt": "2026-08-20T20:05:00Z"
        }
        """
        let deposit = try Self.decoder().decode(CashDeposit.self, from: Data(json.utf8))
        #expect(deposit.origin == .simulated)
        #expect(deposit.declaredMxn == 140)
        #expect(deposit.detectedMxn == nil)
        #expect(deposit.isAcknowledged == false)
    }

    /// A correction stored without provenance is not a supervisor's decision.
    @Test func legacyAdjustmentDecodesAsSimulated() throws {
        let json = """
        {
          "id": "adj-9f21c0",
          "createdAt": "2026-08-21T10:00:00Z",
          "concept": "Ajuste de semana",
          "amountMxn": 450,
          "author": "Supervisión",
          "reason": "Diferencia reportada"
        }
        """
        let adjustment = try Self.decoder().decode(SettlementAdjustment.self, from: Data(json.utf8))
        #expect(adjustment.origin == .simulated)
        #expect(adjustment.author == "Supervisión")
        #expect(adjustment.amountMxn == 450)
    }

    /// An adjustment read by the wrong book is dropped before it can move a net.
    @Test func simulatedAdjustmentIsNotCountedInABackendLedger() throws {
        let json = """
        {
          "id": "adj-9f21c0",
          "createdAt": "2026-08-21T10:00:00Z",
          "concept": "Ajuste de semana",
          "amountMxn": 450,
          "author": "Supervisión",
          "reason": "Diferencia reportada"
        }
        """
        let adjustment = try Self.decoder().decode(SettlementAdjustment.self, from: Data(json.utf8))
        let kept = [adjustment].filter { $0.origin == RecordOrigin.backend }
        #expect(kept.isEmpty)
    }
}

/// 15B.12 · the transfer pipeline is a timer, and a stored blob has to say so.
///
/// `WalletStore` is `@MainActor` and reads `UserDefaults`, so the adoption rule itself is
/// verified by running the app. What is pure — and what actually decides the outcome — is
/// how a blob written before this field existed is read.
struct WalletProvenanceCompatibilityTests {

    /// Mirrors `WalletStore.PersistedState`, which is private.
    private struct StoredWallet: Codable {
        var statuses: [String: String]
        var requestedAt: [String: Date]
        var transferredAt: [String: Date]
        var reviews: [String: String]
        var adjustments: [String: [SettlementAdjustment]]
        var origin: RecordOrigin?
    }

    /// A wallet left mid-pipeline by the simulation — "completed", with a transfer date —
    /// carries no origin. Read as simulated, it is never adopted by a backend session, so
    /// "Completada" and "Depósito confirmado en tu cuenta" cannot be shown for a transfer
    /// that never happened.
    @Test func legacyWalletBlobIsReadAsSimulatedAndNotAdoptedByBackend() throws {
        let json = """
        {
          "statuses": { "liq-drv-001-2026-08-17": "completed" },
          "requestedAt": { "liq-drv-001-2026-08-17": "2026-08-17T12:00:00Z" },
          "transferredAt": { "liq-drv-001-2026-08-17": "2026-08-17T12:04:12Z" },
          "reviews": {},
          "adjustments": {}
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stored = try decoder.decode(StoredWallet.self, from: Data(json.utf8))

        let effective = stored.origin ?? .simulated
        #expect(effective == .simulated)
        // This is the test `load()` performs before adopting anything.
        #expect(effective != RecordOrigin.backend)
        // The demonstration session that wrote it still recognises it as its own.
        #expect(effective == RecordOrigin.simulated)
        #expect(stored.statuses.count == 1)
    }
}

// MARK: - 15B.13.1 · operational coordination boundary

/// A coverage board wired to an isolated `UserDefaults` suite.
///
/// The module persists the whole board under one key. A test must never read or write
/// the board a real session owns, so each one gets its own suite and throws it away.
@MainActor
private struct TestBoard {
    let store: CoverageStore
    let suiteName: String

    init(_ capability: CoordinationCapability) {
        suiteName = "turnoev.tests.coverage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        store = CoverageStore(capability: capability, defaults: defaults)
    }

    func discard() {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private func makeProfile(
    id: String,
    schedule: ScheduleKnowledge,
    slot: ShiftSlot = .morning,
    group: ShiftGroup = .weekday
) -> CoverageDriverProfile {
    CoverageDriverProfile(
        id: id,
        name: "Conductor de prueba",
        employeeNumber: "EMP-TEST",
        stationId: "est-001",
        stationCode: "IZT",
        slot: slot,
        group: group,
        scheduleKnowledge: schedule,
        flags: .clear
    )
}

/// First date on or after `from` that belongs to the given rotation.
private func firstDay(of group: ShiftGroup, from: Date) -> Date {
    let calendar = ShiftRules.calendar
    for offset in 0...8 {
        guard let day = calendar.date(byAdding: .day, value: offset, to: from) else { continue }
        if ShiftRules.group(for: day) == group { return calendar.startOfDay(for: day) }
    }
    return from
}

/// 15B.13.1 · a session the station cannot reach never writes a shared coverage fact.
///
/// Cases A, B and C of the cut. Each one asserts the refusal *and* the absence of every
/// side effect the refused call would otherwise have produced — a request that stops
/// halfway leaves a vacancy searching for a substitute nobody will ever send.
@MainActor
struct CoordinationBoundaryTests {

    /// A · a proved identity cannot file an absence request.
    @Test func backendSessionCannotInsertAnAbsenceRequest() {
        let board = TestBoard(.stationRequired)
        defer { board.discard() }
        let profile = makeProfile(id: "DRV-TEST-001", schedule: .unpublished)

        #expect(throws: CoordinationMutationError.self) {
            try board.store.requestAbsence(
                driver: profile,
                date: Date(),
                slot: .morning,
                kind: .scheduled,
                reason: "Cita médica",
                comments: "",
                evidence: nil
            )
        }
        #expect(board.store.absences.isEmpty)
    }

    /// B · and produces no vacancy, no audit line and no notification on the way out.
    @Test func refusedAbsenceLeavesNoVacancyAuditOrNotification() {
        let board = TestBoard(.stationRequired)
        defer { board.discard() }
        let profile = makeProfile(id: "DRV-TEST-001", schedule: .unpublished)

        try? board.store.requestAbsence(
            driver: profile,
            date: Date(),
            slot: .morning,
            kind: .emergency,
            reason: "No puedo presentarme",
            comments: "",
            evidence: nil
        )

        #expect(board.store.vacancies.isEmpty)
        #expect(board.store.audit.isEmpty)
        #expect(board.store.notifications.isEmpty)
    }

    /// C · no seat is reserved and no swap is proposed.
    @Test func backendSessionCannotReserveAGuardOrProposeASwap() {
        let board = TestBoard(.stationRequired)
        defer { board.discard() }
        let profile = makeProfile(id: "DRV-TEST-001", schedule: .unpublished)
        let partner = makeProfile(id: "DRV-TEST-002", schedule: .unpublished, slot: .evening)

        let seat = CoverageVacancy(
            id: "vac-test",
            stationId: "est-001",
            stationCode: "IZT",
            date: ShiftRules.calendar.startOfDay(for: Date()),
            slot: .evening,
            origin: .extraordinary,
            titularDriverId: nil,
            titularName: nil,
            vehicleId: nil,
            vehicleNumber: nil,
            bonusMode: .fixed,
            bonusMxn: 700,
            reason: "Semilla de prueba",
            status: .searching,
            absenceRequestId: nil,
            claims: [],
            approvedBy: nil,
            approvedAt: nil,
            rejectionNote: nil,
            isCritical: false,
            createdAt: Date(),
            createdBy: "Prueba"
        )
        board.store.vacancies = [seat]

        let outcome = board.store.claimGuard(vacancyId: seat.id, by: profile)
        guard case .stationRequired = outcome else {
            Issue.record("Tomar la guardia debió terminar en .stationRequired.")
            return
        }
        // Refused for the right reason: nobody failed a rule.
        #expect(!outcome.isSuccess)
        #expect(board.store.vacancies[0].claims.isEmpty)
        #expect(board.store.vacancies[0].status == .searching)

        #expect(throws: CoordinationMutationError.self) {
            try board.store.proposeSwap(
                from: profile,
                fromDate: Date(),
                fromSlot: .morning,
                to: partner,
                toDate: Date(),
                toSlot: .evening,
                note: ""
            )
        }
        #expect(board.store.swaps.isEmpty)
        #expect(board.store.audit.isEmpty)
    }

    /// The seat seeded above belongs to the board, not to the driver: it is never offered
    /// as available work either, so the refusal is not the first thing the driver meets.
    @Test func backendSessionIsOfferedNoGuards() {
        let board = TestBoard(.stationRequired)
        defer { board.discard() }
        let profile = makeProfile(id: "DRV-TEST-001", schedule: .unpublished)

        #expect(board.store.availableGuards(for: profile).isEmpty)
        #expect(board.store.absences(driverId: profile.id).isEmpty)
        #expect(board.store.earnedGuardBonusMxn(driverId: profile.id) == 0)
    }
}

/// 15B.13.1 · the calendar states what is known, and a rotation is not an assignment.
@MainActor
struct CoverageCalendarHonestyTests {

    /// D · belonging to the weekday block does not schedule five days.
    ///
    /// This is the assumption removed from `BonusRules`, reaching the calendar by another
    /// road: `worksRegularly` reads group plus slot and answers "Programado" for every
    /// matching date, for a driver whose station never published a calendar.
    @Test func backendWeekdayDriverGetsNoScheduledDays() {
        let board = TestBoard(.stationRequired)
        defer { board.discard() }
        let profile = makeProfile(id: "DRV-TEST-001", schedule: .unpublished)
        let calendar = ShiftRules.calendar
        let monday = firstDay(of: .weekday, from: Date())

        for offset in 0..<5 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: monday) else { continue }
            let reading = board.store.day(for: profile, on: day)
            #expect(reading.kind != .regular)
            #expect(reading.statusLabel != "Programado")
            // Nor the opposite invention: a rest day is a claim about the schedule too.
            #expect(reading.kind != .rest)
            #expect(reading.slot == nil)
        }

        let sample = board.store.day(for: profile, on: monday)
        #expect(sample.kind == .unpublished)
        #expect(sample.statusLabel == "Sin asignación publicada")
    }

    /// The supposed days do not reach the workload, overlap or rest calculations either:
    /// the single rule every one of them reads answers `false` for an unpublished block.
    @Test func unpublishedScheduleProducesNoRegularDayForTheEngine() {
        let weekday = firstDay(of: .weekday, from: Date())
        let unpublished = makeProfileNonIsolated(schedule: .unpublished)
        let declared = makeProfileNonIsolated(schedule: .declaredBlock)

        #expect(CoverageRules.worksRegularly(unpublished, on: weekday) == false)
        #expect(CoverageRules.regularSlot(unpublished, on: weekday) == nil)
        // The demonstration roster keeps the inference it has always had.
        #expect(CoverageRules.worksRegularly(declared, on: weekday))
        #expect(CoverageRules.regularSlot(declared, on: weekday) == .morning)
    }

    private func makeProfileNonIsolated(schedule: ScheduleKnowledge) -> CoverageDriverProfile {
        CoverageDriverProfile(
            id: "drv-001",
            name: "Conductor de prueba",
            employeeNumber: "EMP-TEST",
            stationId: "est-001",
            stationCode: "IZT",
            slot: .morning,
            group: .weekday,
            scheduleKnowledge: schedule,
            flags: .clear
        )
    }
}

/// 15B.13.1 · E · the demonstration workflow is untouched.
@MainActor
struct CoverageDemonstrationTests {

    /// A demonstration session still files the request, opens the seat and writes the
    /// trace — the whole point of a module with no server behind it.
    @Test func demonstrationSessionStillRunsTheWholeWorkflow() throws {
        let board = TestBoard(.localWorkflow)
        defer { board.discard() }
        let profile = makeProfile(id: "drv-001", schedule: .declaredBlock)
        let date = ShiftRules.calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()

        let request = try board.store.requestAbsence(
            driver: profile,
            date: date,
            slot: .morning,
            kind: .scheduled,
            reason: "Asunto familiar",
            comments: "",
            evidence: nil
        )

        #expect(board.store.absences.count == 1)
        #expect(board.store.vacancies.count == 1)
        #expect(request.vacancyId != nil)
        #expect(board.store.vacancy(id: request.vacancyId) != nil)
        // The trace is written by the same call, as it always was.
        #expect(!board.store.audit.isEmpty)
    }

    /// And the demonstration calendar keeps saying "Programado" on the block's own days.
    @Test func demonstrationCalendarKeepsItsRegularDays() {
        let board = TestBoard(.localWorkflow)
        defer { board.discard() }
        let profile = makeProfile(id: "drv-001", schedule: .declaredBlock)
        let weekday = firstDay(of: .weekday, from: Date())
        let weekend = firstDay(of: .weekend, from: Date())

        let working = board.store.day(for: profile, on: weekday)
        #expect(working.kind == .regular)
        #expect(working.statusLabel == "Programado")
        #expect(working.slot == .morning)

        let free = board.store.day(for: profile, on: weekend)
        #expect(free.kind == .rest)
    }
}

// MARK: - 15B.15 · the coverage tray

/// 15B.15 · a shared workflow's messages answer to provenance, not to an address.
///
/// This tray is a harder case than the general bell and for one structural reason: the
/// bell is stored per identity **and** environment, so a demonstration and a proved
/// driver never share a blob. The coverage board is keyed by environment alone — a demo
/// session and a proved identity in production both read `turnoev.coverage.v1`. Every
/// `recipientId` in it is a fixture id (`DRV-TEST-001`, `acc-sup-201`), so being
/// addressed correctly proved nothing at all.
@MainActor
struct CoverageNoticeBoundaryTests {

    // MARK: Provenance

    /// A · a row stored before provenance existed is read as simulated.
    @Test func legacyNotificationDecodesAsSimulated() throws {
        let json = #"""
        {
          "id": "cnot-legacy",
          "recipientId": "DRV-TEST-001",
          "kind": "guardAvailable",
          "title": "Guardia disponible",
          "body": "Sábado 14, matutino en IZT. Bono $700.",
          "createdAt": "2026-08-20T09:15:00Z",
          "vacancyId": "vac-legacy",
          "isRead": false
        }
        """#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notification = try decoder.decode(CoverageNotification.self, from: Data(json.utf8))

        #expect(notification.origin == .simulated)
        #expect(notification.vacancyId == "vac-legacy")
        #expect(CoverageNoticeRules.adopts(origin: notification.origin, authority: .stationRouted) == false)
        #expect(CoverageNoticeRules.adopts(origin: notification.origin, authority: .localWorkflow))
    }

    /// B · a simulated row addressed to this very id is invisible to a proved identity.
    ///
    /// Written through one store and read through another over the same suite, because
    /// the shared key is the whole hazard: this is the restoration path, not an injection.
    @Test func simulatedRowsAreInvisibleToAProvedIdentity() throws {
        let suiteName = "turnoev.tests.coverage.notices.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let demo = CoverageStore(capability: .localWorkflow, defaults: defaults)
        demo.notifications = [
            Self.row(id: "cnot-1", recipient: "DRV-TEST-001", kind: .guardAvailable, title: "Guardia disponible"),
            Self.row(id: "cnot-2", recipient: "DRV-TEST-001", kind: .absenceApproved, title: "Ausencia aprobada"),
        ]
        demo.updatePolicy(.standard)

        let proved = CoverageStore(capability: .stationRequired, defaults: defaults)

        // Restored — nothing was deleted from the board.
        #expect(proved.notifications.count == 2)
        // And unreadable, counted as nothing, by the identity that does not own them.
        #expect(proved.notifications(for: "DRV-TEST-001").isEmpty)
        #expect(proved.unreadCount(for: "DRV-TEST-001") == 0)
        #expect(proved.visibleNotifications.isEmpty)
    }

    /// C · a row the station genuinely routed is shown, and only to that session.
    ///
    /// Nothing can mint one today. Asserting it keeps the cut from being a wall: the day
    /// a coverage service routes a seat, this is the path it arrives on.
    @Test func backendRowsAreShownOnlyToTheProvedSession() throws {
        let suiteName = "turnoev.tests.coverage.notices.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let routed = Self.row(
            id: "cnot-backend",
            recipient: "DRV-9001",
            kind: .guardConfirmed,
            title: "Guardia confirmada",
            origin: .backend
        )

        let proved = CoverageStore(capability: .stationRequired, defaults: defaults)
        proved.notifications = [routed]
        #expect(proved.notifications(for: "DRV-9001").count == 1)
        #expect(proved.unreadCount(for: "DRV-9001") == 1)

        // Strict in both directions: the laboratory does not read the station's tray
        // either. A row here points at a seat id, and that seat exists in one book only.
        let laboratory = CoverageStore(capability: .localWorkflow, defaults: defaults)
        laboratory.notifications = [routed]
        #expect(laboratory.notifications(for: "DRV-9001").isEmpty)
        #expect(laboratory.unreadCount(for: "DRV-9001") == 0)
    }

    /// D · the badge counts exactly what the tray renders.
    @Test func unreadCountMatchesTheVisibleTray() throws {
        let suiteName = "turnoev.tests.coverage.notices.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let proved = CoverageStore(capability: .stationRequired, defaults: defaults)
        proved.notifications = [
            Self.row(id: "cnot-s1", recipient: "DRV-9001", kind: .guardAvailable, title: "Guardia disponible"),
            Self.row(id: "cnot-s2", recipient: "DRV-9001", kind: .swapResolved, title: "Intercambio aprobado"),
            Self.row(id: "cnot-b1", recipient: "DRV-9001", kind: .guardConfirmed, title: "Guardia confirmada", origin: .backend),
            Self.row(id: "cnot-b2", recipient: "DRV-9001", kind: .guardReminder, title: "Cambio de horario", isRead: true, origin: .backend),
            Self.row(id: "cnot-b3", recipient: "acc-sup-201", kind: .criticalCoverage, title: "Turno sin candidatos", origin: .backend),
        ]

        let tray = proved.notifications(for: "DRV-9001")
        #expect(tray.count == 2)
        #expect(proved.unreadCount(for: "DRV-9001") == tray.count { !$0.isRead })
        #expect(proved.unreadCount(for: "DRV-9001") == 1)
        #expect(tray.allSatisfy { $0.origin == .backend })
    }

    /// E · marking read touches only what the reader can see.
    ///
    /// Knowing an id is not title to a row, and in a board of fixtures every id is
    /// guessable.
    @Test func markingReadCannotReachTheOtherBook() throws {
        let suiteName = "turnoev.tests.coverage.notices.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let proved = CoverageStore(capability: .stationRequired, defaults: defaults)
        proved.notifications = [
            Self.row(id: "cnot-sim", recipient: "DRV-9001", kind: .absenceApproved, title: "Ausencia aprobada"),
            Self.row(id: "cnot-real", recipient: "DRV-9001", kind: .guardConfirmed, title: "Guardia confirmada", origin: .backend),
        ]

        proved.markNotificationRead(id: "cnot-sim")
        #expect(proved.notifications.first { $0.id == "cnot-sim" }?.isRead == false)

        proved.markAllNotificationsRead(for: "DRV-9001")
        #expect(proved.notifications.first { $0.id == "cnot-real" }?.isRead == true)
        #expect(proved.notifications.first { $0.id == "cnot-sim" }?.isRead == false)
    }

    // MARK: Environment

    /// F · a row written in the laboratory stays there, and comes back.
    @Test func laboratoryRowsDoNotFollowTheDriverOut() throws {
        let suiteName = "turnoev.tests.coverage.notices.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let environment = RuntimeEnvironment(defaults: defaults)
        let store = CoverageStore(capability: .localWorkflow, defaults: defaults, environment: environment)

        store.notifications = [Self.row(id: "cnot-prod", recipient: "DRV-TEST-001", kind: .guardReminder, title: "Cambio de horario")]
        store.updatePolicy(.standard)

        environment.set(.test)
        store.adoptEnvironment()
        #expect(store.notifications.isEmpty)

        store.notifications = [Self.row(id: "cnot-lab", recipient: "DRV-TEST-001", kind: .guardConfirmed, title: "Guardia confirmada")]
        store.updatePolicy(.standard)

        environment.set(.production)
        store.adoptEnvironment()

        #expect(store.notifications.count == 1)
        #expect(store.notifications.first?.id == "cnot-prod")
        // Two books, both still on disk. Leaving the laboratory deleted nothing.
        #expect(defaults.data(forKey: "turnoev.coverage.v1") != nil)
        #expect(defaults.data(forKey: "turnoev.coverage.v1.lab") != nil)

        environment.set(.test)
        store.adoptEnvironment()
        #expect(store.notifications.first?.id == "cnot-lab")
        #expect(store.notifications(for: "DRV-TEST-001").count == 1)
    }

    // MARK: The mirror into the general bell

    /// G · a coverage row reaches the bell carrying its own provenance.
    @Test func theMirrorKeepsProvenance() throws {
        #expect(CoverageNotificationOrigin.simulated.generalBell == .simulated)
        #expect(CoverageNotificationOrigin.backend.generalBell == .backend)

        let suiteName = "turnoev.tests.coverage.mirror.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fleet = FleetStore(environment: RuntimeEnvironment(defaults: defaults), defaults: defaults)
        let coverage = CoverageStore(capability: .localWorkflow, defaults: defaults)
        coverage.attach(fleet: fleet)

        let actor = try #require(StaffDirectory.accounts.first { $0.role == .supervisor })
        let before = fleet.notices.count
        coverage.absences = [Self.absence(id: "abs-mirror", driverId: fleet.driver.id)]
        coverage.decideAbsence(id: "abs-mirror", approved: true, note: "", by: actor)

        #expect(coverage.notifications.first?.origin == .simulated)
        #expect(fleet.notices.count == before + 1)
        #expect(fleet.notices.first?.title == "Ausencia aprobada")
        #expect(fleet.notices.first?.origin == .simulated)
    }

    /// G · and the day the two boundaries move apart, nothing is laundered across.
    ///
    /// The bell may open before the coverage service does. Pinning the coverage
    /// capability reproduces that future: a local book still writing, a proved bell that
    /// refuses the copy rather than stamping it as the station's.
    @Test func theMirrorRefusesToLaunderASimulatedRow() throws {
        let suiteName = "turnoev.tests.coverage.mirror.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let profileId = "DRV-MIRROR-\(UUID().uuidString.prefix(8))"
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            AssignmentBook.remove(driverId: profileId)
        }

        let fleet = FleetStore(environment: RuntimeEnvironment(defaults: defaults), defaults: defaults)
        try fleet.signIn(
            principal: SessionPrincipal(
                authUserId: UUID().uuidString,
                profileId: profileId,
                name: "Conductor de prueba",
                employeeNumber: "EMP-TEST",
                email: "coverage.driver@joramza.test",
                role: .driver,
                stationId: "est-001",
                stationCode: "IZT",
                stationName: "Estación Iztapalapa",
                shiftGroup: .weekday,
                shiftSlot: .morning
            ),
            method: .credentials
        )

        let coverage = CoverageStore(capability: .localWorkflow, defaults: defaults)
        coverage.attach(fleet: fleet)

        let actor = try #require(StaffDirectory.accounts.first { $0.role == .supervisor })
        coverage.absences = [Self.absence(id: "abs-mirror", driverId: fleet.driver.id)]
        coverage.decideAbsence(id: "abs-mirror", approved: true, note: "", by: actor)

        #expect(coverage.notifications.count == 1)
        #expect(coverage.notifications.first?.origin == .simulated)
        #expect(fleet.notices.isEmpty)
        #expect(fleet.mirrorNotice(kind: .station, title: "Guardia confirmada", body: "—", origin: .simulated) == false)
    }

    // MARK: Writing and the demonstration

    /// The frontier itself: the consoles cannot address a proved driver either.
    ///
    /// Half the producers were already gated on the driver's side; these are the ones that
    /// were not, because they belong to a supervisor screen.
    @Test func consoleProducersWriteNothingForAProvedIdentity() throws {
        let suiteName = "turnoev.tests.coverage.notices.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let proved = CoverageStore(capability: .stationRequired, defaults: defaults)
        let actor = try #require(StaffDirectory.accounts.first { $0.role == .supervisor })
        proved.absences = [Self.absence(id: "abs-blocked", driverId: "DRV-9001")]

        proved.decideAbsence(id: "abs-blocked", approved: true, note: "", by: actor)
        proved.notifySupervisors(
            stationId: actor.stationId ?? "est-001",
            kind: .criticalCoverage,
            title: "Turno sin candidatos",
            body: "—"
        )

        #expect(proved.notifications.isEmpty)
        #expect(proved.visibleNotifications.isEmpty)
    }

    /// H · the demonstration tray behaves exactly as it did.
    @Test func theDemonstrationTrayIsUnchanged() throws {
        let suiteName = "turnoev.tests.coverage.notices.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let demo = CoverageStore(capability: .localWorkflow, defaults: defaults)
        #expect(demo.noticeAuthority == .localWorkflow)

        let actor = try #require(StaffDirectory.accounts.first { $0.role == .supervisor })
        demo.absences = [Self.absence(id: "abs-demo", driverId: "DRV-TEST-001")]
        demo.decideAbsence(id: "abs-demo", approved: true, note: "", by: actor)

        let tray = demo.notifications(for: "DRV-TEST-001")
        #expect(tray.count == 1)
        #expect(tray.first?.title == "Ausencia aprobada")
        #expect(tray.first?.origin == .simulated)
        #expect(demo.unreadCount(for: "DRV-TEST-001") == 1)
        #expect(demo.visibleNotifications.count == demo.notifications.count)

        demo.markAllNotificationsRead(for: "DRV-TEST-001")
        #expect(demo.unreadCount(for: "DRV-TEST-001") == 0)
    }

    // MARK: Fixtures

    private static func row(
        id: String,
        recipient: String,
        kind: CoverageNoticeKind,
        title: String,
        isRead: Bool = false,
        origin: CoverageNotificationOrigin = .simulated
    ) -> CoverageNotification {
        CoverageNotification(
            id: id,
            recipientId: recipient,
            kind: kind,
            title: title,
            body: "—",
            createdAt: Date(),
            vacancyId: nil,
            swapId: nil,
            isRead: isRead,
            origin: origin
        )
    }

    private static func absence(id: String, driverId: String) -> AbsenceRequest {
        AbsenceRequest(
            id: id,
            driverId: driverId,
            driverName: "Conductor de prueba",
            employeeNumber: "EMP-TEST",
            stationId: "est-001",
            stationCode: "IZT",
            date: ShiftRules.calendar.startOfDay(for: Date()),
            slot: .morning,
            kind: .scheduled,
            reason: "Cita médica",
            comments: "",
            evidence: nil,
            status: .requested,
            createdAt: Date(),
            vacancyId: nil,
            decidedAt: nil,
            decidedBy: nil,
            decisionNote: nil
        )
    }
}

// MARK: - 15B.14 · notices and the station's voice

/// 15B.14 · the app may not speak in the station's voice.
///
/// A notice is the smallest thing in this app and the most persuasive: it is a sentence
/// addressed to the driver, in the second person, asserting that some desk somewhere
/// received, approved or confirmed something. Eighteen producers existed and every one
/// of them minted its sentence locally.
@MainActor
struct NoticeBoundaryTests {

    // MARK: Provenance

    /// A · a notice stored before provenance existed is read as simulated.
    @Test func legacyNoticeDecodesAsSimulated() throws {
        let json = #"""
        {
          "id": "not-legacy",
          "kind": "station",
          "title": "Incidencia enviada a la estación",
          "body": "Tu reporte de daño quedó en revisión.",
          "createdAt": "2026-08-20T11:07:00Z",
          "read": false
        }
        """#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notice = try decoder.decode(Notice.self, from: Data(json.utf8))

        #expect(notice.origin == .simulated)
        #expect(notice.isAuthoritative == false)
        // And absence is never promoted: the sentence above is exactly the one that must
        // not survive into a real operation.
        #expect(NoticeRules.adopts(origin: notice.origin, authority: .stationPublished) == false)
    }

    /// B · a simulated notice is invisible to a proved identity in production.
    ///
    /// Notices carry no owner field — the container says whose they are — so provenance
    /// is the whole test, and it is the one that was missing.
    @Test func simulatedNoticesAreNotShownInProduction() {
        let simulated = Self.notice(id: "not-sim", title: "Reserva confirmada", origin: .simulated)

        #expect(NoticeRules.visible([simulated], authority: .stationPublished).isEmpty)
        #expect(NoticeRules.visible([simulated], authority: .localBulletin).count == 1)
    }

    /// C · a notice the station genuinely published is shown.
    ///
    /// Nothing can mint one today, and that is the point of asserting it: the cut must
    /// close the local door without walling off the real one. The day a station publishes
    /// a bay closure, this is the path it arrives on.
    @Test func backendNoticesAreShownInProduction() throws {
        let published = Self.notice(
            id: "not-backend",
            title: "Aviso de estación · Bahía 4 cerrada",
            origin: .backend
        )

        #expect(NoticeRules.visible([published], authority: .stationPublished).count == 1)
        #expect(NoticeRules.visible([published], authority: .localBulletin).count == 1)

        let bench = try Self.bench()
        defer { bench.discard() }

        bench.store.notices = [published, Self.notice(id: "not-sim", title: "Crédito aprobado", origin: .simulated)]

        #expect(bench.store.visibleNotices.count == 1)
        #expect(bench.store.visibleNotices.first?.id == "not-backend")
    }

    // MARK: The single frontier

    /// D · no local operation can publish in the station's voice under a proved identity.
    ///
    /// Walked through the actual producers rather than through `pushNotice` alone: the
    /// failure being fixed was that each of these narrated its own local success as an
    /// authority's acknowledgement.
    @Test func blockedOperationsPublishNoNotice() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        #expect(bench.store.canPublishStationNotices == false)
        #expect(bench.store.noticeAuthority == .stationPublished)

        // The frontier itself.
        #expect(bench.store.pushNotice(kind: .station, title: "Depósito notificado a gerencia", body: "—") == false)

        // "Reporte enviado a supervisión".
        #expect(bench.store.notifySupervisor(reason: "La unidad no enciende") == false)

        // "Incidencia enviada a la estación".
        #expect(throws: OperationalMutationError.backendRequired) {
            try bench.store.reportIncident(kind: .damage, description: "Golpe menor.", photos: [])
        }

        // "Crédito aprobado".
        #expect(throws: FinancialMutationError.backendRequired) {
            try bench.store.requestCredit()
        }

        #expect(bench.store.notices.isEmpty)
        #expect(bench.store.visibleNotices.isEmpty)
        #expect(bench.store.unreadNoticeCount == 0)
    }

    /// E · the recovery programme holds no seat it cannot actually hold.
    ///
    /// The most seductive of the eighteen: a driver who has just been told they lost a
    /// bonus, offered a way back, and shown "Reserva confirmada" for a day nobody
    /// reserved — who would then arrive at a station not expecting them.
    @Test func recoveryBookingIsRefusedInProductionWithNoNotice() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        let day = ShiftRules.calendar.date(byAdding: .day, value: 7, to: bench.store.now) ?? bench.store.now

        #expect(bench.store.bookRecovery(date: day, slot: .morning, bonus: .punctuality) == false)

        #expect(bench.store.recoveryBookings.isEmpty)
        #expect(bench.store.upcomingRecoveryBookings.isEmpty)
        #expect(bench.store.recoveryBooking(on: day) == nil)
        #expect(bench.store.notices.isEmpty)

        // Inside the laboratory the programme works exactly as it did.
        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        let labDay = BonusRules.recoveryGroup(for: bench.store.driver) == bench.store.driver.group
            ? nil
            : Self.firstBookableDay(bench)
        if let labDay {
            #expect(bench.store.bookRecovery(date: labDay, slot: .morning, bonus: .punctuality))
            #expect(bench.store.recoveryBookings.count == 1)
            #expect(bench.store.visibleNotices.contains { $0.title.contains("Reserva confirmada") })
            #expect(bench.store.visibleNotices.allSatisfy { $0.origin == .simulated })
        }
    }

    // MARK: Environment

    /// F · a notice written in the laboratory does not follow the driver out of it.
    ///
    /// Not deleted — filtered. It is waiting where it was written.
    @Test func laboratoryNoticesDoNotLeakIntoProductionAndComeBack() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        #expect(bench.store.pushNotice(kind: .station, title: "Guardia confirmada", body: "Sábado matutino."))
        #expect(bench.store.visibleNotices.count == 1)
        #expect(bench.store.visibleNotices.first?.origin == .simulated)

        bench.environment.set(.production)
        bench.store.adoptEnvironment()

        #expect(bench.store.notices.isEmpty)
        #expect(bench.store.visibleNotices.isEmpty)
        #expect(bench.store.unreadNoticeCount == 0)
        // Both blobs are still on disk; nothing was cleaned up to reach that empty bell.
        #expect(bench.defaults.data(forKey: bench.productionKey) != nil)
        #expect(bench.defaults.data(forKey: bench.laboratoryKey) != nil)

        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        #expect(bench.store.visibleNotices.count == 1)
        #expect(bench.store.visibleNotices.first?.title == "Guardia confirmada")
    }

    /// G · the unread badge counts only what may be shown.
    ///
    /// A bell badge over an empty list is its own small lie, and it is the one a filter
    /// applied at the view layer alone would have left standing.
    @Test func unreadCountRespectsProvenance() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        bench.store.notices = [
            Self.notice(id: "not-sim-1", title: "Turno cerrado", origin: .simulated),
            Self.notice(id: "not-sim-2", title: "Crédito aprobado", origin: .simulated),
            Self.notice(id: "not-backend", title: "Aviso de estación", origin: .backend),
        ]

        #expect(bench.store.visibleNotices.count == 1)
        #expect(bench.store.unreadNoticeCount == 1)

        bench.store.markAllNoticesRead()

        #expect(bench.store.unreadNoticeCount == 0)
        // The laboratory's own notices were not dismissed by a reader who could not see
        // them: they come back unread, in their own environment.
        #expect(bench.store.notices.filter { $0.origin == .simulated }.allSatisfy { !$0.read })
    }

    /// H · the demonstration bell is untouched.
    @Test func theDemonstrationSessionKeepsItsNotices() throws {
        let suiteName = "turnoev.tests.notices.demo.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = FleetStore(environment: RuntimeEnvironment(defaults: defaults), defaults: defaults)

        #expect(store.canPublishStationNotices)
        #expect(store.noticeAuthority == .localBulletin)
        // Everything the seed wrote is still readable: nothing was filtered out from under
        // the demonstration.
        #expect(store.visibleNotices.count == store.notices.count)
        #expect(store.notices.allSatisfy { $0.origin == .simulated })

        let before = store.notices.count
        #expect(store.pushNotice(kind: .station, title: "Incidencia enviada a la estación", body: "En revisión."))
        #expect(store.notices.count == before + 1)
        #expect(store.visibleNotices.count == before + 1)
        #expect(store.unreadNoticeCount >= 1)
    }

    // MARK: Bench

    private struct Bench {
        let suiteName: String
        let defaults: UserDefaults
        let environment: RuntimeEnvironment
        let store: FleetStore
        let profileId: String

        var productionKey: String { "turnoev.state.v4.\(profileId)" }
        var laboratoryKey: String { "turnoev.state.v4.lab.\(profileId)" }

        func discard() {
            defaults.removePersistentDomain(forName: suiteName)
            AssignmentBook.remove(driverId: profileId)
        }
    }

    private static func bench() throws -> Bench {
        let suiteName = "turnoev.tests.notices.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let environment = RuntimeEnvironment(defaults: defaults)
        let store = FleetStore(environment: environment, defaults: defaults)
        let profileId = "DRV-NOTICE-\(UUID().uuidString.prefix(8))"

        try store.signIn(
            principal: SessionPrincipal(
                authUserId: UUID().uuidString,
                profileId: profileId,
                name: "Conductor de prueba",
                employeeNumber: "EMP-TEST",
                email: "notice.driver@joramza.test",
                role: .driver,
                stationId: "est-001",
                stationCode: "IZT",
                stationName: "Estación Iztapalapa",
                shiftGroup: .weekday,
                shiftSlot: .morning
            ),
            method: .credentials
        )

        return Bench(
            suiteName: suiteName,
            defaults: defaults,
            environment: environment,
            store: store,
            profileId: profileId
        )
    }

    /// First day the recovery calendar actually accepts, so the laboratory half of E is
    /// exercising the boundary and not the programme's own eligibility rules.
    private static func firstBookableDay(_ bench: Bench) -> Date? {
        let calendar = ShiftRules.calendar
        let driver = bench.store.driver
        for offset in 1...21 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: bench.store.now) else { continue }
            if BonusRules.canBook(driver: driver, date: day, now: bench.store.now) { return day }
        }
        return nil
    }

    private static func notice(id: String, title: String, origin: NoticeOrigin) -> Notice {
        Notice(
            id: id,
            kind: .station,
            title: title,
            body: "—",
            createdAt: Date(),
            read: false,
            origin: origin
        )
    }
}

// MARK: - 15B.13.3 · shift cycle and incident boundary

/// 15B.13.3 · a shift and an incident are facts of a station's day, not rows of a phone.
///
/// The pure cases come first, because provenance is what the whole cut rests on: a row
/// carrying the right `profileId` is not a station certifying that nine hours were
/// worked, and until 15B.13.3 the two were indistinguishable.
@MainActor
struct OperationalCycleBoundaryTests {

    private static let backendDriverId = "DRV-TEST-001"

    // MARK: Provenance

    /// A · an open shift stored before provenance existed is read as simulated.
    @Test func legacyActiveShiftDecodesAsSimulated() throws {
        let json = #"""
        {
          "id": "shift-legacy",
          "driverId": "DRV-TEST-001",
          "vehicleId": "veh-014",
          "group": "weekday",
          "slot": "morning",
          "scheduledStartAt": "2026-08-20T11:00:00Z",
          "startedAt": "2026-08-20T11:07:00Z",
          "lateMinutes": 7,
          "startOdometerKm": 96480,
          "startBatteryPct": 91,
          "photos": {},
          "trips": 3,
          "earningsMxn": 640
        }
        """#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let shift = try decoder.decode(ActiveShift.self, from: Data(json.utf8))

        #expect(shift.origin == .simulated)
        #expect(shift.isAuthoritative == false)
    }

    /// B · and so is a closed one — the row a settlement multiplies.
    @Test func legacyShiftRecordDecodesAsSimulated() throws {
        let json = #"""
        {
          "id": "shift-h-3",
          "driverId": "DRV-TEST-001",
          "vehicleId": "veh-014",
          "vehicleInternalNumber": "TEV-014",
          "group": "weekday",
          "slot": "morning",
          "scheduledStartAt": "2026-08-18T11:00:00Z",
          "startedAt": "2026-08-18T11:00:00Z",
          "endedAt": "2026-08-18T20:00:00Z",
          "lateMinutes": 0,
          "paidBackMinutes": 0,
          "startOdometerKm": 96000,
          "endOdometerKm": 96180,
          "startBatteryPct": 92,
          "endBatteryPct": 26,
          "trips": 14,
          "earningsMxn": 1450
        }
        """#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(ShiftRecord.self, from: Data(json.utf8))

        #expect(record.origin == .simulated)
        #expect(record.isAuthoritative == false)

        // An incident behaves the same way, and for the same reason: `.open` renders as
        // "waiting for supervision" on every screen that shows it.
        let incidentJSON = #"""
        {
          "id": "inci-legacy",
          "driverId": "DRV-TEST-001",
          "vehicleId": "veh-014",
          "vehicleInternalNumber": "TEV-014",
          "kind": "damage",
          "createdAt": "2026-08-18T20:10:00Z",
          "description": "Rayón en salpicadera.",
          "photos": [],
          "status": "open"
        }
        """#
        let incident = try decoder.decode(Incident.self, from: Data(incidentJSON.utf8))
        #expect(incident.origin == .simulated)
    }

    /// C · a simulated shift carrying the proved identity's own id is still refused.
    ///
    /// This is the exact row a laboratory session run by DRV-TEST-001 produces, and the
    /// one that used to restore straight into production because `driverId` matched.
    @Test func simulatedShiftOfTheSameDriverIsRefusedInProduction() {
        let shift = Self.activeShift(driverId: Self.backendDriverId, origin: .simulated)

        #expect(
            OperationalRecordRules.shift(shift, driverId: Self.backendDriverId, capability: .stationRequired) == nil
        )
        // And it is not gone: the laboratory still adopts it.
        #expect(
            OperationalRecordRules.shift(shift, driverId: Self.backendDriverId, capability: .localWorkflow)?.id == shift.id
        )
    }

    /// D · a certified shift belonging to somebody else is refused too.
    @Test func backendShiftOfAnotherDriverIsRefused() {
        let foreign = Self.activeShift(driverId: "DRV-OTHER-777", origin: .backend)

        #expect(
            OperationalRecordRules.shift(foreign, driverId: Self.backendDriverId, capability: .stationRequired) == nil
        )
        #expect(
            OperationalRecordRules.shift(foreign, driverId: Self.backendDriverId, capability: .localWorkflow) == nil
        )

        let history = [
            Self.record(driverId: Self.backendDriverId, origin: .simulated),
            Self.record(driverId: "DRV-OTHER-777", origin: .backend),
        ]
        #expect(
            OperationalRecordRules.history(history, driverId: Self.backendDriverId, capability: .stationRequired).isEmpty
        )
    }

    /// E · the one combination that is adoptable: certified, and this driver's.
    @Test func backendShiftOfTheSameDriverIsAdopted() {
        let own = Self.activeShift(driverId: Self.backendDriverId, origin: .backend)

        #expect(
            OperationalRecordRules.shift(own, driverId: Self.backendDriverId, capability: .stationRequired)?.id == own.id
        )

        let history = [
            Self.record(driverId: Self.backendDriverId, origin: .backend),
            Self.record(driverId: Self.backendDriverId, origin: .simulated),
        ]
        let adopted = OperationalRecordRules.history(
            history,
            driverId: Self.backendDriverId,
            capability: .stationRequired
        )
        #expect(adopted.count == 1)
        #expect(adopted.first?.origin == .backend)
    }

    // MARK: Writes under a proved identity in production

    /// F · the start of shift stops before the first byte it would have written.
    ///
    /// Asserted one effect at a time, because opening a shift is not one record: it mints
    /// the shift, takes the unit, overwrites its odometer and battery, files evidence and
    /// may register a late arrival.
    @Test func startShiftWritesNothingUnderAProvedIdentityInProduction() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        #expect(bench.store.canRunOperationalCycle == false)
        #expect(bench.store.operationalCapability == .stationRequired)

        let unit = Self.vehicle()
        #expect(throws: OperationalMutationError.backendRequired) {
            try bench.store.startShift(
                vehicle: unit,
                odometerKm: 96_500,
                batteryPct: 88,
                odometerPhoto: Data([0x01]),
                batteryPhoto: Data([0x02])
            )
        }

        #expect(bench.store.activeShift == nil)
        #expect(bench.store.vehicles.isEmpty)
        #expect(bench.store.notices.isEmpty)
        #expect(bench.store.capturedPhotoCount == 0)
        #expect(bench.store.history.isEmpty)

        // Nothing reached storage either: the refusal is upstream of `persist`.
        let stored = try #require(bench.defaults.data(forKey: bench.productionKey))
        let text = try #require(String(data: stored, encoding: .utf8))
        #expect(text.contains("\"activeShift\":null") || !text.contains(unit.id))
    }

    /// G · and the close of shift never turns a local shift into a closed record.
    @Test func finishShiftCreatesNoRecordUnderAProvedIdentityInProduction() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        #expect(throws: OperationalMutationError.backendRequired) {
            try bench.store.finishShift(endOdometerKm: 96_700, endBatteryPct: 24, photo: Data([0x03]))
        }

        #expect(bench.store.history.isEmpty)
        #expect(bench.store.notices.isEmpty)
        #expect(bench.store.activeShift == nil)
    }

    /// H · an incident is not filed, and does not pretend to have been sent.
    @Test func reportIncidentCreatesNothingUnderAProvedIdentityInProduction() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        #expect(throws: OperationalMutationError.backendRequired) {
            try bench.store.reportIncident(
                kind: .accident,
                description: "Colisión con tercero en Calzada Ermita.",
                photos: [Data([0x04])]
            )
        }

        #expect(bench.store.incidents.isEmpty)
        #expect(bench.store.notices.isEmpty)
    }

    /// K · no refused attempt moves a single derived number.
    ///
    /// The chain in full: shift → history → income → bonus → settlement. A blocked start
    /// must leave "Sin evaluar" standing, the day at zero and the week's net untouched.
    @Test func refusedAttemptsLeaveBonusesGoalsAndWalletUntouched() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        let wallet = WalletStore(fleet: bench.store)
        let reference = bench.store.now
        let netBefore = wallet.currentSettlement(now: reference)?.netMxn ?? 0

        #expect(throws: (any Error).self) {
            try bench.store.startShift(
                vehicle: Self.vehicle(),
                odometerKm: 96_500,
                batteryPct: 88,
                odometerPhoto: nil,
                batteryPhoto: nil
            )
        }
        #expect(throws: (any Error).self) {
            try bench.store.finishShift(endOdometerKm: 96_700, endBatteryPct: 24, photo: nil)
        }
        #expect(throws: (any Error).self) {
            try bench.store.reportIncident(kind: .damage, description: "Golpe menor.", photos: [])
        }

        #expect(bench.store.history.isEmpty)
        #expect(bench.store.incomes.isEmpty)
        #expect(bench.store.earnedToday(reference: reference) == 0)
        #expect(bench.store.tripsToday(reference: reference) == 0)
        #expect(bench.store.bonusPayableMxn(reference: reference) == 0)

        // Every bonus stays unevaluated: a week with no evidence is not a week lost.
        let evaluations = bench.store.bonusEvaluations(reference: reference)
        #expect(!evaluations.isEmpty)
        for evaluation in evaluations {
            #expect(evaluation.payableMxn == 0)
        }

        #expect((wallet.currentSettlement(now: reference)?.netMxn ?? 0) == netBefore)
        #expect(bench.store.raiseBonusAlert(reference: reference) == nil)
    }

    // MARK: The laboratory keeps working

    /// A real TEST credential follows the shared laboratory clock but writes the shift
    /// through Supabase. The environment selector must not downgrade it to a local shift.
    @Test func backendTestDriverUsesAuthoritativeShiftCycle() throws {
        let bench = try Self.bench(environmentId: LabEnvironment.sharedTestId)
        defer { bench.discard() }

        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        #expect(bench.store.isBackendTestSession)
        #expect(bench.store.usesBackendShiftCycle)
        #expect(bench.store.canRunShiftCycle)
        #expect(bench.store.shiftCapability == .stationRequired)
        #expect(bench.store.usesBackendIncidentCycle)
        #expect(bench.store.usesBackendCoverageCycle)
        #expect(bench.store.usesBackendFinancialCycle)
        #expect(!bench.store.canSimulateFinancialState)
        #expect(!bench.store.canSimulateOperationalCoordination)
        #expect(!bench.store.canReportIncident)
        #expect(bench.store.operationalCapability == .localWorkflow)
    }

    /// 15G · the ledger is authoritative for both the wallet and the open shift.
    /// Rows from older shifts remain visible in history but cannot inflate the totals
    /// shown for the shift that is currently open.
    @Test func backendFinancialSnapshotRefreshesOnlyTheOpenShiftTotals() throws {
        let bench = try Self.bench(environmentId: LabEnvironment.sharedTestId)
        defer { bench.discard() }

        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        let openShiftId = UUID()
        let olderShiftId = UUID()
        let stationId = UUID()
        let driverProfileId = UUID()
        let reportedAt = Date(timeIntervalSince1970: 1_788_154_100)
        bench.store.activeShift = ActiveShift(
            id: openShiftId.uuidString,
            driverId: bench.profileId,
            vehicleId: "veh-backend-test",
            group: .weekday,
            slot: .morning,
            scheduledStartAt: reportedAt,
            startedAt: reportedAt,
            lateMinutes: 0,
            startOdometerKm: 96_000,
            startBatteryPct: 90,
            photos: [:],
            trips: 99,
            earningsMxn: 9_999,
            origin: .backend
        )

        func income(shiftId: UUID, source: String, amount: Int, trips: Int) -> SupabaseFinancialService.IncomeRow {
            SupabaseFinancialService.IncomeRow(
                id: UUID(),
                station_id: stationId,
                shift_id: shiftId,
                driver_profile_id: driverProfileId,
                reversal_of: nil,
                folio: "INC-\(UUID().uuidString.prefix(8))",
                source: source,
                amount_mxn: amount,
                trips: trips,
                external_reference: nil,
                evidence_path: nil,
                note: nil,
                reported_at: reportedAt
            )
        }

        let snapshot = SupabaseFinancialService.DriverSnapshot(
            driverProfileId: driverProfileId,
            incomes: [
                income(shiftId: openShiftId, source: "uber", amount: 123, trips: 2),
                income(shiftId: openShiftId, source: "didi", amount: 77, trips: 1),
                income(shiftId: olderShiftId, source: "other", amount: 900, trips: 8),
            ],
            cashCharges: [],
            bankAccounts: [],
            settlements: [],
            transfers: []
        )

        bench.store.adoptBackendFinancialSnapshot(snapshot)

        #expect(bench.store.incomes.count == 3)
        #expect(bench.store.incomes.allSatisfy { $0.origin == .backend })
        #expect(bench.store.activeShift?.earningsMxn == 200)
        #expect(bench.store.activeShift?.trips == 3)
    }

    /// I · inside the laboratory the whole cycle runs exactly as before.
    @Test func theLaboratoryStillRunsTheCompleteCycle() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        let unit = try Self.enterLaboratoryWithAUnit(bench)

        #expect(bench.store.canRunOperationalCycle)
        #expect(bench.store.operationalCapability == .localWorkflow)

        let shift = try bench.store.startShift(
            vehicle: unit,
            odometerKm: unit.odometerKm,
            batteryPct: 88,
            odometerPhoto: Data([0x01]),
            batteryPhoto: Data([0x02])
        )

        #expect(shift.origin == .simulated)
        #expect(bench.store.activeShift?.id == shift.id)
        #expect(bench.store.capturedPhotoCount == 2)
        #expect(bench.store.isInspectionComplete)

        let taken = try #require(bench.store.vehicles.first { $0.id == unit.id })
        #expect(taken.status == .occupied)
        #expect(taken.occupiedBy == bench.profileId)

        try bench.store.reportIncident(kind: .damage, description: "Rayón lateral en patio.", photos: [])
        #expect(bench.store.incidents.count == 1)
        #expect(bench.store.incidents.first?.origin == .simulated)

        let summary = try bench.store.finishShift(
            endOdometerKm: unit.odometerKm + 180,
            endBatteryPct: 26,
            photo: Data([0x03])
        )

        #expect(summary.kmDriven == 180)
        #expect(bench.store.activeShift == nil)
        #expect(bench.store.history.count == 1)
        #expect(bench.store.history.first?.origin == .simulated)

        let released = try #require(bench.store.vehicles.first { $0.id == unit.id })
        #expect(released.status == .available)
        #expect(released.occupiedBy == nil)
    }

    /// J · a simulated shift left running does not follow the driver into production.
    ///
    /// Not deleted, not closeable, not blocking — and waiting where it was left.
    @Test func aSimulatedShiftDoesNotSurviveIntoProductionAndComesBack() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        let unit = try Self.enterLaboratoryWithAUnit(bench)
        let shift = try bench.store.startShift(
            vehicle: unit,
            odometerKm: unit.odometerKm,
            batteryPct: 90,
            odometerPhoto: nil,
            batteryPhoto: nil
        )
        #expect(bench.store.activeShift?.id == shift.id)

        bench.environment.set(.production)
        bench.store.adoptEnvironment()

        // Gone from production, in every sense the interface can read.
        #expect(bench.store.activeShift == nil)
        #expect(bench.store.activeVehicle == nil)
        #expect(bench.store.canActOnActiveShift == false)
        #expect(bench.store.history.isEmpty)
        #expect(bench.store.incidents.isEmpty)
        // And it does not stand in the way of the real operation starting one day.
        #expect(throws: OperationalMutationError.backendRequired) {
            try bench.store.finishShift(endOdometerKm: unit.odometerKm + 40, endBatteryPct: 30, photo: nil)
        }

        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        // Exactly where it was left, on the same identity, with no sign in.
        #expect(bench.store.activeShift?.id == shift.id)
        #expect(bench.store.activeShift?.origin == .simulated)
        #expect(bench.store.canActOnActiveShift)
        #expect(bench.store.isBackendSession)

        // And it closes there, which is where it belongs.
        let summary = try bench.store.finishShift(
            endOdometerKm: unit.odometerKm + 120,
            endBatteryPct: 28,
            photo: nil
        )
        #expect(summary.kmDriven == 120)
        #expect(bench.store.history.first?.origin == .simulated)
    }

    // MARK: Bench

    private struct Bench {
        let suiteName: String
        let defaults: UserDefaults
        let environment: RuntimeEnvironment
        let store: FleetStore
        let profileId: String

        var productionKey: String { "turnoev.state.v4.\(profileId)" }

        func discard() {
            defaults.removePersistentDomain(forName: suiteName)
            // The assignment book lives on the device, not in the suite.
            AssignmentBook.remove(driverId: profileId)
        }
    }

    private static func bench(environmentId: String? = nil) throws -> Bench {
        let suiteName = "turnoev.tests.cycle.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let environment = RuntimeEnvironment(defaults: defaults)
        let store = FleetStore(environment: environment, defaults: defaults)
        let profileId = "DRV-CYCLE-\(UUID().uuidString.prefix(8))"

        try store.signIn(
            principal: SessionPrincipal(
                authUserId: UUID().uuidString,
                profileId: profileId,
                name: "Conductor de prueba",
                employeeNumber: "EMP-TEST",
                email: "cycle.driver@joramza.test",
                role: .driver,
                environmentId: environmentId,
                stationId: "est-001",
                stationCode: "IZT",
                stationName: "Estación Iztapalapa",
                shiftGroup: .weekday,
                shiftSlot: .morning
            ),
            method: .credentials
        )

        return Bench(
            suiteName: suiteName,
            defaults: defaults,
            environment: environment,
            store: store,
            profileId: profileId
        )
    }

    /// Moves the open session into the laboratory and gives it a unit the way a
    /// supervisor would: a row in the shared book, never a fabrication by the driver.
    private static func enterLaboratoryWithAUnit(_ bench: Bench) throws -> Vehicle {
        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        let unit = try #require(
            bench.store.vehicles.first { $0.id != MockData.seededTitularVehicleId && $0.status == .available }
        )
        AssignmentBook.upsert(
            AssignmentBook.make(
                stationId: bench.store.driver.stationId,
                driverId: bench.profileId,
                driverName: bench.store.driver.name,
                vehicleId: unit.id,
                vehicleNumber: unit.internalNumber,
                kind: .titular,
                note: "Asignación de laboratorio.",
                assignedBy: "Supervisión de estación",
                origin: .simulated,
                now: bench.store.now,
                previous: nil
            )
        )
        bench.store.reloadAssignment()
        #expect(bench.store.hasAssignedUnit)
        return unit
    }

    // MARK: Fixtures

    private static func activeShift(driverId: String, origin: OperationalRecordOrigin) -> ActiveShift {
        ActiveShift(
            id: "shift-\(driverId)-\(origin.rawValue)",
            driverId: driverId,
            vehicleId: "veh-014",
            group: .weekday,
            slot: .morning,
            scheduledStartAt: Date(),
            startedAt: Date(),
            lateMinutes: 0,
            startOdometerKm: 96_000,
            startBatteryPct: 92,
            photos: [:],
            trips: 0,
            earningsMxn: 0,
            origin: origin
        )
    }

    private static func record(driverId: String, origin: OperationalRecordOrigin) -> ShiftRecord {
        ShiftRecord(
            id: "rec-\(driverId)-\(origin.rawValue)",
            driverId: driverId,
            vehicleId: "veh-014",
            vehicleInternalNumber: "TEV-014",
            group: .weekday,
            slot: .morning,
            scheduledStartAt: Date(),
            startedAt: Date(),
            endedAt: Date(),
            lateMinutes: 0,
            paidBackMinutes: 0,
            startOdometerKm: 96_000,
            endOdometerKm: 96_180,
            startBatteryPct: 92,
            endBatteryPct: 26,
            trips: 14,
            earningsMxn: 1_450,
            origin: origin
        )
    }

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: "veh-014",
            qrCode: "TEV-014-QR",
            internalNumber: "TEV-014",
            model: "BYD Dolphin Mini",
            plates: "ABC-123-A",
            odometerKm: 96_480,
            batteryPct: 92,
            stationId: "est-001",
            station: "Estación Iztapalapa",
            status: .available,
            occupiedBy: nil,
            photoAsset: "ev_taxi_side"
        )
    }
}

// MARK: - 15B.13.2.1 · environment transitions under one identity

@MainActor
struct BackendMaintenanceSessionTests {
    @Test func maintenancePrincipalNeedsNoDriverSchedule() throws {
        let suiteName = "turnoev.tests.maintenance.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let environment = RuntimeEnvironment(defaults: defaults)
        let store = FleetStore(environment: environment, defaults: defaults)
        let principal = SessionPrincipal(
            authUserId: UUID().uuidString,
            profileId: UUID().uuidString,
            name: "Taller TEST 001",
            employeeNumber: "MNT-TEST-001",
            email: "test.maintenance@joramza.test",
            role: .maintenance,
            environmentId: LabEnvironment.sharedTestId,
            stationId: UUID().uuidString,
            stationCode: "PUE-TEST-01",
            stationName: "Puebla Laboratorio 01",
            shiftGroup: nil,
            shiftSlot: nil
        )

        try store.signIn(principal: principal, method: .credentials)

        #expect(store.currentPrincipal?.role == .maintenance)
        #expect(store.hasAccess(to: .maintenance))
        #expect(store.currentAccount == nil)
    }
}

struct CoverageServiceErrorTests {
    @Test func losingTheRaceHasAClearDriverMessage() {
        let error = NSError(
            domain: "TurnoEV.Coverage",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "vacancy_already_claimed"]
        )

        #expect(
            SupabaseCoverageService.userMessage(for: error)
                == "Otro conductor tomó esta guardia primero. Actualiza para ver que ya fue asignada."
        )
    }

    @Test func staleSupervisorDataRequestsARefresh() {
        let error = NSError(
            domain: "TurnoEV.Coverage",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "vacancy_revision_conflict"]
        )

        #expect(
            SupabaseCoverageService.userMessage(for: error)
                == "La información cambió en otro dispositivo. Actualiza antes de continuar."
        )
    }
}

/// 15B.13.2.1 · the laboratory and the proved identity are one session, not two.
///
/// Every case here runs on a single `FleetStore` instance against an isolated defaults
/// suite: nothing is recreated between the assertions, which is the whole point — the
/// failure being fixed was a capability that had been decided once, at sign-in, and never
/// asked again.
@MainActor
struct EnvironmentTransitionTests {

    private struct Bench {
        let suiteName: String
        let defaults: UserDefaults
        let environment: RuntimeEnvironment
        let store: FleetStore
        let profileId: String

        var productionKey: String { "turnoev.state.v4.\(profileId)" }
        var laboratoryKey: String { "turnoev.state.v4.lab.\(profileId)" }

        func discard() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    /// A signed-in backend identity, standing in production, on storage of its own.
    private static func bench() throws -> Bench {
        let suiteName = "turnoev.tests.environment.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let environment = RuntimeEnvironment(defaults: defaults)
        let store = FleetStore(environment: environment, defaults: defaults)
        let profileId = "DRV-TEST-\(UUID().uuidString.prefix(8))"

        try store.signIn(principal: principal(profileId: profileId), method: .credentials)

        return Bench(
            suiteName: suiteName,
            defaults: defaults,
            environment: environment,
            store: store,
            profileId: profileId
        )
    }

    private static func principal(profileId: String) -> SessionPrincipal {
        SessionPrincipal(
            authUserId: UUID().uuidString,
            profileId: profileId,
            name: "Conductor de prueba",
            employeeNumber: "EMP-TEST",
            email: "test.driver@joramza.test",
            role: .driver,
            stationId: "est-001",
            stationCode: "IZT",
            stationName: "Estación Iztapalapa",
            shiftGroup: .weekday,
            shiftSlot: .morning
        )
    }

    /// 1 · turning the laboratory on reaches the session that is already open.
    ///
    /// The capability is asserted **before** `adoptEnvironment()` runs: it has to move on
    /// the environment change itself, not on the clean-up that follows it. Nothing here
    /// rebuilds the store, signs out, or re-selects a profile.
    @Test func activatingTheLaboratoryFlipsCapabilitiesOnTheOpenSession() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        #expect(bench.store.isBackendSession)
        #expect(bench.store.canSimulateUnitAssignment == false)
        #expect(bench.store.canSimulateFinancialState == false)
        #expect(bench.store.canSimulateOperationalCoordination == false)
        #expect(bench.store.unitAssignmentCapability == .stationRequired)
        #expect(bench.store.coordinationCapability == .stationRequired)

        bench.environment.set(.test)

        #expect(bench.store.environment == .test)
        #expect(bench.store.canSimulateUnitAssignment)
        #expect(bench.store.canSimulateFinancialState)
        #expect(bench.store.usesBackendCoverageCycle)
        #expect(bench.store.canSimulateOperationalCoordination == false)
        #expect(bench.store.unitAssignmentCapability == .localSimulation)
        #expect(bench.store.coordinationCapability == .stationRequired)

        // And the state follows: in the laboratory there is a fleet to work with.
        bench.store.adoptEnvironment()
        #expect(!bench.store.vehicles.isEmpty)
    }

    /// 2 · and turning it off puts the boundary back, just as immediately.
    @Test func leavingTheLaboratoryRestoresTheStationBoundary() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        bench.environment.set(.test)
        bench.store.adoptEnvironment()
        #expect(bench.store.canSimulateUnitAssignment)

        bench.environment.set(.production)

        #expect(bench.store.unitAssignmentCapability == .stationRequired)
        #expect(bench.store.coordinationCapability == .stationRequired)
        #expect(bench.store.canSimulateFinancialState == false)

        bench.store.adoptEnvironment()
        #expect(bench.store.vehicles.isEmpty)
        #expect(bench.store.unitAssignment == nil)
        #expect(bench.store.hasAssignedUnit == false)
    }

    /// 3 · the person does not change while the environment does.
    ///
    /// No sign out, no re-selection, no rebuilt identity: the session, the proved
    /// principal and the driver profile are the same objects on both sides of both
    /// transitions.
    @Test func identitySurvivesBothTransitions() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        let driverId = bench.store.driver.id
        let name = bench.store.driver.name
        let accountId = bench.store.session?.accountId

        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        #expect(bench.store.driver.id == driverId)
        #expect(bench.store.driver.name == name)
        #expect(bench.store.session?.accountId == accountId)
        #expect(bench.store.currentPrincipal?.profileId == bench.profileId)
        #expect(bench.store.isBackendSession)

        bench.environment.set(.production)
        bench.store.adoptEnvironment()

        #expect(bench.store.driver.id == driverId)
        #expect(bench.store.driver.name == name)
        #expect(bench.store.session?.accountId == accountId)
        #expect(bench.store.currentPrincipal?.profileId == bench.profileId)
        #expect(bench.store.isBackendSession)
    }

    /// 4 · what was minted inside the simulation does not come back out with it.
    @Test func simulatedRecordsDoNotAppearBackInProduction() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        #expect(bench.store.notifySupervisor(reason: "Prueba de laboratorio"))
        #expect(bench.store.notices.count == 1)

        bench.environment.set(.production)
        bench.store.adoptEnvironment()

        #expect(bench.store.notices.isEmpty)
        #expect(bench.store.vehicles.isEmpty)
        // Refused again, and refused honestly: there is no station service behind it.
        #expect(bench.store.notifySupervisor(reason: "Prueba de producción") == false)
        #expect(bench.store.notices.isEmpty)
    }

    /// 5 · and neither side is deleted to achieve that.
    ///
    /// Two blobs that never meet. The exit from the laboratory is a change of key, not a
    /// wipe: both are still on disk afterwards.
    @Test func neitherEnvironmentIsErasedByTheTransition() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        #expect(bench.defaults.data(forKey: bench.productionKey) != nil)

        bench.environment.set(.test)
        bench.store.adoptEnvironment()
        bench.store.notifySupervisor(reason: "Prueba de laboratorio")

        // The real operation's storage is untouched while the simulation runs.
        #expect(bench.defaults.data(forKey: bench.productionKey) != nil)

        bench.environment.set(.production)
        bench.store.adoptEnvironment()

        #expect(bench.defaults.data(forKey: bench.productionKey) != nil)
        #expect(bench.defaults.data(forKey: bench.laboratoryKey) != nil)

        // Going back in finds the experiment where it was left.
        bench.environment.set(.test)
        bench.store.adoptEnvironment()
        #expect(bench.store.notices.count == 1)
    }

    /// 6 · flipping repeatedly changes nothing that flipping once did not.
    @Test func repeatedTransitionsAreIdempotent() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        let driverId = bench.store.driver.id

        for _ in 0..<3 {
            bench.environment.set(.test)
            bench.store.adoptEnvironment()
            #expect(bench.store.canSimulateUnitAssignment)
            #expect(bench.store.driver.id == driverId)

            bench.environment.set(.production)
            bench.store.adoptEnvironment()
            #expect(bench.store.unitAssignmentCapability == .stationRequired)
            #expect(bench.store.driver.id == driverId)
            #expect(bench.store.vehicles.isEmpty)
            #expect(bench.store.unitAssignment == nil)
        }

        // Asking for the environment already in force is a no-op, not a reload.
        bench.environment.set(.production)
        bench.store.adoptEnvironment()
        #expect(bench.store.isBackendSession)
        #expect(bench.store.session?.accountId == bench.profileId)
    }

    /// 7 · the test clock is the fourth concern, and it moves on its own.
    ///
    /// Moving logical time is not an identity event: nothing about who is signed in, or
    /// what they may do, is allowed to depend on it.
    @Test func movingTheTestClockDoesNotTouchAuthentication() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        let driverId = bench.store.driver.id
        let accountId = bench.store.session?.accountId

        SimulationClock.set(Date().addingTimeInterval(3 * 3600))
        bench.store.syncSimulationClock()

        #expect(bench.store.isBackendSession)
        #expect(bench.store.driver.id == driverId)
        #expect(bench.store.session?.accountId == accountId)
        #expect(bench.store.canSimulateUnitAssignment)

        SimulationClock.reset()
        bench.store.syncSimulationClock()

        #expect(bench.store.isBackendSession)
        #expect(bench.store.driver.id == driverId)
        #expect(bench.store.session?.accountId == accountId)
        #expect(bench.store.environment == .test)
    }

    /// 8 · a relaunch keeps the environment and only the environment.
    ///
    /// This is the update failure, reproduced: the laboratory payload is unreadable — a
    /// field added by a new release is enough — and the environment used to be inside it,
    /// so the first session after an update silently stood in production. It now survives
    /// on a key of its own, and a device that predates that key still recovers its
    /// environment from the old payload without being able to read the rest of it.
    @Test func theEnvironmentSurvivesAnUnreadableLaboratoryPayload() throws {
        let suiteName = "turnoev.tests.environment.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Nothing stored at all: the real operation is the default.
        #expect(EnvironmentStore.load(defaults: defaults) == .production)

        // A payload the current models cannot decode, carrying a legible environment.
        let brokenWorld = #"{"mode":"test","stations":[{"unexpected":true}],"clockOffsetMinutes":"noventa"}"#
        defaults.set(Data(brokenWorld.utf8), forKey: LabPersistence.storageKey)
        #expect((try? JSONDecoder().decode(LabWorld.self, from: Data(brokenWorld.utf8))) == nil)
        #expect(EnvironmentStore.load(defaults: defaults) == .test)

        // Once the environment has a key of its own, it is the one that answers.
        EnvironmentStore.persist(.production, defaults: defaults)
        #expect(EnvironmentStore.load(defaults: defaults) == .production)
    }

    /// 8 (continued) · and a relaunch does not need a sign out to reconcile.
    ///
    /// The environment persists; the proved identity deliberately does not, because no
    /// credential is kept to vouch for it. What must not happen — and no longer does — is
    /// the app coming back up in an environment nobody chose.
    @Test func relaunchKeepsTheEnvironmentAndAsksForCredentialsAgain() throws {
        let bench = try Self.bench()
        defer { bench.discard() }

        bench.environment.set(.test)
        bench.store.adoptEnvironment()

        // A fresh launch on the same storage.
        let relaunchedEnvironment = RuntimeEnvironment(defaults: bench.defaults)
        #expect(relaunchedEnvironment.mode == .test)

        let relaunched = FleetStore(environment: relaunchedEnvironment, defaults: bench.defaults)
        #expect(relaunched.environment == .test)
        #expect(relaunched.isBackendSession == false)
        #expect(relaunched.awaitsCredentialChoice)
        // The laboratory's own blob is still there for the identity that comes back.
        #expect(bench.defaults.data(forKey: bench.laboratoryKey) != nil)
    }
}

// MARK: - 15B.13.2 · unit assignment boundary

/// 15B.13.2 · a unit is adopted only when the station can be shown to have given it.
///
/// The rules are pure on purpose: restoration, an environment switch and a data wipe all
/// ask the same question, and three private copies of the answer is exactly how the
/// documented contradiction appeared.
nonisolated struct UnitAssignmentBoundaryTests {

    private static let backendDriverId = "DRV-TEST-001"

    private static func assignment(
        driverId: String,
        origin: AssignmentOrigin,
        vehicleId: String = "veh-014",
        vehicleNumber: String = "TEV-014"
    ) -> VehicleAssignment {
        VehicleAssignment(
            id: "asg-test",
            stationId: "est-001",
            driverId: driverId,
            driverName: "Conductor de prueba",
            vehicleId: vehicleId,
            vehicleNumber: vehicleNumber,
            kind: .titular,
            titularVehicleId: nil,
            titularVehicleNumber: nil,
            note: "",
            assignedBy: "Supervisión de estación",
            assignedAt: Date(),
            origin: origin
        )
    }

    /// A · a record written before provenance existed reads as local, never as the
    /// station's act. Everything already on a device was written by a demonstration
    /// session, which is the only kind that could write one.
    @Test func legacyAssignmentWithoutOriginReadsAsSimulated() throws {
        let json = """
        {
          "id": "asg-legacy",
          "stationId": "est-001",
          "driverId": "drv-001",
          "driverName": "Carlos Méndez Rivas",
          "vehicleId": "veh-014",
          "vehicleNumber": "TEV-014",
          "kind": "titular",
          "note": "Asignación inicial del perfil de demostración.",
          "assignedBy": "Supervisión de estación",
          "assignedAt": "2026-08-01T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(VehicleAssignment.self, from: Data(json.utf8))

        #expect(decoded.origin == .simulated)
        #expect(decoded.isAuthoritative == false)
        // Still perfectly usable by the world that wrote it.
        #expect(decoded.vehicleNumber == "TEV-014")
    }

    /// B · the same `driverId` is not the station vouching for a unit.
    ///
    /// This is the case the module was one coincidence away from: a local row naming the
    /// proved identity would have been adopted whole.
    @Test func simulatedAssignmentIsRefusedEvenWithTheExactBackendProfileId() {
        let local = Self.assignment(driverId: Self.backendDriverId, origin: .simulated)

        let adopted = UnitAssignmentRules.resolve(
            stored: local,
            driverId: Self.backendDriverId,
            capability: .stationRequired
        )

        #expect(adopted == nil)
    }

    /// C · provenance alone is not enough either: a station record belongs to the person
    /// it names.
    @Test func backendAssignmentOfAnotherDriverIsRefused() {
        let other = Self.assignment(driverId: "DRV-TEST-777", origin: .backend)

        let adopted = UnitAssignmentRules.resolve(
            stored: other,
            driverId: Self.backendDriverId,
            capability: .stationRequired
        )

        #expect(adopted == nil)
    }

    /// D · the legitimate case resolves, so the boundary refuses rather than blocks.
    @Test func backendAssignmentOfTheSameDriverResolves() throws {
        let mine = Self.assignment(driverId: Self.backendDriverId, origin: .backend)

        let adopted = try #require(
            UnitAssignmentRules.resolve(
                stored: mine,
                driverId: Self.backendDriverId,
                capability: .stationRequired
            )
        )

        #expect(adopted.driverId == Self.backendDriverId)
        #expect(adopted.isAuthoritative)
    }

    /// E · with nothing stored there is no unit and no inventory to cross-check against.
    @Test func backendSessionWithoutAssignmentHasNoUnitAndNoFleet() {
        let adopted = UnitAssignmentRules.resolve(
            stored: nil,
            driverId: Self.backendDriverId,
            capability: .stationRequired
        )
        #expect(adopted == nil)
        #expect(UnitAssignmentRules.catalogue([], capability: .stationRequired).isEmpty)
    }

    /// G · no route can hand the demonstration fleet to a proved identity.
    ///
    /// The three that could — an environment switch, a data wipe and the restoration of a
    /// stored catalogue — now ask this one function, so the guarantee is a property of
    /// the rule instead of a promise repeated in three comments.
    @Test func noEnvironmentCanIntroduceTheDemonstrationFleetIntoABackendSession() {
        let demoFleet = MockData.vehicles
        #expect(!demoFleet.isEmpty)

        #expect(UnitAssignmentRules.catalogue(demoFleet, capability: .stationRequired).isEmpty)
        // And a catalogue already persisted under the identity's own key is not adopted
        // either: only the server may fill it.
        #expect(UnitAssignmentRules.catalogue(demoFleet, capability: .localSimulation).count == demoFleet.count)
    }

    /// F · the demonstration world keeps TEV-014 and every previous behaviour.
    @Test func demonstrationSessionKeepsItsTitularUnitAndFleet() throws {
        let carlos = MockData.seededDriver
        let legacy = Self.assignment(
            driverId: carlos.id,
            origin: .simulated,
            vehicleId: MockData.seededTitularVehicleId
        )

        let adopted = try #require(
            UnitAssignmentRules.resolve(
                stored: legacy,
                driverId: carlos.id,
                capability: .localSimulation
            )
        )

        #expect(adopted.vehicleId == MockData.seededTitularVehicleId)
        #expect(adopted.vehicleNumber == "TEV-014")
        #expect(UnitAssignmentRules.catalogue(MockData.vehicles, capability: .localSimulation).contains {
            $0.id == MockData.seededTitularVehicleId
        })
    }

    /// A unit cross-check without a published assignment is not a wrong sticker.
    ///
    /// The distinction the start screen makes in words, held by the rule underneath it:
    /// the issue raised is `.notAssigned`, not `.wrongVehicle`.
    @Test func missingAssignmentIsReportedAsUnassignedNotAsAWrongUnit() throws {
        let driver = MockData.seededDriver
        let vehicle = try #require(MockData.vehicles.first)

        let issues = ShiftRules.validateUnit(
            driver: driver,
            vehicle: vehicle,
            assignedVehicleId: nil,
            now: Date()
        )

        #expect(issues.count == 1)
        #expect(issues.first?.code == .notAssigned)
    }
}

// MARK: - 15B.16 · residual leaks of locally originated data

/// 15B.16 · three fixtures that were reaching a proved identity, closed.
///
/// None of these is a new boundary. All three reuse `runsAgainstStation`, the authority
/// that already exists, and none of them deletes anything: the demonstration keeps its
/// bank file, its network account and its published bonus calendar, byte for byte.
///
/// The decision is never taken by recognising a particular driver. Every case below
/// builds its identity with a random `profileId`, so a rule that had been written against
/// `DRV-TEST-001` would fail here.
@MainActor
struct ResidualFixtureLeakTests {

    /// The BBVA account `StationOfficeMockData` writes for whoever is signed in.
    private static let fabricatedClabe = "012180001234564587"
    private static let bonusStorageKey = "turnoev.bonus.schedule.v1"

    private static func station(id: String) -> Station {
        Station(
            id: id,
            code: "TST",
            name: "Estaci\u{00f3}n de prueba",
            city: "CDMX",
            regionId: "reg-centro",
            vehicleCapacity: 20
        )
    }

    private static func driver(id: String, stationId: String) -> Driver {
        Driver(
            id: id,
            name: "Conductor de prueba",
            employeeNumber: "EMP-TEST",
            email: "residual.driver@joramza.test",
            password: "",
            photoAsset: "rideshare_driver_portrait",
            stationId: stationId,
            station: "Estaci\u{00f3}n de prueba",
            group: .weekday,
            slot: .morning,
            authorizedVehicleIds: []
        )
    }

    private static func principal(profileId: String, stationId: String) -> SessionPrincipal {
        SessionPrincipal(
            authUserId: UUID().uuidString,
            profileId: profileId,
            name: "Conductor de prueba",
            employeeNumber: "EMP-TEST",
            email: "residual.driver@joramza.test",
            role: .driver,
            stationId: stationId,
            stationCode: "TST",
            stationName: "Estaci\u{00f3}n de prueba",
            shiftGroup: .weekday,
            shiftSlot: .morning
        )
    }

    /// A signed-in backend identity standing in production, on storage of its own.
    private static func provedStore(
        defaults: UserDefaults,
        profileId: String,
        stationId: String
    ) throws -> FleetStore {
        let store = FleetStore(environment: RuntimeEnvironment(defaults: defaults), defaults: defaults)
        try store.signIn(principal: principal(profileId: profileId, stationId: stationId), method: .credentials)
        return store
    }

    // MARK: - F1 · the fabricated employee file

    /// A · the office invents no bank account for an identity that answers to a station.
    ///
    /// Asserted on the generator, not on the screen: the leak was a fixture carrying a
    /// CLABE and a `.verified` badge under the proved `profileId`, and hiding the card
    /// downstream would have left the row on disk for the next reader.
    @Test func provedIdentityGetsNoFabricatedBankFileFromTheOffice() {
        let station = Self.station(id: "est-residual-a")
        let live = Self.driver(id: "DRV-PROVED-\(UUID().uuidString.prefix(8))", stationId: station.id)

        let snapshot = StationOfficeMockData.snapshot(
            station: station,
            supervisorName: "Supervisi\u{00f3}n",
            supervisorId: "acc-sup",
            liveDriver: live,
            mayFabricateLiveDriverFile: false,
            now: Date()
        )

        #expect(snapshot.files.contains { $0.id == live.id } == false)
        #expect(snapshot.files.contains { $0.isLiveSession } == false)
        #expect(snapshot.files.contains { $0.bank?.clabe == Self.fabricatedClabe } == false)
        #expect(snapshot.files.contains { $0.bank?.holder == live.name } == false)
        #expect(snapshot.bankRequests.contains { $0.driverId == live.id } == false)

        // A targeted refusal, not a gutted station: the rest of the office is intact.
        #expect(snapshot.files.isEmpty == false)
        #expect(snapshot.files.allSatisfy { $0.bank != nil })
    }

    /// C · the demonstration keeps the file it has always had.
    ///
    /// Same station, same driver, same generator — the single flag apart. What the gate
    /// removes is exactly one row, and it is the row naming the live credential.
    @Test func demonstrationKeepsTheLiveBankFileUnchanged() throws {
        let station = Self.station(id: "est-residual-c")
        let live = Self.driver(id: "DRV-DEMO-\(UUID().uuidString.prefix(8))", stationId: station.id)
        let now = Date()

        let demo = StationOfficeMockData.snapshot(
            station: station,
            supervisorName: "Supervisi\u{00f3}n",
            supervisorId: "acc-sup",
            liveDriver: live,
            mayFabricateLiveDriverFile: true,
            now: now
        )
        let proved = StationOfficeMockData.snapshot(
            station: station,
            supervisorName: "Supervisi\u{00f3}n",
            supervisorId: "acc-sup",
            liveDriver: live,
            mayFabricateLiveDriverFile: false,
            now: now
        )

        let file = try #require(demo.files.first { $0.id == live.id })
        let bank = try #require(file.bank)
        #expect(bank.clabe == Self.fabricatedClabe)
        #expect(bank.status == .verified)
        #expect(bank.hasProof)
        #expect(file.isLiveSession)

        #expect(demo.files.count == proved.files.count + 1)
    }

    /// B · and nothing of that account reaches the national CLABE registry.
    ///
    /// The registry is one global dictionary keyed by CLABE. A fixture registered under a
    /// real `profileId` would reserve an invented account in that person's name — so the
    /// day they file their real one, the network answers that they already have it.
    ///
    /// Runs the real store against the shared registry and restores it afterwards, because
    /// this is precisely the write that must not happen.
    @Test func provedIdentityRegistersNoClabeNationally() throws {
        let suiteName = "turnoev.tests.residual.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let station = Self.station(id: "est-residual-b-\(UUID().uuidString.prefix(8))")
        let profileId = "DRV-PROVED-\(UUID().uuidString.prefix(8))"

        let registryKey = "turnoev.clabe.national.v1"
        let officeKey = "turnoev.office.v1.\(station.id)"
        let registryBefore = UserDefaults.standard.dictionary(forKey: registryKey)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            UserDefaults.standard.removeObject(forKey: officeKey)
            if let registryBefore {
                UserDefaults.standard.set(registryBefore, forKey: registryKey)
            } else {
                UserDefaults.standard.removeObject(forKey: registryKey)
            }
        }

        let fleet = try Self.provedStore(defaults: defaults, profileId: profileId, stationId: station.id)
        #expect(fleet.runsAgainstStation)
        #expect(fleet.driver.stationId == station.id)

        let office = StationOfficeStore(station: station, fleet: fleet, actor: nil)
        office.refresh()

        // The read the wallet performs, answering nothing.
        #expect(office.file(id: fleet.driver.id) == nil)
        #expect(office.bankRequests(driverId: fleet.driver.id).isEmpty)

        // And the registry never heard this person's name, under any CLABE.
        #expect(NationalBankRegistry.owner(of: Self.fabricatedClabe) != profileId)
        let registryAfter = UserDefaults.standard.dictionary(forKey: registryKey) as? [String: String] ?? [:]
        #expect(registryAfter.values.contains(profileId) == false)
        // Not one fixture account of this office was published either.
        #expect(registryAfter.count == (registryBefore?.count ?? 0))
    }

    // MARK: - F2 · the cash deposit account

    /// D · a proved identity is given no account to deposit real cash into.
    ///
    /// The screen is read standing at a counter with money in hand. `networkDefault` is a
    /// fictitious BBVA written into the source, so a plausible CLABE here is worse than
    /// none at all.
    @Test func provedIdentityGetsNoCashDepositAccount() throws {
        let suiteName = "turnoev.tests.residual.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fleet = try Self.provedStore(
            defaults: defaults,
            profileId: "DRV-PROVED-\(UUID().uuidString.prefix(8))",
            stationId: "est-001"
        )

        #expect(fleet.runsAgainstStation)
        #expect(fleet.cashDepositAccount == nil)
    }

    /// E · the demonstration keeps the network account exactly as it was.
    ///
    /// Same store, same person, same instant: only the environment moves.
    @Test func demonstrationKeepsTheNetworkCashAccount() throws {
        let suiteName = "turnoev.tests.residual.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let environment = RuntimeEnvironment(defaults: defaults)
        let fleet = FleetStore(environment: environment, defaults: defaults)
        try fleet.signIn(
            principal: Self.principal(
                profileId: "DRV-PROVED-\(UUID().uuidString.prefix(8))",
                stationId: "est-001"
            ),
            method: .credentials
        )

        #expect(fleet.cashDepositAccount == nil)

        environment.set(.test)

        #expect(fleet.runsAgainstStation == false)
        #expect(fleet.cashDepositAccount == NationalCashBoard.current)
        #expect(fleet.cashDepositAccount?.clabe.isEmpty == false)
    }

    // MARK: - F3 · the national bonus calendar

    /// F and G · what a demonstration desk publishes governs the demonstration only.
    ///
    /// One store, one identity, both sides of the environment. In production the ceiling
    /// is the baseline written in the source, which no console can move; inside the
    /// laboratory the published calendar is visible exactly as before.
    ///
    /// H · and the blob is still on disk when it is done. Production stops consuming it;
    /// nothing migrates it and nothing deletes it.
    @Test func publishedBonusCalendarNeverReachesAProvedIdentity() throws {
        let suiteName = "turnoev.tests.residual.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let published = BonusSchedule(
            punctualityMxn: 9_000,
            billingMxn: 9_000,
            careMxn: 9_000,
            version: 99,
            updatedAt: Date(timeIntervalSince1970: 1_767_225_600),
            updatedBy: "Direcci\u{00f3}n nacional (demostraci\u{00f3}n)"
        )

        let stored = UserDefaults.standard.data(forKey: Self.bonusStorageKey)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            NationalBonusBoard.reset()
            if let stored { UserDefaults.standard.set(stored, forKey: Self.bonusStorageKey) }
        }

        // The demonstration desk moves the amounts.
        NationalBonusBoard.publish(published)
        #expect(NationalBonusBoard.current == published)

        let environment = RuntimeEnvironment(defaults: defaults)
        let fleet = FleetStore(environment: environment, defaults: defaults)
        try fleet.signIn(
            principal: Self.principal(
                profileId: "DRV-PROVED-\(UUID().uuidString.prefix(8))",
                stationId: "est-001"
            ),
            method: .credentials
        )

        // F · production reads the baseline, not the publication.
        #expect(fleet.runsAgainstStation)
        #expect(fleet.bonusSchedule == .networkDefault)
        #expect(fleet.bonusTotalMxn() == BonusSchedule.networkDefault.ceilingMxn)
        #expect(fleet.bonusTotalMxn() != published.ceilingMxn)

        // G · the same publication is still what the laboratory sees.
        environment.set(.test)
        #expect(fleet.runsAgainstStation == false)
        #expect(fleet.bonusSchedule == published)
        #expect(fleet.bonusTotalMxn() == published.ceilingMxn)

        // H · and the stored calendar was never touched by any of it.
        let raw = try #require(UserDefaults.standard.data(forKey: Self.bonusStorageKey))
        let decoded = try JSONDecoder().decode(BonusSchedule.self, from: raw)
        #expect(decoded == published)
    }
}
