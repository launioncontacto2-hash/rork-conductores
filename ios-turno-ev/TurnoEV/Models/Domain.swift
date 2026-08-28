import Foundation

/// Domain model for the fleet driver app. Everything is fed by mock data today and
/// shaped for future Uber, GPS, OCR and telemetry integrations.

nonisolated enum ShiftGroup: String, Codable, CaseIterable, Sendable {
    case weekday
    case weekend

    var label: String {
        switch self {
        case .weekday: "Entre semana"
        case .weekend: "Fin de semana"
        }
    }
}

nonisolated enum ShiftSlot: String, Codable, CaseIterable, Sendable {
    case morning
    case evening

    var label: String {
        switch self {
        case .morning: "Matutino"
        case .evening: "Vespertino"
        }
    }

    var rangeLabel: String {
        switch self {
        case .morning: "05:00 — 14:00"
        case .evening: "14:30 — 23:30"
        }
    }

    var paybackWindowLabel: String {
        switch self {
        case .morning: "04:00 — 05:00"
        case .evening: "23:30 — 00:30"
        }
    }
}

nonisolated struct Driver: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let employeeNumber: String
    let email: String
    let password: String
    let photoAsset: String
    /// Station the driver belongs to; work can only start in this station.
    let stationId: String
    let station: String
    let group: ShiftGroup
    let slot: ShiftSlot
    let authorizedVehicleIds: [String]
}

nonisolated enum VehicleStatus: String, Codable, Sendable {
    case available
    case occupied
    case maintenance

    var label: String {
        switch self {
        case .available: "Disponible"
        case .occupied: "Ocupado"
        case .maintenance: "En mantenimiento"
        }
    }
}

nonisolated struct Vehicle: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let qrCode: String
    let internalNumber: String
    let model: String
    let plates: String
    var odometerKm: Int
    var batteryPct: Int
    let stationId: String
    let station: String
    var status: VehicleStatus
    var occupiedBy: String?
    let photoAsset: String
}

nonisolated enum InspectionSlot: String, Codable, CaseIterable, Sendable {
    case odometer
    case battery
    case front
    case left
    case right
    case rear

    var title: String {
        switch self {
        case .odometer: "Odómetro"
        case .battery: "Nivel de batería"
        case .front: "Frente"
        case .left: "Lateral izquierdo"
        case .right: "Lateral derecho"
        case .rear: "Trasera"
        }
    }

    var hint: String {
        switch self {
        case .odometer: "Lectura legible"
        case .battery: "Tablero encendido"
        case .front: "Placa visible"
        case .left: "Cuerpo completo"
        case .right: "Cuerpo completo"
        case .rear: "Cajuela y micas"
        }
    }

    /// Evidence the driver captures to start the shift: only the two readings.
    /// The body of the unit is no longer photographed at every start.
    static let driverSlots: [InspectionSlot] = [.odometer, .battery]

    /// Body angles. Reserved for supervision when an incident or report is raised.
    static let bodySlots: [InspectionSlot] = [.front, .left, .right, .rear]
}

nonisolated struct ActiveShift: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    let vehicleId: String
    let group: ShiftGroup
    let slot: ShiftSlot
    let scheduledStartAt: Date
    let startedAt: Date
    let lateMinutes: Int
    let startOdometerKm: Int
    let startBatteryPct: Int
    /// Evidence keyed by `InspectionSlot.rawValue`.
    var photos: [String: Data]
    var trips: Int
    var earningsMxn: Int
}

nonisolated struct ShiftRecord: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    let vehicleId: String
    let vehicleInternalNumber: String
    let group: ShiftGroup
    let slot: ShiftSlot
    let scheduledStartAt: Date
    let startedAt: Date
    let endedAt: Date
    let lateMinutes: Int
    var paidBackMinutes: Int
    let startOdometerKm: Int
    let endOdometerKm: Int
    let startBatteryPct: Int
    let endBatteryPct: Int
    let trips: Int
    let earningsMxn: Int

    var kmDriven: Int { max(0, endOdometerKm - startOdometerKm) }
    var durationMinutes: Int { max(0, Int(endedAt.timeIntervalSince(startedAt) / 60)) }
    var pendingLateMinutes: Int { max(0, lateMinutes - paidBackMinutes) }
}

nonisolated enum IncomePlatform: String, Codable, CaseIterable, Sendable {
    case uber = "Uber"
    case didi = "DiDi"
    case cash = "Efectivo"
    case other = "Otro"

    var label: String { rawValue }
}

nonisolated struct IncomeEntry: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    /// Whether the platform reported this income or a demonstration session minted it.
    /// Ownership is already answered by `driverId`; this answers whether it happened.
    let origin: RecordOrigin
    let shiftId: String?
    let date: Date
    let amountMxn: Int
    let trips: Int
    let platform: IncomePlatform
    var evidence: Data?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case driverId
        case origin
        case shiftId
        case date
        case amountMxn
        case trips
        case platform
        case evidence
        case note
    }
}

extension IncomeEntry {
    /// Entries stored before 15B.10 decode as `.simulated`: every one of them was
    /// written by a demonstration session, because no other kind could write one.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        driverId = try container.decode(String.self, forKey: .driverId)
        origin = try container.decodeIfPresent(RecordOrigin.self, forKey: .origin) ?? .simulated
        shiftId = try container.decodeIfPresent(String.self, forKey: .shiftId)
        date = try container.decode(Date.self, forKey: .date)
        amountMxn = try container.decode(Int.self, forKey: .amountMxn)
        trips = try container.decode(Int.self, forKey: .trips)
        platform = try container.decode(IncomePlatform.self, forKey: .platform)
        evidence = try container.decodeIfPresent(Data.self, forKey: .evidence)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

nonisolated enum IncidentKind: String, Codable, CaseIterable, Sendable {
    case accident
    case damage
    case mechanical

    var label: String {
        switch self {
        case .accident: "Accidente"
        case .damage: "Daño"
        case .mechanical: "Falla mecánica"
        }
    }

    var hint: String {
        switch self {
        case .accident: "Con terceros o daños mayores"
        case .damage: "Golpes, rayones, cristales"
        case .mechanical: "Frenos, carga, suspensión"
        }
    }

    var symbol: String {
        switch self {
        case .accident: "exclamationmark.shield.fill"
        case .damage: "car.side.fill"
        case .mechanical: "wrench.and.screwdriver.fill"
        }
    }
}

nonisolated enum IncidentStatus: String, Codable, Sendable {
    case open
    case review
    case closed

    var label: String {
        switch self {
        case .open: "Abierta"
        case .review: "En revisión"
        case .closed: "Cerrada"
        }
    }
}

nonisolated struct Incident: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    let vehicleId: String
    let vehicleInternalNumber: String
    let kind: IncidentKind
    let createdAt: Date
    let description: String
    var photos: [Data]
    var status: IncidentStatus
}

nonisolated enum NoticeKind: String, Codable, Sendable {
    case maintenance
    case credit
    case station
    case reminder

    var label: String {
        switch self {
        case .maintenance: "Mantenimiento"
        case .credit: "Crédito"
        case .station: "Estación"
        case .reminder: "Recordatorio"
        }
    }

    var symbol: String {
        switch self {
        case .maintenance: "wrench.adjustable.fill"
        case .credit: "creditcard.fill"
        case .station: "mappin.and.ellipse"
        case .reminder: "bell.badge.fill"
        }
    }
}

nonisolated struct Notice: Codable, Identifiable, Sendable {
    let id: String
    let kind: NoticeKind
    let title: String
    let body: String
    let createdAt: Date
    var read: Bool
}

nonisolated enum CreditStatus: String, Codable, Sendable {
    case paid
    case due
    case late

    var label: String {
        switch self {
        case .paid: "Pagado"
        case .due: "Por pagar"
        case .late: "Vencido"
        }
    }
}

nonisolated struct CreditPayment: Codable, Identifiable, Sendable {
    let id: String
    let concept: String
    let dueDate: Date
    let amountMxn: Int
    let status: CreditStatus
}

/// A signed credit contract.
///
/// It carries its owner and its provenance because a weekly instalment is a deduction
/// from someone's pay: a contract that cannot say whose it is, and whether an authority
/// produced it, is not something a settlement is allowed to act on. Every other
/// financial record already named its driver; this one did not, and that is what let a
/// locally minted contract charge a real identity.
nonisolated struct CreditAccount: Codable, Sendable {
    /// Driver this contract belongs to. Checked wherever the contract turns into money.
    let driverId: String
    /// Whether an authority produced this contract or a demonstration session minted it.
    let origin: RecordOrigin
    let contractId: String
    let vehicleTarget: String
    /// Contract signature date; the delivery month and the term are measured from here.
    let startedAt: Date
    let totalMxn: Int
    let paidMxn: Int
    let weeklyMxn: Int
    let weeksPaid: Int
    let onTimePayments: Int
    let latePayments: Int
    /// Odometer of the unit reserved for this contract; it leaves the fleet at 110,000-120,000 km.
    let assignedVehicleOdometerKm: Int
    let payments: [CreditPayment]

    enum CodingKeys: String, CodingKey {
        case driverId
        case origin
        case contractId
        case vehicleTarget
        case startedAt
        case totalMxn
        case paidMxn
        case weeklyMxn
        case weeksPaid
        case onTimePayments
        case latePayments
        case assignedVehicleOdometerKm
        case payments
    }

    /// Owner of a contract stored before ownership existed. It matches no driver on
    /// purpose: an unprovable owner must never coincide with a real one.
    static let unattributedOwnerId: String = ""

    /// Whether the contract names someone.
    var isAttributed: Bool { driverId != Self.unattributedOwnerId }

    /// The same contract, named for the driver it belongs to.
    ///
    /// Provenance is deliberately carried over untouched: naming a fixture does not
    /// turn it into an authoritative debt.
    func attributed(to driverId: String) -> CreditAccount {
        CreditAccount(
            driverId: driverId,
            origin: origin,
            contractId: contractId,
            vehicleTarget: vehicleTarget,
            startedAt: startedAt,
            totalMxn: totalMxn,
            paidMxn: paidMxn,
            weeklyMxn: weeklyMxn,
            weeksPaid: weeksPaid,
            onTimePayments: onTimePayments,
            latePayments: latePayments,
            assignedVehicleOdometerKm: assignedVehicleOdometerKm,
            payments: payments
        )
    }
}

extension CreditAccount {
    /// Reads contracts stored before 15B.10, which carry neither owner nor provenance.
    ///
    /// Such a contract is decoded as unattributed and `.simulated`. Both defaults are
    /// the conservative answer: the blob cannot prove who signed it, and a contract
    /// nobody can prove is a fixture. Silently handing it to whoever happens to be
    /// signed in — which is how a backend identity would inherit it — is exactly the
    /// failure this field exists to prevent.
    ///
    /// Declared in an extension so the memberwise initializer survives: there is no
    /// initializer that can build an anonymous contract, only a decoder that can read
    /// one and mark it as unprovable.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        driverId = try container.decodeIfPresent(String.self, forKey: .driverId) ?? Self.unattributedOwnerId
        origin = try container.decodeIfPresent(RecordOrigin.self, forKey: .origin) ?? .simulated
        contractId = try container.decode(String.self, forKey: .contractId)
        vehicleTarget = try container.decode(String.self, forKey: .vehicleTarget)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        totalMxn = try container.decode(Int.self, forKey: .totalMxn)
        paidMxn = try container.decode(Int.self, forKey: .paidMxn)
        weeklyMxn = try container.decode(Int.self, forKey: .weeklyMxn)
        weeksPaid = try container.decode(Int.self, forKey: .weeksPaid)
        onTimePayments = try container.decode(Int.self, forKey: .onTimePayments)
        latePayments = try container.decode(Int.self, forKey: .latePayments)
        assignedVehicleOdometerKm = try container.decode(Int.self, forKey: .assignedVehicleOdometerKm)
        payments = try container.decode([CreditPayment].self, forKey: .payments)
    }
}

nonisolated enum AssignmentIssueCode: String, Sendable {
    case otherStation
    case vehicleOccupied
    case invalidShift
    case notAuthorized
    case lowBattery
    case odometerMismatch
    /// The station never tied a unit to this driver.
    case notAssigned
    /// The sticker read belongs to a unit that is not the assigned one.
    case wrongVehicle
    /// The clock is outside the start window of the block.
    case outsideWindow
}

nonisolated struct AssignmentIssue: Identifiable, Sendable {
    let code: AssignmentIssueCode
    let message: String

    var id: String { code.rawValue }
}

nonisolated struct ShiftSummary: Sendable {
    let kmDriven: Int
    let durationMinutes: Int
    let earningsMxn: Int
    let trips: Int
    let dailyGoalMxn: Int
    let missingMxn: Int
    let missingTrips: Int
    let lateMinutes: Int
}
