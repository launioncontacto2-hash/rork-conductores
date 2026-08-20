import Foundation

/// Maintenance domain. The workshop of a station is responsible for every asset, not
/// only the vehicles: chargers, the electrical installation, solar panels, inverters,
/// the warehouse, tools, computers, network and surveillance.

// MARK: - Assets

nonisolated enum AssetCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case vehicles
    case chargers
    case electrical
    case solar
    case inverters
    case warehouse
    case facilities
    case tools
    case computers
    case network
    case surveillance
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vehicles: "Vehículos"
        case .chargers: "Cargadores"
        case .electrical: "Instalación eléctrica"
        case .solar: "Paneles solares"
        case .inverters: "Inversores"
        case .warehouse: "Bodega"
        case .facilities: "Instalaciones"
        case .tools: "Herramientas"
        case .computers: "Equipos informáticos"
        case .network: "Red"
        case .surveillance: "Videovigilancia"
        case .other: "Otros activos"
        }
    }

    var symbol: String {
        switch self {
        case .vehicles: "car.2.fill"
        case .chargers: "ev.charger.fill"
        case .electrical: "bolt.fill"
        case .solar: "sun.max.fill"
        case .inverters: "powerplug.fill"
        case .warehouse: "shippingbox.fill"
        case .facilities: "building.2.fill"
        case .tools: "wrench.and.screwdriver.fill"
        case .computers: "desktopcomputer"
        case .network: "wifi.router.fill"
        case .surveillance: "video.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}

nonisolated struct StationAsset: Codable, Identifiable, Sendable {
    nonisolated enum State: String, Codable, CaseIterable, Identifiable, Sendable {
        case operational
        case degraded
        case down

        var id: String { rawValue }

        var label: String {
            switch self {
            case .operational: "Operativo"
            case .degraded: "Con falla parcial"
            case .down: "Fuera de servicio"
            }
        }

        var symbol: String {
            switch self {
            case .operational: "checkmark.circle.fill"
            case .degraded: "exclamationmark.triangle.fill"
            case .down: "xmark.octagon.fill"
            }
        }
    }

    let id: String
    let stationId: String
    let category: AssetCategory
    var name: String
    var code: String
    var state: State
    var lastServiceAt: Date
    var note: String
    /// Present when the asset is a unit of the fleet.
    var vehicleId: String?
}

// MARK: - Work orders

nonisolated enum WorkOrderPriority: String, Codable, CaseIterable, Identifiable, Sendable {
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

    var weight: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }

    /// Hours the station gives itself to close an order of this priority.
    var slaHours: Int {
        switch self {
        case .low: 72
        case .medium: 48
        case .high: 12
        case .critical: 4
        }
    }
}

nonisolated enum WorkOrderStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case inProgress
    case waiting
    case finished
    case returned
    case closed
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: "Pendiente"
        case .inProgress: "En proceso"
        case .waiting: "En espera"
        case .finished: "Finalizada"
        case .returned: "Devuelta"
        case .closed: "Cerrada"
        case .cancelled: "Cancelada"
        }
    }

    var symbol: String {
        switch self {
        case .pending: "tray.fill"
        case .inProgress: "wrench.and.screwdriver.fill"
        case .waiting: "pause.circle.fill"
        case .finished: "paperplane.fill"
        case .returned: "arrow.uturn.left.circle.fill"
        case .closed: "checkmark.seal.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    /// Still on the technician's board.
    var isOpen: Bool {
        switch self {
        case .pending, .inProgress, .waiting, .returned: true
        case .finished, .closed, .cancelled: false
        }
    }

    /// Waiting for the supervisor's signature.
    var awaitsValidation: Bool { self == .finished }
}

nonisolated struct WorkOrderMaterial: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var quantity: Int
}

nonisolated struct WorkOrder: Codable, Identifiable, Sendable {
    let id: String
    let folio: String
    let stationId: String
    var assetId: String
    var assetName: String
    var assetCode: String
    var category: AssetCategory
    var problem: String
    var priority: WorkOrderPriority
    var isPreventive: Bool
    let assignedAt: Date
    var assignedByName: String
    var technicianId: String
    var technicianName: String
    var acceptedAt: Date?
    var finishedAt: Date?
    var closedAt: Date?
    var estimatedMinutes: Int
    var status: WorkOrderStatus
    var workDone: String
    var pendingWork: String
    var observations: String
    var materials: [WorkOrderMaterial]
    /// Real captures sent from the technician's phone.
    var evidence: [Data]
    /// Stand-in imagery for the simulated history.
    var evidenceAssets: [String]
    var returnReason: String?
    /// Fleet unit released by this order, if any.
    var vehicleId: String?

    /// Minutes really spent, measured from acceptance to the report.
    var actualMinutes: Int? {
        guard let acceptedAt, let finishedAt else { return nil }
        return max(1, Int(finishedAt.timeIntervalSince(acceptedAt) / 60))
    }

    var dueAt: Date {
        assignedAt.addingTimeInterval(TimeInterval(priority.slaHours * 3_600))
    }

    func isOverdue(now: Date) -> Bool {
        status.isOpen && now > dueAt
    }

    var wasOnTime: Bool {
        guard let finishedAt else { return false }
        return finishedAt <= dueAt
    }

    var hasEvidence: Bool { !evidence.isEmpty || !evidenceAssets.isEmpty }

    /// A report can only be sent with work done and at least one piece of evidence.
    var canSubmitReport: Bool {
        !workDone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasEvidence
    }
}

// MARK: - Metrics and bonus

nonisolated struct WorkshopMetrics: Sendable {
    let pending: Int
    let inProgress: Int
    let waiting: Int
    let awaitingValidation: Int
    let returned: Int
    let closed: Int
    let criticalHandled: Int
    let preventiveDone: Int
    let preventiveProgrammed: Int
    let averageResolutionMinutes: Int
    let recoveredVehicles: Int
    let fleetAvailable: Int
    let fleetTotal: Int
    let onTimeClosed: Int

    var openTotal: Int { pending + inProgress + waiting + returned }
    var fleetAvailabilityRatio: Double { fleetTotal > 0 ? Double(fleetAvailable) / Double(fleetTotal) : 0 }
    var preventiveRatio: Double { preventiveProgrammed > 0 ? Double(preventiveDone) / Double(preventiveProgrammed) : 1 }
    var approvalRatio: Double {
        let reviewed = closed + returned
        return reviewed > 0 ? Double(closed) / Double(reviewed) : 1
    }
    var punctualityRatio: Double { closed > 0 ? Double(onTimeClosed) / Double(closed) : 1 }
}

/// The workshop bonus is an index, not a task counter.
nonisolated struct MaintenanceBonusIndex: Sendable {
    nonisolated struct Factor: Identifiable, Sendable {
        let id: String
        let label: String
        let detail: String
        let weightPct: Int
        /// 0–1 performance of this factor.
        let ratio: Double

        var contribution: Double { Double(weightPct) * ratio }
        var scorePct: Int { Int((ratio * 100).rounded()) }
    }

    let factors: [Factor]
    let goalPct: Int
    let potentialMxn: Int

    var scorePct: Int { Int(factors.reduce(0) { $0 + $1.contribution }.rounded()) }
    var isEarned: Bool { scorePct >= goalPct }
    var earnedMxn: Int { isEarned ? potentialMxn : 0 }
    /// Factors dragging the index down, ordered by how much they cost.
    var weakest: [Factor] {
        factors
            .filter { $0.ratio < 0.9 }
            .sorted { (Double($0.weightPct) * (1 - $0.ratio)) > (Double($1.weightPct) * (1 - $1.ratio)) }
    }
}

nonisolated enum WorkshopRules {
    static let bonusMxn = 1_800
    static let goalPct = 85
    /// Average resolution time that scores full marks.
    static let targetResolutionMinutes = 120

    static func bonus(metrics: WorkshopMetrics) -> MaintenanceBonusIndex {
        let resolutionRatio: Double = {
            guard metrics.averageResolutionMinutes > 0 else { return 1 }
            return min(1, Double(targetResolutionMinutes) / Double(metrics.averageResolutionMinutes))
        }()
        let volumeRatio: Double = {
            let total = metrics.closed + metrics.openTotal + metrics.awaitingValidation
            guard total > 0 else { return 1 }
            return min(1, Double(metrics.closed) / Double(total))
        }()

        let factors: [MaintenanceBonusIndex.Factor] = [
            .init(
                id: "availability",
                label: "Disponibilidad de flotilla",
                detail: "\(metrics.fleetAvailable) de \(metrics.fleetTotal) unidades listas",
                weightPct: 40,
                ratio: min(1, metrics.fleetAvailabilityRatio)
            ),
            .init(
                id: "preventive",
                label: "Preventivos a tiempo",
                detail: "\(metrics.preventiveDone) de \(metrics.preventiveProgrammed) programados",
                weightPct: 25,
                ratio: min(1, metrics.preventiveRatio)
            ),
            .init(
                id: "resolution",
                label: "Tiempo promedio de reparación",
                detail: "\(Fmt.durationText(metrics.averageResolutionMinutes)) contra meta de \(Fmt.durationText(targetResolutionMinutes))",
                weightPct: 20,
                ratio: resolutionRatio
            ),
            .init(
                id: "volume",
                label: "Órdenes completadas",
                detail: "\(metrics.closed) cerradas · \(metrics.openTotal) abiertas",
                weightPct: 10,
                ratio: volumeRatio
            ),
            .init(
                id: "quality",
                label: "Calidad: órdenes aprobadas",
                detail: metrics.returned > 0 ? "\(metrics.returned) devueltas por supervisión" : "Sin devoluciones",
                weightPct: 5,
                ratio: min(1, metrics.approvalRatio)
            ),
        ]

        return MaintenanceBonusIndex(factors: factors, goalPct: goalPct, potentialMxn: bonusMxn)
    }
}

// MARK: - Audit

nonisolated enum AuditAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case candidateCreated
    case interviewSigned
    case documentUpdated
    case hire
    case termination
    case shiftChange
    case bankRegistered
    case bankChangeRequested
    case bankChangeResolved
    case approval
    case rejection
    case workOrderAssigned
    case workOrderResolved
    case settlement
    case permissionChange

    var id: String { rawValue }

    var label: String {
        switch self {
        case .candidateCreated: "Alta de candidato"
        case .interviewSigned: "Entrevista firmada"
        case .documentUpdated: "Modificación de documento"
        case .hire: "Contratación"
        case .termination: "Baja"
        case .shiftChange: "Cambio de turno"
        case .bankRegistered: "Alta bancaria"
        case .bankChangeRequested: "Solicitud de cambio bancario"
        case .bankChangeResolved: "Resolución bancaria"
        case .approval: "Aprobación"
        case .rejection: "Rechazo"
        case .workOrderAssigned: "Orden de mantenimiento"
        case .workOrderResolved: "Cierre de orden"
        case .settlement: "Liquidación"
        case .permissionChange: "Cambio de permisos"
        }
    }

    var symbol: String {
        switch self {
        case .candidateCreated: "person.crop.circle.badge.plus"
        case .interviewSigned: "text.bubble.fill"
        case .documentUpdated: "doc.badge.arrow.up"
        case .hire: "person.badge.plus"
        case .termination: "person.badge.minus"
        case .shiftChange: "arrow.left.arrow.right"
        case .bankRegistered, .bankChangeRequested, .bankChangeResolved: "building.columns.fill"
        case .approval: "checkmark.seal.fill"
        case .rejection: "xmark.octagon.fill"
        case .workOrderAssigned, .workOrderResolved: "wrench.and.screwdriver.fill"
        case .settlement: "banknote.fill"
        case .permissionChange: "lock.rotation"
        }
    }
}

/// Immutable trace of every sensitive action. Supervisors can read it, never edit it.
nonisolated struct AuditEntry: Codable, Identifiable, Sendable {
    let id: String
    let action: AuditAction
    let actorName: String
    let actorRole: StaffRole
    let stationId: String
    let createdAt: Date
    let subject: String
    let previousValue: String?
    let newValue: String?
    let reason: String?
    let authorizerName: String?
}
