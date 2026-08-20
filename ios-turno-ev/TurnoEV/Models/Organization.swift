import Foundation

/// Organizational model of the network: stations, roles and the staff directory that
/// authenticates every access.
///
/// The station is the operating unit of the whole company. Each one concentrates up to
/// 100 units, 4 shifts of drivers, 2 supervisors (morning / evening), maintenance staff,
/// **its own manager** and **its own recruitment desk**. A manager runs one station and
/// only one; recruitment is a department inside the station, not a shared service.
/// Regions exist only to group stations for national direction's reporting.

nonisolated struct Station: Codable, Identifiable, Hashable, Sendable {
    let id: String
    /// Short code printed on the station board and on every unit sticker.
    let code: String
    let name: String
    let city: String
    let regionId: String
    /// Units really installed in the station today. It is data, never a constant: the
    /// design ceiling lives in `HRRules.maxVehiclesPerStation`.
    let vehicleCapacity: Int

    /// Display name used across the operational screens.
    var displayName: String { "\(name) · \(city)" }

    /// Drivers the station needs to cover its four blocks with the installed fleet.
    var requiredDrivers: Int { HRRules.requiredDrivers(activeVehicles: vehicleCapacity) }
}

nonisolated struct Region: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let stationIds: [String]
}

nonisolated enum StaffRole: String, Codable, CaseIterable, Sendable {
    case driver
    case supervisor
    case manager
    case maintenance
    case recruiter
    case national
    /// Test administrator / superadmin. Opens the laboratory console and nothing else.
    case lab

    var label: String {
        switch self {
        case .driver: "Conductor"
        case .supervisor: "Supervisor de estación"
        case .manager: "Gerente de estación"
        case .maintenance: "Mantenimiento"
        case .recruiter: "Reclutamiento de estación"
        case .national: "Dirección nacional"
        case .lab: "Administrador de Pruebas"
        }
    }

    /// Roles whose entire work happens inside one station. Everything they read, decide
    /// and create is bounded by `StaffAccount.stationId`.
    var isStationBound: Bool {
        switch self {
        case .driver, .supervisor, .maintenance, .manager, .recruiter: true
        case .national, .lab: false
        }
    }

    /// Roles that operate the real network. The laboratory is not one of them.
    static var operationalRoles: [StaffRole] {
        allCases.filter { $0 != .lab }
    }

    var shortLabel: String {
        switch self {
        case .driver: "Conductor"
        case .supervisor: "Supervisión"
        case .manager: "Gerencia"
        case .maintenance: "Taller"
        case .recruiter: "Reclutamiento"
        case .national: "Dirección"
        case .lab: "Laboratorio"
        }
    }

    var symbol: String {
        switch self {
        case .driver: "steeringwheel"
        case .supervisor: "person.2.badge.gearshape.fill"
        case .manager: "chart.bar.xaxis"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .recruiter: "person.crop.circle.badge.plus"
        case .national: "building.2.fill"
        case .lab: "testtube.2"
        }
    }

    /// Operational reach of the role, shown right after the role is identified.
    var scopeLabel: String {
        switch self {
        case .driver, .supervisor, .maintenance, .manager: "Una estación"
        case .recruiter: "Reclutamiento de su estación"
        case .national: "Red nacional"
        case .lab: "Entorno de pruebas"
        }
    }

    var workspaceTitle: String {
        switch self {
        case .driver: "Panel de turno"
        case .supervisor: "Control de estación"
        case .manager: "Gerencia de estación"
        case .maintenance: "Taller y flotilla"
        case .recruiter: "Reclutamiento de estación"
        case .national: "Dirección nacional"
        case .lab: "Laboratorio de pruebas"
        }
    }

    /// What the role is able to do; used for the workspace summary and future gating.
    var capabilities: [String] {
        switch self {
        case .driver:
            [
                "Iniciar y cerrar su turno con evidencia fotográfica",
                "Registrar ingresos, viajes e incidencias",
                "Consultar metas, bonos y su crédito",
            ]
        case .supervisor:
            [
                "Asignar unidades y validar inicios y cierres de turno",
                "Recibir, revisar y liberar vehículos en cada entrega",
                "Levantar reportes de limpieza, daños y puntualidad",
                "Sostener la cobertura de sus cuatro bloques",
            ]
        case .manager:
            [
                "Responder por la meta, la flotilla y la plantilla de su estación",
                "Definir cuántas plazas puede contratar su estación",
                "Validar bonos, créditos y bajas de unidades",
            ]
        case .maintenance:
            [
                "Recibir unidades reportadas y abrir órdenes de servicio",
                "Bloquear y liberar vehículos de la flotilla",
                "Programar servicios por kilometraje",
            ]
        case .recruiter:
            [
                "Cubrir las vacantes de su estación y de nadie más",
                "Recibir leads de campañas y referidos de la estación",
                "Precalificar, entrevistar y documentar candidatos",
                "Firmar el alta y generar el expediente del nuevo conductor",
            ]
        case .national:
            [
                "Dar de alta gerentes, supervisores y reclutamiento de cada estación",
                "Abrir estaciones y definir su capacidad",
                "Ver la operación consolidada de todo el país",
            ]
        case .lab:
            [
                "Alimentar el sistema completo desde cero",
                "Crear estaciones, usuarios, flotilla, expedientes y dinero",
                "Simular integraciones, fallos y avance del tiempo",
                "Revisar cualquier interfaz en vista previa y reiniciar el entorno",
            ]
        }
    }

    /// Roles this role is allowed to register. Direction creates the staff of each
    /// station; recruitment creates the drivers it hires. Supervision registers nobody:
    /// it runs the operation.
    var canRegister: [StaffRole] {
        switch self {
        case .lab: StaffRole.operationalRoles
        case .national: [.manager, .supervisor, .maintenance, .recruiter]
        case .recruiter: [.driver]
        case .manager, .maintenance, .driver, .supervisor: []
        }
    }

    /// The station's recruitment desk carries the hiring decision from end to end.
    var authorizesDriverRegistration: Bool { self == .recruiter }

    var registrationNote: String {
        switch self {
        case .national: "Tú generas los registros de gerentes, supervisores, taller y reclutamiento de cada estación."
        case .recruiter: "Tú firmas el alta del conductor: su expediente y su credencial nacen contigo."
        case .manager: "No registras personal: autorizas cuántas plazas puede contratar tu estación."
        case .supervisor: "No registras personal. Tu trabajo es la operación del turno, no la contratación."
        case .maintenance: "No generas registros de personal."
        case .driver: "Tu registro lo genera reclutamiento de tu estación al firmar tu alta."
        case .lab: "Generas cualquier credencial, pero solo dentro del entorno de pruebas."
        }
    }
}

nonisolated enum StaffStatus: String, Codable, Sendable {
    case active
    case suspended

    var label: String {
        switch self {
        case .active: "Activo"
        case .suspended: "Suspendido"
        }
    }
}

/// One credential holder of the network. The role decides which interface opens.
nonisolated struct StaffAccount: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let employeeNumber: String
    let email: String
    let password: String
    let role: StaffRole
    /// Home station. Required for every operational role — drivers, supervisors,
    /// maintenance, the station manager and the station's recruitment desk. Only
    /// national direction and the laboratory leave it `nil`.
    let stationId: String?
    /// Region the station belongs to. Reporting metadata for national direction; it
    /// grants no authority by itself.
    let regionId: String?
    /// Shift the supervisor or maintenance technician covers.
    let slot: ShiftSlot?
    let photoAsset: String?
    var status: StaffStatus
    /// Account that generated this record, following the network hierarchy.
    let createdById: String?
    /// Manager that authorized the hire; required for drivers.
    let authorizedById: String?
    /// Driver profile linked to this credential, only for `role == .driver`.
    let driverId: String?
    /// Direct line of the person. Optional because lab-created accounts may not have
    /// one yet; roles that other roles must reach — recruitment, supervision, the
    /// manager — always carry it so the app can place the call.
    var phone: String?

    /// Digits only, ready for a `tel://` URL.
    var dialablePhone: String? {
        guard let phone else { return nil }
        let digits = phone.filter(\.isNumber)
        return digits.count >= 10 ? digits : nil
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

/// Result of validating credentials against the directory.
nonisolated enum AuthOutcome: Sendable {
    case granted(StaffAccount)
    case unknownIdentity
    case wrongPassword
    case suspended(StaffAccount)
    case missingAssignment(StaffAccount)

    var message: String? {
        switch self {
        case .granted: nil
        case .unknownIdentity: "No encontramos esa cuenta en la red de estaciones."
        case .wrongPassword: "Contraseña incorrecta. Verifica e intenta de nuevo."
        case .suspended: "Cuenta suspendida. Contacta al gerente de tu estación."
        case .missingAssignment: "Tu cuenta no tiene estación asignada. Contacta a dirección."
        }
    }
}

nonisolated enum SignInMethod: String, Codable, Sendable {
    case biometric
    case credentials

    var label: String {
        switch self {
        case .biometric: "Face ID"
        case .credentials: "Credenciales"
        }
    }
}

/// Active session. The role stored here is the only thing that opens an interface.
nonisolated struct StaffSession: Codable, Identifiable, Sendable {
    let accountId: String
    let role: StaffRole
    let stationId: String?
    let method: SignInMethod
    let startedAt: Date

    var id: String { accountId }
}

/// Credential directory. Replace with the real identity provider when the backend lands.
nonisolated enum StaffDirectory {
    /// The directory answers from whichever environment is active. In production it is
    /// the seeded demonstration network; in test mode it is exactly what the laboratory
    /// has created, which starts empty.
    static var regions: [Region] {
        LabRuntime.isTest ? LabRuntime.regions : seededRegions
    }

    static var stations: [Station] {
        LabRuntime.isTest ? LabRuntime.stations : seededStations
    }

    /// The superadmin credential is appended in both environments: it is the only door
    /// into the console, and wiping the test world must never lock the administrator out.
    static var accounts: [StaffAccount] {
        (LabRuntime.isTest ? LabRuntime.accounts : seededAccounts) + [LabRules.adminAccount]
    }

    static let seededRegions: [Region] = [
        Region(id: "reg-vm", name: "Valle de México", stationIds: ["est-nte-cdmx", "est-sur-cdmx"]),
        Region(id: "reg-occ", name: "Occidente", stationIds: ["est-gdl-chap"]),
    ]

    static let seededStations: [Station] = [
        Station(
            id: "est-nte-cdmx",
            code: "NTE-01",
            name: "Estación Norte",
            city: "CDMX",
            regionId: "reg-vm",
            vehicleCapacity: 20
        ),
        Station(
            id: "est-sur-cdmx",
            code: "SUR-02",
            name: "Estación Sur",
            city: "CDMX",
            regionId: "reg-vm",
            vehicleCapacity: 16
        ),
        Station(
            id: "est-gdl-chap",
            code: "GDL-01",
            name: "Estación Chapalita",
            city: "Guadalajara",
            regionId: "reg-occ",
            vehicleCapacity: 24
        ),
    ]

    static let seededAccounts: [StaffAccount] = [
        StaffAccount(
            id: "acc-dir-001",
            name: "Renata Salgado Aguirre",
            employeeNumber: "EV-DIR-001",
            email: "direccion.nacional@turnoev.mx",
            password: "Direccion14",
            role: .national,
            stationId: nil,
            regionId: nil,
            slot: nil,
            photoAsset: nil,
            status: .active,
            createdById: nil,
            authorizedById: nil,
            driverId: nil
        ),
        StaffAccount(
            id: "acc-ger-045",
            name: "Mariana Ochoa Vela",
            employeeNumber: "EV-GER-045",
            email: "gerencia.norte@turnoev.mx",
            password: "Gerencia14",
            role: .manager,
            stationId: "est-nte-cdmx",
            regionId: "reg-vm",
            slot: nil,
            photoAsset: nil,
            status: .active,
            createdById: "acc-dir-001",
            authorizedById: nil,
            driverId: nil,
            phone: "55 3184 2045"
        ),
        StaffAccount(
            id: "acc-ger-046",
            name: "Gerardo Ponce Alcaráz",
            employeeNumber: "EV-GER-046",
            email: "gerencia.sur@turnoev.mx",
            password: "Gerencia14",
            role: .manager,
            stationId: "est-sur-cdmx",
            regionId: "reg-vm",
            slot: nil,
            photoAsset: nil,
            status: .active,
            createdById: "acc-dir-001",
            authorizedById: nil,
            driverId: nil,
            phone: "55 3184 2046"
        ),
        StaffAccount(
            id: "acc-ger-047",
            name: "Verónica Lamadrid Sosa",
            employeeNumber: "EV-GER-047",
            email: "gerencia.chapalita@turnoev.mx",
            password: "Gerencia14",
            role: .manager,
            stationId: "est-gdl-chap",
            regionId: "reg-occ",
            slot: nil,
            photoAsset: nil,
            status: .active,
            createdById: "acc-dir-001",
            authorizedById: nil,
            driverId: nil,
            phone: "33 2740 1047"
        ),
        StaffAccount(
            id: "acc-sup-201",
            name: "Ana Lucía Torres",
            employeeNumber: "EV-SUP-201",
            email: "supervision.norte.am@turnoev.mx",
            password: "Supervisor14",
            role: .supervisor,
            stationId: "est-nte-cdmx",
            regionId: "reg-vm",
            slot: .morning,
            photoAsset: nil,
            status: .active,
            createdById: "acc-dir-001",
            authorizedById: nil,
            driverId: nil,
            phone: "55 3184 2201"
        ),
        StaffAccount(
            id: "acc-sup-202",
            name: "Iván Ramírez Cruz",
            employeeNumber: "EV-SUP-202",
            email: "supervision.norte.pm@turnoev.mx",
            password: "Supervisor14",
            role: .supervisor,
            stationId: "est-nte-cdmx",
            regionId: "reg-vm",
            slot: .evening,
            photoAsset: nil,
            status: .active,
            createdById: "acc-dir-001",
            authorizedById: nil,
            driverId: nil,
            phone: "55 3184 2202"
        ),
        StaffAccount(
            id: "acc-mto-118",
            name: "Luis Ángel Pech",
            employeeNumber: "EV-MTO-118",
            email: "mantenimiento.norte@turnoev.mx",
            password: "Taller14",
            role: .maintenance,
            stationId: "est-nte-cdmx",
            regionId: "reg-vm",
            slot: .morning,
            photoAsset: nil,
            status: .active,
            createdById: "acc-dir-001",
            authorizedById: nil,
            driverId: nil,
            phone: "55 3184 2118"
        ),
        StaffAccount(
            id: "acc-rec-301",
            name: "Paulina Vidal Cordero",
            employeeNumber: "EV-REC-301",
            email: "reclutamiento.norte@turnoev.mx",
            password: "Reclutamiento14",
            role: .recruiter,
            stationId: "est-nte-cdmx",
            regionId: "reg-vm",
            slot: nil,
            photoAsset: nil,
            status: .active,
            createdById: "acc-dir-001",
            authorizedById: nil,
            driverId: nil,
            phone: "55 3184 2207"
        ),
        StaffAccount(
            id: "acc-rec-302",
            name: "Emiliano Cuevas Ordaz",
            employeeNumber: "EV-REC-302",
            email: "reclutamiento.sur@turnoev.mx",
            password: "Reclutamiento14",
            role: .recruiter,
            stationId: "est-sur-cdmx",
            regionId: "reg-vm",
            slot: nil,
            photoAsset: nil,
            status: .active,
            createdById: "acc-dir-001",
            authorizedById: nil,
            driverId: nil,
            phone: "55 3184 2208"
        ),
        StaffAccount(
            id: "acc-rec-303",
            name: "Denisse Arriaga Fuentes",
            employeeNumber: "EV-REC-303",
            email: "reclutamiento.chapalita@turnoev.mx",
            password: "Reclutamiento14",
            role: .recruiter,
            stationId: "est-gdl-chap",
            regionId: "reg-occ",
            slot: nil,
            photoAsset: nil,
            status: .active,
            createdById: "acc-dir-001",
            authorizedById: nil,
            driverId: nil,
            phone: "33 2740 1163"
        ),
        StaffAccount(
            id: "acc-drv-1042",
            name: "Carlos Méndez Rivas",
            employeeNumber: "EV-1042",
            email: "launion.contacto2@gmail.com",
            password: "Kymyly14",
            role: .driver,
            stationId: "est-nte-cdmx",
            regionId: "reg-vm",
            slot: .morning,
            photoAsset: "rideshare_driver_portrait",
            status: .active,
            createdById: "acc-sup-201",
            authorizedById: "acc-ger-045",
            driverId: "drv-1042"
        ),
    ]

    static func station(id: String?) -> Station? {
        guard let id else { return nil }
        return stations.first { $0.id == id }
    }

    static func region(id: String?) -> Region? {
        guard let id else { return nil }
        return regions.first { $0.id == id }
    }

    static func account(id: String?) -> StaffAccount? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    static func stations(inRegion regionId: String?) -> [Station] {
        guard let regionId else { return [] }
        return stations.filter { $0.regionId == regionId }
    }

    /// Stations an account covers. Every operational role is bound to its own station;
    /// only national direction and the laboratory see more than one.
    static func coverage(for account: StaffAccount) -> [Station] {
        guard account.role.isStationBound else { return stations }
        guard let station = station(id: account.stationId) else { return [] }
        return [station]
    }

    /// Managers of a station. A station has exactly one, but the directory can hold a
    /// suspended predecessor, so this returns the active ones in order.
    static func managers(ofStation stationId: String?) -> [StaffAccount] {
        guard let stationId else { return [] }
        return accounts.filter { $0.role == .manager && $0.stationId == stationId }
    }

    /// The manager who authorizes hires for a station.
    static func manager(ofStation stationId: String?) -> StaffAccount? {
        managers(ofStation: stationId).first { $0.status == .active }
            ?? managers(ofStation: stationId).first
    }

    /// The recruitment desk that belongs to a station.
    static func recruiter(ofStation stationId: String?) -> StaffAccount? {
        guard let stationId else { return nil }
        return accounts.first { $0.role == .recruiter && $0.stationId == stationId && $0.status == .active }
            ?? accounts.first { $0.role == .recruiter && $0.stationId == stationId }
    }

    /// Scope line shown in every workspace header. Every operational role now reads the
    /// same thing: the one station it answers for.
    static func scopeDescription(for account: StaffAccount) -> String {
        switch account.role {
        case .driver, .supervisor, .maintenance, .manager:
            station(id: account.stationId)?.displayName ?? "Sin estación asignada"
        case .recruiter:
            station(id: account.stationId).map { "Reclutamiento · \($0.displayName)" }
                ?? "Sin estación asignada"
        case .national:
            "\(stations.count) estaciones · \(regions.count) regiones"
        case .lab:
            "\(LabRuntime.mode.label) · \(stations.count) estaciones creadas"
        }
    }

    /// Validates an identifier (email or employee number) plus password.
    static func authenticate(identifier: String, password: String) -> AuthOutcome {
        let cleaned = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .unknownIdentity }

        let byEmail = cleaned.lowercased()
        let byEmployee = cleaned.uppercased()
        guard let account = accounts.first(where: { $0.email == byEmail || $0.employeeNumber == byEmployee }) else {
            return .unknownIdentity
        }
        guard account.password == password else { return .wrongPassword }
        guard account.status == .active else { return .suspended(account) }

        if account.role == .lab { return .granted(account) }
        // Managers and recruiters are station staff now: without a station there is
        // nothing for them to open.
        if account.role.isStationBound, account.stationId == nil { return .missingAssignment(account) }

        return .granted(account)
    }
}
