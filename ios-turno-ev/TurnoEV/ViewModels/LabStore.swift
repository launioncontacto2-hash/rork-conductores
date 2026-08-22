import Foundation
import Observation

/// Engine of the test laboratory. It owns the whole test world, feeds it to the rest of
/// the app through `LabRuntime`, records every action in its own audit trail and can wipe
/// itself back to zero without touching the production seed.
@Observable
final class LabStore {
    private(set) var world: LabWorld
    /// Operational store the laboratory keeps in sync after every change.
    private weak var fleet: FleetStore?

    /// Last thing that happened, surfaced as a toast in the console.
    var lastMessage: LabMessage?

    init() {
        world = LabPersistence.load()
        LabRuntime.install(world)
    }

    func attach(fleet: FleetStore) {
        self.fleet = fleet
    }

    // MARK: - Environment

    var mode: LabMode { world.mode }
    var isTest: Bool { world.mode == .test }

    var now: Date {
        _ = ClockSignal.shared.generation
        return AppClock.now()
    }

    func setMode(_ mode: LabMode) {
        guard world.mode != mode else { return }
        world.mode = mode
        commit()
        fleet?.adoptEnvironment()
        record(
            action: mode == .test ? "Entrar a modo prueba" : "Volver a producción",
            section: .system,
            detail: mode.detail,
            result: .success
        )
        notify(mode == .test ? "Modo prueba activo" : "Producción activa", tone: mode == .test ? .warning : .success)
    }

    /// The laboratory no longer keeps a clock of its own: it moves the one simulation
    /// clock every role reads.
    func setClockOffset(minutes: Int) {
        if minutes == 0 {
            SimulationClock.reset()
        } else {
            SimulationClock.set(Date().addingTimeInterval(TimeInterval(minutes * 60)))
        }
        world.clockOffsetMinutes = minutes
        commit()
        fleet?.syncSimulationClock()
        record(
            action: "Ajustar reloj",
            section: .system,
            detail: minutes == 0 ? "Reloj real del dispositivo" : "Desfase de \(minutes) minutos",
            result: .success
        )
    }

    func advanceTime(days: Int) {
        setClockOffset(minutes: world.clockOffsetMinutes + days * 24 * 60)
        applyTimeConsequences(days: days)
    }

    /// Moving the clock forward has to move the world with it, otherwise the test is a lie.
    private func applyTimeConsequences(days: Int) {
        guard days > 0 else { return }
        var creditsAdvanced = 0
        for index in world.credits.indices where world.credits[index].state.isOpen {
            let weeks = days / 7
            guard weeks > 0 else { continue }
            let due = min(weeks, world.credits[index].weeks - world.credits[index].weeksPaid)
            guard due > 0 else { continue }
            world.credits[index].weeksPaid += due
            world.credits[index].paidMxn += due * world.credits[index].weeklyMxn
            world.credits[index].movements.insert(
                LabCreditMovement(
                    id: "labmov-\(UUID().uuidString.prefix(6))",
                    date: now,
                    concept: "Abono automático por avance de tiempo",
                    amountMxn: due * world.credits[index].weeklyMxn,
                    detail: "\(due) semana(s) aplicadas"
                ),
                at: 0
            )
            if world.credits[index].paidMxn >= world.credits[index].principalMxn {
                world.credits[index].state = .settled
            }
            creditsAdvanced += 1
        }

        var expired = 0
        for fileIndex in world.employeeFiles.indices {
            for docIndex in world.employeeFiles[fileIndex].documents.indices {
                guard let expiresAt = world.employeeFiles[fileIndex].documents[docIndex].expiresAt,
                      expiresAt < now,
                      world.employeeFiles[fileIndex].documents[docIndex].status != .expired
                else { continue }
                world.employeeFiles[fileIndex].documents[docIndex].status = .expired
                expired += 1
            }
        }

        commit()
        record(
            action: "Avanzar \(days) días",
            section: .system,
            detail: "\(creditsAdvanced) crédito(s) con abono aplicado · \(expired) documento(s) vencido(s)",
            result: expired > 0 ? .warning : .success
        )
    }

    func updateShiftConfig(_ config: LabShiftConfig) {
        world.shiftConfig = config
        commit()
        fleet?.adoptEnvironment()
        record(
            action: "Actualizar reglas de turno",
            section: .system,
            detail: "\(config.driversPerVehicle) conductores por unidad · \(config.shiftHours) h por turno · batería mínima \(config.minimumBatteryPct)%",
            result: .success
        )
    }

    // MARK: - Dashboard

    struct Counter: Identifiable, Sendable {
        let id: String
        let label: String
        let value: Int
        let symbol: String
    }

    var counters: [Counter] {
        [
            Counter(id: "stations", label: "Estaciones", value: world.stations.count, symbol: "building.2.fill"),
            Counter(id: "vehicles", label: "Vehículos", value: world.vehicles.count, symbol: "car.2.fill"),
            Counter(id: "users", label: "Usuarios", value: world.users.count, symbol: "person.badge.key.fill"),
            Counter(id: "drivers", label: "Conductores", value: world.driverUsers.count, symbol: "steeringwheel"),
            Counter(id: "prospects", label: "Candidatos", value: world.prospects.count, symbol: "person.crop.circle.badge.plus"),
            Counter(id: "credits", label: "Créditos", value: world.credits.count, symbol: "creditcard.fill"),
            Counter(id: "orders", label: "Órdenes", value: world.orders.count, symbol: "wrench.and.screwdriver.fill"),
            Counter(id: "documents", label: "Documentos", value: world.documents.count, symbol: "doc.viewfinder.fill"),
            Counter(id: "alerts", label: "Alertas", value: world.alerts.count, symbol: "bell.badge.fill"),
        ]
    }

    var openAlerts: [LabAlert] {
        world.alerts.filter { !$0.isRead }.sorted { $0.createdAt > $1.createdAt }
    }

    var activeFaults: [LabFault] {
        world.faults.filter { !$0.isResolved }.sorted { $0.triggeredAt > $1.triggeredAt }
    }

    /// Roles that already have at least one credential, so the preview knows what can be opened.
    func credentials(for role: StaffRole) -> [LabUser] {
        world.users.filter { $0.role == role }
    }

    // MARK: - Regions and stations

    @discardableResult
    func addRegion(name: String) -> Region? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            fail("Crear región", section: .stations, error: "El nombre de la región no puede quedar vacío.")
            return nil
        }
        guard !world.regions.contains(where: { $0.name.localizedCaseInsensitiveCompare(cleaned) == .orderedSame }) else {
            fail("Crear región", section: .stations, error: "Ya existe una región con ese nombre.")
            return nil
        }
        let region = Region(id: "labreg-\(UUID().uuidString.prefix(6))", name: cleaned, stationIds: [])
        world.regions.append(region)
        commit()
        record(action: "Crear región", section: .stations, detail: cleaned, result: .success)
        return region
    }

    func deleteRegion(id: String) {
        guard !world.stations.contains(where: { $0.regionId == id }) else {
            fail("Eliminar región", section: .stations, error: "La región todavía tiene estaciones asignadas.")
            return
        }
        world.regions.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar región", section: .stations, detail: id, result: .success)
    }

    @discardableResult
    func saveStation(_ station: LabStation) -> Bool {
        let duplicate = world.stations.contains {
            $0.id != station.id && $0.code.localizedCaseInsensitiveCompare(station.code) == .orderedSame
        }
        guard !duplicate else {
            fail("Guardar estación", section: .stations, error: "El código \(station.code) ya existe en la red.")
            return false
        }
        guard !station.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            fail("Guardar estación", section: .stations, error: "La estación necesita nombre.")
            return false
        }
        if let index = world.stations.firstIndex(where: { $0.id == station.id }) {
            world.stations[index] = station
            commit()
            record(action: "Editar estación", section: .stations, detail: station.displayName, result: .success)
        } else {
            world.stations.append(station)
            commit()
            record(
                action: "Crear estación",
                section: .stations,
                detail: "\(station.displayName) · cupo \(station.maxVehicles) unidades",
                result: .success
            )
        }
        fleet?.adoptEnvironment()
        return true
    }

    func setStationLifecycle(id: String, lifecycle: StationLifecycle) {
        guard let index = world.stations.firstIndex(where: { $0.id == id }) else { return }
        let previous = world.stations[index].lifecycle
        world.stations[index].lifecycle = lifecycle
        commit()
        fleet?.adoptEnvironment()
        record(
            action: "Cambiar estado de estación",
            section: .stations,
            detail: "\(world.stations[index].displayName): \(previous.label) → \(lifecycle.label)",
            result: lifecycle == .closed ? .warning : .success
        )
    }

    func deleteStation(id: String) {
        guard let station = world.station(id: id) else { return }
        let units = world.vehicles(at: id).count
        let staff = world.users.filter { $0.stationId == id }.count
        world.stations.removeAll { $0.id == id }
        world.vehicles.removeAll { $0.stationId == id }
        world.users.removeAll { $0.stationId == id }
        world.employeeFiles.removeAll { $0.stationId == id }
        world.prospects.removeAll { $0.stationId == id }
        world.assets.removeAll { $0.stationId == id }
        world.orders.removeAll { $0.stationId == id }
        commit()
        fleet?.adoptEnvironment()
        record(
            action: "Eliminar estación",
            section: .stations,
            detail: "\(station.displayName) · \(units) unidades y \(staff) usuarios eliminados en cascada",
            result: .warning
        )
    }

    // MARK: - Users

    @discardableResult
    func saveUser(_ user: LabUser) -> Bool {
        let cleanedEmail = user.email.trimmingCharacters(in: .whitespaces).lowercased()
        guard cleanedEmail.contains("@") else {
            fail("Guardar usuario", section: .users, error: "El correo no es válido.")
            return false
        }
        let duplicate = world.users.contains {
            $0.id != user.id && ($0.email.lowercased() == cleanedEmail
                || $0.employeeNumber.localizedCaseInsensitiveCompare(user.employeeNumber) == .orderedSame)
        }
        guard !duplicate else {
            fail("Guardar usuario", section: .users, error: "Ya existe una credencial con ese correo o número de empleado.")
            return false
        }
        guard user.password.count >= 6 else {
            fail("Guardar usuario", section: .users, error: "La contraseña necesita al menos 6 caracteres.")
            return false
        }
        // Managers and recruiters are station staff: a station owns exactly one of each.
        guard !user.role.isStationBound || user.stationId != nil else {
            fail("Guardar usuario", section: .users, error: "\(user.role.label) requiere estación asignada.")
            return false
        }
        if user.role == .manager || user.role == .recruiter, let stationId = user.stationId {
            let taken = world.users.first {
                $0.id != user.id && $0.role == user.role && $0.stationId == stationId
            }
            if let taken {
                fail(
                    "Guardar usuario",
                    section: .users,
                    error: "\(world.station(id: stationId)?.code ?? "La estación") ya tiene \(user.role.label.lowercased()): \(taken.name)."
                )
                return false
            }
        }
        if user.role == .driver, let stationId = user.stationId {
            let installed = world.installedCount(at: stationId)
            let ceiling = installed * max(1, world.shiftConfig.driversPerVehicle)
            let current = world.users(at: stationId, role: .driver).filter { $0.id != user.id }.count
            if ceiling > 0, current >= ceiling {
                notify(
                    "Sobrecupo: la estación ya tiene \(current) conductores para \(installed) unidades",
                    tone: .warning
                )
                raiseAlert(
                    level: .important,
                    audience: .supervisor,
                    stationId: stationId,
                    title: "Sobrecupo de plantilla",
                    detail: "\(current + 1) conductores para \(installed) unidades (máximo \(ceiling)).",
                    origin: "regla"
                )
            }
        }

        var stored = user
        stored.email = cleanedEmail
        if stored.role == .driver, stored.driverId == nil {
            stored.driverId = "labdrv-\(UUID().uuidString.prefix(6))"
        }

        if let index = world.users.firstIndex(where: { $0.id == stored.id }) {
            world.users[index] = stored
            commit()
            record(action: "Editar usuario", section: .users, detail: "\(stored.name) · \(stored.role.label)", result: .success)
        } else {
            world.users.append(stored)
            if stored.role == .driver { createFile(for: stored) }
            commit()
            record(
                action: "Crear usuario",
                section: .users,
                detail: "\(stored.name) · \(stored.role.label) · \(stored.email)",
                result: .success
            )
        }
        fleet?.adoptEnvironment()
        return true
    }

    /// A hired driver always gets an employee file, so the HR interface has something real.
    private func createFile(for user: LabUser) {
        guard let stationId = user.stationId else { return }
        let file = EmployeeFile(
            id: user.driverId ?? user.id,
            name: user.name,
            employeeNumber: user.employeeNumber,
            photoAsset: nil,
            stationId: stationId,
            block: user.block ?? .weekdayMorning,
            hiredAt: user.hiredAt,
            status: user.employment,
            supervisorName: world.users(at: stationId, role: .supervisor).first?.name ?? "Sin supervisor",
            phone: user.phone,
            curp: "",
            rfc: "",
            documents: DocumentKind.allCases.filter(\.isCritical).map { kind in
                StaffDocument(kind: kind, status: .pending)
            },
            events: [
                FileEvent(
                    id: "labev-\(UUID().uuidString.prefix(6))",
                    kind: .hire,
                    date: user.hiredAt,
                    detail: "Alta generada desde el laboratorio de pruebas.",
                    author: LabRules.adminAccount.name
                ),
            ],
            bank: nil,
            isLiveSession: false
        )
        world.employeeFiles.append(file)
    }

    func setUserStatus(id: String, status: StaffStatus) {
        guard let index = world.users.firstIndex(where: { $0.id == id }) else { return }
        world.users[index].status = status
        commit()
        fleet?.adoptEnvironment()
        record(
            action: status == .suspended ? "Suspender usuario" : "Reactivar usuario",
            section: .users,
            detail: world.users[index].name,
            result: status == .suspended ? .warning : .success
        )
    }

    func setEmployment(id: String, employment: EmploymentStatus) {
        guard let index = world.users.firstIndex(where: { $0.id == id }) else { return }
        world.users[index].employment = employment
        if let fileIndex = world.employeeFiles.firstIndex(where: { $0.id == world.users[index].driverId }) {
            world.employeeFiles[fileIndex].status = employment
            world.employeeFiles[fileIndex].events.insert(
                FileEvent(
                    id: "labev-\(UUID().uuidString.prefix(6))",
                    kind: employment == .terminated ? .termination : .suspension,
                    date: now,
                    detail: "Cambio de situación laboral: \(employment.label).",
                    author: LabRules.adminAccount.name
                ),
                at: 0
            )
        }
        commit()
        fleet?.adoptEnvironment()
        record(
            action: "Cambiar situación laboral",
            section: .humanResources,
            detail: "\(world.users[index].name) → \(employment.label)",
            result: employment.canOperate ? .success : .warning
        )
    }

    func deleteUser(id: String) {
        guard let user = world.user(id: id) else { return }
        world.users.removeAll { $0.id == id }
        world.employeeFiles.removeAll { $0.id == user.driverId }
        world.credits.removeAll { $0.driverId == user.driverId }
        world.bankAccounts.removeAll { $0.driverId == user.driverId }
        commit()
        fleet?.adoptEnvironment()
        record(action: "Eliminar usuario", section: .users, detail: user.name, result: .warning)
    }

    /// Reviews another interface without changing the real role of anyone.
    func setPreviewRole(userId: String, role: StaffRole?) {
        guard let index = world.users.firstIndex(where: { $0.id == userId }) else { return }
        world.users[index].testRole = role
        commit()
        fleet?.adoptEnvironment()
        record(
            action: "Vista previa de rol",
            section: .users,
            detail: role == nil
                ? "\(world.users[index].name) vuelve a su rol real"
                : "\(world.users[index].name) se revisa como \(role?.label ?? "")",
            result: .success
        )
    }

    // MARK: - Vehicles

    @discardableResult
    func saveVehicle(_ vehicle: LabVehicle) -> Bool {
        guard world.station(id: vehicle.stationId) != nil else {
            fail("Guardar vehículo", section: .vehicles, error: "Primero crea la estación a la que pertenece la unidad.")
            return false
        }
        let duplicate = world.vehicles.contains {
            $0.id != vehicle.id && ($0.internalNumber.localizedCaseInsensitiveCompare(vehicle.internalNumber) == .orderedSame
                || $0.plates.localizedCaseInsensitiveCompare(vehicle.plates) == .orderedSame
                || $0.vin.localizedCaseInsensitiveCompare(vehicle.vin) == .orderedSame)
        }
        guard !duplicate else {
            fail("Guardar vehículo", section: .vehicles, error: "El número interno, las placas o el VIN ya existen.")
            return false
        }
        if let station = world.station(id: vehicle.stationId) {
            let installed = world.vehicles(at: station.id).filter { $0.id != vehicle.id && $0.stage.isInstalled }.count
            if vehicle.stage.isInstalled, installed >= station.maxVehicles {
                fail(
                    "Guardar vehículo",
                    section: .vehicles,
                    error: "\(station.name) llegó a su cupo de \(station.maxVehicles) unidades instaladas."
                )
                return false
            }
        }

        if let index = world.vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            world.vehicles[index] = vehicle
            commit()
            record(action: "Editar vehículo", section: .vehicles, detail: vehicle.internalNumber, result: .success)
        } else {
            world.vehicles.append(vehicle)
            world.assets.append(
                StationAsset(
                    id: "labast-\(vehicle.id)",
                    stationId: vehicle.stationId,
                    category: .vehicles,
                    name: vehicle.fullModel,
                    code: vehicle.internalNumber,
                    state: .operational,
                    lastServiceAt: vehicle.incorporatedAt,
                    note: "Alta generada desde el laboratorio.",
                    vehicleId: vehicle.id
                )
            )
            commit()
            record(
                action: "Crear vehículo",
                section: .vehicles,
                detail: "\(vehicle.internalNumber) · \(vehicle.fullModel) · \(vehicle.stage.label)",
                result: .success
            )
            checkCoverage(stationId: vehicle.stationId)
        }
        fleet?.adoptEnvironment()
        return true
    }

    func setVehicleStage(id: String, stage: LabVehicleStage) {
        guard let index = world.vehicles.firstIndex(where: { $0.id == id }) else { return }
        let previous = world.vehicles[index].stage
        world.vehicles[index].stage = stage
        if !stage.isInstalled { world.vehicles[index].occupiedBy = nil }
        commit()
        fleet?.adoptEnvironment()
        record(
            action: "Cambiar etapa de vehículo",
            section: .vehicles,
            detail: "\(world.vehicles[index].internalNumber): \(previous.label) → \(stage.label)",
            result: stage == .outOfService ? .warning : .success
        )
        checkCoverage(stationId: world.vehicles[index].stationId)
    }

    func updateVehicleReadings(id: String, odometerKm: Int?, batteryPct: Int?, photoOdometerKm: Int?) {
        guard let index = world.vehicles.firstIndex(where: { $0.id == id }) else { return }
        if let odometerKm { world.vehicles[index].odometerKm = max(0, odometerKm) }
        if let batteryPct { world.vehicles[index].batteryPct = min(100, max(0, batteryPct)) }
        if let photoOdometerKm { world.vehicles[index].photoOdometerKm = max(0, photoOdometerKm) }
        commit()
        fleet?.adoptEnvironment()

        let gap = world.vehicles[index].odometerGapKm
        record(
            action: "Actualizar lecturas",
            section: .vehicles,
            detail: "\(world.vehicles[index].internalNumber) · \(Fmt.km(world.vehicles[index].odometerKm)) · \(world.vehicles[index].batteryPct)%",
            result: gap > 0 ? .warning : .success
        )
        if gap > 0 {
            raiseAlert(
                level: gap > 50 ? .critical : .important,
                audience: .supervisor,
                stationId: world.vehicles[index].stationId,
                title: "Discrepancia de kilometraje",
                detail: "\(world.vehicles[index].internalNumber) presenta \(gap) km de diferencia entre lectura manual, foto y telemetría.",
                origin: "regla"
            )
        }
    }

    func deleteVehicle(id: String) {
        guard let vehicle = world.vehicle(id: id) else { return }
        world.vehicles.removeAll { $0.id == id }
        world.assets.removeAll { $0.vehicleId == id }
        world.orders.removeAll { $0.vehicleId == id }
        commit()
        fleet?.adoptEnvironment()
        record(action: "Eliminar vehículo", section: .vehicles, detail: vehicle.internalNumber, result: .warning)
        checkCoverage(stationId: vehicle.stationId)
    }

    /// Every fleet change re-runs the arithmetic that governs the network.
    private func checkCoverage(stationId: String) {
        guard let station = world.station(id: stationId) else { return }
        let installed = world.installedCount(at: stationId)
        let required = installed * max(1, world.shiftConfig.driversPerVehicle)
        let available = world.users(at: stationId, role: .driver).filter { $0.employment.canOperate }.count
        let deficit = max(0, required - available)
        guard deficit > 0 else { return }
        raiseAlert(
            level: deficit > required / 2 ? .critical : .important,
            audience: .recruiter,
            stationId: stationId,
            title: "Vacantes en \(station.name)",
            detail: "\(installed) unidades exigen \(required) conductores y hay \(available). Faltan \(deficit).",
            origin: "regla"
        )
    }

    // MARK: - Human resources

    func attachDocument(_ document: LabDocument) {
        world.documents.insert(document, at: 0)
        if let fileIndex = world.employeeFiles.firstIndex(where: { $0.id == document.subjectId }),
           let docIndex = world.employeeFiles[fileIndex].documents.firstIndex(where: { $0.kind == document.kind }) {
            let status: DocumentStatus = document.ocr?.outcome.documentStatus ?? .delivered
            world.employeeFiles[fileIndex].documents[docIndex].status = status
            world.employeeFiles[fileIndex].documents[docIndex].uploadedAt = document.capturedAt
            world.employeeFiles[fileIndex].documents[docIndex].uploadedBy = LabRules.adminAccount.name
            world.employeeFiles[fileIndex].documents[docIndex].versions.insert(
                DocumentVersion(
                    id: "labver-\(UUID().uuidString.prefix(6))",
                    uploadedAt: document.capturedAt,
                    uploadedBy: LabRules.adminAccount.name,
                    note: "\(document.source.label) · \(document.fileName)"
                ),
                at: 0
            )
        }
        commit()
        let outcome = document.ocr?.outcome
        record(
            action: "Adjuntar documento",
            section: .documents,
            detail: "\(document.kind.label) · \(document.subjectName) · \(document.source.label) · \(document.sizeLabel)",
            result: outcome == nil || outcome == .correct ? .success : .warning,
            error: outcome == .correct ? nil : outcome?.appResponse
        )
    }

    func deleteDocument(id: String) {
        world.documents.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar documento", section: .documents, detail: id, result: .warning)
    }

    // MARK: - Recruitment

    @discardableResult
    func addProspect(_ prospect: Prospect) -> Bool {
        let duplicate = world.prospects.contains {
            $0.phone.filter(\.isNumber) == prospect.phone.filter(\.isNumber) && !prospect.phone.isEmpty
        }
        world.prospects.insert(prospect, at: 0)
        commit()
        record(
            action: "Crear candidato",
            section: .recruitment,
            detail: "\(prospect.name) · \(prospect.source.label) · \(prospect.stage.label)",
            result: duplicate ? .warning : .success,
            error: duplicate ? "Teléfono repetido: el guardia de duplicados debe marcarlo en reclutamiento." : nil
        )
        return true
    }

    func advanceProspect(id: String, to stage: RecruitStage) {
        guard let index = world.prospects.firstIndex(where: { $0.id == id }) else { return }
        let previous = world.prospects[index].stage
        world.prospects[index].stage = stage
        world.prospects[index].history.insert(
            ProspectEvent(
                id: "labpe-\(UUID().uuidString.prefix(6))",
                kind: .stage,
                date: now,
                detail: "\(previous.label) → \(stage.label)",
                author: LabRules.adminAccount.name
            ),
            at: 0
        )
        if stage == .hired { world.prospects[index].hiredAt = now }
        commit()
        record(
            action: "Mover candidato",
            section: .recruitment,
            detail: "\(world.prospects[index].name): \(previous.label) → \(stage.label)",
            result: stage == .lost ? .warning : .success
        )
    }

    func deleteProspect(id: String) {
        world.prospects.removeAll { $0.id == id }
        world.appointments.removeAll { $0.prospectId == id }
        commit()
        record(action: "Eliminar candidato", section: .recruitment, detail: id, result: .warning)
    }

    @discardableResult
    func saveCampaign(_ campaign: RecruitCampaign) -> Bool {
        guard campaign.budgetMxn > 0 else {
            fail("Guardar campaña", section: .recruitment, error: "El presupuesto tiene que ser mayor a cero.")
            return false
        }
        if let index = world.campaigns.firstIndex(where: { $0.id == campaign.id }) {
            world.campaigns[index] = campaign
        } else {
            world.campaigns.append(campaign)
        }
        commit()
        record(
            action: "Guardar campaña",
            section: .recruitment,
            detail: "\(campaign.name) · \(campaign.platform.label) · \(Fmt.mxn(campaign.budgetMxn))",
            result: .success
        )
        return true
    }

    func deleteCampaign(id: String) {
        world.campaigns.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar campaña", section: .recruitment, detail: id, result: .warning)
    }

    func addAppointment(_ appointment: Appointment) {
        world.appointments.append(appointment)
        commit()
        record(
            action: "Agendar cita",
            section: .recruitment,
            detail: "\(appointment.prospectName) · \(appointment.kind.label) · \(Fmt.dateShort(appointment.date))",
            result: .success
        )
    }

    // MARK: - Maintenance

    @discardableResult
    func saveAsset(_ asset: StationAsset) -> Bool {
        if let index = world.assets.firstIndex(where: { $0.id == asset.id }) {
            world.assets[index] = asset
        } else {
            world.assets.append(asset)
        }
        commit()
        record(action: "Guardar activo", section: .maintenance, detail: "\(asset.name) · \(asset.code)", result: .success)
        return true
    }

    func deleteAsset(id: String) {
        world.assets.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar activo", section: .maintenance, detail: id, result: .warning)
    }

    @discardableResult
    func saveOrder(_ order: WorkOrder) -> Bool {
        if let index = world.orders.firstIndex(where: { $0.id == order.id }) {
            world.orders[index] = order
            commit()
            record(action: "Editar orden", section: .maintenance, detail: order.folio, result: .success)
        } else {
            world.orders.append(order)
            commit()
            record(
                action: "Crear orden",
                section: .maintenance,
                detail: "\(order.folio) · \(order.assetName) · \(order.priority.label)",
                result: .success
            )
        }
        return true
    }

    func setOrderStatus(id: String, status: WorkOrderStatus) {
        guard let index = world.orders.firstIndex(where: { $0.id == id }) else { return }
        let previous = world.orders[index].status
        world.orders[index].status = status
        switch status {
        case .inProgress: world.orders[index].acceptedAt = now
        case .finished: world.orders[index].finishedAt = now
        case .closed: world.orders[index].closedAt = now
        default: break
        }
        commit()
        record(
            action: "Cambiar estado de orden",
            section: .maintenance,
            detail: "\(world.orders[index].folio): \(previous.label) → \(status.label)",
            result: .success
        )
    }

    func deleteOrder(id: String) {
        world.orders.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar orden", section: .maintenance, detail: id, result: .warning)
    }

    // MARK: - Operation

    func registerIncident(_ incident: StationIncident) {
        world.incidents.insert(incident, at: 0)
        if incident.severity == .critical, let index = world.vehicles.firstIndex(where: { $0.internalNumber == incident.vehicleNumber }) {
            world.vehicles[index].stage = .outOfService
            world.vehicles[index].occupiedBy = nil
        }
        commit()
        fleet?.adoptEnvironment()
        record(
            action: "Registrar incidencia",
            section: .operation,
            detail: "\(incident.kind.label) · \(incident.vehicleNumber) · \(incident.severity.label)",
            result: incident.severity == .critical ? .failure : .warning
        )
        raiseAlert(
            level: incident.severity == .critical ? .critical : .important,
            audience: .supervisor,
            stationId: incident.stationId,
            title: "Incidencia: \(incident.kind.label)",
            detail: incident.detail,
            origin: "operación"
        )
    }

    // MARK: - Money

    @discardableResult
    func saveCredit(_ credit: LabCredit) -> Bool {
        guard credit.principalMxn > 0, credit.weeklyMxn > 0 else {
            fail("Guardar crédito", section: .credits, error: "El monto y el abono semanal tienen que ser mayores a cero.")
            return false
        }
        if let index = world.credits.firstIndex(where: { $0.id == credit.id }) {
            world.credits[index] = credit
            commit()
            record(action: "Editar crédito", section: .credits, detail: credit.driverName, result: .success)
        } else {
            world.credits.append(credit)
            commit()
            record(
                action: "Crear crédito",
                section: .credits,
                detail: "\(credit.driverName) · \(Fmt.mxn(credit.principalMxn)) en \(credit.weeks) semanas",
                result: .success
            )
        }
        return true
    }

    func setCreditState(id: String, state: LabCreditState) {
        guard let index = world.credits.firstIndex(where: { $0.id == id }) else { return }
        let previous = world.credits[index].state
        world.credits[index].state = state
        commit()
        record(
            action: "Cambiar estado de crédito",
            section: .credits,
            detail: "\(world.credits[index].driverName): \(previous.label) → \(state.label)",
            result: state == .late || state == .suspended ? .warning : .success
        )
        if state == .late {
            raiseAlert(
                level: .important,
                audience: .manager,
                stationId: nil,
                title: "Crédito atrasado",
                detail: "\(world.credits[index].driverName) acumula atraso en su contrato.",
                origin: "regla"
            )
        }
    }

    func registerCreditPayment(id: String, amountMxn: Int) {
        guard let index = world.credits.firstIndex(where: { $0.id == id }), amountMxn > 0 else { return }
        world.credits[index].paidMxn += amountMxn
        world.credits[index].weeksPaid += 1
        world.credits[index].movements.insert(
            LabCreditMovement(
                id: "labmov-\(UUID().uuidString.prefix(6))",
                date: now,
                concept: "Abono manual",
                amountMxn: amountMxn,
                detail: "Registrado desde el laboratorio"
            ),
            at: 0
        )
        if world.credits[index].paidMxn >= world.credits[index].principalMxn {
            world.credits[index].state = .settled
        } else {
            world.credits[index].state = .current
        }
        commit()
        record(
            action: "Registrar abono",
            section: .credits,
            detail: "\(world.credits[index].driverName) · \(Fmt.mxn(amountMxn)) · saldo \(Fmt.mxn(world.credits[index].balanceMxn))",
            result: .success
        )
    }

    func deleteCredit(id: String) {
        world.credits.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar crédito", section: .credits, detail: id, result: .warning)
    }

    @discardableResult
    func saveBonus(_ bonus: LabBonus) -> Bool {
        guard bonus.amountMxn > 0 else {
            fail("Guardar bono", section: .bonuses, error: "El monto del bono tiene que ser mayor a cero.")
            return false
        }
        if let index = world.bonuses.firstIndex(where: { $0.id == bonus.id }) {
            world.bonuses[index] = bonus
        } else {
            world.bonuses.append(bonus)
        }
        commit()
        record(
            action: "Guardar bono",
            section: .bonuses,
            detail: "\(bonus.name) · \(Fmt.mxn(bonus.amountMxn)) · \(bonus.period.label) · \(bonus.role.label)",
            result: .success
        )
        return true
    }

    func deleteBonus(id: String) {
        world.bonuses.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar bono", section: .bonuses, detail: id, result: .warning)
    }

    @discardableResult
    func saveGoal(_ goal: LabGoal) -> Bool {
        guard goal.hourlyMxn > 0, goal.hoursPerDay > 0 else {
            fail("Guardar meta", section: .goals, error: "La meta por hora y las horas por día tienen que ser mayores a cero.")
            return false
        }
        if let index = world.goals.firstIndex(where: { $0.id == goal.id }) {
            world.goals[index] = goal
        } else {
            world.goals.append(goal)
        }
        commit()
        record(
            action: "Guardar meta",
            section: .goals,
            detail: "\(goal.name) · \(goal.scope.label) · \(Fmt.mxn(goal.dailyMxn)) al día",
            result: .success
        )
        return true
    }

    func deleteGoal(id: String) {
        world.goals.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar meta", section: .goals, detail: id, result: .warning)
    }

    @discardableResult
    func saveBankAccount(_ account: LabBankAccount) -> Bool {
        guard HRRules.isValidClabe(account.clabe) else {
            fail("Guardar cuenta bancaria", section: .finance, error: "La CLABE debe tener 18 dígitos.")
            return false
        }
        guard !LabRules.isDuplicate(clabe: account.clabe, in: world.bankAccounts, excluding: account.id) else {
            fail(
                "Guardar cuenta bancaria",
                section: .finance,
                error: "Esa CLABE ya está registrada con otro conductor. Una CLABE solo puede existir una vez en la red."
            )
            raiseAlert(
                level: .critical,
                audience: .manager,
                stationId: nil,
                title: "CLABE duplicada",
                detail: "Se intentó registrar \(HRRules.mask(clabe: account.clabe)) en dos expedientes.",
                origin: "regla"
            )
            return false
        }
        if let index = world.bankAccounts.firstIndex(where: { $0.id == account.id }) {
            world.bankAccounts[index] = account
        } else {
            world.bankAccounts.append(account)
        }
        commit()
        record(
            action: "Guardar cuenta bancaria",
            section: .finance,
            detail: "\(account.driverName) · \(account.bank) · \(account.maskedClabe)",
            result: .success
        )
        return true
    }

    func deleteBankAccount(id: String) {
        world.bankAccounts.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar cuenta bancaria", section: .finance, detail: id, result: .warning)
    }

    @discardableResult
    func saveSettlement(_ settlement: WeeklySettlement) -> Bool {
        if let index = world.settlements.firstIndex(where: { $0.id == settlement.id }) {
            world.settlements[index] = settlement
        } else {
            world.settlements.append(settlement)
        }
        commit()
        record(
            action: "Guardar liquidación",
            section: .finance,
            detail: "\(settlement.rangeLabel) · neto \(Fmt.mxn(settlement.netMxn))",
            result: .success
        )
        return true
    }

    func deleteSettlement(id: String) {
        world.settlements.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar liquidación", section: .finance, detail: id, result: .warning)
    }

    // MARK: - Simulated integrations

    func receiveUberFeed(_ feed: LabUberFeed) {
        world.uberFeeds.insert(feed, at: 0)
        commit()
        record(
            action: "Recibir datos de Uber",
            section: .integrations,
            detail: "\(feed.driverName) · \(feed.trips) viajes · \(Fmt.mxn(feed.totalMxn)) · \(feed.km) km",
            result: .success
        )
    }

    func receiveTelemetry(_ reading: LabTelemetryReading) {
        world.telemetry.insert(reading, at: 0)
        if let index = world.vehicles.firstIndex(where: { $0.id == reading.vehicleId }) {
            world.vehicles[index].batteryPct = reading.batteryPct
            world.vehicles[index].telemetryOdometerKm = reading.odometerKm
            world.vehicles[index].rangeKm = reading.rangeKm
            world.vehicles[index].lastTelemetryAt = reading.receivedAt
        }
        commit()
        fleet?.adoptEnvironment()
        let gap = world.vehicle(id: reading.vehicleId)?.odometerGapKm ?? 0
        record(
            action: "Recibir telemetría",
            section: .integrations,
            detail: "\(reading.vehicleLabel) · \(reading.batteryPct)% · \(Fmt.km(reading.odometerKm)) · \(reading.chargeState.label)",
            result: gap > 0 ? .warning : .success,
            error: gap > 0 ? "La telemetría no coincide con la lectura manual: \(gap) km de diferencia." : nil
        )
        if reading.batteryPct < world.shiftConfig.minimumBatteryPct {
            raiseAlert(
                level: .important,
                audience: .supervisor,
                stationId: world.vehicle(id: reading.vehicleId)?.stationId,
                title: "Batería por debajo del mínimo",
                detail: "\(reading.vehicleLabel) reporta \(reading.batteryPct)% y el mínimo para iniciar turno es \(world.shiftConfig.minimumBatteryPct)%.",
                origin: "telemetría"
            )
        }
    }

    /// Meta lead form: the campaign produces a prospect exactly as the real webhook would.
    func receiveMetaLead(campaign: RecruitCampaign, name: String, phone: String, city: String) {
        let prospect = Prospect(
            id: "labpro-\(UUID().uuidString.prefix(6))",
            name: name,
            phone: phone,
            email: "",
            city: city,
            age: 30,
            curp: "",
            stationId: campaign.stationId,
            requestedBlock: .weekdayMorning,
            experienceYears: 0,
            platforms: [],
            hasLicense: true,
            source: campaign.platform,
            campaignId: campaign.id,
            createdAt: now,
            stage: .lead,
            contactedAt: nil,
            screening: nil,
            interview: nil,
            documents: [],
            authorizedAt: nil,
            hiringVerdict: nil,
            hiringNote: nil,
            verdictAt: nil,
            hiredAt: nil,
            lossReason: nil,
            lossNote: nil,
            ownerName: LabRules.adminAccount.name,
            notes: "Lead recibido del formulario simulado de \(campaign.platform.label).",
            history: []
        )
        world.prospects.insert(prospect, at: 0)
        if let index = world.campaigns.firstIndex(where: { $0.id == campaign.id }) {
            world.campaigns[index].spentMxn += max(1, campaign.budgetMxn / 100)
        }
        commit()
        record(
            action: "Recibir lead de Meta",
            section: .integrations,
            detail: "\(name) · \(campaign.name) · \(campaign.platform.label)",
            result: .success
        )
    }

    func runTransfer(_ transfer: LabTransfer) {
        world.transfers.insert(transfer, at: 0)
        if transfer.outcome.isSuccess,
           let index = world.settlements.firstIndex(where: { $0.driverId == transfer.driverId && !$0.isClosed }) {
            world.settlements[index].status = .transferred
            world.settlements[index].transferredAt = now
        }
        commit()
        record(
            action: "Simular transferencia",
            section: .integrations,
            detail: "\(transfer.driverName) · \(Fmt.mxn(transfer.amountMxn)) · \(transfer.outcome.label)",
            result: transfer.outcome.result,
            error: transfer.outcome.isSuccess ? nil : transfer.outcome.appResponse
        )
        if !transfer.outcome.isSuccess {
            raiseAlert(
                level: .important,
                audience: .manager,
                stationId: nil,
                title: "Dispersión fallida",
                detail: "\(transfer.driverName): \(transfer.outcome.label). \(transfer.outcome.appResponse)",
                origin: "banca"
            )
        }
    }

    // MARK: - Alerts and faults

    func raiseAlert(
        level: OpsAlertLevel,
        audience: StaffRole,
        stationId: String?,
        title: String,
        detail: String,
        origin: String
    ) {
        world.alerts.insert(
            LabAlert(
                id: "labalr-\(UUID().uuidString.prefix(6))",
                level: level,
                audience: audience,
                stationId: stationId,
                title: title,
                detail: detail,
                createdAt: now,
                origin: origin,
                isRead: false
            ),
            at: 0
        )
        commit()
    }

    func createManualAlert(level: OpsAlertLevel, audience: StaffRole, stationId: String?, title: String, detail: String) {
        raiseAlert(level: level, audience: audience, stationId: stationId, title: title, detail: detail, origin: "manual")
        record(
            action: "Generar alerta",
            section: .alerts,
            detail: "\(level.label) · \(audience.label) · \(title)",
            result: .success
        )
    }

    func markAlertRead(id: String) {
        guard let index = world.alerts.firstIndex(where: { $0.id == id }) else { return }
        world.alerts[index].isRead = true
        commit()
    }

    func clearAlerts() {
        let count = world.alerts.count
        world.alerts.removeAll()
        commit()
        record(action: "Limpiar alertas", section: .alerts, detail: "\(count) alerta(s) eliminadas", result: .warning)
    }

    /// Injects a controlled failure and applies its real consequence to the world.
    func injectFault(kind: LabFaultKind, targetId: String?, targetLabel: String) {
        let fault = LabFault(
            id: "labflt-\(UUID().uuidString.prefix(6))",
            kind: kind,
            targetId: targetId,
            targetLabel: targetLabel,
            triggeredAt: now,
            isResolved: false,
            detail: kind.expectedResponse
        )
        world.faults.insert(fault, at: 0)
        applyFaultConsequence(kind: kind, targetId: targetId)
        raiseAlert(
            level: kind.level,
            audience: kind.audience,
            stationId: stationId(forFault: kind, targetId: targetId),
            title: kind.label,
            detail: "\(targetLabel). \(kind.expectedResponse)",
            origin: "fallo simulado"
        )
        commit()
        fleet?.adoptEnvironment()
        record(
            action: "Inyectar fallo",
            section: .integrations,
            detail: "\(kind.label) · \(targetLabel)",
            result: .warning,
            error: kind.expectedResponse
        )
    }

    private func stationId(forFault kind: LabFaultKind, targetId: String?) -> String? {
        switch kind.target {
        case .vehicle: world.vehicle(id: targetId)?.stationId
        case .driver: world.users.first { $0.driverId == targetId || $0.id == targetId }?.stationId
        case .order: world.orders.first { $0.id == targetId }?.stationId
        case .station: targetId
        case .candidate: world.prospects.first { $0.id == targetId }?.stationId
        }
    }

    private func applyFaultConsequence(kind: LabFaultKind, targetId: String?) {
        switch kind {
        case .vehicleBreakdown:
            if let index = world.vehicles.firstIndex(where: { $0.id == targetId }) {
                world.vehicles[index].stage = .outOfService
                world.vehicles[index].occupiedBy = nil
            }
        case .lowBattery:
            if let index = world.vehicles.firstIndex(where: { $0.id == targetId }) {
                world.vehicles[index].batteryPct = max(0, world.shiftConfig.minimumBatteryPct - 25)
            }
        case .overdueMaintenance:
            if let index = world.vehicles.firstIndex(where: { $0.id == targetId }) {
                world.vehicles[index].stage = .maintenance
            }
        case .odometerMismatch:
            if let index = world.vehicles.firstIndex(where: { $0.id == targetId }) {
                world.vehicles[index].telemetryOdometerKm = world.vehicles[index].odometerKm + 137
            }
        case .driverAbsent:
            if let index = world.users.firstIndex(where: { $0.driverId == targetId || $0.id == targetId }) {
                world.users[index].employment = .suspended
            }
        case .expiredDocument:
            if let fileIndex = world.employeeFiles.firstIndex(where: { $0.id == targetId }),
               let docIndex = world.employeeFiles[fileIndex].documents.indices.first {
                world.employeeFiles[fileIndex].documents[docIndex].status = .expired
                world.employeeFiles[fileIndex].documents[docIndex].expiresAt = now.addingTimeInterval(-86400)
            }
        case .lateCredit:
            if let index = world.credits.firstIndex(where: { $0.driverId == targetId }) {
                world.credits[index].state = .late
            }
        case .overdueOrder:
            if let index = world.orders.firstIndex(where: { $0.id == targetId }) {
                world.orders[index].priority = .critical
            }
        case .candidateNoShow:
            if let index = world.prospects.firstIndex(where: { $0.id == targetId }) {
                world.prospects[index].stage = .lost
                world.prospects[index].lossReason = .noShow
            }
        case .vehicleWithoutDriver:
            if let index = world.vehicles.firstIndex(where: { $0.id == targetId }) {
                world.vehicles[index].occupiedBy = nil
                world.vehicles[index].stage = .available
            }
        case .duplicateClabe, .rejectedTransfer, .driverLate, .invalidQr, .staffOvercapacity, .staffDeficit:
            break
        }
    }

    func resolveFault(id: String) {
        guard let index = world.faults.firstIndex(where: { $0.id == id }) else { return }
        world.faults[index].isResolved = true
        commit()
        record(action: "Resolver fallo", section: .integrations, detail: world.faults[index].kind.label, result: .success)
    }

    // MARK: - Scenarios

    var scenarios: [LabScenario] { LabScenario.library + world.customScenarios }

    func saveScenario(_ scenario: LabScenario) {
        if let index = world.customScenarios.firstIndex(where: { $0.id == scenario.id }) {
            world.customScenarios[index] = scenario
        } else {
            world.customScenarios.append(scenario)
        }
        commit()
        record(action: "Guardar escenario", section: .scenarios, detail: scenario.name, result: .success)
    }

    func deleteScenario(id: String) {
        world.customScenarios.removeAll { $0.id == id }
        commit()
        record(action: "Eliminar escenario", section: .scenarios, detail: id, result: .warning)
    }

    /// Builds a whole network in one shot. Everything it writes is regular test data that
    /// can be edited or wiped like anything else.
    func load(scenario: LabScenario) {
        world.mode = .test
        let stamp = Int(Date().timeIntervalSince1970) % 100_000
        var createdStations: [LabStation] = []

        if world.regions.isEmpty {
            world.regions.append(Region(id: "labreg-\(stamp)", name: "Región de pruebas", stationIds: []))
        }
        let regionId = world.regions[0].id

        for stationIndex in 0..<max(1, scenario.stations) {
            let id = "labest-\(stamp)-\(stationIndex)"
            let station = LabStation(
                id: id,
                code: "PRB-\(String(format: "%02d", world.stations.count + stationIndex + 1))",
                name: "Estación Prueba \(world.stations.count + stationIndex + 1)",
                city: "CDMX",
                state: "Ciudad de México",
                address: "Av. de Pruebas \(100 + stationIndex)",
                regionId: regionId,
                openedAt: now,
                maxVehicles: max(scenario.vehicles, HRRules.maxVehiclesPerStation),
                plannedVehicles: scenario.vehicles + scenario.incomingVehicles,
                lifecycle: .active,
                driversPerVehicle: world.shiftConfig.driversPerVehicle,
                supervisorsRequired: scenario.supervisors,
                maintenanceRequired: scenario.maintenance,
                managerId: nil,
                activeBlocks: ShiftBlock.allCases,
                createdAt: now
            )
            world.stations.append(station)
            createdStations.append(station)
        }

        guard let primary = createdStations.first else { return }

        for index in 0..<scenario.vehicles {
            world.vehicles.append(makeVehicle(index: index, stamp: stamp, stationId: primary.id, stage: .available))
        }
        for index in 0..<scenario.incomingVehicles {
            var unit = makeVehicle(index: 500 + index, stamp: stamp, stationId: primary.id, stage: .transit)
            unit.operationStartAt = now.addingTimeInterval(TimeInterval(scenario.incomingInDays * 86400))
            world.vehicles.append(unit)
        }

        let blocks = ShiftBlock.allCases
        for index in 0..<scenario.drivers {
            let block = blocks[index % blocks.count]
            let user = makeUser(
                index: index,
                stamp: stamp,
                role: .driver,
                stationId: primary.id,
                regionId: regionId,
                block: block
            )
            world.users.append(user)
            createFile(for: user)
        }
        for index in 0..<scenario.supervisors {
            world.users.append(
                makeUser(
                    index: index,
                    stamp: stamp,
                    role: .supervisor,
                    stationId: primary.id,
                    regionId: regionId,
                    block: index % 2 == 0 ? .weekdayMorning : .weekdayEvening
                )
            )
        }
        for index in 0..<scenario.maintenance {
            world.users.append(
                makeUser(index: index, stamp: stamp, role: .maintenance, stationId: primary.id, regionId: regionId, block: .weekdayMorning)
            )
        }
        // One recruitment desk per station, never a shared one: recruitment is a
        // department of the station, so a scenario cannot create more desks than
        // stations without leaving two people on the same vacancies.
        for (index, station) in createdStations.prefix(max(0, scenario.recruiters)).enumerated() {
            world.users.append(
                makeUser(index: index, stamp: stamp, role: .recruiter, stationId: station.id, regionId: regionId, block: nil)
            )
        }

        // Every station also needs the one manager that answers for it.
        for (index, station) in createdStations.enumerated() {
            world.users.append(
                makeUser(index: index, stamp: stamp, role: .manager, stationId: station.id, regionId: regionId, block: nil)
            )
        }
        for index in 0..<scenario.candidates {
            world.prospects.append(makeProspect(index: index, stamp: stamp, stationId: primary.id))
        }

        commit()
        fleet?.adoptEnvironment()
        record(
            action: "Cargar escenario",
            section: .scenarios,
            detail: "\(scenario.name): \(scenario.stations) estación(es), \(scenario.vehicles) unidades, \(scenario.drivers) conductores",
            result: .success
        )
        notify("Escenario «\(scenario.name)» cargado", tone: .success)
        for station in createdStations { checkCoverage(stationId: station.id) }
    }

    private func makeVehicle(index: Int, stamp: Int, stationId: String, stage: LabVehicleStage) -> LabVehicle {
        let models = [("BYD", "Dolphin Mini"), ("BYD", "Yuan Plus"), ("Nissan", "Leaf"), ("JAC", "E10X")]
        let pick = models[index % models.count]
        let number = world.vehicles.count + index + 1
        let code = "PRB-\(String(format: "%03d", number))"
        return LabVehicle(
            id: "labveh-\(stamp)-\(index)",
            internalNumber: code,
            brand: pick.0,
            model: pick.1,
            year: 2025,
            vin: LabRules.generateVin(seed: stamp + index),
            plates: LabRules.generatePlates(seed: stamp + index),
            odometerKm: 1000 + index * 137,
            batteryPct: 80 + (index % 20),
            rangeKm: 300,
            stationId: stationId,
            stage: stage,
            incorporatedAt: now,
            operationStartAt: now,
            qrCode: code,
            occupiedBy: nil,
            photoOdometerKm: nil,
            telemetryOdometerKm: nil,
            lastTelemetryAt: nil,
            createdAt: now
        )
    }

    private static let sampleFirstNames = [
        "Alejandro", "Brenda", "Cristian", "Daniela", "Emiliano", "Fernanda", "Gerardo", "Hilda",
        "Ismael", "Jazmín", "Kevin", "Lucía", "Marcos", "Nadia", "Osvaldo", "Paola",
    ]

    private static let sampleLastNames = [
        "Hernández", "García", "Martínez", "López", "Sánchez", "Ramírez", "Torres", "Flores",
        "Rivera", "Gómez", "Díaz", "Cruz", "Morales", "Reyes", "Gutiérrez", "Ortiz",
    ]

    private func sampleName(_ index: Int) -> String {
        let first = Self.sampleFirstNames[index % Self.sampleFirstNames.count]
        let last = Self.sampleLastNames[(index / 3) % Self.sampleLastNames.count]
        let second = Self.sampleLastNames[(index / 5 + 4) % Self.sampleLastNames.count]
        return "\(first) \(last) \(second)"
    }

    private func makeUser(
        index: Int,
        stamp: Int,
        role: StaffRole,
        stationId: String?,
        regionId: String?,
        block: ShiftBlock?
    ) -> LabUser {
        let name = sampleName(index + role.rawValue.count)
        let prefix = role.rawValue.prefix(3).uppercased()
        let serial = world.users.filter { $0.role == role }.count + index + 1
        let id = "labusr-\(stamp)-\(role.rawValue)-\(index)"
        return LabUser(
            id: id,
            name: name,
            employeeNumber: "PRB-\(prefix)-\(String(format: "%04d", serial))",
            email: "prueba.\(role.rawValue).\(serial)@turnoev.mx",
            phone: "55\(String(format: "%08d", (stamp + index * 37) % 99_999_999))",
            password: "Prueba14",
            role: role,
            stationId: stationId,
            regionId: regionId,
            block: block,
            photoData: nil,
            status: .active,
            employment: .active,
            hiredAt: now,
            driverId: role == .driver ? "labdrv-\(stamp)-\(index)" : nil,
            createdAt: now,
            testRole: nil
        )
    }

    private func makeProspect(index: Int, stamp: Int, stationId: String) -> Prospect {
        let stages: [RecruitStage] = [.lead, .contacted, .prequalified, .interviewed, .documents]
        let serial: Int = (stamp + index * 91) % 99_999_999
        let phone: String = "55" + String(format: "%08d", serial)
        return Prospect(
            id: "labpro-\(stamp)-\(index)",
            name: sampleName(index + 7),
            phone: phone,
            email: "candidato.prueba.\(index)@correo.mx",
            city: "CDMX",
            age: 25 + index % 20,
            curp: "",
            stationId: stationId,
            requestedBlock: ShiftBlock.allCases[index % ShiftBlock.allCases.count],
            experienceYears: index % 6,
            platforms: index % 2 == 0 ? ["Uber"] : ["Uber", "DiDi"],
            hasLicense: true,
            source: LeadSource.allCases[index % LeadSource.allCases.count],
            campaignId: nil,
            createdAt: now,
            stage: stages[index % stages.count],
            contactedAt: nil,
            screening: nil,
            interview: nil,
            documents: [],
            authorizedAt: nil,
            hiringVerdict: nil,
            hiringNote: nil,
            verdictAt: nil,
            hiredAt: nil,
            lossReason: nil,
            lossNote: nil,
            ownerName: LabRules.adminAccount.name,
            notes: "Candidato generado por escenario de pruebas.",
            history: []
        )
    }

    // MARK: - Reset

    enum ResetTarget: String, CaseIterable, Identifiable, Sendable {
        case operation
        case people
        case fleet
        case money
        case documents
        case everything

        var id: String { rawValue }

        var label: String {
            switch self {
            case .operation: "Operación y alertas"
            case .people: "Usuarios y candidatos"
            case .fleet: "Estaciones y flotilla"
            case .money: "Créditos, bonos y finanzas"
            case .documents: "Documentos y evidencias"
            case .everything: "Todo el entorno"
            }
        }

        var detail: String {
            switch self {
            case .operation: "Turnos, incidencias, órdenes, alertas y fallos simulados."
            case .people: "Credenciales, expedientes, candidatos y campañas."
            case .fleet: "Regiones, estaciones, unidades y activos."
            case .money: "Contratos, bonos, metas, liquidaciones y datos bancarios."
            case .documents: "Fotos, archivos y lecturas de OCR."
            case .everything: "Vuelve el entorno de pruebas exactamente a cero."
            }
        }

        var symbol: String {
            switch self {
            case .operation: "gauge.with.dots.needle.bottom.50percent"
            case .people: "person.2.slash.fill"
            case .fleet: "car.2.fill"
            case .money: "banknote.fill"
            case .documents: "doc.badge.gearshape.fill"
            case .everything: "trash.fill"
            }
        }
    }

    func reset(_ target: ResetTarget) {
        let before = world.totalRecords
        switch target {
        case .operation:
            world.incidents = []
            world.orders = []
            world.alerts = []
            world.faults = []
            world.uberFeeds = []
            world.telemetry = []
            world.clockOffsetMinutes = 0
        case .people:
            world.users = []
            world.employeeFiles = []
            world.prospects = []
            world.campaigns = []
            world.appointments = []
        case .fleet:
            world.regions = []
            world.stations = []
            world.vehicles = []
            world.assets = []
        case .money:
            world.credits = []
            world.bonuses = []
            world.goals = []
            world.settlements = []
            world.bankAccounts = []
            world.transfers = []
        case .documents:
            world.documents = []
        case .everything:
            let audit = world.audit
            world = .empty
            world.mode = .test
            world.audit = audit
        }
        world.lastResetAt = Date()
        commit()
        fleet?.clearOperationalData()
        record(
            action: "Reiniciar: \(target.label)",
            section: .reset,
            detail: "\(before - world.totalRecords) registro(s) eliminados. El entorno de producción no se tocó.",
            result: .warning
        )
        notify("\(target.label): entorno reiniciado", tone: .warning)
    }

    func clearAudit() {
        world.audit = []
        commit()
    }

    // MARK: - Audit

    var auditEntries: [LabAuditEntry] { world.audit }

    func auditEntries(section: LabSection?, result: LabResult?) -> [LabAuditEntry] {
        world.audit.filter { entry in
            (section == nil || entry.section == section) && (result == nil || entry.result == result)
        }
    }

    /// Plain-text export of the whole trace, ready to be shared out of the device.
    func exportAudit() -> String {
        var lines: [String] = [
            "TurnoEV · Laboratorio de pruebas",
            "Exportado: \(Fmt.dateLong(Date())) \(Fmt.clockSeconds(Date()))",
            "Entorno: \(world.mode.label)",
            "Registros en el mundo de pruebas: \(world.totalRecords)",
            "",
        ]
        for entry in world.audit {
            var line = "[\(Fmt.dateShort(entry.createdAt)) \(Fmt.clock(entry.createdAt))] "
            line += "\(entry.result.label.uppercased()) · \(entry.section.label) · \(entry.action) — \(entry.detail)"
            if let error = entry.errorMessage { line += " | Respuesta: \(error)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    func record(
        action: String,
        section: LabSection,
        detail: String,
        result: LabResult,
        error: String? = nil
    ) {
        world.audit.insert(
            LabAuditEntry(
                id: "labaud-\(UUID().uuidString.prefix(8))",
                action: action,
                section: section,
                actor: LabRules.adminAccount.name,
                detail: detail,
                result: result,
                errorMessage: error,
                createdAt: Date()
            ),
            at: 0
        )
        if world.audit.count > 500 { world.audit.removeLast(world.audit.count - 500) }
        LabPersistence.save(world)
        LabRuntime.install(world)
    }

    private func fail(_ action: String, section: LabSection, error: String) {
        record(action: action, section: section, detail: "Operación rechazada", result: .failure, error: error)
        notify(error, tone: .failure)
    }

    // MARK: - Plumbing

    private func commit() {
        LabPersistence.save(world)
        LabRuntime.install(world)
    }

    func notify(_ text: String, tone: LabMessage.Tone) {
        lastMessage = LabMessage(id: UUID().uuidString, text: text, tone: tone)
    }
}

/// Toast surfaced by the console after an action.
nonisolated struct LabMessage: Identifiable, Sendable {
    enum Tone: Sendable {
        case success
        case warning
        case failure
    }

    let id: String
    let text: String
    let tone: Tone
}
