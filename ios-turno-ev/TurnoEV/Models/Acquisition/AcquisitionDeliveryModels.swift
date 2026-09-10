import Foundation

nonisolated enum AcquisitionDeliveryAction: String, Equatable, Sendable {
    case ready
    case receive
    case resolveCondition = "resolve_condition"
    case closeCondition = "close_condition"
}

nonisolated enum AcquisitionReceptionResult: String, Decodable, Equatable, Sendable {
    case accepted
    case acceptedWithObservations = "accepted_with_observations"
    case acceptedWithCondition = "accepted_with_condition"
    case rejected

    var visibleLabel: String {
        switch self {
        case .accepted: "Aceptada"
        case .acceptedWithObservations: "Aceptada con observaciones"
        case .acceptedWithCondition: "Aceptada con condición"
        case .rejected: "No aceptada"
        }
    }
}

nonisolated struct AcquisitionReceptionChecklist: Codable, Equatable, Sendable {
    let vinCorrect: Bool
    let mileageCorrect: Bool
    let chargersComplete: Bool
    let keysComplete: Bool
    let newDamage: Bool

    enum CodingKeys: String, CodingKey {
        case vinCorrect = "vin_correct"
        case mileageCorrect = "mileage_correct"
        case chargersComplete = "chargers_complete"
        case keysComplete = "keys_complete"
        case newDamage = "new_damage"
    }
}

nonisolated struct AcquisitionReceptionFormData: Equatable, Sendable {
    var vinCorrect: Bool?
    var mileageCorrect: Bool?
    var chargersComplete: Bool?
    var keysComplete: Bool?
    var newDamage: Bool?
    var note = ""

    func checklist() throws -> AcquisitionReceptionChecklist {
        guard let vinCorrect, let mileageCorrect, let chargersComplete,
              let keysComplete, let newDamage else {
            throw AcquisitionDeliveryIssue.incompleteChecklist
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if (!vinCorrect || !keysComplete || !chargersComplete), trimmedNote.isEmpty {
            throw AcquisitionDeliveryIssue.noteRequired
        }
        return AcquisitionReceptionChecklist(
            vinCorrect: vinCorrect,
            mileageCorrect: mileageCorrect,
            chargersComplete: chargersComplete,
            keysComplete: keysComplete,
            newDamage: newDamage
        )
    }
}

nonisolated enum AcquisitionDeliveryIssue: Error, Equatable, Sendable {
    case incompleteChecklist
    case noteRequired

    var message: String {
        switch self {
        case .incompleteChecklist: "Responde todo el checklist para continuar."
        case .noteRequired: "Agrega una observación breve sobre el faltante."
        }
    }
}

nonisolated struct AcquisitionReception: Equatable, Sendable {
    let checklist: AcquisitionReceptionChecklist
    let result: AcquisitionReceptionResult
    let issueSummary: String?
    let holdAmountMxn: Int
}

nonisolated enum AcquisitionHoldStatus: String, Decodable, Equatable, Sendable {
    case pendingSupplier = "pending_supplier"
    case readyForReview = "ready_for_review"
    case resolved
}

nonisolated struct AcquisitionHold: Equatable, Sendable {
    let amountMxn: Int
    let reason: String
    let status: AcquisitionHoldStatus
    let supplierResolutionNote: String?

    var amountText: String { AcquisitionOfferSummary.currencyText(amountMxn) }
}

nonisolated struct AcquisitionDeliveryJourney: Equatable, Sendable {
    let orderID: UUID
    let supplierName: String?
    let finalPriceMxn: Int
    let orderStatus: String
    let deliveryStatus: String
    let reception: AcquisitionReception?
    let hold: AcquisitionHold?

    var finalPriceText: String { AcquisitionOfferSummary.currencyText(finalPriceMxn) }
    var canProviderMarkReady: Bool { orderStatus == "awarded" }
    var canDORIReceive: Bool { orderStatus == "ready_for_delivery" }
    var canProviderResolve: Bool {
        orderStatus == "accepted_with_condition" && hold?.status == .pendingSupplier
    }
    var canDORIClose: Bool {
        orderStatus == "accepted_with_condition" && hold?.status == .readyForReview
    }
}

nonisolated struct AcquisitionDeliveryCommand: Equatable, Sendable {
    let orderID: UUID
    let action: AcquisitionDeliveryAction
    let checklist: AcquisitionReceptionChecklist?
    let note: String?
    let idempotencyKey: String

    init(
        orderID: UUID,
        action: AcquisitionDeliveryAction,
        checklist: AcquisitionReceptionChecklist? = nil,
        note: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.orderID = orderID
        self.action = action
        self.checklist = checklist
        self.note = note
        self.idempotencyKey = idempotencyKey
            ?? "ios-acquisition-delivery-\(action.rawValue)-\(UUID().uuidString.lowercased())"
    }
}

nonisolated struct AcquisitionDeliveryCommandResult: Equatable, Sendable {
    let orderID: UUID
    let status: String
    let receptionResult: AcquisitionReceptionResult?
    let holdAmountMxn: Int
}
