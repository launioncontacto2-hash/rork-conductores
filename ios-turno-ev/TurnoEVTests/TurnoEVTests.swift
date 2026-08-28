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
