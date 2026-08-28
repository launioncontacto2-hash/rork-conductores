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
