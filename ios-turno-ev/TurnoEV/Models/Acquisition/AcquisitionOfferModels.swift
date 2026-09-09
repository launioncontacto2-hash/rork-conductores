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

nonisolated struct AcquisitionOfferFormData: Equatable, Sendable {
    var vin = ""
    var year = ""
    var mileage = ""
    var price = ""
    var color = ""
    var transferIncluded = false
    var batteryKnowledge: AcquisitionBatteryKnowledge = .requiresDORIVerification
    var soh = ""
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
