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

nonisolated struct AcquisitionSupplierSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let city: String
}

nonisolated struct AcquisitionInstitutionalContact: Identifiable, Equatable, Sendable {
    let id: UUID
    let supplierID: UUID?
    let organizationName: String
    let personName: String
    let jobTitle: String
    let phone: String
    let email: String
    let businessHours: String
    let isPrimary: Bool

    var callURL: URL? {
        let allowed = CharacterSet(charactersIn: "+0123456789")
        let normalized = phone.unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
        guard normalized.contains(where: { $0.isNumber }) else { return nil }
        return URL(string: "tel:\(normalized)")
    }

    var emailURL: URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), !trimmed.contains(where: { $0.isWhitespace }) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = trimmed
        return components.url
    }
}

nonisolated enum AcquisitionContactDirectory {
    static func counterpartContacts(
        _ contacts: [AcquisitionInstitutionalContact],
        membership: AcquisitionMembership
    ) -> [AcquisitionInstitutionalContact] {
        contacts.filter { contact in
            switch membership.role {
            case .doriAdmin:
                contact.supplierID != nil
            case .provider:
                contact.supplierID == nil
            }
        }
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
    /// Prepared for the approved detailed-requirements screen. An empty array
    /// keeps the current compact request experience unchanged until the backend
    /// publishes these fields explicitly.
    let detailedRequirements: [AcquisitionRequestRequirement]

    init(
        id: UUID,
        code: String,
        title: String,
        targetQuantity: Int,
        model: String,
        versions: [String],
        minimumYear: Int,
        maximumYear: Int,
        maximumMileage: Int,
        deliveryCity: String,
        deadlineAt: Date?,
        detailedRequirements: [AcquisitionRequestRequirement] = []
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.targetQuantity = targetQuantity
        self.model = model
        self.versions = versions
        self.minimumYear = minimumYear
        self.maximumYear = maximumYear
        self.maximumMileage = maximumMileage
        self.deliveryCity = deliveryCity
        self.deadlineAt = deadlineAt
        self.detailedRequirements = detailedRequirements
    }

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

nonisolated struct AcquisitionRequestRequirement: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let value: String

    init(id: String, title: String, value: String) {
        self.id = id
        self.title = title
        self.value = value
    }
}

nonisolated extension AcquisitionRequest {
    /// Public, role-neutral requirements used by both experiences. Sensitive
    /// valuation rules are intentionally excluded from this projection.
    var visibleRequirements: [AcquisitionRequestRequirement] {
        if !detailedRequirements.isEmpty { return detailedRequirements }
        return [
            .init(id: "model_year", title: "Año modelo", value: yearRange),
            .init(id: "mileage", title: "Kilometraje", value: "0–\(maximumMileageText) km"),
            .init(id: "color", title: "Color", value: "Indiferente"),
            .init(id: "charger_110v", title: "Cargador 110V", value: "Incluido"),
            .init(id: "charger_220v", title: "Cargador 220V", value: "Incluido"),
            .init(id: "battery", title: "Estado de batería", value: "Diagnóstico vigente o verificación DORI"),
            .init(id: "original_invoice", title: "Factura de origen", value: "BYD México"),
            .init(id: "reinvoice", title: "Refactura", value: "A título de DORI"),
            .init(id: "plates", title: "Placas", value: "Incluidas"),
            .init(id: "ownership", title: "Cambio de propietario", value: "Incluido en el precio"),
            .init(id: "byd_warranty", title: "Garantía de origen BYD", value: "Remanente vigente y comprobable"),
            .init(id: "used_warranty", title: "Garantía seminuevos", value: "90 días comprobables"),
        ]
    }
}

/// Public commercial fields shared by the offer owner and DORI. Internal
/// assessment remains in a separate administrator-only projection.
nonisolated struct AcquisitionOfferSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let requestID: UUID
    let status: String
    let model: String
    let version: String?
    let year: Int
    let mileage: Int
    let priceMxn: Int
    let transferIncluded: Bool
    let vin: String
    let declaredSoh: Int?
    let agreedPriceMxn: Int?
    let submittedAt: Date?

    init(
        id: UUID,
        requestID: UUID,
        status: String,
        model: String = "",
        version: String? = nil,
        year: Int = 0,
        mileage: Int = 0,
        priceMxn: Int = 0,
        transferIncluded: Bool = false,
        vin: String = "",
        declaredSoh: Int? = nil,
        agreedPriceMxn: Int? = nil,
        submittedAt: Date? = nil
    ) {
        self.id = id
        self.requestID = requestID
        self.status = status
        self.model = model
        self.version = version
        self.year = year
        self.mileage = mileage
        self.priceMxn = priceMxn
        self.transferIncluded = transferIncluded
        self.vin = vin
        self.declaredSoh = declaredSoh
        self.agreedPriceMxn = agreedPriceMxn
        self.submittedAt = submittedAt
    }

    var modelAndVersion: String {
        guard let version, !version.isEmpty else { return model }
        return "\(model) \(version)"
    }

    /// Years are identifiers, not quantities. Returning a String prevents
    /// SwiftUI's localized integer interpolation from rendering 2025 as 2,025.
    var yearText: String { String(year) }

    var mileageText: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: mileage as NSNumber) ?? "\(mileage)"
    }

    var priceText: String {
        Self.currencyText(priceMxn)
    }

    var agreedPriceText: String? {
        agreedPriceMxn.map(Self.currencyText)
    }

    var abbreviatedVin: String {
        guard vin.count >= 8 else { return vin }
        return "•••• \(vin.suffix(6))"
    }

    static func currencyText(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "MXN"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSNumber) ?? "$\(amount)"
    }
}

nonisolated enum AcquisitionHomeGroup: Equatable, Sendable {
    case attention
    case inProgress
    case finished
}

/// Presentation-only rules. Backend values remain internal and are converted into
/// plain language at the last possible boundary before rendering.
nonisolated enum AcquisitionHumanStatus {
    static func title(for status: String, role: AcquisitionRole) -> String {
        switch (status, role) {
        case ("submitted", .doriAdmin): "Propuesta por revisar"
        case ("submitted", .provider): "Esperando revisión de DORI"
        case ("negotiating", .doriAdmin): "Negociación por resolver"
        case ("negotiating", .provider): "DORI hizo una oferta"
        case ("price_agreed", _): "Precio acordado"
        case ("awarded", _): "Compra confirmada"
        case ("ready_for_delivery", .doriAdmin): "Esperando entrega"
        case ("ready_for_delivery", .provider): "Esperando recepción de DORI"
        case ("received", _), ("accepted", _): "Unidad recibida"
        case ("accepted_with_observations", _): "Recibida con observaciones"
        case ("accepted_with_condition", .doriAdmin): "Recibida; falta resolver un detalle"
        case ("accepted_with_condition", .provider): "Falta resolver un detalle"
        case ("closed", _): "Operación terminada"
        case ("rejected", _): "Proceso terminado sin compra"
        default: "Operación actualizada"
        }
    }

    static func group(for status: String, role: AcquisitionRole) -> AcquisitionHomeGroup {
        if ["closed", "rejected"].contains(status) { return .finished }
        switch (status, role) {
        case ("submitted", .doriAdmin), ("negotiating", _),
             ("price_agreed", .doriAdmin), ("accepted_with_condition", _):
            return .attention
        default:
            return .inProgress
        }
    }

    static func uniqueVehicles(_ offers: [AcquisitionOfferSummary]) -> [AcquisitionOfferSummary] {
        var seenOfferIDs = Set<UUID>()
        var seenVINs = Set<String>()
        return offers.filter { offer in
            guard seenOfferIDs.insert(offer.id).inserted else { return false }
            let normalizedVIN = offer.vin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalizedVIN.isEmpty else { return true }
            return seenVINs.insert(normalizedVIN).inserted
        }
    }
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
