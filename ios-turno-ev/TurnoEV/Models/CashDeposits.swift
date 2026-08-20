import Foundation

/// Cash is not an authorized way to pay at the station. It happens anyway: a card that
/// does not read, an app that fails, a passenger with bills in hand. When it happens the
/// money cannot stay in the driver's pocket — it goes into the network account the same
/// day, and the deposit slip is the proof.
///
/// The account below is written by national direction only. Every other role reads it.

nonisolated struct CashDepositAccount: Codable, Sendable, Equatable {
    var bank: String
    var holder: String
    var accountNumber: String
    var clabe: String
    /// Reference the convenience store asks for (Oxxo, farmacias, etc.).
    var reference: String
    var instructions: String
    var version: Int
    var updatedAt: Date
    var updatedBy: String

    /// Demo account of the network. Fictitious on purpose.
    static let networkDefault = CashDepositAccount(
        bank: "BBVA México",
        holder: "Turno EV Movilidad S.A. de C.V.",
        accountNumber: "0148 7723 91",
        clabe: "012180014877239104",
        reference: "TEV-EFECTIVO",
        instructions: "Deposita el mismo día en cualquier Oxxo o sucursal. Pide el comprobante impreso y fotografíalo completo.",
        version: 1,
        updatedAt: Date(timeIntervalSince1970: 1_735_689_600),
        updatedBy: "Administración nacional"
    )

    /// CLABE grouped for reading out loud at the counter.
    var readableClabe: String {
        let digits = clabe.filter(\.isNumber)
        return stride(from: 0, to: digits.count, by: 4).map { index -> String in
            let start = digits.index(digits.startIndex, offsetBy: index)
            let end = digits.index(start, offsetBy: min(4, digits.count - index))
            return String(digits[start..<end])
        }.joined(separator: " ")
    }
}

/// Shared board: direction publishes the account, the driver app reads it.
nonisolated enum NationalCashBoard {
    private static let storageKey = "turnoev.cash.account.v1"
    private static var cache: CashDepositAccount?

    static var current: CashDepositAccount {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            cache = .networkDefault
            return .networkDefault
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(CashDepositAccount.self, from: data) else {
            cache = .networkDefault
            return .networkDefault
        }
        cache = decoded
        return decoded
    }

    static func publish(_ account: CashDepositAccount) {
        cache = account
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(account) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func reset() {
        cache = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

/// How the slip photo compared against the amount the driver typed.
nonisolated enum DepositMatch: String, Codable, Sendable {
    case matched
    case mismatched
    case unreadable
    case notChecked

    var label: String {
        switch self {
        case .matched: "Monto verificado"
        case .mismatched: "Monto distinto al comprobante"
        case .unreadable: "Comprobante ilegible"
        case .notChecked: "Sin comprobante"
        }
    }

    var symbol: String {
        switch self {
        case .matched: "checkmark.seal.fill"
        case .mismatched: "exclamationmark.triangle.fill"
        case .unreadable: "questionmark.circle.fill"
        case .notChecked: "camera.fill"
        }
    }
}

/// One cash deposit reported by a driver. The manager sees it the moment it is saved.
nonisolated struct CashDeposit: Codable, Identifiable, Sendable {
    let id: String
    let stationId: String
    let driverId: String
    let driverName: String
    let vehicleNumber: String
    let declaredMxn: Int
    /// Amount read from the slip photo, when the reader could find one.
    let detectedMxn: Int?
    let match: DepositMatch
    /// Verdict of the destination account printed on the slip. Optional so deposits
    /// filed before this check keep decoding.
    var accountMatch: DepositMatch?
    /// Digits of the destination the slip actually shows, as printed.
    var detectedAccount: String?
    let bank: String
    let clabe: String
    let createdAt: Date
    var slip: Data?
    var acknowledgedAt: Date?

    var isAcknowledged: Bool { acknowledgedAt != nil }

    var differenceMxn: Int {
        guard let detectedMxn else { return 0 }
        return declaredMxn - detectedMxn
    }
}

/// Shared ledger between the driver app and the manager desk.
nonisolated enum CashDepositLedger {
    private static let storageKey = "turnoev.cash.deposits.v1"

    /// Deposits carry the slip photo. The manager's inbox reads this list while drawing,
    /// so it is decoded once and kept in memory instead of rebuilding every image on
    /// each render pass.
    private static var cache: [CashDeposit]?

    private static func load() -> [CashDeposit] {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            cache = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([CashDeposit].self, from: data)) ?? []
        cache = decoded
        return decoded
    }

    private static func save(_ deposits: [CashDeposit]) {
        cache = deposits
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(deposits) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func all() -> [CashDeposit] {
        load().sorted { $0.createdAt > $1.createdAt }
    }

    static func deposits(stationId: String) -> [CashDeposit] {
        all().filter { $0.stationId == stationId }
    }

    static func pending(stationId: String) -> [CashDeposit] {
        deposits(stationId: stationId).filter { !$0.isAcknowledged }
    }

    static func record(_ deposit: CashDeposit) {
        var current = load()
        current.append(deposit)
        save(current)
    }

    static func acknowledge(id: String, at date: Date) {
        var current = load()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index].acknowledgedAt = date
        save(current)
    }

    static func clear() {
        cache = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Cash charges reported by the platform

/// A trip the platform reports as paid in cash. It is not an authorized way to charge:
/// the moment it appears, the driver is holding money that belongs to the network and
/// has until the end of that same day to put it in the account. After that hour the
/// amount stops being a deposit and becomes a discount on the week.
nonisolated struct CashCharge: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    let stationId: String
    /// Trip folio as the platform reports it.
    let tripReference: String
    let amountMxn: Int
    /// Moment the passenger paid in cash. The deadline hangs from this date.
    let generatedAt: Date
    var depositedAt: Date?
    var chargedBackAt: Date?

    var isDeposited: Bool { depositedAt != nil }
    var isChargedBack: Bool { chargedBackAt != nil }
    var isOpen: Bool { depositedAt == nil && chargedBackAt == nil }
}

nonisolated enum CashChargeState: Sendable {
    case onTime(remainingMinutes: Int)
    case expired
    case deposited
    case chargedBack

    var isDepositable: Bool {
        if case .onTime = self { return true }
        return false
    }
}

nonisolated enum CashChargeRules {
    /// The money has to be in the account before the day of the trip ends.
    static func deadline(for charge: CashCharge) -> Date {
        let calendar = ShiftRules.calendar
        let startOfDay = calendar.startOfDay(for: charge.generatedAt)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return nextDay.addingTimeInterval(-1)
    }

    static func state(for charge: CashCharge, now: Date) -> CashChargeState {
        if charge.isDeposited { return .deposited }
        if charge.isChargedBack { return .chargedBack }
        let limit = deadline(for: charge)
        guard now <= limit else { return .expired }
        return .onTime(remainingMinutes: max(0, Int(limit.timeIntervalSince(now) / 60)))
    }

    /// The slip is only good for the day the cash was collected.
    static func isSameOperatingDay(_ date: Date, as charge: CashCharge) -> Bool {
        ShiftRules.calendar.isDate(date, inSameDayAs: charge.generatedAt)
    }

    static func remainingText(minutes: Int) -> String {
        if minutes >= 60 { return "\(minutes / 60) h \(minutes % 60) min" }
        return "\(minutes) min"
    }

    /// Concept the wallet shows when the amount was not deposited in time.
    static let recoveryConcept = "Cobro de viaje en efectivo"
}

/// Cash charges of a driver. In production this list arrives from the platform; here it
/// is filled by the same sync the driver triggers from his income screen.
nonisolated enum CashChargeLedger {
    private static let storageKey = "turnoev.cash.charges.v1"

    private static var cache: [CashCharge]?

    private static func load() -> [CashCharge] {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            cache = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([CashCharge].self, from: data)) ?? []
        cache = decoded
        return decoded
    }

    private static func save(_ charges: [CashCharge]) {
        cache = charges
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(charges) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func charges(driverId: String) -> [CashCharge] {
        load().filter { $0.driverId == driverId }.sorted { $0.generatedAt > $1.generatedAt }
    }

    static func open(driverId: String) -> [CashCharge] {
        charges(driverId: driverId).filter(\.isOpen)
    }

    static func chargedBack(driverId: String) -> [CashCharge] {
        charges(driverId: driverId).filter(\.isChargedBack)
    }

    static func add(_ charge: CashCharge) {
        var current = load()
        current.append(charge)
        save(current)
    }

    static func markDeposited(id: String, at date: Date) {
        var current = load()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index].depositedAt = date
        save(current)
    }

    static func markChargedBack(id: String, at date: Date) {
        var current = load()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index].chargedBackAt = date
        save(current)
    }

    static func clear() {
        cache = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Simulates the platform reporting a trip settled in cash.
    static func make(driverId: String, stationId: String, amountMxn: Int, now: Date) -> CashCharge {
        CashCharge(
            id: "cash-\(UUID().uuidString.prefix(8))",
            driverId: driverId,
            stationId: stationId,
            tripReference: "UBER-\(Int.random(in: 100_000...999_999))",
            amountMxn: amountMxn,
            generatedAt: now,
            depositedAt: nil,
            chargedBackAt: nil
        )
    }
}
