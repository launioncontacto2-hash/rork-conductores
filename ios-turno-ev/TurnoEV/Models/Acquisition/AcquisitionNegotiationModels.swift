import Foundation

nonisolated enum AcquisitionRecommendation: String, Decodable, Sendable {
    case buy
    case negotiate
    case review
    case waitForInformation = "wait_for_information"
    case doNotBuy = "do_not_buy"

    var visibleLabel: String {
        switch self {
        case .buy: "Buena compra"
        case .negotiate: "Conviene negociar"
        case .review, .waitForInformation: "Revisar antes de comprar"
        case .doNotBuy: "No conviene"
        }
    }
}

nonisolated struct AcquisitionOfferAssessment: Equatable, Sendable {
    let suggestedAmountMxn: Int?
    let recommendation: AcquisitionRecommendation
    let evidenceStatus: String
    let summary: String

    var evidenceLabel: String {
        evidenceStatus == "complete" ? "Evidencia completa" : "Evidencia por revisar"
    }
}

nonisolated struct AcquisitionNegotiation: Identifiable, Equatable, Sendable {
    let id: UUID
    let actorRole: AcquisitionRole
    let action: String
    let amountMxn: Int?
    let message: String?
    let createdAt: Date

    var amountText: String? {
        amountMxn.map(AcquisitionOfferSummary.currencyText)
    }
}

nonisolated struct AcquisitionEvidenceItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: AcquisitionEvidenceKind
    let objectPath: String
    let verified: Bool
    var imageData: Data?

    var visibleTitle: String { kind.title }
}

nonisolated struct AcquisitionOfferDetail: Equatable, Sendable {
    static let counterofferLimit = 2
    let offer: AcquisitionOfferSummary
    let assessment: AcquisitionOfferAssessment?
    let negotiations: [AcquisitionNegotiation]
    let evidence: [AcquisitionEvidenceItem]
    let delivery: AcquisitionDeliveryJourney?

    init(
        offer: AcquisitionOfferSummary,
        assessment: AcquisitionOfferAssessment?,
        negotiations: [AcquisitionNegotiation],
        evidence: [AcquisitionEvidenceItem],
        delivery: AcquisitionDeliveryJourney? = nil
    ) {
        self.offer = offer
        self.assessment = assessment
        self.negotiations = negotiations
        self.evidence = evidence
        self.delivery = delivery
    }

    var lastCounteroffer: AcquisitionNegotiation? {
        negotiations.last { $0.action == "counteroffer" }
    }

    var commercialPriceMxn: Int {
        offer.agreedPriceMxn ?? lastCounteroffer?.amountMxn ?? offer.priceMxn
    }

    func hasPendingCounteroffer(for role: AcquisitionRole) -> Bool {
        offer.status == "negotiating" && lastCounteroffer?.actorRole != role
    }

    func counterofferCount(for role: AcquisitionRole) -> Int {
        negotiations.filter { $0.action == "counteroffer" && $0.actorRole == role }.count
    }

    func counteroffersRemaining(for role: AcquisitionRole) -> Int {
        max(0, Self.counterofferLimit - counterofferCount(for: role))
    }

    func canCounteroffer(as role: AcquisitionRole) -> Bool {
        ["submitted", "negotiating"].contains(offer.status)
            && counteroffersRemaining(for: role) > 0
    }
}

nonisolated enum AcquisitionOfferAction: String, Sendable {
    case counteroffer
    case accept
    case award
    case reject
    case withdraw
}

nonisolated struct AcquisitionOfferCommand: Equatable, Sendable {
    let offerID: UUID
    let action: AcquisitionOfferAction
    let amountMxn: Int?
    let message: String?
    let idempotencyKey: String

    init(
        offerID: UUID,
        action: AcquisitionOfferAction,
        amountMxn: Int? = nil,
        message: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.offerID = offerID
        self.action = action
        self.amountMxn = amountMxn
        self.message = message
        self.idempotencyKey = idempotencyKey
            ?? "ios-acquisition-\(action.rawValue)-\(UUID().uuidString.lowercased())"
    }
}

nonisolated struct AcquisitionOfferCommandResult: Equatable, Sendable {
    let offerID: UUID
    let status: String
    let agreedPriceMxn: Int?
    let orderID: UUID?
}
