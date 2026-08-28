import Foundation

/// Who published a notice.
///
/// **Why a fifth vocabulary.** `RecordOrigin` answers "who is good for this money".
/// `AssignmentOrigin` answers "who tied this unit to this person". `OperationalRecordOrigin`
/// answers "did this shift happen, was this incident reported". None of them answers the
/// question a notice raises, which is narrower and stranger than all three: *who is
/// speaking*. A notice is not a record of an event — it is a sentence in the second
/// person, addressed to the driver, in the voice of the station. "Tu reporte quedó en
/// revisión" is an assertion about a desk somewhere, made by an authority the driver
/// cannot audit. That is why it is dangerous out of proportion to its size: an incident
/// row is inert until somebody reads it, but a notice *is* the reading.
///
/// The vocabularies also move apart in a direction the others do not. A station will one
/// day publish notices that correspond to no local record at all — a bay closure, a
/// policy change, a summons. Those are `.backend` with nothing of `RecordOrigin`'s
/// meaning behind them. Sharing an enum would make that legitimate future case
/// indistinguishable from a promoted fixture.
nonisolated enum NoticeOrigin: String, Codable, Sendable {
    /// Written by this device: a demonstration fixture, or a laboratory session
    /// narrating its own simulation back to itself.
    case simulated
    /// Published by the station's system for a proved identity.
    case backend

    var label: String {
        switch self {
        case .simulated: "Aviso de demostración"
        case .backend: "Aviso de la estación"
        }
    }
}

/// Whether the open session may speak in the station's voice.
nonisolated enum NoticeAuthority: Sendable {
    /// A demonstration or laboratory session. The device keeps its own bulletin board,
    /// because narrating the simulation is what makes the simulation legible.
    case localBulletin
    /// A proved identity in production. The bell shows what the station published and
    /// nothing else — which today is nothing, and an empty bell is the truth.
    case stationPublished

    var allowsLocalWriting: Bool { self == .localBulletin }

    /// Provenance a notice written under this authority carries. `.stationPublished`
    /// never reaches a write; the mapping exists so the reading side can ask "which
    /// notices does this authority show" with the same expression the writer refuses on.
    var origin: NoticeOrigin {
        switch self {
        case .localBulletin: .simulated
        case .stationPublished: .backend
        }
    }
}

/// The single place that decides which notices a session may show and write.
///
/// Notices carry no `driverId`: ownership is established by the container they were
/// stored in, one blob per identity per environment. Provenance is therefore the only
/// question left, and it is asked here so restoration, the bell counter and the list all
/// get the same answer.
nonisolated enum NoticeRules {

    static func adopts(origin: NoticeOrigin, authority: NoticeAuthority) -> Bool {
        switch authority {
        case .localBulletin: return true
        case .stationPublished: return origin == .backend
        }
    }

    /// What the interface may render.
    ///
    /// A `.simulated` notice is filtered, never deleted: it stays in the blob it was
    /// written to and reappears the moment the laboratory asks for that blob again.
    static func visible(_ notices: [Notice], authority: NoticeAuthority) -> [Notice] {
        notices.filter { adopts(origin: $0.origin, authority: authority) }
    }
}
