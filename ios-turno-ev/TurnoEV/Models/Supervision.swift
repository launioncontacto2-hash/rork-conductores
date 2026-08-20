import Foundation

/// Supervision domain: everything a station supervisor sees of the shared fleet
/// database, scoped to one station and one shift. Shaped for future Uber, GPS, OCR,
/// telemetry and AI feeds — every value here is produced by the simulated backend.

// MARK: - Drivers

nonisolated enum StationDriverState: String, Codable, CaseIterable, Sendable {
    /// Working with an approved unit.
    case operating
    /// Started after the 10 minute grace period.
    case late
    /// Shift window open and never showed up.
    case absent
    /// Scanned a unit and waits for the supervisor to approve the handover.
    case awaitingHandover
    /// Closed the shift and returned the unit.
    case finished

    var label: String {
        switch self {
        case .operating: "En operación"
        case .late: "Retrasado"
        case .absent: "Ausente"
        case .awaitingHandover: "Pendiente de entrega"
        case .finished: "Turno cerrado"
        }
    }

    var symbol: String {
        switch self {
        case .operating: "steeringwheel"
        case .late: "clock.badge.exclamationmark.fill"
        case .absent: "person.fill.xmark"
        case .awaitingHandover: "hand.raised.fill"
        case .finished: "checkmark.seal.fill"
        }
    }

    /// Present at the station for the head count.
    var isPresent: Bool { self != .absent }
}

nonisolated enum DriverCreditState: String, Codable, CaseIterable, Sendable {
    case none
    case current
    case behind
    case delivered

    var label: String {
        switch self {
        case .none: "Sin crédito"
        case .current: "Crédito al corriente"
        case .behind: "Crédito con atraso"
        case .delivered: "Unidad entregada"
        }
    }

    var shortLabel: String {
        switch self {
        case .none: "Sin crédito"
        case .current: "Al corriente"
        case .behind: "Con atraso"
        case .delivered: "Entregada"
        }
    }
}

/// One driver of the supervised shift, as the supervisor reads them.
nonisolated struct StationDriver: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let employeeNumber: String
    let photoAsset: String?
    let stationId: String
    let slot: ShiftSlot
    let group: ShiftGroup
    let phone: String
    var vehicleId: String?
    var vehicleNumber: String?
    var scheduledStartAt: Date
    var checkInAt: Date?
    var lateMinutes: Int
    var state: StationDriverState
    var earningsMxn: Int
    var trips: Int
    var creditState: DriverCreditState
    var openIncidents: Int
    var platformRating: Double
    /// Marks the credential that is running the driver app on this device.
    var isLiveSession: Bool = false

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var shortName: String {
        let parts = name.split(separator: " ")
        guard parts.count > 1 else { return name }
        return "\(parts[0]) \(parts[1])"
    }
}

nonisolated enum DriverFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case withoutUnit
    case late
    case absent
    case withIncidents

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "Todos"
        case .active: "Activos"
        case .withoutUnit: "Sin unidad"
        case .late: "Retrasados"
        case .absent: "Ausentes"
        case .withIncidents: "Con incidencias"
        }
    }

    var symbol: String {
        switch self {
        case .all: "person.3.fill"
        case .active: "steeringwheel"
        case .withoutUnit: "car.badge.gearshape"
        case .late: "clock.badge.exclamationmark.fill"
        case .absent: "person.fill.xmark"
        case .withIncidents: "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Fleet

nonisolated enum FleetVehicleState: String, Codable, CaseIterable, Identifiable, Sendable {
    case available
    case operating
    case maintenance
    case outOfService

    var id: String { rawValue }

    var label: String {
        switch self {
        case .available: "Disponible"
        case .operating: "En operación"
        case .maintenance: "En mantenimiento"
        case .outOfService: "Fuera de servicio"
        }
    }

    var symbol: String {
        switch self {
        case .available: "bolt.car.fill"
        case .operating: "car.side.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .outOfService: "xmark.octagon.fill"
        }
    }
}

nonisolated enum MaintenanceState: String, Codable, CaseIterable, Sendable {
    case ok
    case dueSoon
    case overdue
    case inWorkshop

    var label: String {
        switch self {
        case .ok: "Al día"
        case .dueSoon: "Servicio próximo"
        case .overdue: "Servicio vencido"
        case .inWorkshop: "En taller"
        }
    }
}

/// Unit of the station fleet with its live telemetry stand-in.
nonisolated struct StationVehicle: Codable, Identifiable, Sendable {
    let id: String
    let internalNumber: String
    let model: String
    let plates: String
    let stationId: String
    let bay: Int
    var state: FleetVehicleState
    var batteryPct: Int
    var odometerKm: Int
    var assignedDriverId: String?
    var assignedDriverName: String?
    var maintenance: MaintenanceState
    var nextServiceKm: Int
    var lastServiceAt: Date
    /// The windshield sticker was read at the start of the shift.
    var qrScanned: Bool
    var photoAsset: String

    var kmToService: Int { nextServiceKm - odometerKm }
}

// MARK: - Handover (entrega y recepción)

nonisolated enum HandoverKind: String, Codable, Sendable {
    case delivery
    case reception

    var label: String {
        switch self {
        case .delivery: "Entrega de unidad"
        case .reception: "Recepción de unidad"
        }
    }

    var shortLabel: String {
        switch self {
        case .delivery: "Entrega"
        case .reception: "Recepción"
        }
    }

    var symbol: String {
        switch self {
        case .delivery: "arrow.up.forward.circle.fill"
        case .reception: "arrow.down.backward.circle.fill"
        }
    }
}

/// The five validations a supervisor signs before a unit leaves or comes back.
nonisolated enum HandoverCheck: String, Codable, CaseIterable, Identifiable, Sendable {
    case assignment
    case qr
    case photos
    case shiftStart
    case vehicleReturn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assignment: "Aprobar asignación del vehículo"
        case .qr: "Validar escaneo del código QR"
        case .photos: "Verificar registro fotográfico"
        case .shiftStart: "Aprobar inicio de turno"
        case .vehicleReturn: "Aprobar entrega del vehículo"
        }
    }

    var hint: String {
        switch self {
        case .assignment: "Unidad de esta estación y conductor autorizado"
        case .qr: "El sticker leído coincide con la unidad"
        case .photos: "6 evidencias: odómetro, batería y 4 costados"
        case .shiftStart: "Batería sobre 70% y hora dentro de tolerancia"
        case .vehicleReturn: "Kilometraje final, carga y estado del interior"
        }
    }

    var symbol: String {
        switch self {
        case .assignment: "checkmark.circle.fill"
        case .qr: "qrcode.viewfinder"
        case .photos: "camera.fill"
        case .shiftStart: "play.circle.fill"
        case .vehicleReturn: "checkmark.seal.fill"
        }
    }

    func applies(to kind: HandoverKind) -> Bool {
        switch kind {
        case .delivery: self != .vehicleReturn
        case .reception: self == .photos || self == .vehicleReturn
        }
    }
}

nonisolated enum HandoverStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected

    var label: String {
        switch self {
        case .pending: "Por revisar"
        case .approved: "Aprobada"
        case .rejected: "Rechazada"
        }
    }
}

/// One delivery or reception waiting for the supervisor's signature.
nonisolated struct HandoverTicket: Codable, Identifiable, Sendable {
    let id: String
    let stationId: String
    let kind: HandoverKind
    let driverId: String
    let driverName: String
    let vehicleId: String
    let vehicleNumber: String
    let createdAt: Date
    let scheduledStartAt: Date
    let startOdometerKm: Int
    /// Reading declared by the driver when closing the shift.
    var endOdometerKm: Int?
    /// Reading the station has on record for the unit.
    var expectedOdometerKm: Int
    var batteryPct: Int
    var qrCodeRead: String?
    var photosCaptured: Int
    var lateMinutes: Int
    var observations: String
    var checks: [String: Bool]
    var status: HandoverStatus
    var resolvedAt: Date?
    var rejectionReason: String?
    /// Evidence rendered for simulated drivers; the live driver shows real captures.
    var odometerPhotoAsset: String?
    var isLiveSession: Bool

    var requiredChecks: [HandoverCheck] {
        HandoverCheck.allCases.filter { $0.applies(to: kind) }
    }

    func isChecked(_ check: HandoverCheck) -> Bool { checks[check.rawValue] == true }

    var completedChecks: Int { requiredChecks.filter { isChecked($0) }.count }

    var isReadyToApprove: Bool { completedChecks == requiredChecks.count }

    var kmDriven: Int? {
        guard let endOdometerKm else { return nil }
        return max(0, endOdometerKm - startOdometerKm)
    }

    /// OCR will validate this automatically; today the reading is compared by hand.
    var odometerGapKm: Int {
        switch kind {
        case .delivery: abs(startOdometerKm - expectedOdometerKm)
        case .reception: abs((endOdometerKm ?? expectedOdometerKm) - expectedOdometerKm)
        }
    }

    var hasOdometerGap: Bool { odometerGapKm > 0 }
}

// MARK: - Incidents

nonisolated enum IncidentSeverity: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high
    case critical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: "Baja"
        case .medium: "Media"
        case .high: "Alta"
        case .critical: "Crítica"
        }
    }

    var hint: String {
        switch self {
        case .low: "La unidad sigue operando"
        case .medium: "Requiere revisión del taller"
        case .high: "Unidad fuera de operación"
        case .critical: "Terceros, lesionados o pérdida total"
        }
    }

    var weight: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }
}

nonisolated struct StationIncident: Codable, Identifiable, Sendable {
    let id: String
    let stationId: String
    let driverId: String?
    let driverName: String
    let vehicleNumber: String
    let kind: IncidentKind
    var severity: IncidentSeverity
    let createdAt: Date
    let detail: String
    var photos: [Data]
    var status: IncidentStatus
    /// "Conductor" when it arrived from the driver app, or the supervisor's name.
    let reportedBy: String

    var isOpen: Bool { status != .closed }
}

// MARK: - Alerts

nonisolated enum StationAlertKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case driverLate
    case vehicleNotScanned
    case lowBattery
    case maintenanceOverdue
    case odometerGap
    case incident

    var id: String { rawValue }

    var label: String {
        switch self {
        case .driverLate: "Retraso de conductor"
        case .vehicleNotScanned: "Vehículo sin escanear"
        case .lowBattery: "Batería baja"
        case .maintenanceOverdue: "Mantenimiento vencido"
        case .odometerGap: "Diferencia de kilometraje"
        case .incident: "Incidente"
        }
    }

    var symbol: String {
        switch self {
        case .driverLate: "clock.badge.exclamationmark.fill"
        case .vehicleNotScanned: "qrcode.viewfinder"
        case .lowBattery: "battery.25percent"
        case .maintenanceOverdue: "wrench.and.screwdriver.fill"
        case .odometerGap: "gauge.with.dots.needle.bottom.50percent"
        case .incident: "exclamationmark.triangle.fill"
        }
    }
}

/// Alerts are generated by the rules engine, never typed by hand.
nonisolated struct StationAlert: Identifiable, Sendable {
    let id: String
    let kind: StationAlertKind
    let severity: IncidentSeverity
    let title: String
    let detail: String
    let createdAt: Date
    let driverId: String?
    let vehicleId: String?
    let ticketId: String?
}

// MARK: - Dashboard

nonisolated struct StationMetrics: Sendable {
    let activeVehicles: Int
    let pendingHandover: Int
    let outOfService: Int
    let inMaintenance: Int
    let presentDrivers: Int
    let absentDrivers: Int
    let lateDrivers: Int
    let openIncidents: Int
    let criticalAlerts: Int
    let capacity: Int
    let rosterSize: Int
    let earningsMxn: Int
    /// Fixed goal of the shift: authorized units by the driver goal of the day.
    let goalMxn: Int
    let tripsToday: Int
    /// Group the fixed goal belongs to, so the board can name weekday or weekend.
    let goalGroup: ShiftGroup

    var occupancyRatio: Double {
        capacity > 0 ? min(1, Double(activeVehicles) / Double(capacity)) : 0
    }

    var attendanceRatio: Double {
        rosterSize > 0 ? Double(presentDrivers) / Double(rosterSize) : 0
    }

    var goalRatio: Double { goalMxn > 0 ? Double(earningsMxn) / Double(goalMxn) : 0 }

    var goalGapMxn: Int { max(0, goalMxn - earningsMxn) }
}

// MARK: - Rules

/// Supervision rules: alert generation and shift-window helpers.
nonisolated enum SupervisionRules {
    /// Units below this level cannot start a shift.
    static let minBatteryPct = ShiftRules.minBatteryPct

    static func window(for slot: ShiftSlot) -> (start: Int, end: Int) { ShiftRules.window(for: slot) }

    /// Progress of the supervised shift, 0 before it opens and 1 once it closed.
    static func shiftProgress(slot: ShiftSlot, now: Date) -> Double {
        let bounds = window(for: slot)
        let current = Double(ShiftRules.minutesOfDay(now))
        let span = Double(bounds.end - bounds.start)
        guard span > 0 else { return 0 }
        return min(1, max(0, (current - Double(bounds.start)) / span))
    }

    static func isShiftOpen(slot: ShiftSlot, now: Date) -> Bool {
        let bounds = window(for: slot)
        let current = ShiftRules.minutesOfDay(now)
        return current >= bounds.start && current <= bounds.end
    }

    static func severity(forLateMinutes minutes: Int) -> IncidentSeverity {
        if minutes >= 45 { return .critical }
        if minutes >= 25 { return .high }
        return .medium
    }

    static func severity(forBattery level: Int) -> IncidentSeverity {
        if level <= 25 { return .high }
        if level <= 45 { return .medium }
        return .low
    }

    /// Builds the automatic alert board from the live station picture.
    static func alerts(
        drivers: [StationDriver],
        vehicles: [StationVehicle],
        tickets: [HandoverTicket],
        incidents: [StationIncident],
        now: Date
    ) -> [StationAlert] {
        var alerts: [StationAlert] = []

        for driver in drivers where driver.state == .late {
            alerts.append(
                StationAlert(
                    id: "alr-late-\(driver.id)",
                    kind: .driverLate,
                    severity: severity(forLateMinutes: driver.lateMinutes),
                    title: "\(driver.shortName) inició con \(Fmt.lateText(driver.lateMinutes)) de atraso",
                    detail: "Programado \(Fmt.clock(driver.scheduledStartAt)) · entrada \(driver.checkInAt.map(Fmt.clock) ?? "sin registro")",
                    createdAt: driver.checkInAt ?? now,
                    driverId: driver.id,
                    vehicleId: driver.vehicleId,
                    ticketId: nil
                )
            )
        }

        for driver in drivers where driver.state == .absent {
            alerts.append(
                StationAlert(
                    id: "alr-absent-\(driver.id)",
                    kind: .driverLate,
                    severity: .high,
                    title: "\(driver.shortName) sin registro de entrada",
                    detail: "Turno \(driver.slot.label.lowercased()) programado \(Fmt.clock(driver.scheduledStartAt)). Unidad sin asignar.",
                    createdAt: driver.scheduledStartAt,
                    driverId: driver.id,
                    vehicleId: nil,
                    ticketId: nil
                )
            )
        }

        for ticket in tickets where ticket.status == .pending && ticket.qrCodeRead == nil {
            alerts.append(
                StationAlert(
                    id: "alr-qr-\(ticket.id)",
                    kind: .vehicleNotScanned,
                    severity: .medium,
                    title: "\(ticket.vehicleNumber) sin lectura de QR",
                    detail: "\(ticket.driverName) pide \(ticket.kind.shortLabel.lowercased()) sin escanear el sticker de la unidad.",
                    createdAt: ticket.createdAt,
                    driverId: ticket.driverId,
                    vehicleId: ticket.vehicleId,
                    ticketId: ticket.id
                )
            )
        }

        for ticket in tickets where ticket.status == .pending && ticket.hasOdometerGap {
            alerts.append(
                StationAlert(
                    id: "alr-odo-\(ticket.id)",
                    kind: .odometerGap,
                    severity: ticket.odometerGapKm > 40 ? .high : .medium,
                    title: "Diferencia de \(Fmt.km(ticket.odometerGapKm)) en \(ticket.vehicleNumber)",
                    detail: "Lectura declarada por \(ticket.driverName) contra el registro de la estación.",
                    createdAt: ticket.createdAt,
                    driverId: ticket.driverId,
                    vehicleId: ticket.vehicleId,
                    ticketId: ticket.id
                )
            )
        }

        for vehicle in vehicles where vehicle.state != .maintenance && vehicle.batteryPct <= minBatteryPct {
            alerts.append(
                StationAlert(
                    id: "alr-bat-\(vehicle.id)",
                    kind: .lowBattery,
                    severity: severity(forBattery: vehicle.batteryPct),
                    title: "\(vehicle.internalNumber) al \(vehicle.batteryPct)% de carga",
                    detail: vehicle.state == .operating
                        ? "En ruta con \(vehicle.assignedDriverName ?? "conductor asignado"). Programa recarga."
                        : "No puede salir a turno con menos de \(minBatteryPct)%. Bahía \(vehicle.bay).",
                    createdAt: now,
                    driverId: vehicle.assignedDriverId,
                    vehicleId: vehicle.id,
                    ticketId: nil
                )
            )
        }

        for vehicle in vehicles where vehicle.maintenance == .overdue {
            alerts.append(
                StationAlert(
                    id: "alr-mto-\(vehicle.id)",
                    kind: .maintenanceOverdue,
                    severity: .high,
                    title: "\(vehicle.internalNumber) con servicio vencido",
                    detail: "Debió entrar a taller en \(Fmt.km(vehicle.nextServiceKm)) y lleva \(Fmt.km(vehicle.odometerKm)).",
                    createdAt: vehicle.lastServiceAt,
                    driverId: vehicle.assignedDriverId,
                    vehicleId: vehicle.id,
                    ticketId: nil
                )
            )
        }

        for incident in incidents where incident.isOpen {
            alerts.append(
                StationAlert(
                    id: "alr-inc-\(incident.id)",
                    kind: .incident,
                    severity: incident.severity,
                    title: "\(incident.kind.label) · \(incident.vehicleNumber)",
                    detail: "\(incident.driverName) · \(incident.detail)",
                    createdAt: incident.createdAt,
                    driverId: incident.driverId,
                    vehicleId: nil,
                    ticketId: nil
                )
            )
        }

        return alerts.sorted { lhs, rhs in
            lhs.severity.weight == rhs.severity.weight
                ? lhs.createdAt > rhs.createdAt
                : lhs.severity.weight > rhs.severity.weight
        }
    }
}
