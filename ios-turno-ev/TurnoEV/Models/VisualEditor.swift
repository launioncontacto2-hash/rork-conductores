import Foundation

/// Visual editor of the test laboratory. It lets the test administrator rearrange, resize,
/// rename, hide, delete, duplicate and re-visualize the elements of an existing interface
/// without touching code — and without ever touching data.
///
/// Two rules hold the whole module up:
/// 1. It only exists inside the TEST environment and only for the laboratory credential.
/// 2. It edits the presentation, never the source. Hiding a KPI does not stop its metric
///    from being computed, and deleting a card does not delete a record.

// MARK: - Screens

nonisolated enum EditorScreen: String, Codable, CaseIterable, Identifiable, Sendable {
    case driverShift
    case driverGoals
    case driverWallet
    case supervisorHome
    case managerHome

    var id: String { rawValue }

    var label: String {
        switch self {
        case .driverShift: "Conductor · Turno"
        case .driverGoals: "Conductor · Metas"
        case .driverWallet: "Conductor · Cartera"
        case .supervisorHome: "Supervisión · Tablero"
        case .managerHome: "Gerencia · Tablero"
        }
    }

    var role: StaffRole {
        switch self {
        case .driverShift, .driverGoals, .driverWallet: .driver
        case .supervisorHome: .supervisor
        case .managerHome: .manager
        }
    }

    var symbol: String {
        switch self {
        case .driverShift: "gauge.with.dots.needle.bottom.50percent"
        case .driverGoals: "target"
        case .driverWallet: "banknote.fill"
        case .supervisorHome: "dot.radiowaves.left.and.right"
        case .managerHome: "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Element vocabulary

nonisolated enum EditorElementKind: String, Codable, Sendable {
    case kpi
    case chart
    case card
    case notice
    case progress
    case list
    case button
    case text
    case separator

    var label: String {
        switch self {
        case .kpi: "Indicador"
        case .chart: "Gráfico"
        case .card: "Tarjeta"
        case .notice: "Aviso"
        case .progress: "Progreso"
        case .list: "Lista"
        case .button: "Botón"
        case .text: "Texto"
        case .separator: "Separador"
        }
    }

    var symbol: String {
        switch self {
        case .kpi: "number.square.fill"
        case .chart: "chart.bar.fill"
        case .card: "rectangle.portrait.fill"
        case .notice: "exclamationmark.bubble.fill"
        case .progress: "chart.bar.horizontal.page.fill"
        case .list: "list.bullet.rectangle.fill"
        case .button: "capsule.fill"
        case .text: "textformat"
        case .separator: "minus"
        }
    }
}

/// Grid width. The canvas is four columns wide, so nothing can be dropped in a position
/// that breaks the responsive layout.
nonisolated enum EditorWidth: String, Codable, CaseIterable, Identifiable, Sendable {
    case quarter
    case half
    case threeQuarters
    case full

    var id: String { rawValue }

    var columns: Int {
        switch self {
        case .quarter: 1
        case .half: 2
        case .threeQuarters: 3
        case .full: 4
        }
    }

    var label: String {
        switch self {
        case .quarter: "25 %"
        case .half: "50 %"
        case .threeQuarters: "75 %"
        case .full: "100 %"
        }
    }

    var shortLabel: String {
        switch self {
        case .quarter: "Pequeño"
        case .half: "Mediano"
        case .threeQuarters: "Grande"
        case .full: "Ancho completo"
        }
    }
}

nonisolated enum EditorHeight: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case compact
    case normal
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automático"
        case .compact: "Compacto"
        case .normal: "Normal"
        case .large: "Grande"
        }
    }

    var minimum: Double? {
        switch self {
        case .automatic: nil
        case .compact: 68
        case .normal: 110
        case .large: 180
        }
    }
}

/// Vertical air between blocks. Kept on a scale so no arbitrary value can break rhythm.
nonisolated enum EditorSpacing: String, Codable, CaseIterable, Identifiable, Sendable {
    case tight
    case normal
    case loose

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tight: "Compacto"
        case .normal: "Normal"
        case .loose: "Amplio"
        }
    }

    var value: Double {
        switch self {
        case .tight: 8
        case .normal: 16
        case .loose: 26
        }
    }
}

// MARK: - Card library

nonisolated enum EditorCardModel: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case bigNumber
    case horizontal
    case progress
    case icon
    case minimal
    case featured
    case alert

    var id: String { rawValue }

    var letter: String {
        switch self {
        case .compact: "A"
        case .bigNumber: "B"
        case .horizontal: "C"
        case .progress: "D"
        case .icon: "E"
        case .minimal: "F"
        case .featured: "G"
        case .alert: "H"
        }
    }

    var label: String {
        switch self {
        case .compact: "Tarjeta compacta"
        case .bigNumber: "Indicador grande"
        case .horizontal: "Tarjeta horizontal"
        case .progress: "Con barra de progreso"
        case .icon: "Con icono principal"
        case .minimal: "Minimalista"
        case .featured: "Destacada"
        case .alert: "Tarjeta de alerta"
        }
    }
}

// MARK: - Chart library

nonisolated enum EditorChartKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case verticalBars
    case horizontalBars
    case line
    case area
    case donut
    case pie
    case radialProgress
    case progressBar
    case kpiCards
    case number

    var id: String { rawValue }

    var label: String {
        switch self {
        case .verticalBars: "Barras verticales"
        case .horizontalBars: "Barras horizontales"
        case .line: "Línea"
        case .area: "Área"
        case .donut: "Dona"
        case .pie: "Circular"
        case .radialProgress: "Progreso circular"
        case .progressBar: "Barra de progreso"
        case .kpiCards: "Tarjetas KPI"
        case .number: "Indicador numérico"
        }
    }

    var symbol: String {
        switch self {
        case .verticalBars: "chart.bar.fill"
        case .horizontalBars: "chart.bar.xaxis"
        case .line: "chart.xyaxis.line"
        case .area: "waveform.path.ecg.rectangle"
        case .donut: "chart.pie"
        case .pie: "chart.pie.fill"
        case .radialProgress: "circle.dashed.inset.filled"
        case .progressBar: "progress.indicator"
        case .kpiCards: "square.grid.2x2.fill"
        case .number: "number"
        }
    }

    /// Which shapes make sense for a data set. A series with one value cannot be a line,
    /// and a set whose parts do not add up to a whole cannot be a pie.
    static func available(for series: EditorSeries) -> [EditorChartKind] {
        var kinds: [EditorChartKind] = [.verticalBars, .horizontalBars, .kpiCards, .number]
        if series.points.count >= 3 {
            kinds.insert(contentsOf: [.line, .area], at: 2)
        }
        if series.isComposition, series.points.count >= 2, series.points.count <= 8 {
            kinds.append(contentsOf: [.donut, .pie])
        }
        if series.totalGoal != nil {
            kinds.append(contentsOf: [.radialProgress, .progressBar])
        }
        return kinds
    }
}

/// One point of a data series exposed to the editor. The editor can change how it looks,
/// never what it says.
nonisolated struct EditorPoint: Identifiable, Sendable {
    let id: String
    let label: String
    let value: Double
    var isHighlighted: Bool = false

    init(_ label: String, _ value: Double, isHighlighted: Bool = false) {
        self.id = label
        self.label = label
        self.value = value
        self.isHighlighted = isHighlighted
    }
}

nonisolated struct EditorSeries: Sendable {
    var points: [EditorPoint]
    /// Reference for a single point, so the bars are drawn against the daily target.
    var goal: Double?
    /// Target for the whole series. It is what the progress shapes measure against, and
    /// its absence is what keeps them out of the library for a set with no target.
    var totalGoal: Double?
    /// True when the parts add up to a whole, which unlocks pie and donut.
    var isComposition: Bool = false
    var unit: EditorUnit = .money

    var total: Double { points.reduce(0) { $0 + $1.value } }
    var peak: Double { max(points.map(\.value).max() ?? 0, goal ?? 0) }

    func formatted(_ value: Double) -> String { unit.format(value) }
}

nonisolated enum EditorUnit: String, Codable, Sendable {
    case money
    case count
    case percent
    case distance

    func format(_ value: Double) -> String {
        switch self {
        case .money: Fmt.mxn(Int(value.rounded()))
        case .count: "\(Int(value.rounded()))"
        case .percent: "\(Int(value.rounded()))%"
        case .distance: Fmt.km(Int(value.rounded()))
        }
    }
}

// MARK: - Controlled data sources

/// The only metrics an element can be pointed at. There are no arbitrary queries: the
/// editor picks from this list or it picks nothing.
nonisolated enum EditorMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case activeVehicles
    case availableVehicles
    case maintenanceVehicles
    case activeDrivers
    case vacancies
    case openAlerts
    case earningsToday
    case earningsWeek
    case coveragePct
    case tripsToday
    case kmToday
    case batteryStart
    case batteryEnd
    case lateMinutes
    case bonusPayable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .activeVehicles: "Vehículos activos"
        case .availableVehicles: "Vehículos disponibles"
        case .maintenanceVehicles: "Vehículos en mantenimiento"
        case .activeDrivers: "Conductores activos"
        case .vacancies: "Vacantes"
        case .openAlerts: "Alertas"
        case .earningsToday: "Ingresos de hoy"
        case .earningsWeek: "Ingresos de la semana"
        case .coveragePct: "Cobertura"
        case .tripsToday: "Viajes de hoy"
        case .kmToday: "Kilómetros de hoy"
        case .batteryStart: "Batería de inicio"
        case .batteryEnd: "Batería de entrega"
        case .lateMinutes: "Minutos de atraso"
        case .bonusPayable: "Bonos por cobrar"
        }
    }

    var unit: EditorUnit {
        switch self {
        case .earningsToday, .earningsWeek, .bonusPayable: .money
        case .coveragePct, .batteryStart, .batteryEnd: .percent
        case .kmToday: .distance
        default: .count
        }
    }

    var symbol: String {
        switch self {
        case .activeVehicles, .availableVehicles, .maintenanceVehicles: "car.side.fill"
        case .activeDrivers, .vacancies: "person.fill"
        case .openAlerts: "bell.badge.fill"
        case .earningsToday, .earningsWeek, .bonusPayable: "banknote.fill"
        case .coveragePct: "chart.pie.fill"
        case .tripsToday: "flag.checkered"
        case .kmToday: "point.topleft.down.to.point.bottomright.curvepath"
        case .batteryStart, .batteryEnd: "bolt.fill"
        case .lateMinutes: "clock.badge.exclamationmark.fill"
        }
    }

    /// Metrics the driver interfaces are allowed to show, so the picker never offers a
    /// number that role cannot legitimately see.
    static let driverScope: [EditorMetric] = [
        .earningsToday, .earningsWeek, .tripsToday, .kmToday,
        .batteryStart, .batteryEnd, .lateMinutes, .bonusPayable,
    ]

    static let stationScope: [EditorMetric] = allCases

    static func scope(for screen: EditorScreen) -> [EditorMetric] {
        screen.role == .driver ? driverScope : stationScope
    }
}

// MARK: - Overrides

/// Everything the editor can say about one element. Every field is optional on purpose:
/// what is not written here keeps the value the screen was born with.
nonisolated struct EditorOverride: Codable, Sendable, Equatable {
    var order: Int?
    var width: EditorWidth?
    var height: EditorHeight?
    var spacing: EditorSpacing?
    var isHidden: Bool = false
    var isDeleted: Bool = false
    var cardModel: EditorCardModel?
    var chartKind: EditorChartKind?
    var metric: EditorMetric?
    var title: String?
    var subtitle: String?
    var showsValues: Bool?
    var showsLegend: Bool?
    var showsLabels: Bool?

    var isPristine: Bool { self == EditorOverride() }

    /// Human sentence for the change log.
    var summary: String {
        var parts: [String] = []
        if isDeleted { parts.append("eliminado del diseño") }
        if isHidden { parts.append("oculto") }
        if let width { parts.append("ancho \(width.label)") }
        if let height { parts.append("alto \(height.label.lowercased())") }
        if let cardModel { parts.append("modelo \(cardModel.letter)") }
        if let chartKind { parts.append(chartKind.label.lowercased()) }
        if let metric { parts.append("dato \(metric.label.lowercased())") }
        if title != nil { parts.append("título editado") }
        if subtitle != nil { parts.append("texto editado") }
        return parts.isEmpty ? "sin cambios" : parts.joined(separator: ", ")
    }
}

/// An element the editor added: a duplicate of an existing one or a component dragged in
/// from the library. It always points at a metric of the controlled list.
nonisolated struct EditorAddedElement: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var sourceId: String?
    var kind: EditorElementKind
    var title: String
    var metric: EditorMetric
    var cardModel: EditorCardModel
    var width: EditorWidth
    var order: Int
    var createdAt: Date
}

/// The design of one screen.
nonisolated struct EditorLayout: Codable, Sendable, Equatable {
    var overrides: [String: EditorOverride] = [:]
    var added: [EditorAddedElement] = []

    var isPristine: Bool { added.isEmpty && overrides.values.allSatisfy(\.isPristine) }

    var hiddenIds: [String] { overrides.filter { $0.value.isHidden }.map(\.key).sorted() }
    var deletedIds: [String] { overrides.filter { $0.value.isDeleted }.map(\.key).sorted() }

    var changeCount: Int {
        overrides.values.filter { !$0.isPristine }.count + added.count
    }
}

// MARK: - Message library

/// A text the system shows, with its key and its dynamic variables. The editor rewrites
/// the sentence; the logic that fires it is never touched.
nonisolated struct EditorMessage: Codable, Identifiable, Sendable {
    let key: String
    var text: String
    let defaultText: String
    let group: String
    let variables: [String]
    let usage: String

    var id: String { key }

    var isEdited: Bool { text != defaultText }

    /// Renders the sentence with sample values so the administrator sees the real shape.
    func preview(samples: [String: String]) -> String {
        variables.reduce(text) { partial, variable in
            partial.replacingOccurrences(of: "{\(variable)}", with: samples[variable] ?? "—")
        }
    }

    /// Variables the administrator removed by accident. They must never be turned into
    /// fixed text, so the editor warns instead of saving silently.
    var droppedVariables: [String] {
        variables.filter { !text.contains("{\($0)}") }
    }
}

nonisolated enum EditorMessageCatalog {
    static let samples: [String: String] = [
        "missingDrivers": "2",
        "shiftName": "Matutino L-V",
        "amount": "$1,520",
        "driver": "Carlos",
        "unit": "TEV-014",
        "minutes": "12",
        "date": "mié 19 ago",
        "count": "3",
    ]

    /// Sentences of the system that the laboratory is allowed to rewrite.
    static let defaults: [EditorMessage] = [
        EditorMessage(
            key: "goal_missing_today",
            text: "Faltan {amount} para la meta del día",
            defaultText: "Faltan {amount} para la meta del día",
            group: "Metas",
            variables: ["amount"],
            usage: "Bajo el anillo de la meta diaria, cuando el conductor aún no la alcanza."
        ),
        EditorMessage(
            key: "goal_reached_today",
            text: "Meta del día cumplida",
            defaultText: "Meta del día cumplida",
            group: "Metas",
            variables: [],
            usage: "Sustituye al aviso anterior en cuanto la meta se cubre."
        ),
        EditorMessage(
            key: "shift_missing_driver",
            text: "Faltan {missingDrivers} conductores para cubrir {shiftName}.",
            defaultText: "Faltan {missingDrivers} conductores para cubrir {shiftName}.",
            group: "Cobertura",
            variables: ["missingDrivers", "shiftName"],
            usage: "Resumen de cobertura del supervisor y digest de Recursos Humanos."
        ),
        EditorMessage(
            key: "shift_late_warning",
            text: "{driver}, tienes un atraso de {minutes} minutos.",
            defaultText: "{driver}, tienes un atraso de {minutes} minutos.",
            group: "Turno",
            variables: ["driver", "minutes"],
            usage: "Aviso ámbar en la pantalla de turno mientras hay tiempo adeudado."
        ),
        EditorMessage(
            key: "shift_workday_closed",
            text: "Tu jornada ya cerró",
            defaultText: "Tu jornada ya cerró",
            group: "Turno",
            variables: [],
            usage: "Bloqueo rojo cuando el bloque terminó y el turno sigue abierto."
        ),
        EditorMessage(
            key: "cash_not_authorized",
            text: "El cobro en efectivo no está autorizado.",
            defaultText: "El cobro en efectivo no está autorizado.",
            group: "Ingresos",
            variables: [],
            usage: "Encabezado del registro de ingresos en efectivo."
        ),
        EditorMessage(
            key: "cash_deposit_deadline",
            text: "Fecha límite {date} · 23:59:59, cotejada con el registro de la plataforma.",
            defaultText: "Fecha límite {date} · 23:59:59, cotejada con el registro de la plataforma.",
            group: "Ingresos",
            variables: ["date"],
            usage: "Reloj del cobro en efectivo pendiente de depositar."
        ),
        EditorMessage(
            key: "empty_no_cash",
            text: "Sin efectivo pendiente",
            defaultText: "Sin efectivo pendiente",
            group: "Estados vacíos",
            variables: [],
            usage: "Cuando la plataforma no reporta cobros en efectivo."
        ),
        EditorMessage(
            key: "empty_no_incidents",
            text: "Sin incidencias registradas.",
            defaultText: "Sin incidencias registradas.",
            group: "Estados vacíos",
            variables: [],
            usage: "Historial de incidencias del conductor."
        ),
        EditorMessage(
            key: "documents_missing",
            text: "Faltan {count} documentos por cargar",
            defaultText: "Faltan {count} documentos por cargar",
            group: "Documentos",
            variables: ["count"],
            usage: "Visor de documentación de la unidad."
        ),
        EditorMessage(
            key: "error_amount_mismatch",
            text: "El monto capturado no coincide con el comprobante. Corrígelo antes de guardar.",
            defaultText: "El monto capturado no coincide con el comprobante. Corrígelo antes de guardar.",
            group: "Errores",
            variables: [],
            usage: "Validación del comprobante de depósito."
        ),
        EditorMessage(
            key: "confirm_delete_element",
            text: "¿Deseas eliminar este elemento de esta interfaz?",
            defaultText: "¿Deseas eliminar este elemento de esta interfaz?",
            group: "Confirmaciones",
            variables: [],
            usage: "Confirmación del propio editor visual."
        ),
    ]

    static var groups: [String] {
        var seen: Set<String> = []
        return defaults.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
    }
}

// MARK: - Versions, history and audit

nonisolated struct EditorVersion: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    let screen: EditorScreen
    let layout: EditorLayout
    let createdAt: Date
    let author: String

    var changeCount: Int { layout.changeCount }
}

nonisolated struct EditorAuditEntry: Codable, Identifiable, Sendable {
    let id: String
    let screen: EditorScreen
    let elementId: String
    let elementTitle: String
    let change: String
    let previousValue: String
    let newValue: String
    let author: String
    let createdAt: Date

    var origin: String { "Editor visual · entorno de pruebas" }
}

/// One step of the session history, used by undo and redo.
nonisolated struct EditorStep: Identifiable, Sendable {
    let id: String
    let screen: EditorScreen
    let summary: String
    let before: EditorLayout
    let after: EditorLayout
    let createdAt: Date
}

// MARK: - Devices

nonisolated enum EditorDevice: String, Codable, CaseIterable, Identifiable, Sendable {
    case phoneSmall
    case phoneLarge
    case android
    case tablet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .phoneSmall: "iPhone pequeño"
        case .phoneLarge: "iPhone grande"
        case .android: "Android"
        case .tablet: "Tablet"
        }
    }

    var width: Double {
        switch self {
        case .phoneSmall: 320
        case .phoneLarge: 393
        case .android: 412
        case .tablet: 744
        }
    }

    var symbol: String {
        switch self {
        case .phoneSmall, .phoneLarge: "iphone"
        case .android: "candybarphone"
        case .tablet: "ipad"
        }
    }
}

// MARK: - Rules

nonisolated enum EditorRules {
    /// The editor is a laboratory tool. Two conditions, and both have to hold:
    ///
    /// 1. The person behind the session signed in with the laboratory credential. That is
    ///    remembered apart from the active session, because reviewing the interface of a
    ///    driver or a supervisor opens a session with *their* credential — the human is
    ///    still the same administrator, and locking him out at exactly the moment he
    ///    reaches the screen he wants to edit was the bug.
    /// 2. The test environment is live. Production is never editable from a device.
    static func canOpen(isUnlocked: Bool, mode: LabMode) -> Bool {
        isUnlocked && mode == .test
    }

    /// Credential that unlocks the editor for the rest of the session.
    static func unlocks(account: StaffAccount?) -> Bool {
        account?.role == .lab
    }

    /// Interfaces that carry the floating access, and the screen each one edits.
    static func screen(forRole role: StaffRole?) -> EditorScreen? {
        switch role {
        case .driver: .driverShift
        case .supervisor: .supervisorHome
        case .manager: .managerHome
        default: nil
        }
    }

    /// Publishing to production is deliberately inert while the product is in development.
    static let isPublishingEnabled = false

    static let publishNotice = "Publicar está desactivado mientras la aplicación está en desarrollo. Todo lo que edites vive en el entorno de pruebas."
}
