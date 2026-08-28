import Foundation

/// Who produced a coverage notification.
///
/// **Why a sixth vocabulary, and specifically why not `NoticeOrigin`.** The two look
/// interchangeable and are not. `NoticeOrigin` seals the general bell: an unaddressed
/// sentence spoken to whoever holds the phone, owned by the container it was stored in.
/// A coverage notification is a different object. It names a `recipientId`, it carries a
/// `vacancyId` or a `swapId`, and it is one half of a workflow the other half of which is
/// a seat on a board — a shared fact that a supervisor, a substitute and a titular all
/// act on. It is not a message *about* an operation; it is a step *of* one, and it is
/// actionable: the driver can take the guard straight from it.
///
/// That difference decides the reading rule below. An unattributed sentence is merely
/// unverified. A row that says "Guardia disponible · Sábado 14, matutino" points at a
/// vacancy id that exists in one book and not in the other, so showing it under the wrong
/// authority is worse than noise — it is an offer of work that resolves to nothing, or an
/// approval for a seat the station never opened.
///
/// The two also diverge in time, like the four boundaries before them: the general bell
/// opens when a station starts *publishing*, this one opens when a coverage *service*
/// exists to route a seat between three people. Neither implies the other.
nonisolated enum CoverageNotificationOrigin: String, Codable, Sendable {
    /// Produced by the local workflow engine: a demonstration or the laboratory driving
    /// the whole absence → vacancy → claim → approval chain on this device.
    case simulated
    /// Routed by the station's coverage service for a proved identity.
    case backend

    /// Provenance the mirrored copy carries in the general bell. The mapping is the whole
    /// point of keeping the two vocabularies apart *and* connected: a simulated coverage
    /// row may reach the bell, but only as a simulated notice.
    var generalBell: NoticeOrigin {
        switch self {
        case .simulated: .simulated
        case .backend: .backend
        }
    }
}

/// Whether the open session's coverage book is a local simulation or the station's.
nonisolated enum CoverageNoticeAuthority: Sendable {
    /// The whole workflow runs here, which is what a demonstration is.
    case localWorkflow
    /// A proved identity. Only what the station routed belongs in this tray, which today
    /// is nothing.
    case stationRouted

    /// Provenance a notification written under this authority carries.
    var origin: CoverageNotificationOrigin {
        switch self {
        case .localWorkflow: .simulated
        case .stationRouted: .backend
        }
    }
}

/// The single place that decides which coverage notifications a session may read, count
/// and mark.
nonisolated enum CoverageNoticeRules {

    /// Strict in both directions, unlike `NoticeRules`, which lets the laboratory read a
    /// station notice.
    ///
    /// The reason is the container: `FleetStore` keeps one blob per identity **and**
    /// environment, so a demonstration and a proved driver never share storage. The
    /// coverage board is keyed by environment alone — a demonstration session and a
    /// proved identity in production read the very same `turnoev.coverage.v1`. Provenance
    /// is therefore the only thing standing between them, and a row minted by one has no
    /// business being counted, shown or dismissed by the other.
    static func adopts(origin: CoverageNotificationOrigin, authority: CoverageNoticeAuthority) -> Bool {
        origin == authority.origin
    }

    /// What the interface may render. Filtered, never deleted: the rows stay in the blob
    /// and come back the moment the laboratory asks for that book again.
    static func visible(
        _ notifications: [CoverageNotification],
        authority: CoverageNoticeAuthority
    ) -> [CoverageNotification] {
        notifications.filter { adopts(origin: $0.origin, authority: authority) }
    }
}
