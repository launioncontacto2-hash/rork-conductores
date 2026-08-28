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
