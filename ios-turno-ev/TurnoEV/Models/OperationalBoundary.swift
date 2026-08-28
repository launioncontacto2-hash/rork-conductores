import Foundation

/// Who certified that an operational event actually happened.
///
/// **Why a fourth vocabulary.** `RecordOrigin` answers "who is good for this money" and
/// is read by settlements. `AssignmentOrigin` answers "who tied this unit to this
/// person" and is read by the start cross-check. This one answers something neither of
/// them does: *did this shift occur, and did this incident get reported to anyone*. A
/// supervisor handing over a vehicle and a station certifying that a nine-hour block was
/// worked are different acts, performed by different desks, and they will very likely
/// reach the server on different days — assignment first, telemetry and shift logs
/// after. One shared enum would mean the day either vocabulary grows a case, that case
/// silently becomes a valid provenance for the other, and someone has to remember it is
/// not. Four questions, four types; each moves on its own schedule.
nonisolated enum OperationalRecordOrigin: String, Codable, Sendable {
    /// Produced on this device by a demonstration or laboratory session.
    case simulated
    /// Certified by the station's operational system for a proved identity.
    case backend

    var label: String {
        switch self {
        case .simulated: "Registro de demostración"
        case .backend: "Registro de la estación"
        }
    }
}

/// What a session may do with the shift cycle and with incidents.
nonisolated enum OperationalCapability: Sendable {
    /// A demonstration or laboratory session: the whole cycle runs locally, because
    /// walking start → evidence → active shift → close is the point of the simulation.
    case localWorkflow
    /// A proved identity in production: opening, closing and reporting are acts the
    /// station's system registers. Nothing here may be minted or closed locally.
    case stationRequired

    var allowsLocalSimulation: Bool { self == .localWorkflow }

    /// Provenance a record written under this capability carries.
    ///
    /// `.stationRequired` never reaches a write — every writer refuses first — but the
    /// mapping is stated so no caller has to invent a stamp, and so the reading side can
    /// ask "which records does this capability adopt" with the same expression.
    var origin: OperationalRecordOrigin {
        switch self {
        case .localWorkflow: .simulated
        case .stationRequired: .backend
        }
    }
}

/// Why an operational write stopped before touching anything.
///
/// Deliberately not phrased as a permission problem. The driver is who they say they
/// are and the app has nothing to object to: what is missing is the system on the other
/// end that would register the event. "No autorizado" would send someone to their
/// supervisor to ask for a right they already have.
nonisolated enum OperationalMutationError: LocalizedError, Sendable {
    /// There is no station service behind the shift cycle yet.
    case backendRequired
    /// A shift is standing in memory that this session cannot answer for.
    case unauthoritativeShift

    var errorDescription: String? {
        switch self {
        case .backendRequired:
            return "Esta operación requiere conexión con el sistema operativo de la estación."
        case .unauthoritativeShift:
            return "Este turno no lo registró el sistema de tu estación."
        }
    }

    var failureReason: String? {
        switch self {
        case .backendRequired:
            return "El inicio y el cierre de turno los registra el sistema operativo de tu estación. En cuanto la aplicación quede conectada, este paso se completa desde aquí."
        case .unauthoritativeShift:
            return "Quedó abierto en una simulación, así que no puede cerrarse como un turno real. Vuelve al laboratorio para cerrarlo ahí."
        }
    }
}

/// The single place that decides which stored operational records the open session may
/// adopt.
///
/// Pure functions, for the same reason the assignment rules are: restoration, an
/// environment switch and the bonus engine all ask this question, and three private
/// copies of the answer is precisely how a fixture ends up being paid.
nonisolated enum OperationalRecordRules {

    /// Whether a record belonging to `driverId` with this provenance is adoptable.
    ///
    /// Two conditions under `.stationRequired`, and both are load-bearing. Ownership
    /// alone is not enough: a `.simulated` row carrying the right `driverId` is still a
    /// row minted on this phone, and a matching string is not the station certifying that
    /// a shift happened. Provenance alone is not enough either: a backend row belongs to
    /// whoever it names.
    static func adopts(
        owner: String,
        origin: OperationalRecordOrigin,
        driverId: String,
        capability: OperationalCapability
    ) -> Bool {
        guard owner == driverId else { return false }
        switch capability {
        case .localWorkflow: return true
        case .stationRequired: return origin == .backend
        }
    }

    static func shift(
        _ stored: ActiveShift?,
        driverId: String,
        capability: OperationalCapability
    ) -> ActiveShift? {
        guard let stored else { return nil }
        return adopts(
            owner: stored.driverId,
            origin: stored.origin,
            driverId: driverId,
            capability: capability
        ) ? stored : nil
    }

    static func history(
        _ stored: [ShiftRecord],
        driverId: String,
        capability: OperationalCapability
    ) -> [ShiftRecord] {
        stored.filter {
            adopts(owner: $0.driverId, origin: $0.origin, driverId: driverId, capability: capability)
        }
    }

    static func incidents(
        _ stored: [Incident],
        driverId: String,
        capability: OperationalCapability
    ) -> [Incident] {
        stored.filter {
            adopts(owner: $0.driverId, origin: $0.origin, driverId: driverId, capability: capability)
        }
    }
}
