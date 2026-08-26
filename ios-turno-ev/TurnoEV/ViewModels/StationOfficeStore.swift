import Foundation
import Observation

/// Back office of one station, shared by every role that works inside it: the supervisor
/// who runs the operation, the technician who executes work orders and the driver who
/// asks for a bank change. Hiring is not here — the recruitment desk of the station owns
/// that process end to end and this office only receives the finished employee file.
@Observable
final class StationOfficeStore {
    // MARK: - Persisted shape

    nonisolated private struct PersistedState: Codable, Sendable {
        var seedKey: String
        var activeVehicles: Int
        var files: [EmployeeFile]
        var candidates: [Candidate]
        var incorporations: [VehicleIncorporation]
        var bankRequests: [BankChangeRequest]
        var assets: [StationAsset]
        var orders: [WorkOrder]
        var hiringDurations: [Int]
        var audit: [AuditEntry]
    }

    // MARK: - Identity

    let station: Station
    private let fleet: FleetStore
    /// Who is writing. Everything sensitive is signed with this identity.
    private(set) var actor: StaffAccount?

    var now: Date { fleet.now }

    // MARK: - State

    var activeVehicles: Int = 0
    var files: [EmployeeFile] = []
    var candidates: [Candidate] = []
    var incorporations: [VehicleIncorporation] = []
    var bankRequests: [BankChangeRequest] = []
    var assets: [StationAsset] = []
    var orders: [WorkOrder] = []
    /// Days each historical hire took, from candidate registration to contract.
    var hiringDurations: [Int] = []
    var audit: [AuditEntry] = []
    private var seedKey: String = ""

    private var storageKey: String { "turnoev.office.v1.\(station.id)" }

    private var actorName: String { actor?.name ?? "Sistema" }
    private var actorRole: StaffRole { actor?.role ?? .supervisor }

    init(station: Station, fleet: FleetStore, actor: StaffAccount?) {
        self.station = station
        self.fleet = fleet
        self.actor = actor
        load()
    }

    func updateActor(_ account: StaffAccount?) {
        actor = account
    }

    // MARK: - Lifecycle

    func refresh() {
        if seedKey != currentSeedKey { rebuild() }
        ingestRecruitmentHires()
        syncLiveDriverFile()
    }

    private var currentSeedKey: String {
        let week = ShiftRules.calendar.ordinality(of: .weekOfYear, in: .era, for: now) ?? 0
        return "\(station.id)|\(week)"
    }

    private func rebuild() {
        let supervisor = StaffDirectory.accounts.first {
            $0.role == .supervisor && $0.stationId == station.id
        }
        let snapshot = StationOfficeMockData.snapshot(
            station: station,
            supervisorName: supervisor?.name ?? actorName,
            supervisorId: supervisor?.id ?? actor?.id ?? "acc-sup",
            liveDriver: fleet.driver.stationId == station.id ? fleet.driver : nil,
            now: now
        )
        activeVehicles = snapshot.activeVehicles
        files = snapshot.files
        candidates = snapshot.candidates
        incorporations = snapshot.incorporations
        bankRequests = snapshot.bankRequests
        assets = snapshot.assets
        orders = snapshot.orders
        hiringDurations = snapshot.hiringDurations
        audit = snapshot.audit
        seedKey = currentSeedKey
        registerClabes()
        persist()
    }

    func regenerate() {
        rebuild()
    }

    /// Keeps the file of the credential running the driver app in sync with the session.
    private func syncLiveDriverFile() {
        let driver = fleet.driver
        guard driver.stationId == station.id else { return }
        guard let index = files.firstIndex(where: { $0.id == driver.id }) else { return }
        if !files[index].isLiveSession {
            files[index].isLiveSession = true
            persist()
        }
    }

    // MARK: - Reads: people

    var activeFiles: [EmployeeFile] {
        files.filter { $0.status != .terminated }
    }

    func file(id: String?) -> EmployeeFile? {
        guard let id else { return nil }
        return files.first { $0.id == id }
    }

    func files(block: ShiftBlock?) -> [EmployeeFile] {
        activeFiles.filter { block == nil || $0.block == block }
    }

    // MARK: - Reads decided by a date
    //
    // Every read below answers differently depending on what day it is, because a document
    // expires on a date and an expired document is what makes a driver unavailable. They
    // therefore take `now` explicitly instead of reaching for `self.now`.
    //
    // Hiding the hour inside a computed property is what made these reads dangerous: a view
    // that touched `office.incompleteFiles` registered a dependency on the global clock
    // without a single mention of time in its own body, and the day it stopped registering
    // that dependency the number would have frozen with no error anywhere.

    func availableFiles(block: ShiftBlock, now: Date) -> [EmployeeFile] {
        files(block: block).filter { $0.isOperationallyAvailable(now: now) }
    }

    /// Employees the station cannot count on today, with the reason.
    func unavailableFiles(now: Date) -> [EmployeeFile] {
        activeFiles.filter { !$0.isOperationallyAvailable(now: now) }
    }

    func incompleteFiles(now: Date) -> [EmployeeFile] {
        activeFiles.filter { $0.completionPct(now: now) < 100 }
    }

    func expiringDocumentFiles(now: Date) -> [EmployeeFile] {
        activeFiles.filter { !$0.expiringDocuments(now: now).isEmpty }
    }

    func expiredDocumentFiles(now: Date) -> [EmployeeFile] {
        activeFiles.filter { !$0.expiredDocuments(now: now).isEmpty }
    }

    func searchFiles(_ query: String, block: ShiftBlock? = nil, onlyIssues: Bool = false, now: Date) -> [EmployeeFile] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return activeFiles
            .filter { block == nil || $0.block == block }
            .filter { !onlyIssues || $0.completionPct(now: now) < 100 || !$0.expiringDocuments(now: now).isEmpty }
            .filter { file in
                guard !cleaned.isEmpty else { return true }
                return file.name.localizedStandardContains(cleaned)
                    || file.employeeNumber.localizedStandardContains(cleaned)
                    || file.curp.localizedStandardContains(cleaned)
                    || file.rfc.localizedStandardContains(cleaned)
            }
            .sorted { lhs, rhs in
                if lhs.isLiveSession != rhs.isLiveSession { return lhs.isLiveSession }
                return lhs.name < rhs.name
            }
    }

    // MARK: - Reads: candidates

    func candidates(stage: CandidateStage?) -> [Candidate] {
        candidates
            .filter { stage == nil || $0.stage == stage }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func candidate(id: String?) -> Candidate? {
        guard let id else { return nil }
        return candidates.first { $0.id == id }
    }

    func count(stage: CandidateStage) -> Int {
        candidates.filter { $0.stage == stage }.count
    }

    var candidatesInProcess: [Candidate] {
        candidates.filter { $0.stage.isInProcess }
    }

    var pendingInterviews: [Candidate] {
        candidates.filter { $0.stage == .interview && ($0.interview?.isComplete != true) }
    }

    func pendingDocumentCandidates(now: Date) -> [Candidate] {
        candidates.filter { $0.stage == .documents && !$0.missingDocuments(now: now).isEmpty }
    }

    // MARK: - Reads: capacity

    var incomingVehicles: Int {
        incorporations.filter { $0.stage.isIncoming }.reduce(0) { $0 + $1.units }
    }

    /// How many drivers the station has against how many its units demand.
    ///
    /// `available` is decided by document expiry, so the whole plan turns on a date.
    func capacityPlan(now: Date) -> CapacityPlan {
        let perBlock = HRRules.requiredDrivers(activeVehicles: activeVehicles) / HRRules.driversPerVehicle
        let onboardingByBlock = Dictionary(grouping: candidatesInProcess, by: \.requestedBlock)
            .mapValues(\.count)

        let blocks = ShiftBlock.allCases.map { block in
            BlockCoverage(
                block: block,
                required: perBlock,
                available: availableFiles(block: block, now: now).count,
                hired: files(block: block).count,
                onboarding: onboardingByBlock[block] ?? 0
            )
        }

        return CapacityPlan(
            activeVehicles: activeVehicles,
            incomingVehicles: incomingVehicles,
            requiredDrivers: HRRules.requiredDrivers(activeVehicles: activeVehicles),
            hiredDrivers: activeFiles.count,
            availableDrivers: activeFiles.filter { $0.isOperationallyAvailable(now: now) }.count,
            onboardingDrivers: candidatesInProcess.count,
            blocks: blocks
        )
    }

    var pipeline: HiringPipeline {
        let interviewed = candidates.filter { $0.interview?.interviewedAt != nil }.count
        let documented = candidates.filter { $0.stage.order >= CandidateStage.documents.order && $0.stage != .rejected }.count
        let approved = candidates.filter { $0.stage.order >= CandidateStage.approved.order && $0.stage != .rejected }.count
        let hired = candidates.filter { $0.stage == .hired }.count
        let average = hiringDurations.isEmpty
            ? 12
            : Int((Double(hiringDurations.reduce(0, +)) / Double(hiringDurations.count)).rounded())
        return HiringPipeline(
            candidates: candidates.count,
            interviewed: interviewed,
            documented: documented,
            approved: approved,
            hired: hired,
            rejected: candidates.filter { $0.stage == .rejected }.count,
            averageHiringDays: average
        )
    }

    /// Recruitment target for today's gap.
    func currentTarget(now: Date) -> RecruitmentTarget {
        HRRules.target(neededDrivers: capacityPlan(now: now).deficit, pipeline: pipeline, daysAvailable: nil)
    }

    /// Recruitment target for the units that will start operating.
    func target(for incorporation: VehicleIncorporation, now: Date) -> RecruitmentTarget {
        HRRules.target(
            neededDrivers: incorporation.requiredDrivers,
            pipeline: pipeline,
            daysAvailable: incorporation.daysToOperation(now: now)
        )
    }

    // MARK: - Reads: workshop

    func assets(category: AssetCategory?) -> [StationAsset] {
        assets
            .filter { category == nil || $0.category == category }
            .sorted { $0.code < $1.code }
    }

    func asset(id: String?) -> StationAsset? {
        guard let id else { return nil }
        return assets.first { $0.id == id }
    }

    func orders(status: WorkOrderStatus?) -> [WorkOrder] {
        orders
            .filter { status == nil || $0.status == status }
            .sorted { lhs, rhs in
                lhs.priority.weight == rhs.priority.weight
                    ? lhs.assignedAt > rhs.assignedAt
                    : lhs.priority.weight > rhs.priority.weight
            }
    }

    func order(id: String?) -> WorkOrder? {
        guard let id else { return nil }
        return orders.first { $0.id == id }
    }

    var openOrders: [WorkOrder] {
        orders(status: nil).filter { $0.status.isOpen }
    }

    var ordersAwaitingValidation: [WorkOrder] {
        orders(status: .finished)
    }

    var workshopMetrics: WorkshopMetrics {
        let vehicleAssets = assets.filter { $0.category == .vehicles }
        let resolved = orders.compactMap(\.actualMinutes)
        let closed = orders.filter { $0.status == .closed }
        return WorkshopMetrics(
            pending: orders.filter { $0.status == .pending }.count,
            inProgress: orders.filter { $0.status == .inProgress }.count,
            waiting: orders.filter { $0.status == .waiting }.count,
            awaitingValidation: orders.filter { $0.status == .finished }.count,
            returned: orders.filter { $0.status == .returned }.count,
            closed: closed.count,
            criticalHandled: orders.filter { $0.priority == .critical && !$0.status.isOpen }.count,
            preventiveDone: orders.filter { $0.isPreventive && $0.status == .closed }.count,
            preventiveProgrammed: max(1, orders.filter(\.isPreventive).count),
            averageResolutionMinutes: resolved.isEmpty ? 0 : resolved.reduce(0, +) / resolved.count,
            recoveredVehicles: closed.filter { $0.vehicleId != nil }.count,
            fleetAvailable: vehicleAssets.filter { $0.state == .operational }.count,
            fleetTotal: max(1, vehicleAssets.count),
            onTimeClosed: closed.filter(\.wasOnTime).count
        )
    }

    var bonusIndex: MaintenanceBonusIndex {
        WorkshopRules.bonus(metrics: workshopMetrics)
    }

    // MARK: - Reads: banking

    var openBankRequests: [BankChangeRequest] {
        bankRequests.filter { $0.status.isOpen }.sorted { $0.createdAt > $1.createdAt }
    }

    func bankRequests(driverId: String) -> [BankChangeRequest] {
        bankRequests.filter { $0.driverId == driverId }.sorted { $0.createdAt > $1.createdAt }
    }

    func validations(for request: BankChangeRequest) -> [BankValidation] {
        request.validations(
            clabeTaken: NationalBankRegistry.isTaken(clabe: request.clabe, excluding: request.driverId),
            fileHolder: file(id: request.driverId)?.name
        )
    }

    // MARK: - Reads: alerts

    /// The exception board. The supervisor should never have to read full lists to find
    /// what is broken: every rule that matters produces its own alert here.
    ///
    /// Mixed cadence, and the finer one governs: most of the board turns on a date —
    /// expiry, days to an incorporation, coverage deficit — but a work order goes past its
    /// commitment at an arbitrary hour, so a consumer of this board has to listen by the
    /// minute to stay honest.
    func alerts(now: Date) -> [OpsAlert] {
        var result: [OpsAlert] = []
        let plan = capacityPlan(now: now)

        for coverage in plan.blocks where coverage.deficit > 0 {
            result.append(
                OpsAlert(
                    id: "cov-\(coverage.block.rawValue)",
                    level: coverage.level,
                    module: .people,
                    title: "Déficit \(coverage.block.label.lowercased()): \(coverage.deficit) conductores",
                    detail: "\(coverage.available) disponibles reales para \(coverage.required) unidades. \(coverage.onboarding) en contratación para este bloque.",
                    createdAt: now
                )
            )
        }

        for incorporation in incorporations where incorporation.stage.isIncoming {
            let target = target(for: incorporation, now: now)
            guard target.level.demandsAction || target.neededDrivers > 0 else { continue }
            let days = incorporation.daysToOperation(now: now)
            result.append(
                OpsAlert(
                    id: "inc-\(incorporation.id)",
                    level: target.level,
                    module: .people,
                    title: "\(incorporation.units) unidades operan en \(days) días",
                    detail: "Requieren \(incorporation.requiredDrivers) conductores. Contratar toma \(target.averageHiringDays) días en promedio.",
                    createdAt: now
                )
            )
        }

        let expired = expiredDocumentFiles(now: now).count
        if expired > 0 {
            result.append(
                OpsAlert(
                    id: "doc-expired",
                    level: .critical,
                    module: .people,
                    title: "\(expired) conductores con documentación vencida",
                    detail: "No pueden tomar turno hasta actualizar licencia o identificación.",
                    createdAt: now
                )
            )
        }

        let expiring = expiringDocumentFiles(now: now).count
        if expiring > 0 {
            result.append(
                OpsAlert(
                    id: "doc-expiring",
                    level: .preventive,
                    module: .people,
                    title: "\(expiring) documentos por vencer",
                    detail: "Vencen dentro de los próximos \(HRRules.documentWarningDays) días.",
                    createdAt: now
                )
            )
        }

        let incomplete = incompleteFiles(now: now).count
        if incomplete > 0 {
            result.append(
                OpsAlert(
                    id: "file-incomplete",
                    level: .informative,
                    module: .people,
                    title: "\(incomplete) expedientes incompletos",
                    detail: "Falta documentación de la lista de contratación.",
                    createdAt: now
                )
            )
        }

        for request in openBankRequests {
            result.append(
                OpsAlert(
                    id: "bank-\(request.id)",
                    level: request.status == .requested ? .important : .preventive,
                    module: .banking,
                    title: "Solicitud bancaria de \(Fmt.firstName(request.driverName))",
                    detail: "\(request.bank) · \(request.maskedClabe) · \(request.status.label.lowercased())",
                    createdAt: request.createdAt
                )
            )
        }

        for order in orders where order.isOverdue(now: now) {
            result.append(
                OpsAlert(
                    id: "wo-\(order.id)",
                    level: order.priority == .critical ? .critical : .important,
                    module: .workshop,
                    title: "\(order.folio) fuera de tiempo · \(order.assetCode)",
                    detail: "\(order.problem)",
                    createdAt: order.assignedAt
                )
            )
        }

        let downAssets = assets.filter { $0.state == .down && $0.category != .vehicles }
        for asset in downAssets {
            result.append(
                OpsAlert(
                    id: "asset-\(asset.id)",
                    level: .important,
                    module: .workshop,
                    title: "\(asset.name) fuera de servicio",
                    detail: "Activo de \(asset.category.label.lowercased()) sin operación.",
                    createdAt: asset.lastServiceAt
                )
            )
        }

        let downVehicles = assets.filter { $0.state == .down && $0.category == .vehicles }.count
        if downVehicles > 0 {
            result.append(
                OpsAlert(
                    id: "fleet-down",
                    level: downVehicles > 2 ? .important : .preventive,
                    module: .fleet,
                    title: "\(downVehicles) unidades fuera de servicio",
                    detail: "Reducen la cobertura posible de los cuatro bloques.",
                    createdAt: now
                )
            )
        }

        if !ordersAwaitingValidation.isEmpty {
            result.append(
                OpsAlert(
                    id: "wo-validate",
                    level: .important,
                    module: .workshop,
                    title: "\(ordersAwaitingValidation.count) reportes de taller por validar",
                    detail: "El técnico envió el trabajo terminado y espera tu firma.",
                    createdAt: now
                )
            )
        }

        return result.sorted { lhs, rhs in
            lhs.level.weight == rhs.level.weight ? lhs.createdAt > rhs.createdAt : lhs.level.weight > rhs.level.weight
        }
    }

    func criticalAlerts(now: Date) -> [OpsAlert] { alerts(now: now).filter { $0.level.demandsAction } }

    // MARK: - Actions: candidates

    @discardableResult
    func addCandidate(_ candidate: Candidate) -> Candidate {
        candidates.insert(candidate, at: 0)
        log(
            action: .candidateCreated,
            subject: candidate.name,
            newValue: "\(candidate.requestedBlock.label) · \(candidate.phone)"
        )
        persist()
        return candidate
    }

    func update(candidate: Candidate) {
        guard let index = candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        candidates[index] = candidate
        persist()
    }

    func setCandidateDocument(_ kind: DocumentKind, status: DocumentStatus, for candidateId: String) {
        guard let index = candidates.firstIndex(where: { $0.id == candidateId }) else { return }
        var documents = candidates[index].documents
        if let position = documents.firstIndex(where: { $0.kind == kind }) {
            let previous = documents[position].status
            documents[position].status = status
            documents[position].uploadedAt = status == .delivered ? now : documents[position].uploadedAt
            documents[position].uploadedBy = actorName
            if previous != status {
                documents[position].versions.append(
                    DocumentVersion(
                        id: "ver-\(UUID().uuidString.prefix(6))",
                        uploadedAt: now,
                        uploadedBy: actorName,
                        note: "\(previous.label) → \(status.label)"
                    )
                )
            }
        } else {
            documents.append(
                StaffDocument(kind: kind, status: status, uploadedAt: now, uploadedBy: actorName)
            )
        }
        candidates[index].documents = documents
        log(action: .documentUpdated, subject: "\(candidates[index].name) · \(kind.label)", newValue: status.label)
        persist()
    }

    // MARK: - Actions: hires received from recruitment

    /// Opens the employee file of every alta the recruitment desk already signed. The
    /// station does not decide anything here: it only registers what recruitment closed,
    /// exactly like the bank registry receives a CLABE from another role.
    private func ingestRecruitmentHires() {
        let packets = RecruitmentHandoff.awaitingFile(stationId: station.id)
        guard !packets.isEmpty else { return }

        var didChange = false
        for packet in packets {
            guard let hiredAt = packet.hiredAt else { continue }
            let fileId = "drv-rec-\(packet.prospectId)"
            guard !files.contains(where: { $0.id == fileId }) else {
                RecruitmentHandoff.markIngested(prospectId: packet.prospectId, at: now)
                continue
            }

            let file = EmployeeFile(
                id: fileId,
                name: packet.name,
                employeeNumber: packet.employeeNumber ?? "\(station.code)-\(files.count + 1)",
                photoAsset: nil,
                stationId: station.id,
                block: packet.block,
                hiredAt: hiredAt,
                status: .active,
                supervisorName: packet.recruiterName,
                phone: packet.phone,
                curp: packet.curp ?? "",
                rfc: "",
                documents: packet.documents ?? [],
                events: [
                    FileEvent(
                        id: "evt-\(packet.prospectId)",
                        kind: .hire,
                        date: hiredAt,
                        detail: "Alta firmada por reclutamiento · bloque \(packet.block.label)",
                        author: packet.recruiterName
                    )
                ],
                bank: nil,
                isLiveSession: false
            )
            files.insert(file, at: 0)
            hiringDurations.append(max(1, Int(hiredAt.timeIntervalSince(packet.sentAt) / 86_400)))
            log(
                action: .hire,
                subject: packet.name,
                newValue: "\(file.employeeNumber) · \(packet.block.label)",
                authorizerName: "Reclutamiento \(station.code)"
            )
            RecruitmentHandoff.markIngested(prospectId: packet.prospectId, at: now)
            didChange = true
        }

        if didChange { persist() }
    }

    /// Legacy path kept for the lab: turns a seeded candidate into an employee file.
    /// Production hires never enter here — they arrive already signed from recruitment.
    @discardableResult
    func hire(candidateId: String, employeeNumber: String) -> EmployeeFile? {
        guard let index = candidates.firstIndex(where: { $0.id == candidateId }) else { return nil }
        var candidate = candidates[index]
        guard candidate.missingDocuments(now: now).isEmpty else { return nil }

        candidate.stage = .hired
        candidate.hiredAt = now
        candidates[index] = candidate

        let file = EmployeeFile(
            id: "drv-h\(UUID().uuidString.prefix(6))",
            name: candidate.name,
            employeeNumber: employeeNumber,
            photoAsset: nil,
            stationId: station.id,
            block: candidate.requestedBlock,
            hiredAt: now,
            status: .active,
            supervisorName: actorName,
            phone: candidate.phone,
            curp: candidate.curp,
            rfc: candidate.rfc,
            documents: candidate.documents,
            events: [
                FileEvent(
                    id: "evt-\(UUID().uuidString.prefix(6))",
                    kind: .hire,
                    date: now,
                    detail: "Alta como conductor · bloque \(candidate.requestedBlock.label)",
                    author: actorName
                )
            ],
            bank: nil,
            isLiveSession: false
        )
        files.insert(file, at: 0)
        hiringDurations.append(candidate.daysInProcess(now: now))
        log(
            action: .hire,
            subject: candidate.name,
            newValue: "\(employeeNumber) · \(candidate.requestedBlock.label)",
            authorizerName: "Reclutamiento \(station.code)"
        )
        persist()
        return file
    }

    // MARK: - Actions: files

    func setEmploymentStatus(_ status: EmploymentStatus, for fileId: String, detail: String) {
        guard let index = files.firstIndex(where: { $0.id == fileId }) else { return }
        let previous = files[index].status
        files[index].status = status
        files[index].events.insert(
            FileEvent(
                id: "evt-\(UUID().uuidString.prefix(6))",
                kind: status == .terminated ? .termination : (status == .suspended ? .suspension : .documentUpdate),
                date: now,
                detail: detail,
                author: actorName
            ),
            at: 0
        )
        log(
            action: status == .terminated ? .termination : .permissionChange,
            subject: files[index].name,
            previousValue: previous.label,
            newValue: status.label,
            reason: detail
        )
        persist()
    }

    func changeBlock(_ block: ShiftBlock, for fileId: String, reason: String) {
        guard let index = files.firstIndex(where: { $0.id == fileId }) else { return }
        let previous = files[index].block
        guard previous != block else { return }
        files[index].block = block
        files[index].events.insert(
            FileEvent(
                id: "evt-\(UUID().uuidString.prefix(6))",
                kind: .shiftChange,
                date: now,
                detail: "\(previous.label) → \(block.label). \(reason)",
                author: actorName
            ),
            at: 0
        )
        log(
            action: .shiftChange,
            subject: files[index].name,
            previousValue: previous.label,
            newValue: block.label,
            reason: reason
        )
        persist()
    }

    func setDocument(_ kind: DocumentKind, status: DocumentStatus, expiresAt: Date?, for fileId: String) {
        guard let index = files.firstIndex(where: { $0.id == fileId }) else { return }
        var documents = files[index].documents
        if let position = documents.firstIndex(where: { $0.kind == kind }) {
            let previous = documents[position]
            documents[position].status = status
            documents[position].expiresAt = expiresAt ?? previous.expiresAt
            documents[position].uploadedAt = now
            documents[position].uploadedBy = actorName
            documents[position].versions.append(
                DocumentVersion(
                    id: "ver-\(UUID().uuidString.prefix(6))",
                    uploadedAt: now,
                    uploadedBy: actorName,
                    note: "Sustituye versión de \(previous.uploadedAt.map(Fmt.dateShort) ?? "origen")"
                )
            )
        } else {
            documents.append(
                StaffDocument(
                    kind: kind,
                    status: status,
                    uploadedAt: now,
                    issuedAt: now,
                    expiresAt: expiresAt,
                    uploadedBy: actorName
                )
            )
        }
        files[index].documents = documents
        files[index].events.insert(
            FileEvent(
                id: "evt-\(UUID().uuidString.prefix(6))",
                kind: .documentUpdate,
                date: now,
                detail: "\(kind.label): \(status.label)",
                author: actorName
            ),
            at: 0
        )
        log(action: .documentUpdated, subject: "\(files[index].name) · \(kind.label)", newValue: status.label)
        persist()
    }

    func addEvent(_ kind: FileEventKind, detail: String, for fileId: String) {
        guard let index = files.firstIndex(where: { $0.id == fileId }) else { return }
        files[index].events.insert(
            FileEvent(
                id: "evt-\(UUID().uuidString.prefix(6))",
                kind: kind,
                date: now,
                detail: detail,
                author: actorName
            ),
            at: 0
        )
        persist()
    }

    // MARK: - Actions: banking

    enum BankRegistrationResult: Sendable {
        case registered
        case duplicated
        case invalidClabe
        case unknownFile

        var message: String? {
            switch self {
            case .registered: nil
            case .duplicated: "Esta cuenta bancaria ya se encuentra registrada en otro expediente. Contacta a Administración."
            case .invalidClabe: "La CLABE debe tener 18 dígitos."
            case .unknownFile: "No encontramos el expediente del conductor."
            }
        }
    }

    /// Initial bank registration. Only the supervisor of the station can do it, and the
    /// CLABE must be unique across the whole national network.
    @discardableResult
    func registerBank(
        fileId: String,
        bank: String,
        clabe: String,
        accountNumber: String,
        holder: String,
        rfc: String,
        hasProof: Bool
    ) -> BankRegistrationResult {
        guard let index = files.firstIndex(where: { $0.id == fileId }) else { return .unknownFile }
        guard HRRules.isValidClabe(clabe) else { return .invalidClabe }
        if NationalBankRegistry.isTaken(clabe: clabe, excluding: fileId) {
            log(
                action: .bankRegistered,
                subject: files[index].name,
                newValue: HRRules.mask(clabe: clabe),
                reason: "Intento bloqueado: CLABE duplicada en la red nacional"
            )
            persist()
            return .duplicated
        }

        let previous = files[index].bank
        files[index].bank = BankAccount(
            bank: bank,
            clabe: clabe,
            accountNumber: accountNumber,
            holder: holder,
            rfc: rfc,
            registeredAt: now,
            registeredBy: actorName,
            status: hasProof ? .verified : .pending,
            hasProof: hasProof
        )
        files[index].events.insert(
            FileEvent(
                id: "evt-\(UUID().uuidString.prefix(6))",
                kind: .bankChange,
                date: now,
                detail: "Alta bancaria \(bank) · \(HRRules.mask(clabe: clabe))",
                author: actorName
            ),
            at: 0
        )
        NationalBankRegistry.register(clabe: clabe, driverId: fileId)
        log(
            action: .bankRegistered,
            subject: files[index].name,
            previousValue: previous.map { "\($0.bank) · \($0.maskedClabe)" },
            newValue: "\(bank) · \(HRRules.mask(clabe: clabe))"
        )
        persist()
        return .registered
    }

    /// Request opened from the driver app. The driver never edits his own account.
    @discardableResult
    func submitBankRequest(
        driverId: String,
        driverName: String,
        bank: String,
        clabe: String,
        holder: String,
        reason: String,
        hasOfficialId: Bool,
        hasBankProof: Bool,
        hasAddressProof: Bool,
        addressMatches: Bool
    ) -> BankChangeRequest {
        let request = BankChangeRequest(
            id: "bnk-\(UUID().uuidString.prefix(6))",
            driverId: driverId,
            driverName: driverName,
            stationId: station.id,
            createdAt: now,
            bank: bank,
            clabe: clabe,
            holder: holder,
            reason: reason,
            hasOfficialId: hasOfficialId,
            hasBankProof: hasBankProof,
            hasAddressProof: hasAddressProof,
            addressMatches: addressMatches,
            status: .requested,
            resolvedAt: nil,
            resolutionNote: nil,
            validatedBy: nil,
            approvedBy: nil
        )
        bankRequests.insert(request, at: 0)
        log(
            action: .bankChangeRequested,
            subject: driverName,
            newValue: "\(bank) · \(HRRules.mask(clabe: clabe))",
            reason: reason
        )
        persist()
        return request
    }

    /// Supervisor validation: the request moves up to the regional manager.
    func validateBankRequest(id: String) {
        guard let index = bankRequests.firstIndex(where: { $0.id == id }) else { return }
        bankRequests[index].status = .review
        bankRequests[index].validatedBy = actorName
        log(action: .bankChangeResolved, subject: bankRequests[index].driverName, newValue: "En revisión de gerencia")
        persist()
    }

    func resolveBankRequest(id: String, approved: Bool, note: String) {
        guard let index = bankRequests.firstIndex(where: { $0.id == id }) else { return }
        bankRequests[index].status = approved ? .approved : .rejected
        bankRequests[index].resolvedAt = now
        bankRequests[index].resolutionNote = note
        bankRequests[index].approvedBy = approved ? actorName : nil
        log(
            action: approved ? .approval : .rejection,
            subject: "Cambio bancario · \(bankRequests[index].driverName)",
            newValue: approved ? "Aprobada" : "Rechazada",
            reason: note
        )
        notifyDriver(
            id: bankRequests[index].driverId,
            title: approved ? "Cambio bancario aprobado" : "Cambio bancario rechazado",
            body: approved
                ? "Tu nueva cuenta quedó autorizada y se aplicará en la siguiente liquidación."
                : note
        )
        persist()
    }

    /// Applies an approved request to the employee file, keeping the previous account.
    func applyBankRequest(id: String) {
        guard let index = bankRequests.firstIndex(where: { $0.id == id }),
              bankRequests[index].status == .approved else { return }
        let request = bankRequests[index]
        guard let fileIndex = files.firstIndex(where: { $0.id == request.driverId }) else { return }

        let previous = files[fileIndex].bank
        if let previous { NationalBankRegistry.release(clabe: previous.clabe) }
        files[fileIndex].bank = BankAccount(
            bank: request.bank,
            clabe: request.clabe,
            accountNumber: String(request.clabe.suffix(10)),
            holder: request.holder,
            rfc: files[fileIndex].rfc,
            registeredAt: now,
            registeredBy: actorName,
            status: .verified,
            hasProof: request.hasBankProof
        )
        files[fileIndex].events.insert(
            FileEvent(
                id: "evt-\(UUID().uuidString.prefix(6))",
                kind: .bankChange,
                date: now,
                detail: "Cuenta anterior \(previous?.maskedClabe ?? "—") sustituida por \(request.maskedClabe)",
                author: actorName
            ),
            at: 0
        )
        NationalBankRegistry.register(clabe: request.clabe, driverId: request.driverId)
        bankRequests[index].status = .applied
        log(
            action: .bankChangeResolved,
            subject: request.driverName,
            previousValue: previous.map { "\($0.bank) · \($0.maskedClabe)" },
            newValue: "\(request.bank) · \(request.maskedClabe)"
        )
        notifyDriver(
            id: request.driverId,
            title: "Cuenta bancaria actualizada",
            body: "Tus pagos se depositarán en \(request.bank) \(request.maskedClabe)."
        )
        persist()
    }

    // MARK: - Actions: workshop

    @discardableResult
    func assignOrder(
        assetId: String,
        problem: String,
        priority: WorkOrderPriority,
        estimatedMinutes: Int,
        isPreventive: Bool
    ) -> WorkOrder? {
        guard let asset = asset(id: assetId) else { return nil }
        let technician = StaffDirectory.accounts.first {
            $0.role == .maintenance && $0.stationId == station.id
        }
        let order = WorkOrder(
            id: "wo-\(UUID().uuidString.prefix(6))",
            folio: "OT-\(String(format: "%04d", 1300 + orders.count))",
            stationId: station.id,
            assetId: asset.id,
            assetName: asset.name,
            assetCode: asset.code,
            category: asset.category,
            problem: problem,
            priority: priority,
            isPreventive: isPreventive,
            assignedAt: now,
            assignedByName: actorName,
            technicianId: technician?.id ?? "acc-mto",
            technicianName: technician?.name ?? "Mantenimiento",
            acceptedAt: nil,
            finishedAt: nil,
            closedAt: nil,
            estimatedMinutes: estimatedMinutes,
            status: .pending,
            workDone: "",
            pendingWork: "",
            observations: "",
            materials: [],
            evidence: [],
            evidenceAssets: [],
            returnReason: nil,
            vehicleId: asset.vehicleId
        )
        orders.insert(order, at: 0)
        log(action: .workOrderAssigned, subject: "\(order.folio) · \(asset.code)", newValue: "\(priority.label) · \(problem)")
        persist()
        return order
    }

    func acceptOrder(id: String) {
        guard let index = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[index].acceptedAt = orders[index].acceptedAt ?? now
        orders[index].status = .inProgress
        persist()
    }

    func setOrderStatus(_ status: WorkOrderStatus, id: String) {
        guard let index = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[index].status = status
        if status == .inProgress { orders[index].acceptedAt = orders[index].acceptedAt ?? now }
        persist()
    }

    func addEvidence(_ data: Data, to id: String) {
        guard let index = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[index].evidence.append(data)
        persist()
    }

    func addMaterial(name: String, quantity: Int, to id: String) {
        guard let index = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[index].materials.append(
            WorkOrderMaterial(id: "mat-\(UUID().uuidString.prefix(6))", name: name, quantity: quantity)
        )
        persist()
    }

    /// The technician sends the report; the supervisor still has to validate it.
    @discardableResult
    func submitReport(id: String, workDone: String, pendingWork: String, observations: String) -> Bool {
        guard let index = orders.firstIndex(where: { $0.id == id }) else { return false }
        orders[index].workDone = workDone
        orders[index].pendingWork = pendingWork
        orders[index].observations = observations
        guard orders[index].canSubmitReport else { return false }
        orders[index].acceptedAt = orders[index].acceptedAt ?? now
        orders[index].finishedAt = now
        orders[index].status = .finished
        persist()
        return true
    }

    func validateOrder(id: String, approved: Bool, note: String) {
        guard let index = orders.firstIndex(where: { $0.id == id }) else { return }
        if approved {
            orders[index].status = .closed
            orders[index].closedAt = now
            orders[index].returnReason = nil
            let assetId = orders[index].assetId
            if let assetIndex = assets.firstIndex(where: { $0.id == assetId }) {
                assets[assetIndex].state = .operational
                assets[assetIndex].lastServiceAt = now
            }
        } else {
            orders[index].status = .returned
            orders[index].returnReason = note
            orders[index].finishedAt = nil
        }
        log(
            action: .workOrderResolved,
            subject: "\(orders[index].folio) · \(orders[index].assetCode)",
            newValue: approved ? "Cerrada" : "Devuelta",
            reason: approved ? nil : note
        )
        persist()
    }

    func setAssetState(_ state: StationAsset.State, id: String) {
        guard let index = assets.firstIndex(where: { $0.id == id }) else { return }
        assets[index].state = state
        persist()
    }

    // MARK: - Actions: incoming units

    func addIncorporation(model: String, units: Int, stage: IncorporationStage, arrivalAt: Date, operationStartAt: Date, note: String) {
        incorporations.append(
            VehicleIncorporation(
                id: "inc-\(UUID().uuidString.prefix(6))",
                stationId: station.id,
                model: model,
                units: units,
                stage: stage,
                arrivalAt: arrivalAt,
                operationStartAt: operationStartAt,
                note: note
            )
        )
        persist()
    }

    func advance(incorporationId: String) {
        guard let index = incorporations.firstIndex(where: { $0.id == incorporationId }) else { return }
        let stages = IncorporationStage.allCases.sorted { $0.order < $1.order }
        guard let position = stages.firstIndex(of: incorporations[index].stage), position + 1 < stages.count else { return }
        incorporations[index].stage = stages[position + 1]
        if incorporations[index].stage == .active {
            activeVehicles += incorporations[index].units
        }
        persist()
    }

    // MARK: - Audit

    func log(
        action: AuditAction,
        subject: String,
        previousValue: String? = nil,
        newValue: String? = nil,
        reason: String? = nil,
        authorizerName: String? = nil
    ) {
        audit.insert(
            AuditEntry(
                id: "aud-\(UUID().uuidString.prefix(8))",
                action: action,
                actorName: actorName,
                actorRole: actorRole,
                stationId: station.id,
                createdAt: now,
                subject: subject,
                previousValue: previousValue,
                newValue: newValue,
                reason: reason,
                authorizerName: authorizerName
            ),
            at: 0
        )
        if audit.count > 400 { audit.removeLast(audit.count - 400) }
    }

    func auditEntries(action: AuditAction?) -> [AuditEntry] {
        audit.filter { action == nil || $0.action == action }
    }

    // MARK: - Helpers

    private func notifyDriver(id: String, title: String, body: String) {
        guard id == fleet.driver.id else { return }
        fleet.pushNotice(kind: .station, title: title, body: body)
    }

    private func registerClabes() {
        for file in files {
            guard let bank = file.bank else { continue }
            NationalBankRegistry.register(clabe: bank.clabe, driverId: file.id)
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            rebuild()
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            seedKey = state.seedKey
            activeVehicles = state.activeVehicles
            files = state.files
            candidates = state.candidates
            incorporations = state.incorporations
            bankRequests = state.bankRequests
            assets = state.assets
            orders = state.orders
            hiringDurations = state.hiringDurations
            audit = state.audit
            if seedKey != currentSeedKey { rebuild() } else { registerClabes() }
        } catch {
            print("No se pudo leer la administración de la estación: \(error.localizedDescription)")
            rebuild()
        }
    }

    private func persist() {
        let state = PersistedState(
            seedKey: seedKey,
            activeVehicles: activeVehicles,
            files: files,
            candidates: candidates,
            incorporations: incorporations,
            bankRequests: bankRequests,
            assets: assets,
            orders: orders,
            hiringDurations: hiringDurations,
            audit: audit
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("No se pudo guardar la administración de la estación: \(error.localizedDescription)")
        }
    }
}

/// National CLABE registry. One bank account can only belong to one driver in the whole
/// network; the check runs before any registration and the attempt is always audited.
nonisolated enum NationalBankRegistry {
    private static let storageKey = "turnoev.clabe.national.v1"

    private static func map() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    private static func normalize(_ clabe: String) -> String {
        clabe.filter(\.isNumber)
    }

    static func owner(of clabe: String) -> String? {
        map()[normalize(clabe)]
    }

    static func isTaken(clabe: String, excluding driverId: String?) -> Bool {
        guard let owner = owner(of: clabe) else { return false }
        return owner != driverId
    }

    static func register(clabe: String, driverId: String) {
        var current = map()
        current[normalize(clabe)] = driverId
        UserDefaults.standard.set(current, forKey: storageKey)
    }

    static func release(clabe: String) {
        var current = map()
        current.removeValue(forKey: normalize(clabe))
        UserDefaults.standard.set(current, forKey: storageKey)
    }
}
