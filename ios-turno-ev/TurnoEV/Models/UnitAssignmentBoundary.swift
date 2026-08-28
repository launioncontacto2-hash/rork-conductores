import Foundation

/// Where a unit assignment came from.
///
/// **Why not `RecordOrigin`.** The financial stamp answers "who is good for this money":
/// it lives on ledgers, and a settlement subtracts by it. This answers a different
/// question — "who tied this unit to this person" — and it is read by the start of
/// shift, the QR cross-check and the dossier, never by a settlement. Sharing one type
/// would mean that the day the financial vocabulary grows a third case (an imported
/// statement, a reconciled deposit), that case silently becomes a valid provenance for
/// a vehicle assignment as well, and someone would have to remember it does not belong
/// there. Same philosophy, two vocabularies: the operation and the money can move to
/// the server on different days, and neither should drag the other along.
nonisolated enum AssignmentOrigin: String, Codable, Sendable {
    /// Written on this device by a demonstration or laboratory session.
    case simulated
    /// Delivered by the station's operational system for a proved identity.
    case backend

    var label: String {
        switch self {
        case .simulated: "Asignación de demostración"
        case .backend: "Asignación de la estación"
        }
    }
}

/// What a session is allowed to do with unit assignments and fleet inventory.
nonisolated enum UnitAssignmentCapability: Sendable {
    /// A demonstration session: it may seed, assign and release units locally, because
    /// walking the operation end to end is the whole point of the demonstration.
    case localSimulation
    /// A proved identity: units and inventory belong to the station's system. Nothing
    /// here may be minted, adopted or released locally.
    case stationRequired

    var allowsLocalSimulation: Bool { self == .localSimulation }

    /// Provenance an assignment written under this capability carries.
    ///
    /// `.stationRequired` never actually reaches a write — every writer refuses first —
    /// but the mapping is stated so no caller has to invent a stamp.
    var origin: AssignmentOrigin {
        switch self {
        case .localSimulation: .simulated
        case .stationRequired: .backend
        }
    }
}

/// Why a unit operation stopped before touching anything.
nonisolated enum UnitAssignmentError: LocalizedError, Sendable {
    /// The station's system has to assign, change or release the unit.
    case stationRequired
    /// The unit handed to the shift is not the one this driver has assigned.
    case unitNotAssigned

    var errorDescription: String? {
        switch self {
        case .stationRequired:
            return "La asignación de unidades todavía la lleva el sistema de la estación."
        case .unitNotAssigned:
            return "Esta unidad no es la que tienes asignada."
        }
    }

    var failureReason: String? {
        switch self {
        case .stationRequired:
            return "Tu unidad la registra tu supervisor en el sistema operativo. En cuanto quede publicada aparecerá aquí."
        case .unitNotAssigned:
            return "El inicio de turno sólo procede con la unidad que la estación registró a tu nombre."
        }
    }
}

/// The single place that decides whether a stored assignment or a stored catalogue may
/// be adopted by the open session.
///
/// Pure functions on purpose: the same decision is asked from restoration, from an
/// environment switch and from a data wipe, and three copies of it is exactly how the
/// documented contradiction appeared — one route said a proved identity starts with no
/// inventory while two others handed it the demonstration fleet.
nonisolated enum UnitAssignmentRules {

    /// The assignment the session may treat as authoritative, or `nil`.
    ///
    /// Two conditions under `.stationRequired`, and both are load-bearing. Ownership
    /// alone is not enough: a `.simulated` record carrying the right `driverId` is still
    /// a row minted on this phone, and a matching string is not the station vouching for
    /// a unit. Provenance alone is not enough either: a backend row belongs to whoever
    /// it names.
    static func resolve(
        stored: VehicleAssignment?,
        driverId: String,
        capability: UnitAssignmentCapability
    ) -> VehicleAssignment? {
        guard let stored, stored.driverId == driverId else { return nil }
        switch capability {
        case .localSimulation:
            return stored
        case .stationRequired:
            return stored.origin == .backend ? stored : nil
        }
    }

    /// The fleet catalogue the session may show.
    ///
    /// A proved identity gets what the server sent, which today is nothing. The
    /// demonstration catalogue is not a reasonable stand-in: every unit in it is a real
    /// looking vehicle with a plate, a QR sticker and a bay, and showing it to a driver
    /// the station never gave a unit is how a scan gets cross-checked against a fleet
    /// that is not theirs.
    static func catalogue(
        _ stored: [Vehicle],
        capability: UnitAssignmentCapability
    ) -> [Vehicle] {
        capability.allowsLocalSimulation ? stored : []
    }
}
