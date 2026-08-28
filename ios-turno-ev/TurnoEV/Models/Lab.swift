import Foundation

/// Test laboratory domain. Two environments live in the same binary: PRODUCTION, which
/// keeps the seeded demonstration network, and TEST, which starts completely empty and
/// is fed exclusively by the test administrator. Nothing created here can reach a real
/// record: every entity carries the test origin and the whole environment can be wiped.

// MARK: - Environment

nonisolated enum LabMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case production
    case test

    var id: String { rawValue }

    var label: String {
        switch self {
        case .production: "Producción"
        case .test: "Modo prueba"
        }
    }

    var shortLabel: String {
        switch self {
        case .production: "PROD"
        case .test: "PRUEBA"
        }
    }

    var detail: String {
        switch self {
        case .production: "Red demostrativa sembrada: estaciones, flotilla y personal precargados."
        case .test: "Entorno vacío. Solo existe lo que tú creas desde el laboratorio."
        }
    }

    var symbol: String {
        switch self {
        case .production: "checkmark.seal.fill"
        case .test: "testtube.2"
        }
    }
}

/// Projection of the test world that the `nonisolated` seed layer reads. It is the only
/// bridge between the laboratory and the rest of the app: when the mode is production it
/// is inert and every simulator keeps its original behaviour.
nonisolated struct LabBridge: Sendable {
    var mode: LabMode = .production
    var regions: [Region] = []
    var stations: [Station] = []
    var accounts: [StaffAccount] = []
    var vehicles: [Vehicle] = []
    var drivers: [Driver] = []
    var driversPerVehicle: Int = 4

    var isTest: Bool { mode == .test }

    func driver(id: String?) -> Driver? {
        guard let id else { return nil }
        return drivers.first { $0.id == id }
    }

    static let production = LabBridge()
}

/// Synchronous, self-bootstrapping access point. The first read hydrates itself from
/// disk so a store built during app launch already sees the right environment.
nonisolated enum LabRuntime {
    /// Written only from the main actor (the lab store) and read from seed builders that
    /// run in the same synchronous call stack; no concurrent mutation exists.
    nonisolated(unsafe) private static var cache: LabWorld?

    /// Full test world. Seed builders read it to rebuild every module snapshot.
    static var world: LabWorld {
        if let cache { return cache }
        let loaded = LabPersistence.load()
        cache = loaded
        return loaded
    }

    static var bridge: LabBridge { world.bridge }

    static func install(_ world: LabWorld) { cache = world }

    /// The environment is **not** read from the world any more.
    ///
    /// `bridge.mode` came out of `turnoev.lab.v1`, which decodes all-or-nothing: one
    /// unreadable fixture and the whole payload fell back to `.empty`, whose mode is
    /// production. The environment now has a key of its own and cannot be lost by a
    /// scenario — see `EnvironmentStore`.
    static var isTest: Bool { mode == .test }
    static var mode: LabMode { EnvironmentStore.current }
    static var regions: [Region] { bridge.regions }
    static var stations: [Station] { bridge.stations }
    static var accounts: [StaffAccount] { bridge.accounts }
    static var vehicles: [Vehicle] { bridge.vehicles }
    static var drivers: [Driver] { bridge.drivers }
    static var driver: Driver? { bridge.drivers.first }
    static func driver(id: String?) -> Driver? { bridge.driver(id: id) }
    static var driversPerVehicle: Int { max(1, bridge.driversPerVehicle) }
}

// MARK: - Sections of the console

nonisolated enum LabSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case stations
    case users
    case vehicles
    case humanResources
    case recruitment
    case operation
    case coverage
    case credits
    case bonuses
    case goals
    case maintenance
    case finance
    case documents
    case alerts
    case integrations
    case scenarios
    case visualEditor
    case audit
    case reset

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Sistema"
        case .stations: "Estaciones"
        case .users: "Usuarios"
        case .vehicles: "Vehículos"
        case .humanResources: "Recursos Humanos"
        case .recruitment: "Reclutamiento"
        case .operation: "Operación"
        case .coverage: "Cobertura de turnos"
        case .credits: "Créditos"
        case .bonuses: "Bonos"
        case .goals: "Metas"
        case .maintenance: "Mantenimiento"
        case .finance: "Finanzas"
        case .documents: "Documentos"
        case .alerts: "Alertas"
        case .integrations: "Integraciones simuladas"
        case .scenarios: "Escenarios"
        case .visualEditor: "Editor visual"
        case .audit: "Auditoría"
        case .reset: "Reiniciar sistema"
        }
    }

    var symbol: String {
        switch self {
        case .system: "gearshape.2.fill"
        case .stations: "building.2.fill"
        case .users: "person.badge.key.fill"
        case .vehicles: "car.2.fill"
        case .humanResources: "folder.fill.badge.person.crop"
        case .recruitment: "person.crop.circle.badge.plus"
        case .operation: "gauge.with.dots.needle.bottom.50percent"
        case .coverage: "calendar.badge.clock"
        case .credits: "creditcard.fill"
        case .bonuses: "rosette"
        case .goals: "target"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .finance: "banknote.fill"
        case .documents: "doc.viewfinder.fill"
        case .alerts: "bell.badge.fill"
        case .integrations: "antenna.radiowaves.left.and.right"
        case .scenarios: "square.stack.3d.up.fill"
        case .visualEditor: "square.dashed.inset.filled"
        case .audit: "list.bullet.rectangle.portrait.fill"
        case .reset: "trash.fill"
        }
    }

    var caption: String {
        switch self {
        case .system: "Modo, reloj y configuración global"
        case .stations: "Alta y ciclo de vida de estaciones"
        case .users: "Credenciales de todos los roles"
        case .vehicles: "Flotilla, QR, odómetro y batería"
        case .humanResources: "Expedientes, documentos y bajas"
        case .recruitment: "Leads, embudo y campañas"
        case .operation: "Turnos, eventos e incidencias"
        case .coverage: "Ausencias, guardias y reemplazos"
        case .credits: "Contratos y su comportamiento"
        case .bonuses: "Reglas de bonos por rol"
        case .goals: "Metas por alcance"
        case .maintenance: "Activos y órdenes de servicio"
        case .finance: "Liquidaciones y datos bancarios"
        case .documents: "Cámara, galería y archivos reales"
        case .alerts: "Generador manual por nivel"
        case .integrations: "Uber, BYD, Meta y banca"
        case .scenarios: "Cargar una red completa de golpe"
        case .visualEditor: "Editar las interfaces sin escribir código"
        case .audit: "Historial de todo lo ejecutado"
        case .reset: "Vaciar el entorno de pruebas"
        }
    }

    /// Sections that describe the state of the world rather than an action on it.
    var isDestructive: Bool { self == .reset }
}

// MARK: - Stations

nonisolated enum StationLifecycle: String, Codable, CaseIterable, Identifiable, Sendable {
    case planning
    case installation
    case opening
    case active
    case suspended
    case closed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .planning: "Planeación"
        case .installation: "Instalación"
        case .opening: "Próxima apertura"
        case .active: "Activa"
        case .suspended: "Suspendida"
        case .closed: "Cerrada"
        }
    }

    var symbol: String {
        switch self {
        case .planning: "map"
        case .installation: "hammer.fill"
        case .opening: "calendar.badge.clock"
        case .active: "bolt.fill"
        case .suspended: "pause.circle.fill"
        case .closed: "xmark.circle.fill"
        }
    }

    /// Only an operating station is visible to the operational roles.
    var isOperational: Bool { self == .active || self == .opening }
}

nonisolated struct LabStation: Codable, Identifiable, Sendable {
    let id: String
    var code: String
    var name: String
    var city: String
    var state: String
    var address: String
    var regionId: String
    var openedAt: Date
    var maxVehicles: Int
    var plannedVehicles: Int
    var lifecycle: StationLifecycle
    var driversPerVehicle: Int
    var supervisorsRequired: Int
    var maintenanceRequired: Int
    var managerId: String?
    var activeBlocks: [ShiftBlock]
    var createdAt: Date

    var displayName: String { "\(name) · \(city)" }

    /// Domain station seen by every other module. The installed fleet is data, so it is
    /// injected by the world projection, never stored twice.
    func station(installedVehicles: Int) -> Station {
        Station(
            id: id,
            code: code,
            name: name,
            city: city,
            regionId: regionId,
            vehicleCapacity: installedVehicles
        )
    }
}

// MARK: - Vehicles

nonisolated enum LabVehicleStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case purchase
    case transit
    case preparation
    case available
    case operating
    case maintenance
    case outOfService

    var id: String { rawValue }

    var label: String {
        switch self {
        case .purchase: "En compra"
        case .transit: "En traslado"
        case .preparation: "En preparación"
        case .available: "Disponible"
        case .operating: "En operación"
        case .maintenance: "En mantenimiento"
        case .outOfService: "Fuera de servicio"
        }
    }

    var symbol: String {
        switch self {
        case .purchase: "cart.fill"
        case .transit: "truck.box.fill"
        case .preparation: "shippingbox.fill"
        case .available: "checkmark.circle.fill"
        case .operating: "steeringwheel"
        case .maintenance: "wrench.adjustable.fill"
        case .outOfService: "exclamationmark.octagon.fill"
        }
    }

    /// Units that already count for the driver arithmetic (units × drivers per vehicle).
    var isInstalled: Bool {
        switch self {
        case .available, .operating, .maintenance: true
        case .purchase, .transit, .preparation, .outOfService: false
        }
    }

    /// Units still on their way in; they generate future vacancies.
    var isIncoming: Bool {
        switch self {
        case .purchase, .transit, .preparation: true
        default: false
        }
    }

    var fleetState: VehicleStatus {
        switch self {
        case .operating: .occupied
        case .maintenance, .outOfService: .maintenance
        default: .available
        }
    }
}

nonisolated struct LabVehicle: Codable, Identifiable, Sendable {
    let id: String
    var internalNumber: String
    var brand: String
    var model: String
    var year: Int
    var vin: String
    var plates: String
    var odometerKm: Int
    var batteryPct: Int
    var rangeKm: Int
    var stationId: String
    var stage: LabVehicleStage
    var incorporatedAt: Date
    var operationStartAt: Date
    var qrCode: String
    var occupiedBy: String?
    /// Readings coming from the two simulated sources, kept apart so a discrepancy is visible.
    var photoOdometerKm: Int?
    var telemetryOdometerKm: Int?
    var lastTelemetryAt: Date?
    var createdAt: Date

    var fullModel: String { "\(brand) \(model) \(year)" }

    /// The station name is injected instead of looked up: the projection runs while the
    /// runtime cache is being built, so reading it back here would recurse.
    func vehicle(stationName: String) -> Vehicle {
        Vehicle(
            id: id,
            qrCode: qrCode,
            internalNumber: internalNumber,
            model: fullModel,
            plates: plates,
            odometerKm: odometerKm,
            batteryPct: batteryPct,
            stationId: stationId,
            station: stationName,
            status: stage.fleetState,
            occupiedBy: occupiedBy,
            photoAsset: "electric_sedan_charging"
        )
    }

    /// Largest gap between the three odometer sources. Anything above zero must raise an alert.
    var odometerGapKm: Int {
        let readings = [odometerKm, photoOdometerKm, telemetryOdometerKm].compactMap { $0 }
        guard let low = readings.min(), let high = readings.max() else { return 0 }
        return high - low
    }
}

// MARK: - Users

nonisolated struct LabUser: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var employeeNumber: String
    var email: String
    var phone: String
    var password: String
    var role: StaffRole
    var stationId: String?
    var regionId: String?
    var block: ShiftBlock?
    var photoData: Data?
    var status: StaffStatus
    var employment: EmploymentStatus
    var hiredAt: Date
    var driverId: String?
    var createdAt: Date
    /// Temporary role used only to review another interface; the real role never changes.
    var testRole: StaffRole?

    var effectiveRole: StaffRole { testRole ?? role }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var slot: ShiftSlot? { block?.slot }

    var account: StaffAccount {
        StaffAccount(
            id: id,
            name: name,
            employeeNumber: employeeNumber,
            email: email.lowercased(),
            password: password,
            role: effectiveRole,
            stationId: stationId,
            regionId: regionId,
            slot: slot,
            photoAsset: nil,
            status: status,
            createdById: LabRules.adminAccountId,
            authorizedById: nil,
            driverId: driverId,
            phone: phone.isEmpty ? nil : phone
        )
    }
}

// MARK: - Credits

nonisolated enum LabCreditState: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case current
    case late
    case suspended
    case settled
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: "Activo"
        case .current: "Al corriente"
        case .late: "Atrasado"
        case .suspended: "Suspendido"
        case .settled: "Liquidado"
        case .cancelled: "Cancelado"
        }
    }

    var isOpen: Bool {
        switch self {
        case .active, .current, .late, .suspended: true
        case .settled, .cancelled: false
        }
    }
}

nonisolated struct LabCreditMovement: Codable, Identifiable, Sendable {
    let id: String
    var date: Date
    var concept: String
    var amountMxn: Int
    var detail: String
}

nonisolated struct LabCredit: Codable, Identifiable, Sendable {
    let id: String
    var driverId: String
    var driverName: String
    var vehicleId: String?
    var vehicleLabel: String
    var principalMxn: Int
    var weeklyMxn: Int
    var weeks: Int
    var weeksPaid: Int
    var paidMxn: Int
    var startedAt: Date
    var endsAt: Date
    var state: LabCreditState
    var movements: [LabCreditMovement]
    var createdAt: Date

    var balanceMxn: Int { max(0, principalMxn - paidMxn) }
    var progress: Double { principalMxn > 0 ? min(1, Double(paidMxn) / Double(principalMxn)) : 0 }
}

// MARK: - Bonuses and goals

nonisolated enum LabBonusPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly
    case monthly
    case quarterly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekly: "Semanal"
        case .monthly: "Mensual"
        case .quarterly: "Trimestral"
        }
    }
}

nonisolated struct LabBonus: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var detail: String
    var amountMxn: Int
    var condition: String
    var period: LabBonusPeriod
    var stationId: String?
    var role: StaffRole
    var startsAt: Date
    var endsAt: Date
    var isActive: Bool
    var createdAt: Date
}

nonisolated enum LabGoalScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case national
    case station
    case block
    case driver

    var id: String { rawValue }

    var label: String {
        switch self {
        case .national: "Nacional"
        case .station: "Por estación"
        case .block: "Por turno"
        case .driver: "Por conductor"
        }
    }

    var symbol: String {
        switch self {
        case .national: "globe.americas.fill"
        case .station: "building.2.fill"
        case .block: "clock.fill"
        case .driver: "person.fill"
        }
    }
}

nonisolated struct LabGoal: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var scope: LabGoalScope
    var targetId: String?
    var targetLabel: String
    var group: ShiftGroup
    var hourlyMxn: Int
    var hoursPerDay: Int
    var tripsPerDay: Int
    var createdAt: Date

    var dailyMxn: Int { hourlyMxn * hoursPerDay }
    var weeklyMxn: Int { dailyMxn * 6 }
    var monthlyMxn: Int { dailyMxn * 26 }
}

// MARK: - Shift configuration

nonisolated struct LabBlockConfig: Codable, Identifiable, Sendable {
    var block: ShiftBlock
    var startMinute: Int
    var endMinute: Int
    var isActive: Bool

    var id: String { block.rawValue }

    var scheduleLabel: String {
        "\(Self.clock(startMinute)) — \(Self.clock(endMinute))"
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

nonisolated struct LabShiftConfig: Codable, Sendable {
    var driversPerVehicle: Int
    var shiftHours: Int
    var mealHours: Int
    var graceMinutes: Int
    var minimumBatteryPct: Int
    var inspectionPhotos: Int
    var blocks: [LabBlockConfig]

    static let standard = LabShiftConfig(
        driversPerVehicle: 4,
        shiftHours: 8,
        mealHours: 1,
        graceMinutes: 10,
        minimumBatteryPct: 70,
        inspectionPhotos: 6,
        blocks: [
            LabBlockConfig(block: .weekdayMorning, startMinute: 5 * 60, endMinute: 14 * 60, isActive: true),
            LabBlockConfig(block: .weekdayEvening, startMinute: 14 * 60 + 30, endMinute: 23 * 60 + 30, isActive: true),
            LabBlockConfig(block: .weekendMorning, startMinute: 5 * 60, endMinute: 14 * 60, isActive: true),
            LabBlockConfig(block: .weekendEvening, startMinute: 14 * 60 + 30, endMinute: 23 * 60 + 30, isActive: true),
        ]
    )

    var activeBlocks: [LabBlockConfig] { blocks.filter(\.isActive) }
}

// MARK: - Documents captured in the laboratory

nonisolated enum LabDocumentSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case camera
    case gallery
    case file

    var id: String { rawValue }

    var label: String {
        switch self {
        case .camera: "Cámara"
        case .gallery: "Galería"
        case .file: "Archivo"
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .gallery: "photo.on.rectangle.angled"
        case .file: "folder.fill"
        }
    }
}

nonisolated enum LabOcrOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case correct
    case incorrect
    case unreadable
    case incomplete
    case expired

    var id: String { rawValue }

    var label: String {
        switch self {
        case .correct: "Lectura correcta"
        case .incorrect: "Lectura incorrecta"
        case .unreadable: "Documento ilegible"
        case .incomplete: "Datos incompletos"
        case .expired: "Documento vencido"
        }
    }

    var symbol: String {
        switch self {
        case .correct: "checkmark.seal.fill"
        case .incorrect: "exclamationmark.triangle.fill"
        case .unreadable: "eye.slash.fill"
        case .incomplete: "square.dashed"
        case .expired: "calendar.badge.exclamationmark"
        }
    }

    /// How the app reacts: the document is accepted only on a clean read.
    var documentStatus: DocumentStatus {
        switch self {
        case .correct: .delivered
        case .incorrect, .unreadable, .incomplete: .rejected
        case .expired: .expired
        }
    }

    var appResponse: String {
        switch self {
        case .correct: "Documento aceptado y adjuntado al expediente. El campo de captura se llena solo."
        case .incorrect: "Los datos leídos no coinciden con el expediente. Se pide recaptura manual."
        case .unreadable: "No se pudo extraer texto. Se solicita nueva fotografía con mejor luz."
        case .incomplete: "Faltan campos obligatorios. El expediente queda incompleto y bloquea la contratación."
        case .expired: "La vigencia ya pasó. El expediente se marca vencido y se avisa al supervisor."
        }
    }

    var confidence: Int {
        switch self {
        case .correct: 97
        case .incorrect: 71
        case .unreadable: 12
        case .incomplete: 58
        case .expired: 94
        }
    }
}

nonisolated struct LabOcrResult: Codable, Sendable {
    var outcome: LabOcrOutcome
    var fields: [String: String]
    var confidence: Int
    var readAt: Date
}

nonisolated struct LabDocument: Codable, Identifiable, Sendable {
    let id: String
    var kind: DocumentKind
    var subjectId: String
    var subjectName: String
    var fileName: String
    var mime: String
    var data: Data?
    var byteCount: Int
    var source: LabDocumentSource
    var capturedAt: Date
    var ocr: LabOcrResult?

    var isPdf: Bool { mime == "application/pdf" }

    var sizeLabel: String {
        let kb = Double(byteCount) / 1024
        return kb >= 1024
            ? String(format: "%.1f MB", kb / 1024)
            : String(format: "%.0f KB", kb)
    }
}

// MARK: - Alerts, faults and audit

nonisolated struct LabAlert: Codable, Identifiable, Sendable {
    let id: String
    var level: OpsAlertLevel
    var audience: StaffRole
    var stationId: String?
    var title: String
    var detail: String
    var createdAt: Date
    var origin: String
    var isRead: Bool
}

nonisolated enum LabFaultKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case vehicleBreakdown
    case lowBattery
    case overdueMaintenance
    case driverAbsent
    case driverLate
    case expiredDocument
    case lateCredit
    case duplicateClabe
    case rejectedTransfer
    case overdueOrder
    case candidateNoShow
    case vehicleWithoutDriver
    case staffOvercapacity
    case staffDeficit
    case odometerMismatch
    case invalidQr

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vehicleBreakdown: "Vehículo averiado"
        case .lowBattery: "Batería baja"
        case .overdueMaintenance: "Mantenimiento vencido"
        case .driverAbsent: "Conductor ausente"
        case .driverLate: "Conductor retrasado"
        case .expiredDocument: "Documento vencido"
        case .lateCredit: "Crédito atrasado"
        case .duplicateClabe: "CLABE duplicada"
        case .rejectedTransfer: "Transferencia rechazada"
        case .overdueOrder: "Orden vencida"
        case .candidateNoShow: "Candidato que no se presenta"
        case .vehicleWithoutDriver: "Vehículo sin conductor"
        case .staffOvercapacity: "Sobrecupo de personal"
        case .staffDeficit: "Déficit de personal"
        case .odometerMismatch: "Error de kilometraje"
        case .invalidQr: "QR inválido"
        }
    }

    var symbol: String {
        switch self {
        case .vehicleBreakdown: "car.side.rear.and.collision.and.car.side.front"
        case .lowBattery: "battery.25percent"
        case .overdueMaintenance: "wrench.adjustable.fill"
        case .driverAbsent: "person.fill.xmark"
        case .driverLate: "clock.badge.exclamationmark.fill"
        case .expiredDocument: "doc.badge.clock.fill"
        case .lateCredit: "creditcard.trianglebadge.exclamationmark"
        case .duplicateClabe: "doc.on.doc.fill"
        case .rejectedTransfer: "arrow.uturn.backward.circle.fill"
        case .overdueOrder: "hourglass.bottomhalf.filled"
        case .candidateNoShow: "calendar.badge.minus"
        case .vehicleWithoutDriver: "steeringwheel.slash"
        case .staffOvercapacity: "person.3.sequence.fill"
        case .staffDeficit: "person.badge.minus"
        case .odometerMismatch: "gauge.with.needle.fill"
        case .invalidQr: "qrcode.viewfinder"
        }
    }

    /// Severity the operational board should raise when the fault is injected.
    var level: OpsAlertLevel {
        switch self {
        case .vehicleBreakdown, .duplicateClabe, .staffDeficit, .rejectedTransfer: .critical
        case .lowBattery, .overdueMaintenance, .driverAbsent, .expiredDocument,
             .lateCredit, .overdueOrder, .odometerMismatch, .vehicleWithoutDriver: .important
        case .driverLate, .candidateNoShow, .invalidQr, .staffOvercapacity: .preventive
        }
    }

    /// Who has to act on it, so the alert lands on the right desk.
    var audience: StaffRole {
        switch self {
        case .vehicleBreakdown, .lowBattery, .overdueMaintenance, .overdueOrder: .maintenance
        case .driverAbsent, .driverLate, .invalidQr, .odometerMismatch, .vehicleWithoutDriver: .supervisor
        case .expiredDocument, .staffOvercapacity: .supervisor
        case .candidateNoShow: .recruiter
        case .lateCredit, .duplicateClabe, .rejectedTransfer: .manager
        case .staffDeficit: .national
        }
    }

    /// What the target of the fault has to be, so the picker asks for the right thing.
    var target: LabFaultTarget {
        switch self {
        case .vehicleBreakdown, .lowBattery, .overdueMaintenance, .odometerMismatch,
             .invalidQr, .vehicleWithoutDriver: .vehicle
        case .driverAbsent, .driverLate, .expiredDocument, .lateCredit,
             .duplicateClabe, .rejectedTransfer: .driver
        case .overdueOrder: .order
        case .candidateNoShow: .candidate
        case .staffOvercapacity, .staffDeficit: .station
        }
    }

    var expectedResponse: String {
        switch self {
        case .vehicleBreakdown: "La unidad sale de la flotilla disponible, se abre orden crítica y el turno queda sin vehículo."
        case .lowBattery: "El inicio de turno se bloquea: la regla exige más del mínimo configurado."
        case .overdueMaintenance: "La unidad se marca no operable hasta cerrar el servicio programado."
        case .driverAbsent: "Se libera la unidad, baja la cobertura del bloque y sube el déficit del día."
        case .driverLate: "Se registran los minutos de atraso en la bitácora y se pone en riesgo el bono de puntualidad."
        case .expiredDocument: "El expediente pierde vigencia y el conductor deja de ser operativamente disponible."
        case .lateCredit: "El contrato pasa a atrasado y el descuento se acumula a la siguiente liquidación."
        case .duplicateClabe: "El alta se bloquea: una CLABE solo puede existir una vez en toda la red."
        case .rejectedTransfer: "La liquidación regresa a revisión y se conserva el movimiento rechazado."
        case .overdueOrder: "La orden supera su SLA, pesa en el índice de mantenimiento y escala al supervisor."
        case .candidateNoShow: "La cita se marca como inasistencia y el candidato se descarta con motivo."
        case .vehicleWithoutDriver: "La unidad queda ociosa y aparece como vacante inmediata en reclutamiento."
        case .staffOvercapacity: "La plantilla supera unidades × conductores por vehículo y se frena la contratación."
        case .staffDeficit: "La cobertura cae por debajo del umbral y dirección recibe alerta crítica."
        case .odometerMismatch: "Se comparan las tres lecturas y se levanta discrepancia para el supervisor."
        case .invalidQr: "El escaneo no corresponde a la estación y la asignación se rechaza."
        }
    }
}

nonisolated enum LabFaultTarget: String, Sendable {
    case vehicle
    case driver
    case order
    case candidate
    case station

    var label: String {
        switch self {
        case .vehicle: "Vehículo"
        case .driver: "Conductor"
        case .order: "Orden"
        case .candidate: "Candidato"
        case .station: "Estación"
        }
    }
}

nonisolated struct LabFault: Codable, Identifiable, Sendable {
    let id: String
    var kind: LabFaultKind
    var targetId: String?
    var targetLabel: String
    var triggeredAt: Date
    var isResolved: Bool
    var detail: String
}

nonisolated enum LabResult: String, Codable, CaseIterable, Identifiable, Sendable {
    case success
    case warning
    case failure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .success: "Correcto"
        case .warning: "Con aviso"
        case .failure: "Error"
        }
    }

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }
}

/// Immutable trace of everything the test administrator executes. It is stored apart from
/// the production audit and always carries the test origin.
nonisolated struct LabAuditEntry: Codable, Identifiable, Sendable {
    let id: String
    var action: String
    var section: LabSection
    var actor: String
    var detail: String
    var result: LabResult
    var errorMessage: String?
    var createdAt: Date

    var origin: String { "Entorno de pruebas" }
}

// MARK: - Simulated integrations

nonisolated struct LabUberFeed: Codable, Identifiable, Sendable {
    let id: String
    var driverId: String
    var driverName: String
    var vehicleId: String?
    var vehicleLabel: String
    var date: Date
    var trips: Int
    var earningsMxn: Int
    var tipsMxn: Int
    var onlineMinutes: Int
    var km: Int
    var receivedAt: Date

    var totalMxn: Int { earningsMxn + tipsMxn }
    var sourceLabel: String { "API simulada · Uber" }
}

nonisolated enum LabChargeState: String, Codable, CaseIterable, Identifiable, Sendable {
    case charging
    case idle
    case discharging
    case fault

    var id: String { rawValue }

    var label: String {
        switch self {
        case .charging: "Cargando"
        case .idle: "En reposo"
        case .discharging: "En ruta"
        case .fault: "Falla de carga"
        }
    }
}

nonisolated struct LabTelemetryReading: Codable, Identifiable, Sendable {
    let id: String
    var vehicleId: String
    var vehicleLabel: String
    var batteryPct: Int
    var odometerKm: Int
    var rangeKm: Int
    var latitude: Double
    var longitude: Double
    var chargeState: LabChargeState
    var stage: LabVehicleStage
    var receivedAt: Date

    var sourceLabel: String { "Telemetría simulada · BYD" }
    var coordinateLabel: String { String(format: "%.4f, %.4f", latitude, longitude) }
}

nonisolated enum LabTransferOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case success
    case rejected
    case invalidAccount
    case insufficientFunds
    case duplicate
    case connectionError

    var id: String { rawValue }

    var label: String {
        switch self {
        case .success: "Transferencia exitosa"
        case .rejected: "Transferencia rechazada"
        case .invalidAccount: "Cuenta inválida"
        case .insufficientFunds: "Saldo insuficiente"
        case .duplicate: "Transferencia duplicada"
        case .connectionError: "Error de conexión"
        }
    }

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .rejected: "xmark.octagon.fill"
        case .invalidAccount: "person.crop.circle.badge.xmark"
        case .insufficientFunds: "banknote"
        case .duplicate: "doc.on.doc.fill"
        case .connectionError: "wifi.exclamationmark"
        }
    }

    var isSuccess: Bool { self == .success }

    var appResponse: String {
        switch self {
        case .success: "La liquidación pasa a transferida y se cierra la semana."
        case .rejected: "La liquidación regresa a revisión con el motivo del banco."
        case .invalidAccount: "Se bloquea la cuenta y se pide solicitud de cambio de CLABE."
        case .insufficientFunds: "Se detiene la dispersión y se avisa a finanzas."
        case .duplicate: "Se descarta el segundo envío y se conserva la referencia original."
        case .connectionError: "Se reintenta más tarde; la liquidación no cambia de estado."
        }
    }

    var result: LabResult {
        switch self {
        case .success: .success
        case .duplicate, .connectionError: .warning
        case .rejected, .invalidAccount, .insufficientFunds: .failure
        }
    }
}

nonisolated struct LabTransfer: Codable, Identifiable, Sendable {
    let id: String
    var driverId: String
    var driverName: String
    var amountMxn: Int
    var bank: String
    var clabe: String
    var outcome: LabTransferOutcome
    var reference: String
    var createdAt: Date
}

nonisolated struct LabBankAccount: Codable, Identifiable, Sendable {
    let id: String
    var driverId: String
    var driverName: String
    var bank: String
    var clabe: String
    var accountNumber: String
    var holder: String
    var hasProof: Bool
    var status: BankAccountStatus
    var registeredAt: Date

    var maskedClabe: String { HRRules.mask(clabe: clabe) }
}

// MARK: - Scenarios

nonisolated struct LabScenario: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var detail: String
    var stations: Int
    var vehicles: Int
    var drivers: Int
    var supervisors: Int
    var maintenance: Int
    var recruiters: Int
    var candidates: Int
    var incomingVehicles: Int
    var incomingInDays: Int
    var isBuiltIn: Bool
    var createdAt: Date

    var requiredDrivers: Int { vehicles * LabRuntime.driversPerVehicle }
    var deficit: Int { max(0, requiredDrivers - drivers) }
    var coveragePct: Int {
        requiredDrivers > 0 ? Int((Double(drivers) / Double(requiredDrivers) * 100).rounded()) : 100
    }

    static let library: [LabScenario] = [
        LabScenario(
            id: "scn-new-station",
            name: "Estación nueva",
            detail: "Se acaba de instalar: hay flotilla y mandos, no hay un solo conductor.",
            stations: 1, vehicles: 10, drivers: 0, supervisors: 1, maintenance: 1,
            recruiters: 1, candidates: 0, incomingVehicles: 0, incomingInDays: 0,
            isBuiltIn: true, createdAt: .distantPast
        ),
        LabScenario(
            id: "scn-normal",
            name: "Operación normal",
            detail: "Cobertura completa: cuatro conductores por unidad y agenda sana.",
            stations: 1, vehicles: 20, drivers: 80, supervisors: 2, maintenance: 2,
            recruiters: 1, candidates: 12, incomingVehicles: 0, incomingInDays: 0,
            isBuiltIn: true, createdAt: .distantPast
        ),
        LabScenario(
            id: "scn-deficit",
            name: "Déficit crítico",
            detail: "Faltan 25 conductores: unidades paradas y bloques sin cubrir.",
            stations: 1, vehicles: 20, drivers: 55, supervisors: 2, maintenance: 1,
            recruiters: 1, candidates: 20, incomingVehicles: 0, incomingInDays: 0,
            isBuiltIn: true, createdAt: .distantPast
        ),
        LabScenario(
            id: "scn-expansion",
            name: "Expansión",
            detail: "Llegan 20 unidades en 15 días: 80 conductores más por contratar.",
            stations: 1, vehicles: 20, drivers: 80, supervisors: 2, maintenance: 2,
            recruiters: 2, candidates: 30, incomingVehicles: 20, incomingInDays: 15,
            isBuiltIn: true, createdAt: .distantPast
        ),
    ]
}

// MARK: - Capacity simulator

nonisolated struct LabCapacityInput: Sendable {
    var vehicles: Int
    var drivers: Int
    var incomingVehicles: Int
    var daysToArrival: Int
    var conversionRate: Double
    var averageHiringDays: Int
}

nonisolated struct LabCapacityResult: Sendable {
    let requiredDrivers: Int
    let deficit: Int
    let coveragePct: Int
    let futureVehicles: Int
    let futureRequired: Int
    let futureVacancies: Int
    let leadsNeeded: Int
    let startInDays: Int
    let level: OpsAlertLevel

    var isLate: Bool { startInDays < 0 }
}

// MARK: - Rules

nonisolated enum LabRules {
    static let adminAccountId = "acc-lab-001"
    static let adminEmail = "laboratorio@turnoev.mx"
    static let adminPassword = "Laboratorio14"

    /// The superadmin credential. It exists in both environments because it is the only
    /// door into the console; no other role can ever open it.
    static let adminAccount = StaffAccount(
        id: adminAccountId,
        name: "Administrador de Pruebas",
        employeeNumber: "EV-LAB-001",
        email: adminEmail,
        password: adminPassword,
        role: .lab,
        stationId: nil,
        regionId: nil,
        slot: nil,
        photoAsset: nil,
        status: .active,
        createdById: nil,
        authorizedById: nil,
        driverId: nil
    )

    static func capacity(_ input: LabCapacityInput) -> LabCapacityResult {
        let perVehicle = LabRuntime.driversPerVehicle
        let required = input.vehicles * perVehicle
        let deficit = max(0, required - input.drivers)
        let futureVehicles = input.vehicles + input.incomingVehicles
        let futureRequired = futureVehicles * perVehicle
        let futureVacancies = max(0, futureRequired - input.drivers)
        let conversion = max(0.01, input.conversionRate)
        let leads = Int((Double(futureVacancies) / conversion * (1 + Double(HRRules.safetyMarginPct) / 100)).rounded(.up))
        let startInDays = input.daysToArrival - input.averageHiringDays

        let level: OpsAlertLevel
        if futureVacancies == 0 {
            level = .informative
        } else if startInDays < 0 {
            level = .critical
        } else if startInDays < 7 {
            level = .important
        } else {
            level = .preventive
        }

        return LabCapacityResult(
            requiredDrivers: required,
            deficit: deficit,
            coveragePct: required > 0 ? Int((Double(input.drivers) / Double(required) * 100).rounded()) : 100,
            futureVehicles: futureVehicles,
            futureRequired: futureRequired,
            futureVacancies: futureVacancies,
            leadsNeeded: leads,
            startInDays: startInDays,
            level: level
        )
    }

    /// A CLABE can exist only once in the whole network; the laboratory honours the rule.
    static func isDuplicate(clabe: String, in accounts: [LabBankAccount], excluding id: String?) -> Bool {
        let cleaned = clabe.filter(\.isNumber)
        guard cleaned.count == 18 else { return false }
        return accounts.contains { $0.clabe.filter(\.isNumber) == cleaned && $0.id != id }
    }

    static func generateClabe(seed: Int) -> String {
        let base = 646180_000000000 + (seed * 977 % 999_999)
        return String(base).padding(toLength: 18, withPad: "0", startingAt: 0)
    }

    static func generateVin(seed: Int) -> String {
        let letters = Array("ABCDEFGHJKLMNPRSTUVWXYZ")
        let prefix = "LGX"
        let alphabetCount: Int = letters.count
        var body = ""
        for index in 0..<8 {
            let divided: Int = seed / (index + 1)
            let offset: Int = index * 7
            let position: Int = (divided + offset) % alphabetCount
            body.append(letters[position])
        }
        return prefix + body + String(format: "%06d", seed % 999_999)
    }

    static func generatePlates(seed: Int) -> String {
        let letters = Array("ABCDEFGHJKLMNPRSTUVWXYZ")
        let a = String(letters[seed % letters.count])
        let b = String(letters[(seed / 3) % letters.count])
        let c = String(letters[(seed / 7) % letters.count])
        return "\(a)\(b)\(c)-\(String(format: "%03d", seed % 999))-\(String(letters[(seed / 11) % letters.count]))"
    }
}
