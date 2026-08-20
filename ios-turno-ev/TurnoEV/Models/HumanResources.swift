import Foundation

/// Human resources domain of a station: candidates, interviews, documents, employee
/// files, bank data and the capacity maths that answer the only question that matters —
/// ¿tengo gente suficiente para operar cada turno, hoy y cuando lleguen más unidades?
/// Every number here is derived, never typed by hand.

// MARK: - Shift blocks

/// The four blocks a station must cover. One driver per vehicle per block.
nonisolated enum ShiftBlock: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekdayMorning
    case weekdayEvening
    case weekendMorning
    case weekendEvening

    var id: String { rawValue }

    var group: ShiftGroup {
        switch self {
        case .weekdayMorning, .weekdayEvening: .weekday
        case .weekendMorning, .weekendEvening: .weekend
        }
    }

    var slot: ShiftSlot {
        switch self {
        case .weekdayMorning, .weekendMorning: .morning
        case .weekdayEvening, .weekendEvening: .evening
        }
    }

    var label: String {
        switch self {
        case .weekdayMorning: "Matutino L-V"
        case .weekdayEvening: "Vespertino L-V"
        case .weekendMorning: "Matutino S-D"
        case .weekendEvening: "Vespertino S-D"
        }
    }

    var shortLabel: String {
        switch self {
        case .weekdayMorning: "Mat L-V"
        case .weekdayEvening: "Ves L-V"
        case .weekendMorning: "Mat S-D"
        case .weekendEvening: "Ves S-D"
        }
    }

    var symbol: String {
        slot == .morning ? "sunrise.fill" : "moon.stars.fill"
    }

    var scheduleLabel: String { slot.rangeLabel }

    static func block(group: ShiftGroup, slot: ShiftSlot) -> ShiftBlock {
        switch (group, slot) {
        case (.weekday, .morning): .weekdayMorning
        case (.weekday, .evening): .weekdayEvening
        case (.weekend, .morning): .weekendMorning
        case (.weekend, .evening): .weekendEvening
        }
    }

    /// Block being covered at this moment of the week.
    static func current(now: Date) -> ShiftBlock {
        let slot: ShiftSlot = ShiftRules.minutesOfDay(now) < ShiftRules.window(for: .evening).start ? .morning : .evening
        return block(group: ShiftRules.group(for: now), slot: slot)
    }
}

// MARK: - Operational alerts

/// Four levels, so the supervisor can manage by exception instead of reading lists.
nonisolated enum OpsAlertLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case informative
    case preventive
    case important
    case critical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .informative: "Informativa"
        case .preventive: "Preventiva"
        case .important: "Importante"
        case .critical: "Crítica"
        }
    }

    var weight: Int {
        switch self {
        case .informative: 0
        case .preventive: 1
        case .important: 2
        case .critical: 3
        }
    }

    var symbol: String {
        switch self {
        case .informative: "info.circle.fill"
        case .preventive: "shield.lefthalf.filled"
        case .important: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    /// Anything from here up needs the supervisor today.
    var demandsAction: Bool { weight >= 2 }
}

nonisolated enum OpsModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case fleet
    case drivers
    case people
    case workshop
    case banking

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fleet: "Vehículos"
        case .drivers: "Conductores"
        case .people: "Personal"
        case .workshop: "Mantenimiento"
        case .banking: "Bancario"
        }
    }

    var symbol: String {
        switch self {
        case .fleet: "car.2.fill"
        case .drivers: "person.2.fill"
        case .people: "person.text.rectangle.fill"
        case .workshop: "wrench.and.screwdriver.fill"
        case .banking: "building.columns.fill"
        }
    }
}

nonisolated struct OpsAlert: Identifiable, Sendable {
    let id: String
    let level: OpsAlertLevel
    let module: OpsModule
    let title: String
    let detail: String
    let createdAt: Date
}

// MARK: - Candidates

nonisolated enum CandidateStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case lead
    case interview
    case documents
    case approved
    case toHire
    case hired
    case rejected

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lead: "Nuevo"
        case .interview: "Entrevista"
        case .documents: "Documentación"
        case .approved: "Aprobado"
        case .toHire: "Por contratar"
        case .hired: "Contratado"
        case .rejected: "Rechazado"
        }
    }

    var symbol: String {
        switch self {
        case .lead: "person.crop.circle.badge.plus"
        case .interview: "text.bubble.fill"
        case .documents: "doc.text.fill"
        case .approved: "checkmark.seal.fill"
        case .toHire: "signature"
        case .hired: "person.badge.shield.checkmark.fill"
        case .rejected: "xmark.circle.fill"
        }
    }

    var order: Int {
        switch self {
        case .lead: 0
        case .interview: 1
        case .documents: 2
        case .approved: 3
        case .toHire: 4
        case .hired: 5
        case .rejected: 6
        }
    }

    /// Still moving through the funnel.
    var isInProcess: Bool { order <= 4 }

    var next: CandidateStage? {
        switch self {
        case .lead: .interview
        case .interview: .documents
        case .documents: .approved
        case .approved: .toHire
        case .toHire: .hired
        case .hired, .rejected: nil
        }
    }
}

nonisolated struct Candidate: Codable, Identifiable, Sendable {
    let id: String
    // Información personal
    var name: String
    var birthDate: Date
    var phone: String
    var email: String
    var curp: String
    var rfc: String
    var officialId: String
    var address: String
    var postalCode: String
    var city: String
    var state: String
    // Información laboral
    var experienceYears: Int
    var platforms: [String]
    var requestedBlock: ShiftBlock
    var availableWeekdays: Bool
    var availableWeekends: Bool
    var possibleStartAt: Date
    var availabilityNote: String
    // Contacto de emergencia
    var emergencyName: String
    var emergencyPhone: String
    var emergencyRelation: String
    // Registro automático
    let stationId: String
    let supervisorId: String
    let supervisorName: String
    let createdAt: Date
    // Proceso
    var stage: CandidateStage
    var interview: InterviewSheet?
    var documents: [StaffDocument]
    var hiredAt: Date?
    var rejectionReason: String?

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var shortName: String {
        let parts = name.split(separator: " ")
        guard parts.count > 1 else { return name }
        return "\(parts[0]) \(parts[1])"
    }

    func daysInProcess(now: Date) -> Int {
        max(0, Int((hiredAt ?? now).timeIntervalSince(createdAt) / 86_400))
    }

    /// Documents required before a contract can be signed.
    func missingDocuments(now: Date) -> [DocumentKind] {
        DocumentKind.hiringChecklist.filter { kind in
            guard let document = documents.first(where: { $0.kind == kind }) else { return true }
            return document.resolvedStatus(now: now) != .delivered
        }
    }

    var documentProgress: Double {
        let total = Double(DocumentKind.hiringChecklist.count)
        guard total > 0 else { return 0 }
        let done = Double(DocumentKind.hiringChecklist.count - missingDocuments(now: createdAt.addingTimeInterval(0)).count)
        return max(0, min(1, done / total))
    }
}

// MARK: - Interview

nonisolated enum InterviewCriterion: String, Codable, CaseIterable, Identifiable, Sendable {
    case experience
    case presentation
    case punctuality
    case communication
    case platforms
    case driving
    case availability
    case references
    case schedule
    case attitude

    var id: String { rawValue }

    var label: String {
        switch self {
        case .experience: "Experiencia"
        case .presentation: "Presentación"
        case .punctuality: "Puntualidad"
        case .communication: "Comunicación"
        case .platforms: "Conocimiento de plataformas"
        case .driving: "Conducción"
        case .availability: "Disponibilidad"
        case .references: "Antecedentes laborales"
        case .schedule: "Compatibilidad de horarios"
        case .attitude: "Actitud"
        }
    }

    var hint: String {
        switch self {
        case .experience: "Años y tipo de servicio"
        case .presentation: "Imagen y trato al pasajero"
        case .punctuality: "Historial de asistencia"
        case .communication: "Claridad al reportar"
        case .platforms: "Uber, DiDi, apps de flotilla"
        case .driving: "Manejo defensivo y eléctrico"
        case .availability: "Cobertura real del turno"
        case .references: "Referencias verificables"
        case .schedule: "Se ajusta al bloque solicitado"
        case .attitude: "Disposición y trabajo en equipo"
        }
    }
}

nonisolated enum InterviewSuggestion: String, Codable, Sendable {
    case recommended
    case secondReview
    case notRecommended

    var label: String {
        switch self {
        case .recommended: "Recomendado"
        case .secondReview: "Segunda revisión"
        case .notRecommended: "No recomendado"
        }
    }

    var symbol: String {
        switch self {
        case .recommended: "hand.thumbsup.fill"
        case .secondReview: "questionmark.circle.fill"
        case .notRecommended: "hand.thumbsdown.fill"
        }
    }
}

/// Structured interview. The score is a suggestion; the decision stays human.
nonisolated struct InterviewSheet: Codable, Sendable {
    var scores: [String: Int]
    var notes: String
    var interviewedAt: Date?
    var interviewerName: String
    /// Decision the supervisor signed, independent of the calculated suggestion.
    var decision: InterviewSuggestion?

    init(interviewerName: String) {
        scores = [:]
        notes = ""
        interviewedAt = nil
        self.interviewerName = interviewerName
        decision = nil
    }

    func score(_ criterion: InterviewCriterion) -> Int {
        scores[criterion.rawValue] ?? 0
    }

    var isComplete: Bool {
        InterviewCriterion.allCases.allSatisfy { score($0) > 0 }
    }

    var answered: Int {
        InterviewCriterion.allCases.filter { score($0) > 0 }.count
    }

    var average: Double {
        let values = InterviewCriterion.allCases.map { score($0) }.filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    /// 0–100 reading of the sheet.
    var scorePct: Int { Int((average / 5 * 100).rounded()) }

    var suggestion: InterviewSuggestion {
        if average >= 4 { return .recommended }
        if average >= 3 { return .secondReview }
        return .notRecommended
    }
}

// MARK: - Documents

nonisolated enum DocumentCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case identity
    case address
    case licenses
    case banking
    case labor
    case privacy
    case incidents
    case termination

    var id: String { rawValue }

    var label: String {
        switch self {
        case .identity: "Identificación"
        case .address: "Domicilio"
        case .licenses: "Licencias"
        case .banking: "Bancarios"
        case .labor: "Laborales"
        case .privacy: "Seguridad y privacidad"
        case .incidents: "Incidencias laborales"
        case .termination: "Baja"
        }
    }

    var symbol: String {
        switch self {
        case .identity: "person.text.rectangle.fill"
        case .address: "house.fill"
        case .licenses: "car.fill"
        case .banking: "building.columns.fill"
        case .labor: "doc.text.fill"
        case .privacy: "lock.shield.fill"
        case .incidents: "exclamationmark.bubble.fill"
        case .termination: "arrow.uturn.left.circle.fill"
        }
    }
}

nonisolated enum DocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case officialId
    case curp
    case rfc
    case addressProof
    case license
    case bankProof
    case clabe
    case socialSecurity
    case photo
    case contract
    case privacyNotice
    case consent
    case emergencyContact
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .officialId: "Identificación oficial"
        case .curp: "CURP"
        case .rfc: "RFC / Constancia fiscal"
        case .addressProof: "Comprobante de domicilio"
        case .license: "Licencia vigente"
        case .bankProof: "Comprobante bancario"
        case .clabe: "CLABE"
        case .socialSecurity: "Seguridad social"
        case .photo: "Fotografía"
        case .contract: "Contrato firmado"
        case .privacyNotice: "Aviso de privacidad"
        case .consent: "Consentimientos"
        case .emergencyContact: "Contacto de emergencia"
        case .other: "Documento adicional"
        }
    }

    var category: DocumentCategory {
        switch self {
        case .officialId, .curp, .rfc, .photo: .identity
        case .addressProof: .address
        case .license: .licenses
        case .bankProof, .clabe: .banking
        case .contract, .socialSecurity, .emergencyContact, .other: .labor
        case .privacyNotice, .consent: .privacy
        }
    }

    /// Loses validity with time, so it can expire.
    var expires: Bool {
        switch self {
        case .license, .addressProof, .officialId: true
        default: false
        }
    }

    /// Blocks the shift when expired.
    var isCritical: Bool {
        switch self {
        case .license, .officialId: true
        default: false
        }
    }

    /// What a candidate must deliver before signing.
    static let hiringChecklist: [DocumentKind] = [
        .officialId, .curp, .rfc, .addressProof, .license, .bankProof,
        .clabe, .photo, .contract, .privacyNotice, .consent, .emergencyContact,
    ]
}

nonisolated enum DocumentStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case delivered
    case pending
    case rejected
    case expiringSoon
    case expired

    var id: String { rawValue }

    var label: String {
        switch self {
        case .delivered: "Entregado"
        case .pending: "Pendiente"
        case .rejected: "Rechazado"
        case .expiringSoon: "Por vencer"
        case .expired: "Vencido"
        }
    }

    var symbol: String {
        switch self {
        case .delivered: "checkmark.seal.fill"
        case .pending: "clock.fill"
        case .rejected: "xmark.octagon.fill"
        case .expiringSoon: "exclamationmark.triangle.fill"
        case .expired: "calendar.badge.exclamationmark"
        }
    }

    var needsAttention: Bool { self != .delivered }
}

/// A replaced document is never deleted: the previous file stays as a version.
nonisolated struct DocumentVersion: Codable, Identifiable, Sendable {
    let id: String
    let uploadedAt: Date
    let uploadedBy: String
    let note: String
}

nonisolated struct StaffDocument: Codable, Identifiable, Sendable {
    let id: String
    let kind: DocumentKind
    var status: DocumentStatus
    var uploadedAt: Date?
    var issuedAt: Date?
    var expiresAt: Date?
    var uploadedBy: String?
    var rejectionReason: String?
    var versions: [DocumentVersion]

    init(
        kind: DocumentKind,
        status: DocumentStatus = .pending,
        uploadedAt: Date? = nil,
        issuedAt: Date? = nil,
        expiresAt: Date? = nil,
        uploadedBy: String? = nil,
        rejectionReason: String? = nil,
        versions: [DocumentVersion] = []
    ) {
        id = kind.rawValue
        self.kind = kind
        self.status = status
        self.uploadedAt = uploadedAt
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.uploadedBy = uploadedBy
        self.rejectionReason = rejectionReason
        self.versions = versions
    }

    /// Expiry is recalculated against the operating clock, never stored stale.
    func resolvedStatus(now: Date) -> DocumentStatus {
        if status == .pending || status == .rejected { return status }
        guard let expiresAt else { return status }
        if expiresAt < now { return .expired }
        if expiresAt.timeIntervalSince(now) < 30 * 86_400 { return .expiringSoon }
        return .delivered
    }

    func daysToExpiry(now: Date) -> Int? {
        guard let expiresAt else { return nil }
        return Int(expiresAt.timeIntervalSince(now) / 86_400)
    }
}

// MARK: - Employee file

nonisolated enum EmploymentStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case onboarding
    case active
    case suspended
    case medicalLeave
    case vacation
    case terminated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onboarding: "En contratación"
        case .active: "Activo"
        case .suspended: "Suspendido"
        case .medicalLeave: "Incapacidad"
        case .vacation: "Vacaciones"
        case .terminated: "Baja"
        }
    }

    /// Only an active driver can be counted as operational coverage.
    var canOperate: Bool { self == .active }

    var symbol: String {
        switch self {
        case .onboarding: "hourglass"
        case .active: "checkmark.circle.fill"
        case .suspended: "pause.circle.fill"
        case .medicalLeave: "cross.case.fill"
        case .vacation: "beach.umbrella.fill"
        case .terminated: "xmark.circle.fill"
        }
    }
}

nonisolated enum FileEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case hire
    case shiftChange
    case incident
    case recognition
    case suspension
    case vacation
    case termination
    case rehire
    case bankChange
    case documentUpdate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hire: "Contratación"
        case .shiftChange: "Cambio de turno"
        case .incident: "Incidencia"
        case .recognition: "Reconocimiento"
        case .suspension: "Suspensión"
        case .vacation: "Vacaciones"
        case .termination: "Baja"
        case .rehire: "Reingreso"
        case .bankChange: "Cambio bancario"
        case .documentUpdate: "Actualización documental"
        }
    }

    var symbol: String {
        switch self {
        case .hire: "person.badge.plus"
        case .shiftChange: "arrow.left.arrow.right"
        case .incident: "exclamationmark.triangle.fill"
        case .recognition: "star.fill"
        case .suspension: "pause.circle.fill"
        case .vacation: "beach.umbrella.fill"
        case .termination: "arrow.uturn.left"
        case .rehire: "arrow.uturn.right"
        case .bankChange: "building.columns.fill"
        case .documentUpdate: "doc.badge.arrow.up"
        }
    }
}

nonisolated struct FileEvent: Codable, Identifiable, Sendable {
    let id: String
    let kind: FileEventKind
    let date: Date
    let detail: String
    let author: String
}

/// Digital file of one employee. It is the record the station never deletes.
nonisolated struct EmployeeFile: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var employeeNumber: String
    var photoAsset: String?
    let stationId: String
    var block: ShiftBlock
    var hiredAt: Date
    var status: EmploymentStatus
    var supervisorName: String
    var phone: String
    var curp: String
    var rfc: String
    var documents: [StaffDocument]
    var events: [FileEvent]
    var bank: BankAccount?
    /// Marks the credential currently running the driver app on this device.
    var isLiveSession: Bool

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var shortName: String {
        let parts = name.split(separator: " ")
        guard parts.count > 1 else { return name }
        return "\(parts[0]) \(parts[1])"
    }

    func document(_ kind: DocumentKind) -> StaffDocument? {
        documents.first { $0.kind == kind }
    }

    func missingDocuments(now: Date) -> [DocumentKind] {
        DocumentKind.hiringChecklist.filter { kind in
            guard let document = document(kind) else { return true }
            return document.resolvedStatus(now: now) != .delivered
        }
    }

    func expiringDocuments(now: Date) -> [StaffDocument] {
        documents.filter { $0.resolvedStatus(now: now) == .expiringSoon }
    }

    func expiredDocuments(now: Date) -> [StaffDocument] {
        documents.filter { $0.resolvedStatus(now: now) == .expired }
    }

    /// "Expediente 92 % completo" — the headline of the file.
    func completionPct(now: Date) -> Int {
        let total = DocumentKind.hiringChecklist.count
        guard total > 0 else { return 100 }
        let missing = missingDocuments(now: now).count
        return Int((Double(total - missing) / Double(total) * 100).rounded())
    }

    func hasCriticalExpired(now: Date) -> Bool {
        documents.contains { $0.kind.isCritical && $0.resolvedStatus(now: now) == .expired }
    }

    /// Operationally available: hired is not the same as being able to drive today.
    func isOperationallyAvailable(now: Date) -> Bool {
        unavailableReason(now: now) == nil
    }

    func unavailableReason(now: Date) -> String? {
        if !status.canOperate { return status.label }
        if hasCriticalExpired(now: now) { return "Documentación crítica vencida" }
        return nil
    }
}

// MARK: - Banking

nonisolated enum BankAccountStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case verified
    case pending
    case rejected
    case blocked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .verified: "Verificada"
        case .pending: "Pendiente"
        case .rejected: "Rechazada"
        case .blocked: "Bloqueada"
        }
    }

    var symbol: String {
        switch self {
        case .verified: "checkmark.seal.fill"
        case .pending: "clock.fill"
        case .rejected: "xmark.octagon.fill"
        case .blocked: "lock.fill"
        }
    }
}

nonisolated struct BankAccount: Codable, Sendable {
    var bank: String
    var clabe: String
    var accountNumber: String
    var holder: String
    var rfc: String
    var registeredAt: Date
    var registeredBy: String
    var status: BankAccountStatus
    var hasProof: Bool

    /// The full CLABE is never rendered; only the last four digits identify the account.
    var maskedClabe: String { HRRules.mask(clabe: clabe) }
}

nonisolated enum BankRequestStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case requested
    case review
    case approved
    case rejected
    case applied

    var id: String { rawValue }

    var label: String {
        switch self {
        case .requested: "Solicitada"
        case .review: "En revisión"
        case .approved: "Aprobada"
        case .rejected: "Rechazada"
        case .applied: "Aplicada"
        }
    }

    var order: Int {
        switch self {
        case .requested: 0
        case .review: 1
        case .approved: 2
        case .applied: 3
        case .rejected: 4
        }
    }

    var isOpen: Bool { self == .requested || self == .review || self == .approved }
}

/// One validation of a bank change. A failed non-blocking check sends the request to
/// manual review instead of rejecting it.
nonisolated struct BankValidation: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let passed: Bool
    let isBlocking: Bool
}

nonisolated struct BankChangeRequest: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    let driverName: String
    let stationId: String
    let createdAt: Date
    var bank: String
    var clabe: String
    var holder: String
    var reason: String
    var hasOfficialId: Bool
    var hasBankProof: Bool
    var hasAddressProof: Bool
    /// The address on the proof is not identical to the file. Never an automatic reject.
    var addressMatches: Bool
    var status: BankRequestStatus
    var resolvedAt: Date?
    var resolutionNote: String?
    var validatedBy: String?
    var approvedBy: String?

    var maskedClabe: String { HRRules.mask(clabe: clabe) }

    /// Checks the supervisor signs before sending the request to the regional manager.
    func validations(clabeTaken: Bool, fileHolder: String?) -> [BankValidation] {
        [
            BankValidation(
                id: "holder",
                title: "Nombre del titular",
                detail: fileHolder.map { "Expediente: \($0)" } ?? "Sin expediente ligado",
                passed: fileHolder == nil ? false : holder.localizedCaseInsensitiveCompare(fileHolder ?? "") == .orderedSame,
                isBlocking: true
            ),
            BankValidation(
                id: "format",
                title: "CLABE válida",
                detail: "18 dígitos · \(maskedClabe)",
                passed: HRRules.isValidClabe(clabe),
                isBlocking: true
            ),
            BankValidation(
                id: "unique",
                title: "CLABE no duplicada en la red",
                detail: clabeTaken
                    ? "Esta cuenta bancaria ya se encuentra registrada en otro expediente."
                    : "Sin coincidencias en la base nacional",
                passed: !clabeTaken,
                isBlocking: true
            ),
            BankValidation(
                id: "identity",
                title: "Identidad",
                detail: "Identificación oficial adjunta",
                passed: hasOfficialId,
                isBlocking: true
            ),
            BankValidation(
                id: "docs",
                title: "Documentación",
                detail: "Comprobante bancario y de domicilio",
                passed: hasBankProof && hasAddressProof,
                isBlocking: true
            ),
            BankValidation(
                id: "address",
                title: "Coincidencia de domicilio",
                detail: addressMatches
                    ? "Coincide con el expediente"
                    : "No coincide exactamente: pasa a revisión manual, no se rechaza",
                passed: addressMatches,
                isBlocking: false
            ),
        ]
    }
}

// MARK: - Incoming vehicles

nonisolated enum IncorporationStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case purchasing
    case purchaseConfirmed
    case inTransit
    case arrivingSoon
    case preparing
    case active

    var id: String { rawValue }

    var label: String {
        switch self {
        case .purchasing: "En compra"
        case .purchaseConfirmed: "Compra confirmada"
        case .inTransit: "En traslado"
        case .arrivingSoon: "Próximo a incorporarse"
        case .preparing: "En preparación"
        case .active: "Activo"
        }
    }

    var order: Int {
        switch self {
        case .purchasing: 0
        case .purchaseConfirmed: 1
        case .inTransit: 2
        case .arrivingSoon: 3
        case .preparing: 4
        case .active: 5
        }
    }

    var symbol: String {
        switch self {
        case .purchasing: "cart.fill"
        case .purchaseConfirmed: "checkmark.circle.fill"
        case .inTransit: "truck.box.fill"
        case .arrivingSoon: "calendar.badge.clock"
        case .preparing: "wrench.adjustable.fill"
        case .active: "bolt.car.fill"
        }
    }

    /// Still counted as future capacity.
    var isIncoming: Bool { self != .active }
}

nonisolated struct VehicleIncorporation: Codable, Identifiable, Sendable {
    let id: String
    let stationId: String
    var model: String
    var units: Int
    var stage: IncorporationStage
    var arrivalAt: Date
    var operationStartAt: Date
    var note: String

    var requiredDrivers: Int { units * HRRules.driversPerVehicle }

    func daysToOperation(now: Date) -> Int {
        Int(operationStartAt.timeIntervalSince(now) / 86_400)
    }
}

// MARK: - Capacity

nonisolated struct BlockCoverage: Identifiable, Sendable {
    let block: ShiftBlock
    let required: Int
    let available: Int
    let hired: Int
    let onboarding: Int

    var id: String { block.rawValue }
    var deficit: Int { max(0, required - available) }
    var ratio: Double { required > 0 ? Double(available) / Double(required) : 1 }

    var level: OpsAlertLevel {
        if deficit == 0 { return .informative }
        if ratio >= 0.9 { return .preventive }
        if ratio >= 0.75 { return .important }
        return .critical
    }
}

nonisolated struct CapacityPlan: Sendable {
    let activeVehicles: Int
    let incomingVehicles: Int
    let requiredDrivers: Int
    let hiredDrivers: Int
    let availableDrivers: Int
    let onboardingDrivers: Int
    let blocks: [BlockCoverage]

    var deficit: Int { max(0, requiredDrivers - availableDrivers) }
    var coverageRatio: Double { requiredDrivers > 0 ? Double(availableDrivers) / Double(requiredDrivers) : 1 }
    var coveragePct: Int { Int((coverageRatio * 100).rounded()) }
    var futureVehicles: Int { activeVehicles + incomingVehicles }
    var futureRequired: Int { HRRules.requiredDrivers(activeVehicles: futureVehicles) }
    var futureDeficit: Int { max(0, futureRequired - availableDrivers - onboardingDrivers) }
    var worstBlock: BlockCoverage? { blocks.max { $0.deficit < $1.deficit } }
}

/// Funnel of the station, used to translate vacancies into candidates.
nonisolated struct HiringPipeline: Sendable {
    let candidates: Int
    let interviewed: Int
    let documented: Int
    let approved: Int
    let hired: Int
    let rejected: Int
    let averageHiringDays: Int

    var conversionRate: Double { candidates > 0 ? Double(hired) / Double(candidates) : 0 }
    var conversionPct: Int { Int((conversionRate * 100).rounded()) }
    var rejectionRate: Double { candidates > 0 ? Double(rejected) / Double(candidates) : 0 }

    var stages: [(label: String, value: Int)] {
        [
            ("Candidatos", candidates),
            ("Entrevistados", interviewed),
            ("Documentación", documented),
            ("Aprobados", approved),
            ("Contratados", hired),
        ]
    }
}

/// Recruitment target for a given deficit, using the station's own conversion history.
nonisolated struct RecruitmentTarget: Sendable {
    let neededDrivers: Int
    let conversionRate: Double
    let marginPct: Int
    let baseCandidates: Int
    let recommendedCandidates: Int
    let averageHiringDays: Int
    let daysAvailable: Int?
    let level: OpsAlertLevel

    var startByDays: Int { averageHiringDays }
}

// MARK: - Rules

nonisolated enum HRRules {
    /// 4 shifts per unit: matutino y vespertino, entre semana y fin de semana.
    static let driversPerVehicle = 4
    /// Design ceiling of a station; the real numbers are always read from the data.
    static let maxVehiclesPerStation = 50
    static let maxDriversPerStation = 200
    /// Extra candidates started on top of the statistical need.
    static let safetyMarginPct = 15
    static let documentWarningDays = 30

    static func requiredDrivers(activeVehicles: Int) -> Int {
        activeVehicles * driversPerVehicle
    }

    static func mask(clabe: String) -> String {
        let digits = clabe.filter(\.isNumber)
        guard digits.count >= 4 else { return "••••" }
        return "•••• •••• •••• " + String(digits.suffix(4))
    }

    static func isValidClabe(_ clabe: String) -> Bool {
        clabe.filter(\.isNumber).count == 18
    }

    /// Candidates to start so that `needed` contracts are actually signed.
    static func recommendedCandidates(needed: Int, conversionRate: Double, marginPct: Int = safetyMarginPct) -> Int {
        guard needed > 0 else { return 0 }
        let rate = conversionRate > 0.05 ? conversionRate : 0.5
        let base = Double(needed) / rate
        return Int((base * (1 + Double(marginPct) / 100)).rounded(.up))
    }

    /// Risk of not having drivers by the day the units start operating.
    static func hiringRisk(daysAvailable: Int, averageHiringDays: Int, deficit: Int) -> OpsAlertLevel {
        guard deficit > 0 else { return .informative }
        if daysAvailable < averageHiringDays { return .critical }
        if daysAvailable < averageHiringDays + 7 { return .important }
        return .preventive
    }

    static func target(
        neededDrivers: Int,
        pipeline: HiringPipeline,
        daysAvailable: Int?,
        marginPct: Int = safetyMarginPct
    ) -> RecruitmentTarget {
        let base = neededDrivers > 0 && pipeline.conversionRate > 0.05
            ? Int((Double(neededDrivers) / pipeline.conversionRate).rounded(.up))
            : neededDrivers * 2
        let recommended = recommendedCandidates(
            needed: neededDrivers,
            conversionRate: pipeline.conversionRate,
            marginPct: marginPct
        )
        let level: OpsAlertLevel = {
            guard let daysAvailable else { return neededDrivers > 0 ? .preventive : .informative }
            return hiringRisk(
                daysAvailable: daysAvailable,
                averageHiringDays: pipeline.averageHiringDays,
                deficit: neededDrivers
            )
        }()
        return RecruitmentTarget(
            neededDrivers: neededDrivers,
            conversionRate: pipeline.conversionRate,
            marginPct: marginPct,
            baseCandidates: base,
            recommendedCandidates: recommended,
            averageHiringDays: pipeline.averageHiringDays,
            daysAvailable: daysAvailable,
            level: level
        )
    }
}
