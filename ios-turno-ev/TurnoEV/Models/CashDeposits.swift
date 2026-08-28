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
///
/// It carries its provenance for the same reason the credit contract does: a deposit is
/// the proof that money left the driver's hands, and a slip minted on the phone to walk
/// through the flow is not that proof. Ownership alone cannot separate them — both the
/// fixture and the real record would name the same driver.
nonisolated struct CashDeposit: Codable, Identifiable, Sendable {
    let id: String
    /// Whether an authority produced this deposit or a demonstration session minted it.
    let origin: RecordOrigin
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

    enum CodingKeys: String, CodingKey {
        case id
        case origin
        case stationId
        case driverId
        case driverName
        case vehicleNumber
        case declaredMxn
        case detectedMxn
        case match
        case accountMatch
        case detectedAccount
        case bank
        case clabe
        case createdAt
        case slip
        case acknowledgedAt
    }
}

extension CashDeposit {
    /// Decoded by hand so slips filed before provenance existed still restore.
    ///
    /// A record whose JSON has no `origin` key is read as `.simulated`, never as
    /// `.backend`. The absent key means nobody ever asserted where it came from, and the
    /// only safe reading of that silence is the one that cannot turn a fixture into
    /// money. Declaring this in an extension keeps the memberwise initializer.
    ///
    /// `nonisolated` because the ledger is decoded off the main actor; without it the
    /// `Decodable` conformance of a `nonisolated` type would cross back into it.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        origin = try container.decodeIfPresent(RecordOrigin.self, forKey: .origin) ?? .simulated
        stationId = try container.decode(String.self, forKey: .stationId)
        driverId = try container.decode(String.self, forKey: .driverId)
        driverName = try container.decode(String.self, forKey: .driverName)
        vehicleNumber = try container.decode(String.self, forKey: .vehicleNumber)
        declaredMxn = try container.decode(Int.self, forKey: .declaredMxn)
        detectedMxn = try container.decodeIfPresent(Int.self, forKey: .detectedMxn)
        match = try container.decode(DepositMatch.self, forKey: .match)
        accountMatch = try container.decodeIfPresent(DepositMatch.self, forKey: .accountMatch)
        detectedAccount = try container.decodeIfPresent(String.self, forKey: .detectedAccount)
        bank = try container.decode(String.self, forKey: .bank)
        clabe = try container.decode(String.self, forKey: .clabe)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        slip = try container.decodeIfPresent(Data.self, forKey: .slip)
        acknowledgedAt = try container.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
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

    private static func all() -> [CashDeposit] {
        load().sorted { $0.createdAt > $1.createdAt }
    }

    /// Deposits of one station, in one ledger.
    ///
    /// `origin` has no default on purpose. A caller that does not say which ledger it is
    /// reading is a caller that has not decided whether fixtures count as money, and that
    /// is precisely the decision this parameter exists to force.
    static func deposits(stationId: String, origin: RecordOrigin) -> [CashDeposit] {
        all().filter { $0.stationId == stationId && $0.origin == origin }
    }

    static func pending(stationId: String, origin: RecordOrigin) -> [CashDeposit] {
        deposits(stationId: stationId, origin: origin).filter { !$0.isAcknowledged }
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
    /// Whether the platform really reported this trip or a demonstration session minted
    /// it. A charge becomes a deduction on the week the moment its day ends, so this is
    /// the field that decides whether an unpaid fixture can take money from someone.
    let origin: RecordOrigin
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

    enum CodingKeys: String, CodingKey {
        case id
        case origin
        case driverId
        case stationId
        case tripReference
        case amountMxn
        case generatedAt
        case depositedAt
        case chargedBackAt
    }
}

extension CashCharge {
    /// Decoded by hand so charges stored before provenance existed still restore.
    ///
    /// Same silence, same reading as `CashDeposit`: no `origin` key means `.simulated`.
    /// The trips already sitting in this ledger were all minted by the sync button on the
    /// income screen, and reading them as `.backend` would hand a real identity a debt
    /// that a tap on a phone invented.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        origin = try container.decodeIfPresent(RecordOrigin.self, forKey: .origin) ?? .simulated
        driverId = try container.decode(String.self, forKey: .driverId)
        stationId = try container.decode(String.self, forKey: .stationId)
        tripReference = try container.decode(String.self, forKey: .tripReference)
        amountMxn = try container.decode(Int.self, forKey: .amountMxn)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        depositedAt = try container.decodeIfPresent(Date.self, forKey: .depositedAt)
        chargedBackAt = try container.decodeIfPresent(Date.self, forKey: .chargedBackAt)
    }
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

    /// Charges of one driver, in one ledger.
    ///
    /// Both tests are required and neither has a default. Ownership alone was never a
    /// boundary here: a demonstration session and a proved identity can hold the same
    /// `driverId` — the laboratory seeds one, and a backend profile can be given the same
    /// id by hand — and every charge in this store was minted on the device. Filtering by
    /// name only would hand those fixtures straight to the identity that matched.
    static func charges(driverId: String, origin: RecordOrigin) -> [CashCharge] {
        load()
            .filter { $0.driverId == driverId && $0.origin == origin }
            .sorted { $0.generatedAt > $1.generatedAt }
    }

    static func open(driverId: String, origin: RecordOrigin) -> [CashCharge] {
        charges(driverId: driverId, origin: origin).filter(\.isOpen)
    }

    static func chargedBack(driverId: String, origin: RecordOrigin) -> [CashCharge] {
        charges(driverId: driverId, origin: origin).filter(\.isChargedBack)
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
    ///
    /// Sealed `.simulated` with no parameter to say otherwise. This function *is* the
    /// simulation: there is no argument a caller could pass that would make what it
    /// returns any more real, so the provenance is written here rather than trusted to
    /// whoever calls it.
    static func make(driverId: String, stationId: String, amountMxn: Int, now: Date) -> CashCharge {
        CashCharge(
            id: "cash-\(UUID().uuidString.prefix(8))",
            origin: .simulated,
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
