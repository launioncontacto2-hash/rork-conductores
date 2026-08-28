import Foundation

/// Where a financial record came from.
///
/// The app has two kinds of money on screen and, until 15B.10, no way to tell them
/// apart once they were stored: fixtures a demonstration session minted on the phone to
/// walk through a flow, and records an authority produced. Settlement and bonuses
/// consumed both as truth.
///
/// This is the field that separates them. It travels **inside** the record, so the
/// question "is this real?" can be answered wherever the record is read, instead of
/// being inferred from the session that happens to be open at the time.
nonisolated enum RecordOrigin: String, Codable, Sendable {
    /// Minted locally to demonstrate a flow. Never authoritative.
    case simulated
    /// Produced by the backend for a proved identity.
    case backend
}

/// Refusal to write financial state that this session cannot vouch for.
///
/// It is not a permission problem and must never be worded as one: the driver is not
/// doing anything forbidden, the capability simply does not exist yet on the server.
nonisolated enum FinancialMutationError: LocalizedError, Sendable {
    /// The operation needs a backend that can register it, and there is none yet.
    case backendRequired

    var errorDescription: String? {
        switch self {
        case .backendRequired:
            "Esta operación requiere sincronización con el sistema financiero y todavía no está disponible."
        }
    }

    var failureReason: String? {
        switch self {
        case .backendRequired:
            "Tu sesión está conectada al servidor, y un movimiento financiero sólo puede registrarse allí. Aún no existe esa conexión, así que la app no lo simula localmente."
        }
    }
}
