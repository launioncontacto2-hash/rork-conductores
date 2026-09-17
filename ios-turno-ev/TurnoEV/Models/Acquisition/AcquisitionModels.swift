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
    let targetDeliveryDate: Date?
    /// Accounting period selected explicitly by DORI. It is never inferred from
    /// the request creation timestamp.
    let fiscalPeriod: Date
    let maximumUnitPriceMxn: Int
    let minimumSoh: Int
    let sohDiagnosisMaximumAgeDays: Int
    let destinationStationName: String
    let deliveryTermsDocumentPath: String?
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
        targetDeliveryDate: Date? = nil,
        fiscalPeriod: Date = Date(),
        maximumUnitPriceMxn: Int = 0,
        minimumSoh: Int = 90,
        sohDiagnosisMaximumAgeDays: Int = 30,
        destinationStationName: String = "DORI Puebla",
        deliveryTermsDocumentPath: String? = nil,
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
        self.targetDeliveryDate = targetDeliveryDate
        self.fiscalPeriod = fiscalPeriod
        self.maximumUnitPriceMxn = maximumUnitPriceMxn
        self.minimumSoh = minimumSoh
        self.sohDiagnosisMaximumAgeDays = sohDiagnosisMaximumAgeDays
        self.destinationStationName = destinationStationName
        self.deliveryTermsDocumentPath = deliveryTermsDocumentPath
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

    var fiscalPeriodText: String {
        AcquisitionFiscalPeriodPresentation.text(for: fiscalPeriod)
    }

    var maximumUnitPriceText: String {
        AcquisitionOfferSummary.currencyText(maximumUnitPriceMxn)
    }

    var visibleStatus: AcquisitionRequestStatusPresentation {
        isExpired() ? AcquisitionRequestStatusPresentation(expired: ()) : AcquisitionRequestStatusPresentation(rawStatus: status)
    }

    func isExpired(at date: Date = Date()) -> Bool {
        guard status == "published", let deadlineAt else { return false }
        return deadlineAt < date
    }

    var deadlineText: String {
        deadlineAt.map(AcquisitionSpanishDate.text) ?? "Pendiente"
    }

    var targetDeliveryText: String {
        targetDeliveryDate.map(AcquisitionSpanishDate.text) ?? "Pendiente"
    }
}

nonisolated enum AcquisitionSpanishDate {
    static func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        "\(text(date)) · \(time(date))"
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

    init(expired: Void) {
        (title, systemImage, tone) = ("Vencida", "calendar.badge.exclamationmark", .neutral)
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
    let responseType: AcquisitionRequirementResponseType
    let requiresDORIVerification: Bool

    init(
        id: String,
        category: AcquisitionRequestRequirementCategory = .specification,
        title: String,
        value: String,
        required: Bool = true,
        displayOrder: Int = 0,
        responseType: AcquisitionRequirementResponseType = .confirmation,
        requiresDORIVerification: Bool = false
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.value = value
        self.required = required
        self.displayOrder = displayOrder
        self.responseType = responseType
        self.requiresDORIVerification = requiresDORIVerification
    }
}

nonisolated enum AcquisitionRequirementResponseType: String, Codable, CaseIterable, Sendable {
    case confirmation
    case text
    case number
    case date
    case document
    case photo

    var visibleTitle: String {
        switch self {
        case .confirmation: "Confirmación"
        case .text: "Texto"
        case .number: "Número"
        case .date: "Fecha"
        case .document: "Documento"
        case .photo: "Fotografía"
        }
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
    static let maximumDeliveryTermsBytes = 10 * 1_024 * 1_024
    static let acceptedDeliveryTermsMIMETypes: Set<String> = [
        "application/pdf", "text/plain",
    ]
    private static let testDeliveryTerms = """
    Condiciones de entrega DORI Adquisición — entorno TEST.
    Documento institucional administrado por DORI. El supervisor no puede modificarlo.
    """

    var model = ""
    var idempotencyKey = "ios-acquisition-request-\(UUID().uuidString.lowercased())"
    var versions = ""
    var targetQuantity = ""
    var minimumYear = ""
    var maximumYear = ""
    var maximumMileage = ""
    var maximumUnitPrice = ""
    var deliveryCity = "Puebla"
    var destinationStationName = "DORI Puebla"
    var fiscalPeriod = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    var minimumSoh = "90"
    var sohDiagnosisMaximumAgeDays = "30"
    // Station policy values: the request author can review them but cannot edit them.
    var deliveryTermsDocument: Data? = Data(Self.testDeliveryTerms.utf8)
    var deliveryTermsFilename: String? = "condiciones-entrega-dori-test.txt"
    var deliveryTermsMimeType: String? = "text/plain"
    var deadlineAt: Date? = Self.defaultDate(daysFromNow: 14)
    var targetDeliveryDate: Date? = Self.defaultDate(daysFromNow: 30)
    var requirements: [AcquisitionRequestRequirement] = AcquisitionRequestDraft.defaultRequirements

    static let defaultRequirements: [AcquisitionRequestRequirement] = [
        .init(id: "origin_invoice_document", category: .documentation, title: "Factura de origen", value: "Requerido", displayOrder: 1),
        .init(id: "reinvoice_to_dori", category: .documentation, title: "Refactura a título de DORI", value: "Requerido", displayOrder: 2),
        .init(id: "soh_report", category: .documentation, title: "Reporte SOH%", value: "Requerido", displayOrder: 3),
        .init(id: "condition_keys", category: .condition, title: "Duplicado de llaves", value: "Requerido", displayOrder: 4),
        .init(id: "condition_charger_110v", category: .condition, title: "Cargador 110V", value: "Requerido", displayOrder: 5),
        .init(id: "condition_charger_220v", category: .condition, title: "Cargador 220V", value: "Requerido", displayOrder: 6),
        .init(id: "plates", category: .documentation, title: "Placas", value: "Requerido", displayOrder: 7),
        .init(id: "ownership_to_dori", category: .documentation, title: "Cambio de propietario a título de DORI", value: "Requerido", displayOrder: 8),
        .init(id: "manufacturer_warranty", category: .documentation, title: "Garantía remanente del fabricante", value: "Requerido", displayOrder: 9),
        .init(id: "used_vehicle_warranty", category: .documentation, title: "Garantía de 90 días de Seminuevos", value: "Requerido", displayOrder: 10),
    ] + AcquisitionEvidenceKind.detailedStandard.enumerated().map { index, kind in
        .init(
            id: kind.rawValue,
            category: .evidence,
            title: kind.title,
            value: kind.hint,
            displayOrder: 100 + index
        )
    }

    /// Draft convenience only. The backend remains authoritative for expiry;
    /// noon avoids surprising midnight deadlines in the creation form.
    static func defaultDate(daysFromNow days: Int, now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: days, to: now) else { return nil }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)
    }

    func makePublication(
        idempotencyKey: String? = nil,
        authoritativeNow: Date? = nil
    ) throws -> AcquisitionRequestPublication {
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
        guard let maximumPrice = Int(maximumUnitPrice.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")), maximumPrice > 0 else {
            throw AcquisitionRequestDraftIssue.invalidMaximumPrice
        }
        guard let minimumSohValue = Int(minimumSoh), (0...100).contains(minimumSohValue) else {
            throw AcquisitionRequestDraftIssue.invalidMinimumSoh
        }
        guard let diagnosisAge = Int(sohDiagnosisMaximumAgeDays), diagnosisAge > 0 else {
            throw AcquisitionRequestDraftIssue.invalidDiagnosisAge
        }
        let city = deliveryCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { throw AcquisitionRequestDraftIssue.cityRequired }
        let station = destinationStationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !station.isEmpty else { throw AcquisitionRequestDraftIssue.stationRequired }
        guard let deliveryTermsDocument, !deliveryTermsDocument.isEmpty,
              let deliveryTermsFilename, !deliveryTermsFilename.isEmpty else {
            throw AcquisitionRequestDraftIssue.deliveryTermsRequired
        }
        guard deliveryTermsDocument.count <= Self.maximumDeliveryTermsBytes else {
            throw AcquisitionRequestDraftIssue.deliveryTermsTooLarge
        }
        let resolvedDeliveryTermsMimeType = deliveryTermsMimeType
            ?? Self.deliveryTermsMIMEType(for: deliveryTermsFilename)
        guard let resolvedDeliveryTermsMimeType,
              Self.acceptedDeliveryTermsMIMETypes.contains(resolvedDeliveryTermsMimeType) else {
            throw AcquisitionRequestDraftIssue.invalidDeliveryTermsType
        }
        guard !requirements.isEmpty else { throw AcquisitionRequestDraftIssue.requirementsRequired }
        guard Set(requirements.map(\.id)).count == requirements.count else {
            throw AcquisitionRequestDraftIssue.duplicateRequirements
        }
        guard let deadlineAt else { throw AcquisitionRequestDraftIssue.deadlineRequired }
        guard let targetDeliveryDate else { throw AcquisitionRequestDraftIssue.targetDeliveryRequired }
        if let authoritativeNow, deadlineAt <= authoritativeNow {
            throw AcquisitionRequestDraftIssue.deadlineMustBeFuture
        }
        let calendar = Calendar.current
        guard calendar.startOfDay(for: targetDeliveryDate) >= calendar.startOfDay(for: deadlineAt) else {
            throw AcquisitionRequestDraftIssue.targetDeliveryBeforeDeadline
        }
        return AcquisitionRequestPublication(
            model: cleanModel,
            versions: versions.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            targetQuantity: quantity,
            minimumYear: minimum,
            maximumYear: maximum,
            maximumMileage: mileage,
            maximumUnitPriceMxn: maximumPrice,
            deliveryCity: city,
            destinationStationName: station,
            fiscalPeriod: Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month], from: fiscalPeriod)
            ) ?? fiscalPeriod,
            minimumSoh: minimumSohValue,
            sohDiagnosisMaximumAgeDays: diagnosisAge,
            deliveryTermsDocument: deliveryTermsDocument,
            deliveryTermsFilename: deliveryTermsFilename,
            deliveryTermsMimeType: resolvedDeliveryTermsMimeType,
            deadlineAt: deadlineAt,
            targetDeliveryDate: targetDeliveryDate,
            requirements: requirements,
            idempotencyKey: idempotencyKey ?? self.idempotencyKey
        )
    }

    static func deliveryTermsMIMEType(for filename: String) -> String? {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "pdf": "application/pdf"
        case "txt": "text/plain"
        default: nil
        }
    }
}

nonisolated struct AcquisitionRequestPublication: Equatable, Sendable {
    let model: String
    let versions: [String]
    let targetQuantity: Int
    let minimumYear: Int
    let maximumYear: Int
    let maximumMileage: Int
    let maximumUnitPriceMxn: Int
    let deliveryCity: String
    let destinationStationName: String
    let fiscalPeriod: Date
    let minimumSoh: Int
    let sohDiagnosisMaximumAgeDays: Int
    let deliveryTermsDocument: Data
    let deliveryTermsFilename: String
    let deliveryTermsMimeType: String
    let deadlineAt: Date?
    let targetDeliveryDate: Date?
    let requirements: [AcquisitionRequestRequirement]
    let idempotencyKey: String
}

nonisolated enum AcquisitionRequestDraftIssue: Error, Equatable, Sendable {
    case modelRequired, invalidQuantity, invalidYears, invalidMileage, invalidMaximumPrice
    case invalidMinimumSoh, invalidDiagnosisAge, cityRequired, stationRequired, deliveryTermsRequired, requirementsRequired
    case duplicateRequirements, invalidDeliveryTermsType, deliveryTermsTooLarge
    case deadlineRequired, targetDeliveryRequired, deadlineMustBeFuture, targetDeliveryBeforeDeadline

    var message: String {
        switch self {
        case .modelRequired: "Captura el modelo solicitado."
        case .invalidQuantity: "Captura una cantidad válida."
        case .invalidYears: "Revisa los años permitidos."
        case .invalidMileage: "Captura un kilometraje válido."
        case .invalidMaximumPrice: "Captura un precio máximo válido."
        case .invalidMinimumSoh: "Captura un SOH mínimo entre 0 y 100 %."
        case .invalidDiagnosisAge: "Captura una vigencia válida para el diagnóstico SOH."
        case .cityRequired: "Captura la ciudad de entrega."
        case .stationRequired: "Captura la estación destino."
        case .deliveryTermsRequired: "Adjunta las condiciones de entrega de esta solicitud."
        case .invalidDeliveryTermsType: "Adjunta las condiciones en formato PDF o TXT."
        case .deliveryTermsTooLarge: "El documento de condiciones debe pesar máximo 10 MB."
        case .requirementsRequired: "Agrega al menos un requisito."
        case .duplicateRequirements: "Cada requisito debe ser único."
        case .deadlineRequired: "Selecciona la fecha límite para recibir ofertas."
        case .targetDeliveryRequired: "Selecciona la fecha objetivo de entrega."
        case .deadlineMustBeFuture:
            "La fecha límite para recibir ofertas ya venció. Selecciona una fecha futura."
        case .targetDeliveryBeforeDeadline:
            "La fecha objetivo de entrega no puede ser anterior al cierre de ofertas."
        }
    }
}

nonisolated extension AcquisitionRequest {
    /// Public, role-neutral requirements used by both experiences. Sensitive
    /// valuation rules are intentionally excluded from this projection.
    var visibleRequirements: [AcquisitionRequestRequirement] {
        if !detailedRequirements.isEmpty {
            let nonEvidence = detailedRequirements.filter { $0.category != .evidence }
            let evidenceCount = detailedRequirements.filter {
                $0.category == .evidence && $0.required
            }.count
            let photoSummary = evidenceCount > 0
                ? [AcquisitionRequestRequirement(
                    id: "required_photos_summary",
                    category: .evidence,
                    title: "Evidencia fotográfica",
                    value: "\(evidenceCount) fotos requeridas",
                    required: true,
                    displayOrder: 99,
                    responseType: .photo
                )]
                : []
            return (nonEvidence + photoSummary).sorted { $0.displayOrder < $1.displayOrder }
        }
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
    let committedDeliveryDate: Date?
    let fiscalPeriod: Date?
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
        committedDeliveryDate: Date? = nil,
        fiscalPeriod: Date? = nil,
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
        self.committedDeliveryDate = committedDeliveryDate
        self.fiscalPeriod = fiscalPeriod
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

    var fiscalPeriodText: String? {
        fiscalPeriod.map { AcquisitionFiscalPeriodPresentation.text(for: $0) }
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

nonisolated enum AcquisitionFiscalPeriodPresentation {
    static let spanishMonthNames = [
        "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
        "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
    ]

    static func monthName(_ month: Int) -> String {
        guard (1...spanishMonthNames.count).contains(month) else { return "Mes" }
        return spanishMonthNames[month - 1]
    }

    static func text(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month], from: date)
        return "\(monthName(components.month ?? 0)) \(components.year ?? 0)"
    }
}

nonisolated enum AcquisitionCommercialLane: Equatable, Sendable {
    case proposal
    case negotiation
    case purchase
    case hidden

    static func resolve(status: String) -> Self {
        switch status {
        case "submitted":
            .proposal
        case "negotiating", "price_agreed":
            .negotiation
        case "awarded", "ready_for_delivery", "received", "accepted",
             "accepted_with_observations", "accepted_with_condition", "closed":
            .purchase
        default:
            .hidden
        }
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
