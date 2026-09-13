import Foundation

nonisolated enum AcquisitionBatteryKnowledge: String, CaseIterable, Identifiable, Sendable {
    case diagnosed
    case requiresDORIVerification

    var id: String { rawValue }

    var label: String {
        switch self {
        case .diagnosed: "Tengo diagnóstico"
        case .requiresDORIVerification: "DORI deberá verificarla"
        }
    }
}

nonisolated enum AcquisitionEvidenceKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case vin
    case dashboard
    case front

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vin: "Foto del VIN"
        case .dashboard: "Tablero y kilometraje"
        case .front: "Vista general"
        }
    }

    var hint: String {
        switch self {
        case .vin: "Que el número sea legible"
        case .dashboard: "Enciende el tablero y muestra los km"
        case .front: "Fotografía completa del vehículo"
        }
    }
}

nonisolated struct AcquisitionEvidenceUpload: Equatable, Sendable {
    let kind: AcquisitionEvidenceKind
    let data: Data
}

nonisolated enum AcquisitionOfferRequirement: String, CaseIterable, Hashable, Identifiable, Sendable {
    case charger110
    case charger220
    case originalInvoice
    case reinvoice
    case plates
    case ownershipTransfer
    case bydWarranty
    case usedWarranty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .charger110: "Cargador 110V incluido"
        case .charger220: "Cargador 220V incluido"
        case .originalInvoice: "Factura de origen BYD México"
        case .reinvoice: "Refactura a título de DORI"
        case .plates: "Placas incluidas"
        case .ownershipTransfer: "Cambio de propietario incluido"
        case .bydWarranty: "Garantía BYD remanente y comprobable"
        case .usedWarranty: "Garantía seminuevos de 90 días"
        }
    }
}

nonisolated struct AcquisitionOfferSubmission: Equatable, Sendable {
    let offerID: UUID
    let requestID: UUID
    let model: String
    let version: String?
    let vin: String
    let year: Int
    let mileage: Int
    let declaredSoh: Int?
    let color: String
    let priceMxn: Int
    let transferIncluded: Bool
    let evidence: [AcquisitionEvidenceUpload]
    let idempotencyKey: String
}

nonisolated enum AcquisitionOfferSubmissionStage: String, Equatable, Sendable {
    case authorization
    case evidenceUpload
    case rpc
    case persistenceCheck
}

nonisolated struct AcquisitionOfferSubmissionError: LocalizedError, Sendable {
    let stage: AcquisitionOfferSubmissionStage
    let evidenceKind: AcquisitionEvidenceKind?
    let technicalDescription: String

    var errorDescription: String? {
        switch stage {
        case .authorization:
            "Tu acceso de proveedor no está disponible. Vuelve a iniciar sesión."
        case .evidenceUpload:
            if let evidenceKind {
                "No pudimos subir \(evidenceKind.title.lowercased()). Revisa tu conexión e intenta nuevamente."
            } else {
                "No pudimos subir las fotografías. Revisa tu conexión e intenta nuevamente."
            }
        case .rpc:
            if technicalDescription.localizedCaseInsensitiveContains("duplicate")
                || technicalDescription.localizedCaseInsensitiveContains("unique") {
                "Ya existe una propuesta para ese VIN. Revisa Mis vehículos."
            } else {
                "Las fotografías se guardaron, pero no pudimos registrar la propuesta. Intenta nuevamente."
            }
        case .persistenceCheck:
            "La propuesta se envió, pero no pudimos confirmar su carga. Actualiza Mis vehículos."
        }
    }
}

nonisolated struct AcquisitionOfferFormData: Equatable, Sendable {
    var vin = ""
    var year = ""
    var mileage = ""
    var price = ""
    var color = ""
    var transferIncluded = false
    var batteryKnowledge: AcquisitionBatteryKnowledge = .requiresDORIVerification
    var soh = ""
    var confirmedRequirements: Set<AcquisitionOfferRequirement> = []
    var evidence: [AcquisitionEvidenceKind: Data] = [:]

    func makeSubmission(
        request: AcquisitionRequest,
        offerID: UUID = UUID(),
        idempotencyKey: String? = nil
    ) throws -> AcquisitionOfferSubmission {
        let normalizedVin = vin
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedVin.isEmpty else { throw AcquisitionOfferFormIssue.vinRequired }
        guard normalizedVin.range(
            of: "^[A-HJ-NPR-Z0-9]{17}$",
            options: .regularExpression
        ) != nil else {
            throw AcquisitionOfferFormIssue.invalidVin
        }

        guard let parsedYear = Self.integer(from: year), (2000...2100).contains(parsedYear) else {
            throw AcquisitionOfferFormIssue.invalidYear
        }
        guard let parsedMileage = Self.integer(from: mileage), parsedMileage >= 0 else {
            throw AcquisitionOfferFormIssue.invalidMileage
        }
        guard let parsedPrice = Self.integer(from: price), parsedPrice > 0 else {
            throw AcquisitionOfferFormIssue.invalidPrice
        }

        let normalizedColor = color.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedColor.isEmpty else { throw AcquisitionOfferFormIssue.colorRequired }

        guard confirmedRequirements.count == AcquisitionOfferRequirement.allCases.count else {
            throw AcquisitionOfferFormIssue.requirementsRequired
        }

        let parsedSoh: Int?
        switch batteryKnowledge {
        case .requiresDORIVerification:
            parsedSoh = nil
        case .diagnosed:
            guard let value = Self.integer(from: soh), (0...100).contains(value) else {
                throw AcquisitionOfferFormIssue.invalidSoh
            }
            parsedSoh = value
        }

        let uploads = try AcquisitionEvidenceKind.allCases.map { kind in
            guard let data = evidence[kind], !data.isEmpty else {
                throw AcquisitionOfferFormIssue.evidenceRequired(kind)
            }
            return AcquisitionEvidenceUpload(kind: kind, data: data)
        }

        return AcquisitionOfferSubmission(
            offerID: offerID,
            requestID: request.id,
            model: request.model,
            version: request.versions.first,
            vin: normalizedVin,
            year: parsedYear,
            mileage: parsedMileage,
            declaredSoh: parsedSoh,
            color: normalizedColor,
            priceMxn: parsedPrice,
            transferIncluded: transferIncluded,
            evidence: uploads,
            idempotencyKey: idempotencyKey ?? "ios-acquisition-offer-\(offerID.uuidString.lowercased())"
        )
    }

    private static func integer(from text: String) -> Int? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Int(normalized)
    }
}

nonisolated enum AcquisitionOfferFormIssue: Error, Equatable, Sendable {
    case vinRequired
    case invalidVin
    case invalidYear
    case invalidMileage
    case invalidPrice
    case colorRequired
    case invalidSoh
    case requirementsRequired
    case evidenceRequired(AcquisitionEvidenceKind)

    var message: String {
        switch self {
        case .vinRequired: "Captura el VIN para continuar."
        case .invalidVin: "Revisa el VIN. Debe contener 17 caracteres válidos."
        case .invalidYear: "Captura un año válido."
        case .invalidMileage: "Captura un kilometraje válido."
        case .invalidPrice: "Captura un precio válido."
        case .colorRequired: "Captura el color de la unidad."
        case .invalidSoh: "Captura un diagnóstico de batería entre 0 y 100 %."
        case .requirementsRequired: "Confirma que la unidad cumple todos los requisitos."
        case .evidenceRequired(let kind): "Falta \(kind.title.lowercased())."
        }
    }
}

nonisolated enum AcquisitionEvidencePath {
    static func make(
        environmentID: UUID,
        supplierID: UUID,
        offerID: UUID,
        kind: AcquisitionEvidenceKind
    ) -> String {
        [
            environmentID.uuidString.lowercased(),
            supplierID.uuidString.lowercased(),
            offerID.uuidString.lowercased(),
            "\(kind.rawValue).jpg",
        ].joined(separator: "/")
    }
}
