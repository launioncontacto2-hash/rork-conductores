import Foundation

nonisolated enum AcquisitionRole: String, Codable, Sendable {
    case doriAdmin = "dori_admin"
    case provider

    var sessionRole: StaffRole {
        switch self {
        case .doriAdmin: .doriAdmin
        case .provider: .provider
        }
    }
}

/// The acquisition-specific authorization granted to the authenticated profile.
/// External providers live here and never become members of `staff_memberships`.
nonisolated struct AcquisitionMembership: Codable, Equatable, Sendable {
    let id: UUID
    let environmentID: UUID
    let profileID: UUID
    let supplierID: UUID?
    let role: AcquisitionRole

    init(
        id: UUID,
        environmentID: UUID,
        profileID: UUID,
        supplierID: UUID?,
        role: AcquisitionRole
    ) {
        self.id = id
        self.environmentID = environmentID
        self.profileID = profileID
        self.supplierID = supplierID
        self.role = role
    }
}

/// Public request fields only. Internal SOH and price rules deliberately have no client model.
nonisolated struct AcquisitionRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let code: String
    let title: String
    let targetQuantity: Int
    let model: String
    let versions: [String]
    let minimumYear: Int
    let maximumYear: Int
    let maximumMileage: Int
    let deliveryCity: String
    let deadlineAt: Date?

    var modelAndVersions: String {
        guard !versions.isEmpty else { return model }
        return ([model] + versions).joined(separator: " / ")
    }

    var yearRange: String { "\(minimumYear)–\(maximumYear)" }

    var maximumMileageText: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: maximumMileage)) ?? "\(maximumMileage)"
    }
}

/// Minimal offer projection needed by the first dashboards.
/// Price, VIN, declared SOH and internal assessment are intentionally not loaded.
nonisolated struct AcquisitionOfferSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let requestID: UUID
    let status: String
}

nonisolated struct AcquisitionRequestSummary: Equatable, Sendable {
    let request: AcquisitionRequest
    let securedCount: Int
    let decidingCount: Int

    init(request: AcquisitionRequest, offers: [AcquisitionOfferSummary]) {
        self.request = request
        let matching = offers.filter { $0.requestID == request.id }
        securedCount = matching.filter { Self.securedStatuses.contains($0.status) }.count
        decidingCount = matching.filter { Self.decidingStatuses.contains($0.status) }.count
    }

    var missingCount: Int {
        max(request.targetQuantity - securedCount, 0)
    }

    private static let securedStatuses: Set<String> = [
        "awarded", "ready_for_delivery", "received", "accepted",
        "accepted_with_observations", "accepted_with_condition",
    ]

    private static let decidingStatuses: Set<String> = [
        "submitted", "negotiating", "price_agreed",
    ]
}

nonisolated enum AcquisitionDestination: Equatable, Sendable {
    case administrator
    case provider
}

nonisolated enum AcquisitionNavigation {
    static func destination(for role: StaffRole) -> AcquisitionDestination? {
        switch role {
        case .doriAdmin: .administrator
        case .provider: .provider
        default: nil
        }
    }
}
