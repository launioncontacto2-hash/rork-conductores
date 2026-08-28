import Foundation

/// Weekly settlement of a driver: what the week produced, what was withheld and what
/// is actually available to transfer. Once a week closes, the calculation is frozen and
/// any later correction lives as a separate movement.

nonisolated enum SettlementStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case available
    case requested
    case validated
    case processing
    case transferred
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .available: "Disponible"
        case .requested: "Solicitada"
        case .validated: "Validada"
        case .processing: "Procesando"
        case .transferred: "Transferida"
        case .completed: "Completada"
        }
    }

    var order: Int {
        switch self {
        case .available: 0
        case .requested: 1
        case .validated: 2
        case .processing: 3
        case .transferred: 4
        case .completed: 5
        }
    }

    var symbol: String {
        switch self {
        case .available: "banknote.fill"
        case .requested: "paperplane.fill"
        case .validated: "checkmark.circle.fill"
        case .processing: "arrow.triangle.2.circlepath"
        case .transferred: "arrow.up.right.circle.fill"
        case .completed: "checkmark.seal.fill"
        }
    }

    var next: SettlementStatus? {
        switch self {
        case .available: .requested
        case .requested: .validated
        case .validated: .processing
        case .processing: .transferred
        case .transferred: .completed
        case .completed: nil
        }
    }

    var hint: String {
        switch self {
        case .available: "El saldo de la semana está listo para solicitarse."
        case .requested: "Tu supervisor recibió la solicitud."
        case .validated: "Los montos fueron verificados contra tu bitácora."
        case .processing: "La dispersión está en curso hacia tu cuenta."
        case .transferred: "El banco recibió la orden de pago."
        case .completed: "Depósito confirmado en tu cuenta."
        }
    }
}

nonisolated enum SettlementLineKind: String, Codable, Sendable {
    case income
    case bonus
    case deduction
    case credit

    var label: String {
        switch self {
        case .income: "Ingresos"
        case .bonus: "Bonificaciones"
        case .deduction: "Deducciones"
        case .credit: "Crédito"
        }
    }

    var symbol: String {
        switch self {
        case .income: "arrow.down.circle.fill"
        case .bonus: "star.fill"
        case .deduction: "minus.circle.fill"
        case .credit: "creditcard.fill"
        }
    }
}

nonisolated struct SettlementLine: Codable, Identifiable, Sendable {
    let id: String
    let concept: String
    let detail: String
    /// Positive adds, negative subtracts.
    let amountMxn: Int
    let kind: SettlementLineKind
}

/// A correction after the week closed. It never rewrites the original calculation.
/// A correction appended after a week closed.
///
/// It signs itself with an author — "Supervisión" — and it moves the net of a frozen
/// week, which makes it the one movement in the wallet that looks most like an authority
/// speaking. It is therefore the one that most needs to say where it came from: without
/// provenance, a driver holding the phone could mint a movement that presents itself as
/// a supervisor's decision.
nonisolated struct SettlementAdjustment: Codable, Identifiable, Sendable {
    let id: String
    /// Whether an authority produced this correction or a demonstration session minted it.
    let origin: RecordOrigin
    let createdAt: Date
    let concept: String
    let amountMxn: Int
    let author: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case id
        case origin
        case createdAt
        case concept
        case amountMxn
        case author
        case reason
    }
}

extension SettlementAdjustment {
    /// Corrections stored before provenance existed decode as `.simulated`.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        origin = try container.decodeIfPresent(RecordOrigin.self, forKey: .origin) ?? .simulated
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        concept = try container.decode(String.self, forKey: .concept)
        amountMxn = try container.decode(Int.self, forKey: .amountMxn)
        author = try container.decode(String.self, forKey: .author)
        reason = try container.decode(String.self, forKey: .reason)
    }
}

nonisolated struct WeeklySettlement: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    let weekStart: Date
    let weekEnd: Date
    var lines: [SettlementLine]
    var status: SettlementStatus
    var requestedAt: Date?
    var transferredAt: Date?
    /// Set the moment the week closes; from here the calculation is immutable.
    var closedAt: Date?
    var adjustments: [SettlementAdjustment]
    var reviewNote: String?
    var reviewOpenedAt: Date?

    var isClosed: Bool { closedAt != nil }

    var grossMxn: Int { lines.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountMxn } }
    var bonusMxn: Int { lines.filter { $0.kind == .bonus }.reduce(0) { $0 + $1.amountMxn } }
    var creditMxn: Int { lines.filter { $0.kind == .credit }.reduce(0) { $0 + $1.amountMxn } }
    var deductionMxn: Int { lines.filter { $0.kind == .deduction }.reduce(0) { $0 + $1.amountMxn } }
    var adjustmentMxn: Int { adjustments.reduce(0) { $0 + $1.amountMxn } }
    var netMxn: Int { lines.reduce(0) { $0 + $1.amountMxn } + adjustmentMxn }

    var rangeLabel: String { "\(Fmt.dayNumber(weekStart)) — \(Fmt.dayNumber(weekEnd))" }
}

nonisolated enum SettlementRules {
    /// Authorized recurring deduction (uniform, station services).
    static let serviceDeductionMxn = 300

    static func weekId(driverId: String, weekStart: Date) -> String {
        "liq-\(driverId)-\(Fmt.monthKey(weekStart))-\(ShiftRules.calendar.component(.day, from: weekStart))"
    }

    /// Builds the settlement of a week from the shift log, the credit and the bonuses.
    ///
    /// The credit arrives as the contract itself, not as a weekly figure. A bare `Int`
    /// could not be questioned: by the time it got here it had lost its owner, its
    /// signature date and its provenance, so the only thing this function could do was
    /// subtract it. With the contract in hand the rule can refuse it — and it does,
    /// without ever asking what kind of session is open.
    static func build(
        driverId: String,
        records: [ShiftRecord],
        activeEarningsMxn: Int,
        credit: CreditAccount?,
        ledgerOrigin: RecordOrigin,
        bonusMxn: Int,
        cashRecoveries: [CashCharge] = [],
        weekStart: Date,
        now: Date
    ) -> WeeklySettlement {
        let weekEnd = ShiftRules.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let weekRecords = records.filter { ShiftRules.isInSameWeek($0.startedAt, as: weekStart) }
        let recordedMxn = weekRecords.reduce(0) { $0 + $1.earningsMxn }
        let trips = weekRecords.reduce(0) { $0 + $1.trips }
        let gross = recordedMxn + activeEarningsMxn
        // A week the driver never worked is not a week with a balance. Nothing is earned,
        // nothing is bonused and no station service is consumed, so the settlement is
        // zero instead of a debt built out of recurring lines that never happened.
        let hasOperation = !weekRecords.isEmpty || activeEarningsMxn > 0

        var lines: [SettlementLine] = [
            SettlementLine(
                id: "income",
                concept: "Ingresos generados",
                detail: "\(weekRecords.count) turnos · \(trips) viajes",
                amountMxn: gross,
                kind: .income
            )
        ]

        if bonusMxn > 0, hasOperation {
            lines.append(
                SettlementLine(
                    id: "bonus",
                    concept: "Bonificaciones",
                    detail: "Estímulos acreditados esta semana",
                    amountMxn: bonusMxn,
                    kind: .bonus
                )
            )
        }

        // An instalment is charged only when the contract answers three questions.
        //
        // Whose it is: a contract that does not name the driver being settled has no
        // business inside their pay. Whether it existed yet: a contract signed this week
        // cannot be owed for weeks that closed before it was signed — without this test
        // a signature today rewrote five frozen weeks into a debt. And whether it belongs
        // to the same ledger being settled: an instalment from a simulated contract
        // cannot be deducted from records an authority produced, or the other way round.
        if let credit,
           credit.driverId == driverId,
           credit.origin == ledgerOrigin,
           credit.startedAt <= weekEnd,
           credit.weeklyMxn > 0 {
            lines.append(
                SettlementLine(
                    id: "credit",
                    concept: "Crédito de unidad",
                    detail: "Abono semanal vía nómina",
                    amountMxn: -credit.weeklyMxn,
                    kind: .credit
                )
            )
        }

        // Cash collected on a trip and never deposited the same day. It is not a fine:
        // it is the network recovering money that never reached its account.
        //
        // Which makes provenance decisive: a trip nobody reported cannot be money that
        // never arrived. The same three questions the credit answers are asked here —
        // whose the charge is, and whether it belongs to the ledger being settled — so a
        // charge minted on the phone can never be recovered from records an authority
        // produced, and the caller cannot forget to filter beforehand.
        let recovered = cashRecoveries.filter {
            $0.driverId == driverId
                && $0.origin == ledgerOrigin
                && ShiftRules.isInSameWeek($0.chargedBackAt ?? $0.generatedAt, as: weekStart)
        }
        for charge in recovered {
            lines.append(
                SettlementLine(
                    id: "cash-\(charge.id)",
                    concept: CashChargeRules.recoveryConcept,
                    detail: "\(charge.tripReference) · \(Fmt.dateShort(charge.generatedAt)) sin depósito el mismo día",
                    amountMxn: -charge.amountMxn,
                    kind: .deduction
                )
            )
        }

        let lateMinutes = weekRecords.reduce(0) { $0 + $1.pendingLateMinutes }
        if lateMinutes > 0 {
            lines.append(
                SettlementLine(
                    id: "late",
                    concept: "Tiempo no repuesto",
                    detail: "\(Fmt.lateText(lateMinutes)) pendientes de reponer",
                    amountMxn: -min(600, lateMinutes * 4),
                    kind: .deduction
                )
            )
        }

        if hasOperation {
            lines.append(
                SettlementLine(
                    id: "services",
                    concept: "Servicios de estación",
                    detail: "Deducción autorizada en contrato",
                    amountMxn: -serviceDeductionMxn,
                    kind: .deduction
                )
            )
        }

        let isPast = !ShiftRules.isInSameWeek(now, as: weekStart)
        return WeeklySettlement(
            id: weekId(driverId: driverId, weekStart: weekStart),
            driverId: driverId,
            weekStart: weekStart,
            weekEnd: weekEnd,
            lines: lines,
            status: .available,
            requestedAt: nil,
            transferredAt: nil,
            closedAt: isPast ? weekEnd : nil,
            adjustments: [],
            reviewNote: nil,
            reviewOpenedAt: nil
        )
    }
}
