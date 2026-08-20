import Foundation

/// Recruitment domain: a demand-driven talent acquisition centre. Nothing here starts
/// with a candidate — everything starts with a vehicle. Units × 4 turnos = plantilla,
/// plantilla − disponibles = vacantes, vacantes ÷ conversión = leads necesarios, leads ×
/// costo por lead = presupuesto. The recruiter never sees money of the drivers, credits
/// or settlements: only the cost of acquiring the people the fleet is going to need.

// MARK: - Sources

nonisolated enum LeadSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case facebook
    case instagram
    case referral
    case website
    case walkIn
    case jobBoard
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .facebook: "Facebook"
        case .instagram: "Instagram"
        case .referral: "Referido"
        case .website: "Página web"
        case .walkIn: "Reclutamiento presencial"
        case .jobBoard: "Bolsa de trabajo"
        case .other: "Otro"
        }
    }

    var shortLabel: String {
        switch self {
        case .facebook: "FB"
        case .instagram: "IG"
        case .referral: "Referido"
        case .website: "Web"
        case .walkIn: "Presencial"
        case .jobBoard: "Bolsa"
        case .other: "Otro"
        }
    }

    var symbol: String {
        switch self {
        case .facebook: "f.circle.fill"
        case .instagram: "camera.circle.fill"
        case .referral: "person.2.wave.2.fill"
        case .website: "globe"
        case .walkIn: "figure.walk"
        case .jobBoard: "briefcase.fill"
        case .other: "questionmark.circle.fill"
        }
    }

    /// Paid media: it has budget, cost per lead and cost per hire.
    var isPaid: Bool {
        switch self {
        case .facebook, .instagram, .jobBoard: true
        case .referral, .website, .walkIn, .other: false
        }
    }

    /// Arrives through a Meta Lead Ads form. Today simulated, tomorrow a webhook.
    var isMetaChannel: Bool { self == .facebook || self == .instagram }
}

// MARK: - Stages

/// The funnel of the recruitment area, from the ad to the signed contract. Recruitment
/// owns every stage: nobody else decides, approves or signs the alta.
nonisolated enum RecruitStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case lead
    case contacted
    case prequalified
    case interviewed
    case documents
    /// Documentation complete and interview signed: the alta can be signed today.
    /// The raw value keeps its old spelling so saved funnels still decode.
    case readyToHire = "supervisor"
    case approved
    case hired
    case lost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lead: "Lead"
        case .contacted: "Contactado"
        case .prequalified: "Precalificado"
        case .interviewed: "Entrevistado"
        case .documents: "Documentación"
        case .readyToHire: "Listo para contratar"
        case .approved: "Alta autorizada"
        case .hired: "Contratado"
        case .lost: "Perdido"
        }
    }

    var shortLabel: String {
        switch self {
        case .lead: "Leads"
        case .contacted: "Contacto"
        case .prequalified: "Precalif."
        case .interviewed: "Entrevista"
        case .documents: "Docs"
        case .readyToHire: "Por contratar"
        case .approved: "Autorizados"
        case .hired: "Contratados"
        case .lost: "Perdidos"
        }
    }

    var symbol: String {
        switch self {
        case .lead: "sparkles"
        case .contacted: "phone.fill"
        case .prequalified: "checklist"
        case .interviewed: "text.bubble.fill"
        case .documents: "doc.text.fill"
        case .readyToHire: "signature"
        case .approved: "checkmark.seal.fill"
        case .hired: "steeringwheel"
        case .lost: "xmark.circle.fill"
        }
    }

    var order: Int {
        switch self {
        case .lead: 0
        case .contacted: 1
        case .prequalified: 2
        case .interviewed: 3
        case .documents: 4
        case .readyToHire: 5
        case .approved: 6
        case .hired: 7
        case .lost: 8
        }
    }

    /// Still moving: neither hired nor lost.
    var isOpen: Bool { order <= 6 }

    /// Every stage up to the signed contract belongs to recruitment. The station only
    /// receives the employee file once the alta is signed.
    var isOwnedByRecruitment: Bool { order <= 6 }

    /// Ordered funnel used by the pipeline board.
    static let funnel: [RecruitStage] = [
        .lead, .contacted, .prequalified, .interviewed, .documents, .readyToHire, .approved, .hired,
    ]
}

// MARK: - Loss reasons

/// Leaving the pipeline always has a reason. Without it there is no way to tell whether
/// the problem is the campaign, the salary, the schedule or the process itself.
nonisolated enum LossReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case noAnswer
    case notInterested
    case salary
    case schedule
    case documents
    case license
    case distance
    case noShow
    case rejectedByRecruiter
    /// Discarded at the hiring decision itself. Raw value kept for saved funnels.
    case rejectedAtHire = "rejectedBySupervisor"
    case otherJob
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .noAnswer: "No respondió"
        case .notInterested: "No interesado"
        case .salary: "Salario"
        case .schedule: "Horarios"
        case .documents: "Documentación"
        case .license: "Licencia"
        case .distance: "Distancia"
        case .noShow: "No asistió"
        case .rejectedByRecruiter: "Rechazado en entrevista"
        case .rejectedAtHire: "Rechazado en la alta"
        case .otherJob: "Encontró otro empleo"
        case .other: "Otro"
        }
    }

    var symbol: String {
        switch self {
        case .noAnswer: "phone.down.fill"
        case .notInterested: "hand.raised.fill"
        case .salary: "banknote.fill"
        case .schedule: "clock.badge.xmark.fill"
        case .documents: "doc.badge.ellipsis"
        case .license: "car.circle.fill"
        case .distance: "map.fill"
        case .noShow: "calendar.badge.exclamationmark"
        case .rejectedByRecruiter: "person.crop.circle.badge.xmark"
        case .rejectedAtHire: "person.badge.shield.exclamationmark.fill"
        case .otherJob: "arrow.uturn.right"
        case .other: "questionmark.circle.fill"
        }
    }

    /// Reasons the company can act on: offer, schedule, process speed, campaign targeting.
    var isActionable: Bool {
        switch self {
        case .salary, .schedule, .distance, .otherJob, .noAnswer, .noShow: true
        case .notInterested, .documents, .license, .rejectedByRecruiter, .rejectedAtHire, .other: false
        }
    }
}

// MARK: - Screening

nonisolated enum ScreeningCheck: String, Codable, CaseIterable, Identifiable, Sendable {
    case age
    case license
    case drivingExperience
    case platformExperience
    case blockAvailability
    case cityMatch
    case immediateStart
    case basicDocuments
    case scheduleCompliance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .age: "Edad conforme a política"
        case .license: "Licencia vigente"
        case .drivingExperience: "Experiencia conduciendo"
        case .platformExperience: "Experiencia en plataformas"
        case .blockAvailability: "Disponibilidad del turno solicitado"
        case .cityMatch: "Vive en la ciudad de la estación"
        case .immediateStart: "Disponibilidad inmediata"
        case .basicDocuments: "Documentación básica completa"
        case .scheduleCompliance: "Puede cumplir horarios fijos"
        }
    }

    var hint: String {
        switch self {
        case .age: "21 años o más al día de hoy"
        case .license: "Tipo A o equivalente sin vencer"
        case .drivingExperience: "Al menos un año al volante"
        case .platformExperience: "Uber, DiDi u otra app"
        case .blockAvailability: "Cubre el bloque completo, no fracciones"
        case .cityMatch: "Traslado razonable a la estación"
        case .immediateStart: "Puede iniciar en menos de 15 días"
        case .basicDocuments: "Identificación, CURP y comprobante"
        case .scheduleCompliance: "8 h de turno más 1 h de comida"
        }
    }

    /// A failed blocking check cannot end in "apto".
    var isBlocking: Bool {
        switch self {
        case .age, .license, .blockAvailability: true
        case .drivingExperience, .platformExperience, .cityMatch, .immediateStart, .basicDocuments, .scheduleCompliance: false
        }
    }
}

nonisolated enum ScreeningOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case fit
    case review
    case unfit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fit: "Apto"
        case .review: "Revisión"
        case .unfit: "No apto"
        }
    }

    var symbol: String {
        switch self {
        case .fit: "checkmark.seal.fill"
        case .review: "questionmark.circle.fill"
        case .unfit: "xmark.octagon.fill"
        }
    }
}

/// Quick screening form. The suggestion is arithmetic; the resolution is signed by a person.
nonisolated struct Screening: Codable, Sendable {
    var answers: [String: Bool]
    var notes: String
    var reviewedAt: Date?
    var reviewer: String
    var decision: ScreeningOutcome?

    init(reviewer: String) {
        answers = [:]
        notes = ""
        reviewedAt = nil
        self.reviewer = reviewer
        decision = nil
    }

    func answer(_ check: ScreeningCheck) -> Bool? { answers[check.rawValue] }

    var answered: Int { ScreeningCheck.allCases.filter { answers[$0.rawValue] != nil }.count }

    var isComplete: Bool { answered == ScreeningCheck.allCases.count }

    var passed: Int { ScreeningCheck.allCases.filter { answers[$0.rawValue] == true }.count }

    var blockingFailures: [ScreeningCheck] {
        ScreeningCheck.allCases.filter { $0.isBlocking && answers[$0.rawValue] == false }
    }

    /// Suggested outcome: any blocking failure sinks it, otherwise it reads the ratio.
    var suggestion: ScreeningOutcome {
        if !blockingFailures.isEmpty { return .unfit }
        let total = ScreeningCheck.allCases.count
        if passed >= total - 1 { return .fit }
        if passed >= total - 3 { return .review }
        return .unfit
    }

    var outcome: ScreeningOutcome { decision ?? suggestion }
}

// MARK: - Appointments

nonisolated enum AppointmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case phone
    case video
    case onsite
    case operational

    var id: String { rawValue }

    var label: String {
        switch self {
        case .phone: "Telefónica"
        case .video: "Videollamada"
        case .onsite: "Presencial"
        case .operational: "Cierre de expediente"
        }
    }

    var symbol: String {
        switch self {
        case .phone: "phone.fill"
        case .video: "video.fill"
        case .onsite: "building.2.fill"
        case .operational: "signature"
        }
    }
}

nonisolated enum AppointmentStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case scheduled
    case confirmed
    case rescheduled
    case attended
    case noShow
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scheduled: "Programada"
        case .confirmed: "Confirmada"
        case .rescheduled: "Reprogramada"
        case .attended: "Asistió"
        case .noShow: "No asistió"
        case .cancelled: "Cancelada"
        }
    }

    var symbol: String {
        switch self {
        case .scheduled: "calendar"
        case .confirmed: "checkmark.circle.fill"
        case .rescheduled: "arrow.triangle.2.circlepath"
        case .attended: "checkmark.seal.fill"
        case .noShow: "calendar.badge.exclamationmark"
        case .cancelled: "xmark.circle.fill"
        }
    }

    /// Still going to happen: it belongs to the agenda.
    var isOpen: Bool {
        switch self {
        case .scheduled, .confirmed, .rescheduled: true
        case .attended, .noShow, .cancelled: false
        }
    }
}

nonisolated struct Appointment: Codable, Identifiable, Sendable {
    let id: String
    let prospectId: String
    var prospectName: String
    var stationId: String
    var date: Date
    var kind: AppointmentKind
    /// Who receives the candidate: recruiter or the station supervisor.
    var owner: String
    var status: AppointmentStatus
    var note: String
    var remindedAt: Date?

    func hoursAway(now: Date) -> Int { Int(date.timeIntervalSince(now) / 3_600) }
    func isToday(now: Date) -> Bool { ShiftRules.calendar.isDate(date, inSameDayAs: now) }
}

// MARK: - History

nonisolated enum ProspectEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case created
    case contact
    case screening
    case interview
    case document
    case appointment
    case stage
    case handoff
    case verdict
    case lost
    case reentry

    var id: String { rawValue }

    var label: String {
        switch self {
        case .created: "Alta"
        case .contact: "Contacto"
        case .screening: "Precalificación"
        case .interview: "Entrevista"
        case .document: "Documentación"
        case .appointment: "Cita"
        case .stage: "Cambio de etapa"
        case .handoff: "Envío a supervisor"
        case .verdict: "Resultado del supervisor"
        case .lost: "Salida del proceso"
        case .reentry: "Reingreso"
        }
    }

    var symbol: String {
        switch self {
        case .created: "sparkles"
        case .contact: "phone.fill"
        case .screening: "checklist"
        case .interview: "text.bubble.fill"
        case .document: "doc.badge.arrow.up"
        case .appointment: "calendar"
        case .stage: "arrow.right.circle.fill"
        case .handoff: "paperplane.fill"
        case .verdict: "person.badge.shield.checkmark.fill"
        case .lost: "xmark.circle.fill"
        case .reentry: "arrow.uturn.right"
        }
    }
}

/// One line of the candidate history. It is never deleted, not even on rejection.
nonisolated struct ProspectEvent: Codable, Identifiable, Sendable {
    let id: String
    let kind: ProspectEventKind
    let date: Date
    let detail: String
    let author: String
}

// MARK: - Hiring verdict

/// The decision recruitment itself takes at the end of its own process. No other role
/// signs, approves or vetoes it.
nonisolated enum HiringVerdict: String, Codable, CaseIterable, Identifiable, Sendable {
    case approved
    case secondInterview
    case rejected

    var id: String { rawValue }

    var label: String {
        switch self {
        case .approved: "Alta autorizada"
        case .secondInterview: "Segunda entrevista"
        case .rejected: "Rechazado"
        }
    }

    var symbol: String {
        switch self {
        case .approved: "checkmark.seal.fill"
        case .secondInterview: "arrow.triangle.2.circlepath"
        case .rejected: "xmark.octagon.fill"
        }
    }
}

// MARK: - Prospect

/// A person in the recruitment process, from the first call to the signed alta.
/// Payroll, CLABE and settlements are still born at the station: recruitment writes the
/// initial file, never the money.
nonisolated struct Prospect: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var phone: String
    var email: String
    var city: String
    var age: Int
    var curp: String
    /// Station the candidate applied for.
    var stationId: String
    var requestedBlock: ShiftBlock
    var experienceYears: Int
    var platforms: [String]
    var hasLicense: Bool
    var source: LeadSource
    var campaignId: String?
    let createdAt: Date
    var stage: RecruitStage
    var contactedAt: Date?
    var screening: Screening?
    var interview: InterviewSheet?
    var documents: [StaffDocument]
    /// When recruitment authorized the alta of this candidate.
    var authorizedAt: Date?
    var hiringVerdict: HiringVerdict?
    var hiringNote: String?
    var verdictAt: Date?
    var hiredAt: Date?
    var lossReason: LossReason?
    var lossNote: String?
    var ownerName: String
    var notes: String
    var history: [ProspectEvent]

    /// Storage keys are frozen: three fields were renamed when the hiring decision moved
    /// from the station to recruitment, and saved candidates must keep decoding.
    private enum CodingKeys: String, CodingKey {
        case id, name, phone, email, city, age, curp, stationId, requestedBlock
        case experienceYears, platforms, hasLicense, source, campaignId, createdAt
        case stage, contactedAt, screening, interview, documents
        case authorizedAt = "sentToSupervisorAt"
        case hiringVerdict = "supervisorVerdict"
        case hiringNote = "supervisorNote"
        case verdictAt, hiredAt, lossReason, lossNote, ownerName, notes, history
    }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var shortName: String {
        let parts = name.split(separator: " ")
        guard parts.count > 1 else { return name }
        return "\(parts[0]) \(parts[1])"
    }

    var platformsLabel: String { platforms.isEmpty ? "Sin plataformas" : platforms.joined(separator: " · ") }

    /// Minutes from lead registration to first human contact.
    var firstContactMinutes: Int? {
        guard let contactedAt else { return nil }
        return max(0, Int(contactedAt.timeIntervalSince(createdAt) / 60))
    }

    func waitingMinutes(now: Date) -> Int { max(0, Int(now.timeIntervalSince(createdAt) / 60)) }

    func daysInProcess(now: Date) -> Int {
        max(0, Int((hiredAt ?? now).timeIntervalSince(createdAt) / 86_400))
    }

    /// Waiting for a first call beyond the service level.
    func isOverdueContact(now: Date) -> Bool {
        stage == .lead && waitingMinutes(now: now) > RecruitRules.contactSlaMinutes
    }

    func missingDocuments(now: Date) -> [DocumentKind] {
        DocumentKind.recruitmentChecklist.filter { kind in
            guard let document = documents.first(where: { $0.kind == kind }) else { return true }
            return document.resolvedStatus(now: now) != .delivered
        }
    }

    func documentPct(now: Date) -> Int {
        let total = DocumentKind.recruitmentChecklist.count
        guard total > 0 else { return 100 }
        return Int((Double(total - missingDocuments(now: now).count) / Double(total) * 100).rounded())
    }

    var interviewScorePct: Int? {
        guard let interview, interview.interviewedAt != nil else { return nil }
        return interview.scorePct
    }

    /// Everything recruitment needs before signing: screening apta, interview signed and
    /// not rejected. Documentation is checked apart because it is the slow half.
    func passedEvaluation() -> Bool {
        guard screening?.outcome == .fit else { return false }
        guard let interview, interview.interviewedAt != nil else { return false }
        return interview.decision != .notRecommended
    }

    /// The alta can be signed today: evaluation passed and the initial file is complete.
    func isReadyToHire(now: Date) -> Bool {
        guard stage.isOpen, hiredAt == nil else { return false }
        guard passedEvaluation() else { return false }
        return missingDocuments(now: now).isEmpty
    }
}

// MARK: - Campaigns

/// Advertising campaign. Budget and spend are the only money the recruiter ever sees.
nonisolated struct RecruitCampaign: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var platform: LeadSource
    var stationId: String
    var startedAt: Date
    var endsAt: Date
    var budgetMxn: Int
    var spentMxn: Int
    var isActive: Bool
    /// Meta form the leads come from. Wired to the webhook when the integration lands.
    var externalFormId: String?

    func daysLeft(now: Date) -> Int { Int(endsAt.timeIntervalSince(now) / 86_400) }
    var spentRatio: Double { budgetMxn > 0 ? Double(spentMxn) / Double(budgetMxn) : 0 }
}

/// Read-only performance of a campaign, always derived from the prospects it generated.
nonisolated struct CampaignPerformance: Identifiable, Sendable {
    let campaign: RecruitCampaign
    let leads: Int
    let interviews: Int
    let hires: Int

    var id: String { campaign.id }
    var costPerLead: Double { leads > 0 ? Double(campaign.spentMxn) / Double(leads) : 0 }
    var costPerHire: Double { hires > 0 ? Double(campaign.spentMxn) / Double(hires) : 0 }
    var conversion: Double { leads > 0 ? Double(hires) / Double(leads) : 0 }
}

/// Comparison between acquisition channels: which one really produces drivers.
nonisolated struct SourcePerformance: Identifiable, Sendable {
    let source: LeadSource
    let leads: Int
    let interviews: Int
    let hires: Int
    let spentMxn: Int

    var id: String { source.rawValue }
    var conversion: Double { leads > 0 ? Double(hires) / Double(leads) : 0 }
    var costPerHire: Double { hires > 0 ? Double(spentMxn) / Double(hires) : 0 }
    var costPerLead: Double { leads > 0 ? Double(spentMxn) / Double(leads) : 0 }
}

// MARK: - Demand

/// Vacancies of one station, derived from the fleet — never typed by hand.
nonisolated struct StationDemand: Identifiable, Sendable {
    let station: Station
    let activeVehicles: Int
    let availableDrivers: Int
    let inProcess: Int
    let blocks: [BlockCoverage]
    let incorporations: [VehicleIncorporation]

    var id: String { station.id }
    var requiredDrivers: Int { HRRules.requiredDrivers(activeVehicles: activeVehicles) }
    var vacancies: Int { max(0, requiredDrivers - availableDrivers) }
    var coverageRatio: Double { requiredDrivers > 0 ? Double(availableDrivers) / Double(requiredDrivers) : 1 }
    var coveragePct: Int { Int((coverageRatio * 100).rounded()) }

    var incomingVehicles: Int {
        incorporations.filter { $0.stage.isIncoming }.reduce(0) { $0 + $1.units }
    }

    /// Drivers the units already bought will demand on top of today's gap.
    var futureDrivers: Int { incomingVehicles * HRRules.driversPerVehicle }
    var projectedVacancies: Int { vacancies + futureDrivers }

    /// The closest incorporation still pending, the one that sets the clock.
    func nextIncorporation(now: Date) -> VehicleIncorporation? {
        incorporations
            .filter { $0.stage.isIncoming }
            .sorted { $0.operationStartAt < $1.operationStartAt }
            .first
    }

    func daysToNextIncorporation(now: Date) -> Int? {
        nextIncorporation(now: now).map { $0.daysToOperation(now: now) }
    }

    var worstBlock: BlockCoverage? { blocks.max { $0.deficit < $1.deficit } }
}

// MARK: - Funnel

/// Counts of every stage plus the conversions that matter. A lead is not a hire.
nonisolated struct RecruitFunnel: Sendable {
    let counts: [RecruitStage: Int]
    let lost: Int
    let averageHiringDays: Int

    func count(_ stage: RecruitStage) -> Int { counts[stage] ?? 0 }

    /// Cumulative: everyone who reached this stage or went further.
    var stages: [(stage: RecruitStage, value: Int)] {
        RecruitStage.funnel.map { ($0, count($0)) }
    }

    var leads: Int { count(.lead) }
    var hires: Int { count(.hired) }

    var leadToContact: Double { ratio(.contacted, over: .lead) }
    var contactToInterview: Double { ratio(.interviewed, over: .contacted) }
    var interviewToApproved: Double { ratio(.approved, over: .interviewed) }
    var approvedToHire: Double { ratio(.hired, over: .approved) }
    var leadToHire: Double { ratio(.hired, over: .lead) }

    private func ratio(_ numerator: RecruitStage, over denominator: RecruitStage) -> Double {
        let base = count(denominator)
        guard base > 0 else { return 0 }
        return Double(count(numerator)) / Double(base)
    }
}

// MARK: - Recruiter performance

nonisolated struct RecruiterMetrics: Sendable {
    let assignedLeads: Int
    let contacted: Int
    let averageFirstContactMinutes: Int
    let interviewsDone: Int
    let interviewsScheduled: Int
    let attendedAppointments: Int
    let noShowAppointments: Int
    let readyToHire: Int
    let approved: Int
    let hires: Int
    let averageHiringDays: Int

    var contactRate: Double { assignedLeads > 0 ? Double(contacted) / Double(assignedLeads) : 0 }
    var attendanceRate: Double {
        let total = attendedAppointments + noShowAppointments
        return total > 0 ? Double(attendedAppointments) / Double(total) : 0
    }
    var conversion: Double { assignedLeads > 0 ? Double(hires) / Double(assignedLeads) : 0 }
}

// MARK: - Alerts

nonisolated enum RecruitAlertKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case coverageRisk
    case incomingUnits
    case uncontactedLeads
    case appointmentsToday
    case documentsStalled
    case hiresPending
    case leadDeficit
    case conversionDrop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coverageRisk: "Riesgo de cobertura"
        case .incomingUnits: "Unidades por incorporarse"
        case .uncontactedLeads: "Leads sin contactar"
        case .appointmentsToday: "Agenda de hoy"
        case .documentsStalled: "Documentación detenida"
        case .hiresPending: "Altas sin firmar"
        case .leadDeficit: "Leads insuficientes"
        case .conversionDrop: "Conversión a la baja"
        }
    }

    var symbol: String {
        switch self {
        case .coverageRisk: "exclamationmark.octagon.fill"
        case .incomingUnits: "bolt.car.fill"
        case .uncontactedLeads: "phone.badge.waveform.fill"
        case .appointmentsToday: "calendar.badge.clock"
        case .documentsStalled: "doc.badge.ellipsis"
        case .hiresPending: "signature"
        case .leadDeficit: "chart.line.downtrend.xyaxis"
        case .conversionDrop: "percent"
        }
    }
}

/// Where the alert takes the recruiter. An alert with no destination is just noise.
nonisolated enum RecruitDestination: String, Codable, Sendable {
    case leads
    case prospects
    case appointments
    case vacancies
    case campaigns
    case pipeline
}

nonisolated struct RecruitAlert: Identifiable, Sendable {
    let id: String
    let kind: RecruitAlertKind
    let level: OpsAlertLevel
    let title: String
    let detail: String
    let actionLabel: String
    let destination: RecruitDestination
    let stationId: String?
}

// MARK: - Documents

extension DocumentKind {
    /// What recruitment collects before signing. Contract, CLABE and social security are
    /// never asked here: those belong to the station payroll, not to the hiring process.
    static let recruitmentChecklist: [DocumentKind] = [
        .officialId, .curp, .rfc, .license, .addressProof, .photo,
    ]

    /// Documents recruitment may never touch once the contract is signed.
    var isProtectedAfterHire: Bool {
        switch self {
        case .contract, .clabe, .bankProof, .socialSecurity: true
        default: false
        }
    }
}

// MARK: - Future integrations

/// Everything the module is shaped for but does not call yet. Listed in the interface so
/// nobody assumes a connection that is not there.
nonisolated enum IntegrationChannel: String, CaseIterable, Identifiable, Sendable {
    case metaLeadAds
    case metaMarketing
    case whatsapp
    case email
    case sms
    case calendar
    case eSignature
    case ocr
    case documentAI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .metaLeadAds: "Meta Lead Ads"
        case .metaMarketing: "Meta Marketing API"
        case .whatsapp: "WhatsApp Business"
        case .email: "Correo"
        case .sms: "SMS"
        case .calendar: "Calendarios"
        case .eSignature: "Firma electrónica"
        case .ocr: "OCR de documentos"
        case .documentAI: "IA documental"
        }
    }

    var detail: String {
        switch self {
        case .metaLeadAds: "Formulario de Facebook e Instagram → webhook → lead automático"
        case .metaMarketing: "Lectura de inversión, alcance y costo por lead por campaña"
        case .whatsapp: "Primer contacto y recordatorios de cita"
        case .email: "Envío de requisitos y confirmaciones"
        case .sms: "Recordatorio de entrevista"
        case .calendar: "Agenda del reclutador y del supervisor"
        case .eSignature: "Firma de aviso de privacidad y consentimientos"
        case .ocr: "Lectura de identificación, CURP y licencia"
        case .documentAI: "Validación automática de expediente inicial"
        }
    }

    var symbol: String {
        switch self {
        case .metaLeadAds: "megaphone.fill"
        case .metaMarketing: "chart.bar.xaxis"
        case .whatsapp: "bubble.left.and.bubble.right.fill"
        case .email: "envelope.fill"
        case .sms: "message.fill"
        case .calendar: "calendar"
        case .eSignature: "signature"
        case .ocr: "doc.viewfinder.fill"
        case .documentAI: "sparkles.rectangle.stack.fill"
        }
    }
}

/// Shape of a Meta Lead Ads form submission. Today it is filled by the simulator; when
/// the webhook lands only the transport changes, not this contract.
nonisolated struct LeadAdPayload: Codable, Sendable {
    let leadgenId: String
    let formId: String
    let campaignId: String?
    let platform: LeadSource
    let fullName: String
    let phone: String
    let email: String
    let city: String
    let stationCode: String
    let requestedBlock: ShiftBlock
    let experienceYears: Int
    let platforms: [String]
    let age: Int
    let hasLicense: Bool
    let createdAt: Date
}

// MARK: - Alta delivered to the station

/// What the station receives once recruitment signs the alta. It is a one-way, read-only
/// packet: nobody at the station approves it, the office only turns it into an employee
/// file so the driver can start working.
nonisolated struct HirePacket: Codable, Identifiable, Sendable {
    let id: String
    let prospectId: String
    let stationId: String
    var name: String
    var initials: String
    var phone: String
    var block: ShiftBlock
    var experienceYears: Int
    var platforms: [String]
    var availabilityNote: String
    var screeningOutcome: ScreeningOutcome
    var interviewScorePct: Int
    var interviewSuggestion: InterviewSuggestion
    var documentPct: Int
    var recruiterName: String
    var comments: String
    var sentAt: Date
    var verdict: HiringVerdict?
    var verdictNote: String?
    var verdictAt: Date?
    /// Who signed the alta. Always the recruitment desk of the station.
    var verdictBy: String?
    /// When the contract was signed by recruitment.
    var hiredAt: Date?
    /// Payload the station office needs to open the employee file. Optional so packets
    /// saved before recruitment owned the hire still decode.
    var employeeNumber: String?
    var curp: String?
    var email: String?
    var documents: [StaffDocument]?
    /// Set by the station office once the employee file exists.
    var ingestedAt: Date?

    /// Signed by recruitment and not yet turned into an employee file.
    var needsFile: Bool { hiredAt != nil && ingestedAt == nil }
}

/// Bridge from the recruitment desk to the station office. Same pattern as the national
/// CLABE registry: what one role writes, the other reads on its next refresh. It only
/// carries finished altas — there is no pending tray to approve on the other side.
nonisolated enum RecruitmentHandoff {
    private static let storageKey = "turnoev.recruit.handoff.v1"

    private static func load() -> [HirePacket] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([HirePacket].self, from: data)) ?? []
    }

    private static func save(_ packets: [HirePacket]) {
        guard let data = try? JSONEncoder().encode(packets) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func all() -> [HirePacket] {
        load().sorted { $0.sentAt > $1.sentAt }
    }

    static func packets(stationId: String) -> [HirePacket] {
        all().filter { $0.stationId == stationId }
    }

    /// Altas already signed that the station has not turned into a file yet.
    static func awaitingFile(stationId: String) -> [HirePacket] {
        packets(stationId: stationId).filter(\.needsFile)
    }

    /// Hires of a station, most recent first. Read-only for the station.
    static func hires(stationId: String) -> [HirePacket] {
        packets(stationId: stationId).filter { $0.hiredAt != nil }
    }

    static func submit(_ packet: HirePacket) {
        var packets = load().filter { $0.prospectId != packet.prospectId }
        packets.append(packet)
        save(packets)
    }

    /// The station office signals that the employee file already exists.
    static func markIngested(prospectId: String, at date: Date) {
        var packets = load()
        guard let index = packets.firstIndex(where: { $0.prospectId == prospectId }) else { return }
        packets[index].ingestedAt = date
        save(packets)
    }

    static func remove(prospectId: String) {
        save(load().filter { $0.prospectId != prospectId })
    }
}

// MARK: - Rules

nonisolated enum RecruitRules {
    /// A lead that waits longer than this stops answering. Four hours.
    static let contactSlaMinutes = 240
    /// Default safety margin over the statistical need.
    static let defaultMarginPct = 15
    /// Fallback when there is no history yet.
    static let defaultHiringDays = 12
    /// Documentation is considered stalled after this many days without movement.
    static let documentStallDays = 5

    /// Leads to generate so that `hires` contracts actually get signed.
    static func leadsNeeded(hires: Int, conversion: Double, marginPct: Int = defaultMarginPct) -> Int {
        guard hires > 0 else { return 0 }
        let rate = conversion > 0.02 ? conversion : 0.25
        let base = Double(hires) / rate
        return Int((base * (1 + Double(marginPct) / 100)).rounded(.up))
    }

    /// Recommended budget. It is a recommendation: nothing is activated automatically.
    static func budget(leads: Int, costPerLead: Double) -> Int {
        guard leads > 0, costPerLead > 0 else { return 0 }
        return Int((Double(leads) * costPerLead).rounded())
    }

    /// Can the current pace deliver the drivers before the units start operating?
    static func coverageRisk(daysAvailable: Int, averageHiringDays: Int, deficit: Int) -> OpsAlertLevel {
        HRRules.hiringRisk(daysAvailable: daysAvailable, averageHiringDays: averageHiringDays, deficit: deficit)
    }

    /// Hires the pipeline will realistically deliver by the deadline.
    static func projectedHires(inProcess: Int, conversion: Double, daysAvailable: Int, averageHiringDays: Int) -> Int {
        guard inProcess > 0, daysAvailable > 0 else { return 0 }
        let rate = conversion > 0.02 ? conversion : 0.25
        // Only the part of the pipeline that has time to finish counts.
        let usableRatio = min(1, Double(daysAvailable) / Double(max(1, averageHiringDays)))
        return Int((Double(inProcess) * rate * usableRatio).rounded())
    }

    static func normalizePhone(_ phone: String) -> String {
        String(phone.filter(\.isNumber).suffix(10))
    }

    static func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizeCurp(_ curp: String) -> String {
        curp.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Duplicate check before creating a file: phone, email or CURP.
    static func isDuplicate(_ candidate: Prospect, of existing: Prospect) -> Bool {
        if existing.id == candidate.id { return false }
        let phone = normalizePhone(candidate.phone)
        if !phone.isEmpty, normalizePhone(existing.phone) == phone { return true }
        let email = normalizeEmail(candidate.email)
        if !email.isEmpty, normalizeEmail(existing.email) == email { return true }
        let curp = normalizeCurp(candidate.curp)
        if curp.count >= 10, normalizeCurp(existing.curp) == curp { return true }
        return false
    }

    static func duplicateMatch(phone: String, email: String, curp: String, in prospects: [Prospect]) -> Prospect? {
        let normalizedPhone = normalizePhone(phone)
        let normalizedEmail = normalizeEmail(email)
        let normalizedCurp = normalizeCurp(curp)
        return prospects.first { existing in
            if !normalizedPhone.isEmpty, normalizePhone(existing.phone) == normalizedPhone { return true }
            if !normalizedEmail.isEmpty, normalizeEmail(existing.email) == normalizedEmail { return true }
            if normalizedCurp.count >= 10, normalizeCurp(existing.curp) == normalizedCurp { return true }
            return false
        }
    }
}
