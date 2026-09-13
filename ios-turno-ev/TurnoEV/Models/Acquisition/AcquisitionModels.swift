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
    /// Backend lifecycle value. It is retained so every request badge is
    /// rendered from persisted state instead of assuming that it is active.
    let status: String
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
        status: String = "published",
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
        self.status = status
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

    var visibleStatus: AcquisitionRequestStatusPresentation {
        AcquisitionRequestStatusPresentation(rawStatus: status)
    }
}

nonisolated struct AcquisitionRequestStatusPresentation: Equatable, Sendable {
    let title: String
    let systemImage: String
    let tone: AcquisitionRequestStatusTone

    init(rawStatus: String) {
        switch rawStatus {
        case "published":
            (title, systemImage, tone) = ("Activa", "circle.fill", .active)
        case "evaluating":
            (title, systemImage, tone) = ("En evaluación", "clock.fill", .waiting)
        case "partially_awarded":
            (title, systemImage, tone) = ("Activa · Parcialmente cubierta", "circle.lefthalf.filled", .active)
        case "awarded":
            (title, systemImage, tone) = ("Completa", "checkmark.circle.fill", .complete)
        case "closed":
            (title, systemImage, tone) = ("Cerrada", "lock.circle.fill", .neutral)
        case "cancelled":
            (title, systemImage, tone) = ("Cancelada", "xmark.circle.fill", .cancelled)
        default:
            (title, systemImage, tone) = ("Estado no disponible", "questionmark.circle.fill", .neutral)
        }
    }
}

nonisolated enum AcquisitionRequestStatusTone: Equatable, Sendable {
    case active
    case waiting
    case complete
    case neutral
    case cancelled
}

nonisolated struct AcquisitionRequestRequirement: Identifiable, Equatable, Sendable {
    let id: String
    let category: AcquisitionRequestRequirementCategory
    let title: String
    let value: String
    let required: Bool
    let displayOrder: Int

    init(
        id: String,
        category: AcquisitionRequestRequirementCategory = .specification,
        title: String,
        value: String,
        required: Bool = true,
        displayOrder: Int = 0
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.value = value
        self.required = required
        self.displayOrder = displayOrder
    }
}

nonisolated enum AcquisitionRequestRequirementCategory: String, Codable, CaseIterable, Sendable {
    case specification
    case documentation
    case condition
    case evidence

    var visibleTitle: String {
        switch self {
        case .specification: "Especificación"
        case .documentation: "Documentación"
        case .condition: "Condición"
        case .evidence: "Evidencia"
        }
    }
}

nonisolated struct AcquisitionRequestDraft: Equatable, Sendable {
    var model = ""
    var versions = ""
    var targetQuantity = ""
    var minimumYear = ""
    var maximumYear = ""
    var maximumMileage = ""
    var deliveryCity = "Puebla"
    var deadlineAt: Date?
    var requirements: [AcquisitionRequestRequirement] = AcquisitionRequestDraft.defaultRequirements

    static let defaultRequirements: [AcquisitionRequestRequirement] = [
        .init(id: "charger_110v", category: .condition, title: "Cargador 110V", value: "Incluido"),
        .init(id: "charger_220v", category: .condition, title: "Cargador 220V", value: "Incluido"),
        .init(id: "keys", category: .condition, title: "Llaves", value: "Dos llaves completas"),
        .init(id: "origin_invoice_document", category: .documentation, title: "Factura de origen", value: "Documento legible"),
    ] + AcquisitionEvidenceKind.detailedStandard.enumerated().map { index, kind in
        .init(
            id: kind.rawValue,
            category: .evidence,
            title: kind.title,
            value: kind.hint,
            displayOrder: 100 + index
        )
    }

    func makePublication(idempotencyKey: String = "ios-acquisition-request-\(UUID().uuidString.lowercased())") throws -> AcquisitionRequestPublication {
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModel.isEmpty else { throw AcquisitionRequestDraftIssue.modelRequired }
        guard let quantity = Int(targetQuantity), quantity > 0 else {
            throw AcquisitionRequestDraftIssue.invalidQuantity
        }
        guard let minimum = Int(minimumYear), let maximum = Int(maximumYear),
              (2000...2100).contains(minimum), maximum >= minimum else {
            throw AcquisitionRequestDraftIssue.invalidYears
        }
        guard let mileage = Int(maximumMileage.replacingOccurrences(of: ",", with: "")), mileage >= 0 else {
            throw AcquisitionRequestDraftIssue.invalidMileage
        }
        let city = deliveryCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { throw AcquisitionRequestDraftIssue.cityRequired }
        guard !requirements.isEmpty else { throw AcquisitionRequestDraftIssue.requirementsRequired }
        return AcquisitionRequestPublication(
            model: cleanModel,
            versions: versions.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            targetQuantity: quantity,
            minimumYear: minimum,
            maximumYear: maximum,
            maximumMileage: mileage,
            deliveryCity: city,
            deadlineAt: deadlineAt,
            requirements: requirements,
            idempotencyKey: idempotencyKey
        )
    }
}

nonisolated struct AcquisitionRequestPublication: Equatable, Sendable {
    let model: String
    let versions: [String]
    let targetQuantity: Int
    let minimumYear: Int
    let maximumYear: Int
    let maximumMileage: Int
    let deliveryCity: String
    let deadlineAt: Date?
    let requirements: [AcquisitionRequestRequirement]
    let idempotencyKey: String
}

nonisolated enum AcquisitionRequestDraftIssue: Error, Equatable, Sendable {
    case modelRequired, invalidQuantity, invalidYears, invalidMileage, cityRequired, requirementsRequired

    var message: String {
        switch self {
        case .modelRequired: "Captura el modelo solicitado."
        case .invalidQuantity: "Captura una cantidad válida."
        case .invalidYears: "Revisa los años permitidos."
        case .invalidMileage: "Captura un kilometraje válido."
        case .cityRequired: "Captura la ciudad de entrega."
        case .requirementsRequired: "Agrega al menos un requisito."
        }
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

    var requiredEvidenceKinds: [AcquisitionEvidenceKind] {
        let configured = detailedRequirements
            .filter { $0.category == .evidence && $0.required }
            .compactMap { AcquisitionEvidenceKind(rawValue: $0.id) }
        return configured.isEmpty ? AcquisitionEvidenceKind.detailedStandard : configured
    }
}

/// Public commercial fields shared by the offer owner and DORI. Internal
/// assessment remains in a separate administrator-only projection.
nonisolated struct AcquisitionOfferSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let requestID: UUID
    let supplierID: UUID?
    let status: String
    let model: String
    let version: String?
    let year: Int
    let mileage: Int
    let priceMxn: Int
    let transferIncluded: Bool
    let vin: String
    let declaredSoh: Int?
    let color: String?
    let agreedPriceMxn: Int?
    let submittedAt: Date?

    init(
        id: UUID,
        requestID: UUID,
        supplierID: UUID? = nil,
        status: String,
        model: String = "",
        version: String? = nil,
        year: Int = 0,
        mileage: Int = 0,
        priceMxn: Int = 0,
        transferIncluded: Bool = false,
        vin: String = "",
        declaredSoh: Int? = nil,
        color: String? = nil,
        agreedPriceMxn: Int? = nil,
        submittedAt: Date? = nil
    ) {
        self.id = id
        self.requestID = requestID
        self.supplierID = supplierID
        self.status = status
        self.model = model
        self.version = version
        self.year = year
        self.mileage = mileage
        self.priceMxn = priceMxn
        self.transferIncluded = transferIncluded
        self.vin = vin
        self.declaredSoh = declaredSoh
        self.color = color
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

nonisolated struct AcquisitionOfferActivity: Equatable, Sendable {
    let offerID: UUID
    let actorRole: AcquisitionRole
    let action: String
    let amountMxn: Int?
    let previousAmountMxn: Int?
    let createdAt: Date
    let sequence: Int

    var amountChangeText: String? {
        guard let previousAmountMxn, let amountMxn,
              previousAmountMxn != amountMxn else { return nil }
        return "\(AcquisitionOfferSummary.currencyText(previousAmountMxn)) → \(AcquisitionOfferSummary.currencyText(amountMxn))"
    }

    func title(for viewer: AcquisitionRole) -> String {
        if action == "accepted" { return "PRECIO ACORDADO" }
        return actorRole == .doriAdmin ? "NUEVA OFERTA DE DORI" : "NUEVA CONTRAOFERTA"
    }

    func requiresResponse(for viewer: AcquisitionRole, offerStatus: String) -> Bool {
        action == "counteroffer" && actorRole != viewer && offerStatus == "negotiating"
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
