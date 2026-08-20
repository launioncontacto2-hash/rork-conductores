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
    let shiftId: String?
    let date: Date
    let amountMxn: Int
    let trips: Int
    let platform: IncomePlatform
    var evidence: Data?
    var note: String?
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

nonisolated struct CreditAccount: Codable, Sendable {
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
