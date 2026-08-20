import Foundation

/// Cobertura de turnos: the formal answer to "who will drive this vehicle if the
/// scheduled driver cannot work?".
///
/// Two states are kept deliberately apart and never collapse into one:
/// the **coverage** of the seat (is somebody driving that unit) and the **authorization**
/// of the absence (is the driver excused). Finding a substitute never excuses anybody;
/// that decision belongs to Human Resources policy, which this module only feeds.

// MARK: - Configurable policy

/// How much the system decides by itself. The network starts semi-automatic: the engine
/// finds and ranks candidates, a human still signs.
nonisolated enum CoverageAutomation: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case semiAutomatic
    case automatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .semiAutomatic: "Semiautomático"
        case .automatic: "Automático"
        }
    }

    var detail: String {
        switch self {
        case .manual: "El supervisor aprueba cada reemplazo, uno por uno."
        case .semiAutomatic: "El sistema filtra y ordena a los elegibles; el supervisor confirma."
        case .automatic: "El sistema asigna solo cuando todas las reglas configuradas se cumplen."
        }
    }

    var symbol: String {
        switch self {
        case .manual: "hand.raised.fill"
        case .semiAutomatic: "person.badge.shield.checkmark.fill"
        case .automatic: "bolt.badge.automatic.fill"
        }
    }
}

/// Every limit of the module lives here so nothing legal is frozen in code. Human
/// Resources adjusts these numbers later without touching the engine.
nonisolated struct CoveragePolicy: Codable, Sendable {
    /// Hours a driver must rest between the end of one shift and the start of the next.
    var minimumRestHours: Int
    /// Shifts one person may work inside the same week, own turns included.
    var maxShiftsPerWeek: Int
    /// Extra guards one person may take inside the same week.
    var maxGuardsPerWeek: Int
    /// Days in a row somebody may work before the engine stops offering guards.
    var maxConsecutiveDays: Int
    /// Under this many hours before the start, an absence is treated as an emergency.
    var emergencyThresholdHours: Int
    /// How long a reservation holds the seat before it returns to the pool.
    var claimHoldMinutes: Int
    /// Whether a driver of another station may be offered the seat.
    var allowsCrossStation: Bool
    /// Whether the absence needs a signature after the seat is covered.
    var absenceRequiresAuthorization: Bool
    var automation: CoverageAutomation
    /// Default guard bonus proposed when a vacancy opens.
    var defaultBonusMxn: Int

    static let standard = CoveragePolicy(
        minimumRestHours: 8,
        maxShiftsPerWeek: 6,
        maxGuardsPerWeek: 3,
        maxConsecutiveDays: 6,
        emergencyThresholdHours: 12,
        claimHoldMinutes: 120,
        allowsCrossStation: false,
        absenceRequiresAuthorization: true,
        automation: .semiAutomatic,
        defaultBonusMxn: 450
    )
}

// MARK: - Driver status flags

/// Everything about a person that can block a guard and does not live in the operational
/// record yet. The laboratory writes these; production will read them from the employee
/// file and the document vault.
nonisolated struct CoverageDriverFlags: Codable, Sendable, Equatable {
    var licenseValidUntil: Date?
    var documentsValid: Bool
    var isSuspended: Bool
    var vacationUntil: Date?
    var incapacityUntil: Date?
    /// The person told the station they want extraordinary work when it appears.
    var acceptsExtraordinary: Bool

    static let clear = CoverageDriverFlags(
        licenseValidUntil: nil,
        documentsValid: true,
        isSuspended: false,
        vacationUntil: nil,
        incapacityUntil: nil,
        acceptsExtraordinary: false
    )
}

/// A driver as the coverage engine sees them. Built from the active environment, never
/// stored: the module owns no roster of its own.
nonisolated struct CoverageDriverProfile: Identifiable, Sendable {
    let id: String
    let name: String
    let employeeNumber: String
    let stationId: String
    let stationCode: String
    let slot: ShiftSlot
    let group: ShiftGroup
    var flags: CoverageDriverFlags

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var shortName: String {
        let parts = name.split(separator: " ")
        guard parts.count >= 2 else { return name }
        return "\(parts[0]) \(parts[1])"
    }
}

// MARK: - Absences

nonisolated enum AbsenceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case scheduled
    case emergency
    case leave
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scheduled: "Ausencia programada"
        case .emergency: "Emergencia"
        case .leave: "Permiso"
        case .other: "Otro"
        }
    }

    var shortLabel: String {
        switch self {
        case .scheduled: "Programada"
        case .emergency: "Emergencia"
        case .leave: "Permiso"
        case .other: "Otro"
        }
    }

    var hint: String {
        switch self {
        case .scheduled: "Avisas con anticipación y da tiempo de buscar cobertura"
        case .emergency: "Algo ocurrió y el turno está por empezar"
        case .leave: "Trámite, cita médica o asunto autorizado"
        case .other: "Cualquier motivo que no entre en los anteriores"
        }
    }

    var symbol: String {
        switch self {
        case .scheduled: "calendar.badge.clock"
        case .emergency: "exclamationmark.triangle.fill"
        case .leave: "doc.text.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    /// Emergencies raise a critical alert and skip straight to an urgent search.
    var isUrgent: Bool { self == .emergency }
}

/// The life of a request. Coverage advances it up to `awaitingAuthorization`; only a
/// signature moves it to `approved`.
nonisolated enum AbsenceStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case requested
    case searching
    case covered
    case awaitingAuthorization
    case approved
    case rejected
    case cancelled
    case uncovered

    var id: String { rawValue }

    var label: String {
        switch self {
        case .requested: "Solicitada"
        case .searching: "Buscando cobertura"
        case .covered: "Cobertura encontrada"
        case .awaitingAuthorization: "Pendiente de autorización"
        case .approved: "Aprobada"
        case .rejected: "Rechazada"
        case .cancelled: "Cancelada"
        case .uncovered: "Sin cobertura"
        }
    }

    var detail: String {
        switch self {
        case .requested: "Tu solicitud fue recibida. Todavía no está autorizada."
        case .searching: "El sistema está ofreciendo tu turno a conductores elegibles."
        case .covered: "Ya hay un candidato para tu turno, falta la firma del supervisor."
        case .awaitingAuthorization: "El turno queda cubierto. Tu ausencia espera autorización."
        case .approved: "Tu ausencia quedó autorizada."
        case .rejected: "Tu ausencia no fue autorizada. Debes presentarte."
        case .cancelled: "Cancelaste la solicitud."
        case .uncovered: "Nadie elegible tomó el turno. Tu ausencia sigue sin cobertura."
        }
    }

    var symbol: String {
        switch self {
        case .requested: "paperplane.fill"
        case .searching: "magnifyingglass"
        case .covered: "person.fill.checkmark"
        case .awaitingAuthorization: "signature"
        case .approved: "checkmark.seal.fill"
        case .rejected: "xmark.seal.fill"
        case .cancelled: "slash.circle.fill"
        case .uncovered: "exclamationmark.triangle.fill"
        }
    }

    /// Steps shown in the driver's progress rail, in order.
    static let pipeline: [AbsenceStatus] = [.requested, .searching, .covered, .awaitingAuthorization, .approved]

    var isOpen: Bool {
        switch self {
        case .requested, .searching, .covered, .awaitingAuthorization: true
        case .approved, .rejected, .cancelled, .uncovered: false
        }
    }

    var pipelineIndex: Int { Self.pipeline.firstIndex(of: self) ?? -1 }
}

nonisolated struct AbsenceRequest: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    let driverName: String
    let employeeNumber: String
    let stationId: String
    let stationCode: String
    /// Start of the day the person will not work.
    let date: Date
    let slot: ShiftSlot
    var kind: AbsenceKind
    var reason: String
    var comments: String
    /// Evidence attached by the driver. Kept out of the coverage decision on purpose.
    var evidence: Data?
    var status: AbsenceStatus
    let createdAt: Date
    /// Vacancy opened by this request, if the seat needed a substitute.
    var vacancyId: String?
    var decidedAt: Date?
    var decidedBy: String?
    var decisionNote: String?

    var hasEvidence: Bool { evidence != nil }

    var scheduledStartAt: Date { ShiftRules.scheduledStart(slot: slot, on: date) }

    /// Hours between the request and the start of the shift it affects.
    func noticeHours(now: Date) -> Double {
        scheduledStartAt.timeIntervalSince(createdAt < now ? createdAt : now) / 3600
    }
}

// MARK: - Vacancies

nonisolated enum VacancyOrigin: String, Codable, CaseIterable, Identifiable, Sendable {
    case absence
    case extraordinary
    case cancellation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .absence: "Ausencia del titular"
        case .extraordinary: "Cobertura extraordinaria"
        case .cancellation: "Guardia cancelada"
        }
    }

    var symbol: String {
        switch self {
        case .absence: "person.fill.xmark"
        case .extraordinary: "sparkles"
        case .cancellation: "arrow.uturn.backward.circle.fill"
        }
    }
}

nonisolated enum VacancyStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case searching
    case reserved
    case confirmed
    case uncovered
    case cancelled
    case completed
    case noShow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .searching: "Buscando reemplazo"
        case .reserved: "Reservada — pendiente de aprobación"
        case .confirmed: "Confirmada"
        case .uncovered: "Sin candidatos"
        case .cancelled: "Cancelada"
        case .completed: "Completada"
        case .noShow: "No se presentó"
        }
    }

    var shortLabel: String {
        switch self {
        case .searching: "Buscando"
        case .reserved: "Reservada"
        case .confirmed: "Confirmada"
        case .uncovered: "Sin candidatos"
        case .cancelled: "Cancelada"
        case .completed: "Completada"
        case .noShow: "No se presentó"
        }
    }

    var symbol: String {
        switch self {
        case .searching: "magnifyingglass"
        case .reserved: "hourglass"
        case .confirmed: "checkmark.seal.fill"
        case .uncovered: "exclamationmark.triangle.fill"
        case .cancelled: "slash.circle.fill"
        case .completed: "flag.checkered"
        case .noShow: "person.fill.questionmark"
        }
    }

    var isOpen: Bool {
        switch self {
        case .searching, .reserved: true
        default: false
        }
    }
}

/// How the guard is paid. The amount is proposed when the seat opens and never edited
/// by the person who takes it.
nonisolated enum GuardBonusMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixed
    case variable
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: "Bono fijo"
        case .variable: "Bono variable"
        case .none: "Sin bono"
        }
    }

    var hint: String {
        switch self {
        case .fixed: "Monto cerrado al completar el turno"
        case .variable: "Monto sujeto a la facturación del turno"
        case .none: "El turno se cubre sin pago extraordinario"
        }
    }
}

nonisolated enum ClaimStatus: String, Codable, CaseIterable, Sendable {
    case reserved
    case waitlisted
    case approved
    case rejected
    case cancelled
    case expired

    var label: String {
        switch self {
        case .reserved: "Reservada"
        case .waitlisted: "En lista de espera"
        case .approved: "Aprobada"
        case .rejected: "Rechazada"
        case .cancelled: "Cancelada"
        case .expired: "Vencida"
        }
    }
}

/// One person's attempt on a seat. The first eligible claim reserves it; the rest queue
/// so a cancellation does not restart the search from zero.
nonisolated struct CoverageClaim: Codable, Identifiable, Sendable {
    let id: String
    let driverId: String
    let driverName: String
    let employeeNumber: String
    let claimedAt: Date
    var status: ClaimStatus
    var note: String?
}

/// A seat that needs somebody. It exists on its own: an absence creates one, but a
/// supervisor can open one for extra demand with no absence behind it.
nonisolated struct CoverageVacancy: Codable, Identifiable, Sendable {
    let id: String
    let stationId: String
    let stationCode: String
    let date: Date
    let slot: ShiftSlot
    var origin: VacancyOrigin
    var titularDriverId: String?
    var titularName: String?
    var vehicleId: String?
    var vehicleNumber: String?
    var bonusMode: GuardBonusMode
    var bonusMxn: Int
    var reason: String
    var status: VacancyStatus
    var absenceRequestId: String?
    /// Whoever holds the seat right now: reserved, approved or already worked.
    var claims: [CoverageClaim]
    var approvedBy: String?
    var approvedAt: Date?
    var rejectionNote: String?
    var isCritical: Bool
    let createdAt: Date
    let createdBy: String

    var scheduledStartAt: Date { ShiftRules.scheduledStart(slot: slot, on: date) }
    var scheduledEndAt: Date { ShiftRules.scheduledEnd(slot: slot, on: date) }
    var group: ShiftGroup { ShiftRules.group(for: date) }

    var durationHours: Int {
        max(0, Int(scheduledEndAt.timeIntervalSince(scheduledStartAt) / 3600))
    }

    /// The claim currently holding the seat, if any.
    var holder: CoverageClaim? {
        claims.first { $0.status == .reserved || $0.status == .approved }
    }

    var waitlist: [CoverageClaim] {
        claims.filter { $0.status == .waitlisted }.sorted { $0.claimedAt < $1.claimedAt }
    }

    var substituteName: String? { holder?.driverName }
    var substituteId: String? { holder?.driverId }

    /// Money only exists once the turn is actually worked.
    var payableBonusMxn: Int {
        guard status == .completed, bonusMode != .none else { return 0 }
        return bonusMxn
    }

    var bonusLabel: String {
        bonusMode == .none ? "Sin bono" : Fmt.mxn(bonusMxn)
    }

    func hoursUntilStart(now: Date) -> Double {
        scheduledStartAt.timeIntervalSince(now) / 3600
    }

    func isClaimed(by driverId: String) -> Bool {
        claims.contains { $0.driverId == driverId && ($0.status == .reserved || $0.status == .approved || $0.status == .waitlisted) }
    }
}

// MARK: - Shift swaps

nonisolated enum SwapStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case proposed
    case accepted
    case declined
    case awaitingSupervisor
    case approved
    case rejected
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .proposed: "Propuesto"
        case .accepted: "Aceptado por el compañero"
        case .declined: "Rechazado por el compañero"
        case .awaitingSupervisor: "Con el supervisor"
        case .approved: "Aprobado"
        case .rejected: "Rechazado"
        case .cancelled: "Cancelado"
        }
    }

    var symbol: String {
        switch self {
        case .proposed: "paperplane.fill"
        case .accepted: "hand.thumbsup.fill"
        case .declined: "hand.thumbsdown.fill"
        case .awaitingSupervisor: "signature"
        case .approved: "checkmark.seal.fill"
        case .rejected: "xmark.seal.fill"
        case .cancelled: "slash.circle.fill"
        }
    }

    var isOpen: Bool {
        switch self {
        case .proposed, .accepted, .awaitingSupervisor: true
        default: false
        }
    }
}

/// Two drivers agreeing is not enough: the engine re-checks both and the supervisor signs.
nonisolated struct ShiftSwapRequest: Codable, Identifiable, Sendable {
    let id: String
    let stationId: String
    let stationCode: String
    let fromDriverId: String
    let fromDriverName: String
    let fromDate: Date
    let fromSlot: ShiftSlot
    let toDriverId: String
    let toDriverName: String
    let toDate: Date
    let toSlot: ShiftSlot
    var status: SwapStatus
    var note: String
    let createdAt: Date
    var respondedAt: Date?
    var resolvedAt: Date?
    var resolvedBy: String?
    var decisionNote: String?
    /// Blocking findings of the last eligibility pass on both sides.
    var blockers: [String]

    var summary: String {
        "\(Fmt.dateShort(fromDate)) \(fromSlot.label.lowercased()) ⇄ \(Fmt.dateShort(toDate)) \(toSlot.label.lowercased())"
    }
}

// MARK: - Eligibility

nonisolated enum EligibilityRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case station
    case employment
    case notSuspended
    case license
    case documents
    case notOnVacation
    case notIncapacitated
    case slotCompatibility
    case noOverlap
    case rest
    case weeklyLoad
    case guardLoad
    case noConflictingGuard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .station: "Estación autorizada"
        case .employment: "Estado laboral activo"
        case .notSuspended: "Sin suspensión"
        case .license: "Licencia vigente"
        case .documents: "Documentación vigente"
        case .notOnVacation: "Sin vacaciones"
        case .notIncapacitated: "Sin incapacidad"
        case .slotCompatibility: "Compatibilidad de turno"
        case .noOverlap: "Sin turno simultáneo"
        case .rest: "Descanso suficiente"
        case .weeklyLoad: "Límite de jornada"
        case .guardLoad: "Límite de guardias"
        case .noConflictingGuard: "Sin guardia incompatible"
        }
    }

    /// Grouped the way the supervisor reads the approval card.
    var family: String {
        switch self {
        case .station, .slotCompatibility: "Disponibilidad"
        case .employment, .notSuspended, .notOnVacation, .notIncapacitated: "Estado laboral"
        case .license, .documents: "Documentación"
        case .noOverlap, .noConflictingGuard: "Sin conflicto"
        case .rest, .weeklyLoad, .guardLoad: "Horarios"
        }
    }
}

nonisolated struct EligibilityCheck: Codable, Identifiable, Sendable {
    let rule: EligibilityRule
    let passed: Bool
    let detail: String

    var id: String { rule.rawValue }
}

/// Result of running every rule against one person for one seat, plus the score used to
/// order the offer. Order never depends on friendship or on who the titular prefers.
nonisolated struct EligibilityVerdict: Identifiable, Sendable {
    let driverId: String
    let driverName: String
    let employeeNumber: String
    let checks: [EligibilityCheck]
    /// Higher goes first. Built from complementary group, declared availability,
    /// accumulated guards and completion history — never from personal preference.
    let score: Double
    let priorityReason: String

    var id: String { driverId }
    var isEligible: Bool { checks.allSatisfy(\.passed) }
    var blockers: [EligibilityCheck] { checks.filter { !$0.passed } }
    var blockerSummary: String { blockers.map(\.rule.label).joined(separator: " · ") }
}

// MARK: - Reliability

/// Operational reading of how a person behaves with guards. It is information, not a
/// sanction: nothing in the app turns this number into a labour consequence by itself.
nonisolated struct CoverageReliability: Identifiable, Sendable {
    let driverId: String
    let driverName: String
    let accepted: Int
    let completed: Int
    let cancelled: Int
    let noShows: Int
    let lateStarts: Int

    var id: String { driverId }

    var completionRate: Double {
        accepted > 0 ? Double(completed) / Double(accepted) : 0
    }

    /// 0–100. Completing lifts it; cancelling and not showing up pull it down hard.
    var score: Int {
        guard accepted > 0 else { return 0 }
        let base = completionRate * 100
        let penalty = Double(cancelled) * 6 + Double(noShows) * 18 + Double(lateStarts) * 3
        return max(0, min(100, Int((base - penalty).rounded())))
    }

    var label: String {
        guard accepted > 0 else { return "Sin historial" }
        switch score {
        case 85...: return "Confiable"
        case 65..<85: return "Aceptable"
        case 40..<65: return "Irregular"
        default: return "Crítico"
        }
    }
}

// MARK: - Audit

/// Immutable trace. Nothing in the app edits or deletes an entry once written — not the
/// driver, not the supervisor.
nonisolated struct CoverageAuditEntry: Codable, Identifiable, Sendable {
    let id: String
    let createdAt: Date
    /// Who did it, by name and employee number.
    let actor: String
    let actorRole: StaffRole
    let action: String
    let stationCode: String
    let shiftLabel: String
    let previousState: String
    let newState: String
    let detail: String
    let device: String?
}

// MARK: - Calendar

nonisolated enum CoverageDayKind: String, Codable, Sendable {
    case regular
    case rest
    case guardConfirmed
    case guardReserved
    case absenceRequested
    case absenceApproved
    case swap
    case extraordinary
    case noShow

    var label: String {
        switch self {
        case .regular: "Turno normal"
        case .rest: "Día libre"
        case .guardConfirmed: "Guardia confirmada"
        case .guardReserved: "Guardia reservada"
        case .absenceRequested: "Ausencia solicitada"
        case .absenceApproved: "Ausencia aprobada"
        case .swap: "Intercambio"
        case .extraordinary: "Turno extraordinario"
        case .noShow: "No se presentó"
        }
    }

    var symbol: String {
        switch self {
        case .regular: "steeringwheel"
        case .rest: "moon.zzz.fill"
        case .guardConfirmed: "checkmark.seal.fill"
        case .guardReserved: "hourglass"
        case .absenceRequested: "paperplane.fill"
        case .absenceApproved: "checkmark.circle.fill"
        case .swap: "arrow.left.arrow.right"
        case .extraordinary: "sparkles"
        case .noShow: "person.fill.questionmark"
        }
    }
}

/// One square of the driver's month.
nonisolated struct CoverageCalendarDay: Identifiable, Sendable {
    let date: Date
    let kind: CoverageDayKind
    let slot: ShiftSlot?
    let stationCode: String
    let vehicleNumber: String?
    let statusLabel: String
    let detail: String
    let bonusMxn: Int?
    let vacancyId: String?
    let absenceId: String?

    var id: Date { date }

    var scheduleLabel: String {
        guard let slot else { return "Sin turno" }
        return "\(slot.label) · \(slot.rangeLabel)"
    }
}

// MARK: - Notifications

/// Interactive message of the module. A guard offer carries the seat it refers to so the
/// person can take it straight from the notice instead of hunting for it in a list.
nonisolated enum CoverageNoticeKind: String, Codable, Sendable {
    case guardAvailable
    case guardConfirmed
    case guardRejected
    case guardCancelled
    case guardReminder
    case absenceProcessed
    case absenceApproved
    case absenceRejected
    case absenceUncovered
    case swapProposed
    case swapResolved
    case criticalCoverage

    var label: String {
        switch self {
        case .guardAvailable: "Guardia disponible"
        case .guardConfirmed: "Guardia confirmada"
        case .guardRejected: "Guardia rechazada"
        case .guardCancelled: "Guardia cancelada"
        case .guardReminder: "Cambio de horario"
        case .absenceProcessed: "Solicitud procesada"
        case .absenceApproved: "Ausencia aprobada"
        case .absenceRejected: "Ausencia rechazada"
        case .absenceUncovered: "Sin cobertura"
        case .swapProposed: "Intercambio propuesto"
        case .swapResolved: "Intercambio resuelto"
        case .criticalCoverage: "Alerta crítica de cobertura"
        }
    }

    var symbol: String {
        switch self {
        case .guardAvailable: "bell.badge.fill"
        case .guardConfirmed: "checkmark.seal.fill"
        case .guardRejected: "xmark.seal.fill"
        case .guardCancelled: "slash.circle.fill"
        case .guardReminder: "clock.badge.exclamationmark.fill"
        case .absenceProcessed: "arrow.triangle.branch"
        case .absenceApproved: "checkmark.circle.fill"
        case .absenceRejected: "xmark.circle.fill"
        case .absenceUncovered: "exclamationmark.triangle.fill"
        case .swapProposed: "arrow.left.arrow.right"
        case .swapResolved: "arrow.left.arrow.right.circle.fill"
        case .criticalCoverage: "exclamationmark.octagon.fill"
        }
    }

    var isCritical: Bool { self == .criticalCoverage || self == .absenceUncovered }
}

nonisolated struct CoverageNotification: Codable, Identifiable, Sendable {
    let id: String
    /// Person this message belongs to. Supervisor messages carry the account id.
    let recipientId: String
    let kind: CoverageNoticeKind
    let title: String
    let body: String
    let createdAt: Date
    /// Seat the message is about, so the notice itself can carry the action.
    var vacancyId: String?
    var swapId: String?
    var isRead: Bool
}

// MARK: - Station coverage board

/// What the supervisor sees at a glance: seats needed versus seats with a person on them,
/// per block of the day.
nonisolated struct CoverageSlotBoard: Identifiable, Sendable {
    let slot: ShiftSlot
    let group: ShiftGroup
    let required: Int
    let scheduled: Int
    let openVacancies: Int
    let confirmedGuards: Int

    var id: String { slot.rawValue }

    var covered: Int { min(required, scheduled + confirmedGuards) }
    var missing: Int { max(0, required - covered) }
    var ratio: Double { required > 0 ? Double(covered) / Double(required) : 1 }
    var label: String { "\(slot.label) \(group == .weekend ? "S-D" : "L-V")" }
}

/// A future day the station will not be able to staff, detected before it arrives.
nonisolated struct CoverageForecastDay: Identifiable, Sendable {
    let date: Date
    let required: Int
    let scheduled: Int
    let openVacancies: Int

    var id: Date { date }
    var deficit: Int { max(0, required - scheduled) }
    var hasDeficit: Bool { deficit > 0 }
}
