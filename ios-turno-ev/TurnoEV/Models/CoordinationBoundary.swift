import Foundation

/// What a session may do with the shared coverage board.
///
/// Cobertura de turnos is not private state. An absence, a guard, a swap — each one is a
/// fact three parties act on: the driver who stops showing up, the colleague who takes
/// the seat, and the station that has to staff a unit. The whole module writes those
/// facts into one `UserDefaults` blob on one phone.
///
/// For a demonstration session that is exactly right: the laboratory needs to drive the
/// entire chain locally to show what the network will do. For an identity the backend
/// proved it is not, because there is no coverage service behind it yet: the request
/// would be "sent" to a station that never hears it, and the driver would read
/// *Reservada · pendiente de aprobación* for a seat nobody at the station knows exists.
///
/// This is the coordination twin of `FleetStore.canSimulateFinancialState`. Same shape,
/// different subject: that one guards money, this one guards shared operational
/// decisions.
nonisolated enum CoordinationCapability: Sendable {
    /// The whole workflow runs on this device, which is what a demonstration is.
    case localWorkflow
    /// Only the station can produce these facts, and it cannot be reached yet.
    case stationRequired

    var allowsLocalWorkflow: Bool { self == .localWorkflow }
}

/// Refusal to write a shared coverage fact this session cannot deliver to anybody.
///
/// Worded as a missing connection, never as a missing permission: the driver is not
/// forbidden from asking for an absence — the channel that would carry the request to
/// their station does not exist yet.
nonisolated enum CoordinationMutationError: LocalizedError, Sendable {
    case stationRequired

    var errorDescription: String? {
        switch self {
        case .stationRequired:
            "La coordinación con la estación todavía requiere conexión con el sistema operativo."
        }
    }

    var failureReason: String? {
        switch self {
        case .stationRequired:
            "Una ausencia, una guardia o un intercambio son decisiones compartidas entre tú, tu supervisor y la estación. Tu sesión está conectada al servidor y ahí todavía no existe el módulo de cobertura, así que la app no registra el movimiento en este teléfono."
        }
    }
}

/// Whether a person's day-to-day assignment is actually known to the app.
///
/// The coverage engine has always derived a daily schedule from two coarse attributes:
/// the group (weekday / weekend) and the slot (morning / evening). For the demonstration
/// roster that inference is the fixture itself — the laboratory declares those blocks, so
/// reading them back is honest.
///
/// For a proved identity it is a guess dressed as a fact. Belonging to the weekday block
/// does not establish that this person was scheduled to drive on Tuesday the 14th; only a
/// published calendar does, and there is none. The same inference was removed from
/// `BonusRules` for the same reason: it was paying punctuality bonuses for days nobody
/// had ever been assigned.
nonisolated enum ScheduleKnowledge: String, Codable, Sendable {
    /// The environment declares this person's block, so their regular days follow from it.
    case declaredBlock
    /// The block is known, the daily assignment is not, and nothing may invent it.
    case unpublished
}
