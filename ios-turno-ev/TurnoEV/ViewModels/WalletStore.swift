import Foundation
import Observation

/// Cartera del conductor: builds the weekly settlements from the shift log, the credit
/// and the bonuses, and keeps the state of each transfer request. A closed week is never
/// recalculated — corrections are appended as separate movements.
@Observable
final class WalletStore {
    nonisolated private struct PersistedState: Codable, Sendable {
        var statuses: [String: String]
        var requestedAt: [String: Date]
        var transferredAt: [String: Date]
        var reviews: [String: String]
        var adjustments: [String: [SettlementAdjustment]]
    }

    private let fleet: FleetStore
    /// Weeks rendered in the wallet, newest first.
    private let weeksShown = 6

    /// Settlement id → raw status, so the flow survives relaunches.
    var statuses: [String: String] = [:]
    var requestedAt: [String: Date] = [:]
    var transferredAt: [String: Date] = [:]
    var reviews: [String: String] = [:]
    var adjustments: [String: [SettlementAdjustment]] = [:]

    private var storageKey: String { "turnoev.wallet.v1.\(fleet.driver.id)" }

    init(fleet: FleetStore) {
        self.fleet = fleet
        load()
    }

    var now: Date { fleet.now }

    // MARK: - Reads

    /// Every week of the wallet, current one first.
    ///
    /// **Day.** The whole list hangs off `weekStart(for:)`: when the week rolls over, what
    /// was the open settlement becomes a closed one and a new empty week takes its place at
    /// the top. That is decided by the calendar date, never by an hour.
    func settlements(now: Date) -> [WeeklySettlement] {
        let calendar = ShiftRules.calendar
        let currentWeek = ShiftRules.weekStart(for: now)
        return (0..<weeksShown).compactMap { offset -> WeeklySettlement? in
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * offset, to: currentWeek) else { return nil }
            var settlement = SettlementRules.build(
                driverId: fleet.driver.id,
                records: fleet.history,
                activeEarningsMxn: offset == 0 ? activeEarnings : 0,
                credit: fleet.credit,
                ledgerOrigin: fleet.ledgerOrigin,
                bonusMxn: offset == 0 ? weeklyBonusMxn(now: now) : 0,
                cashRecoveries: cashRecoveries,
                weekStart: weekStart,
                now: now
            )
            if let raw = statuses[settlement.id], let status = SettlementStatus(rawValue: raw) {
                settlement.status = status
            }
            settlement.requestedAt = requestedAt[settlement.id]
            settlement.transferredAt = transferredAt[settlement.id]
            settlement.reviewNote = reviews[settlement.id]
            settlement.adjustments = adjustments[settlement.id] ?? []
            return settlement
        }
    }

    func currentSettlement(now: Date) -> WeeklySettlement? { settlements(now: now).first }

    func closedSettlements(now: Date) -> [WeeklySettlement] { Array(settlements(now: now).dropFirst()) }

    /// Money produced by the shift that is still open.
    private var activeEarnings: Int {
        fleet.activeShift?.earningsMxn ?? 0
    }

    /// Cash charges the driver did not deposit in time. They travel to the settlement of
    /// the week in which the deadline was missed.
    private var cashRecoveries: [CashCharge] {
        CashChargeLedger.chargedBack(driverId: fleet.driver.id)
    }

    /// Share of the monthly bonus already earned, spread over the four weeks.
    private func weeklyBonusMxn(now: Date) -> Int {
        fleet.bonusPayableMxn(reference: now) / 4
    }

    // MARK: - Actions

    /// Simulated dispersion flow: request → validated → processing → transferred → completed.
    func requestTransfer(for settlement: WeeklySettlement) {
        guard settlement.status == .available else { return }
        setStatus(.requested, for: settlement.id)
        requestedAt[settlement.id] = now
        persist()
        advanceSimulated(from: .requested, id: settlement.id)
    }

    private func advanceSimulated(from status: SettlementStatus, id: String) {
        guard let next = status.next else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard let self else { return }
            guard self.statuses[id] == status.rawValue else { return }
            self.setStatus(next, for: id)
            if next == .transferred { self.transferredAt[id] = self.now }
            self.persist()
            self.advanceSimulated(from: next, id: id)
        }
    }

    func openReview(for settlementId: String, note: String) {
        reviews[settlementId] = note
        persist()
    }

    /// A correction after the week closed lives as its own movement.
    func addAdjustment(to settlementId: String, concept: String, amountMxn: Int, reason: String) {
        var list = adjustments[settlementId] ?? []
        list.append(
            SettlementAdjustment(
                id: "adj-\(UUID().uuidString.prefix(6))",
                createdAt: now,
                concept: concept,
                amountMxn: amountMxn,
                author: "Supervisión",
                reason: reason
            )
        )
        adjustments[settlementId] = list
        persist()
    }

    private func setStatus(_ status: SettlementStatus, for id: String) {
        statuses[id] = status.rawValue
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            statuses = state.statuses
            requestedAt = state.requestedAt
            transferredAt = state.transferredAt
            reviews = state.reviews
            adjustments = state.adjustments
        } catch {
            print("No se pudo leer la cartera: \(error.localizedDescription)")
        }
    }

    private func persist() {
        let state = PersistedState(
            statuses: statuses,
            requestedAt: requestedAt,
            transferredAt: transferredAt,
            reviews: reviews,
            adjustments: adjustments
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("No se pudo guardar la cartera: \(error.localizedDescription)")
        }
    }
}
