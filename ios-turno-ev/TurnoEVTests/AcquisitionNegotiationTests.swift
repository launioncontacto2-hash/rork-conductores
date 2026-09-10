import Foundation
import Testing
@testable import TurnoEV

struct AcquisitionNegotiationModelTests {
    @Test func translatesEveryInternalRecommendationIntoSimpleSpanish() {
        #expect(AcquisitionRecommendation.buy.visibleLabel == "Buena compra")
        #expect(AcquisitionRecommendation.negotiate.visibleLabel == "Conviene negociar")
        #expect(AcquisitionRecommendation.review.visibleLabel == "Revisar antes de comprar")
        #expect(AcquisitionRecommendation.waitForInformation.visibleLabel == "Revisar antes de comprar")
        #expect(AcquisitionRecommendation.doNotBuy.visibleLabel == "No conviene")
    }

    @Test func recognizesAnIncomingDORIOfferForTheProvider() {
        let detail = Self.detail(lastActor: .doriAdmin, status: "negotiating")
        #expect(detail.hasPendingCounteroffer(for: .provider))
        #expect(detail.lastCounteroffer?.amountMxn == 268_000)
    }

    @Test func recognizesAnIncomingProviderCounterofferForDORI() {
        let detail = Self.detail(lastActor: .provider, status: "negotiating")
        #expect(detail.hasPendingCounteroffer(for: .doriAdmin))
        #expect(!detail.hasPendingCounteroffer(for: .provider))
    }

    @Test func hidesAssessmentFromTheProviderProjection() {
        let offerColumns = AcquisitionQueries.offerColumns.lowercased()
        #expect(!offerColumns.contains("maximum_recommended"))
        #expect(!offerColumns.contains("recommendation"))
        #expect(!offerColumns.contains("risk"))
        #expect(!offerColumns.contains("summary"))
    }

    fileprivate static let offerID = UUID(uuidString: "AD710000-0000-4000-8000-000000000001")!
    fileprivate static let requestID = UUID(uuidString: "AD710000-0000-4000-8000-000000000002")!
    fileprivate static let environmentID = UUID(uuidString: "AD710000-0000-4000-8000-000000000003")!
    fileprivate static let profileID = UUID(uuidString: "AD710000-0000-4000-8000-000000000004")!
    fileprivate static let supplierID = UUID(uuidString: "AD710000-0000-4000-8000-000000000005")!

    fileprivate static func detail(
        lastActor: AcquisitionRole? = nil,
        status: String = "submitted",
        assessment: AcquisitionOfferAssessment? = nil
    ) -> AcquisitionOfferDetail {
        let negotiations: [AcquisitionNegotiation] = lastActor.map {
            [
                AcquisitionNegotiation(
                    id: UUID(),
                    actorRole: $0,
                    action: "counteroffer",
                    amountMxn: 268_000,
                    message: nil,
                    createdAt: Date()
                ),
            ]
        } ?? []
        return AcquisitionOfferDetail(
            offer: AcquisitionOfferSummary(
                id: offerID,
                requestID: requestID,
                status: status,
                model: "Dolphin Mini",
                version: "Plus",
                year: 2025,
                mileage: 8_400,
                priceMxn: 274_000,
                transferIncluded: true,
                vin: "LGXCE6CB1S0000011",
                declaredSoh: 96,
                agreedPriceMxn: status == "price_agreed" ? 268_000 : nil
            ),
            assessment: assessment,
            negotiations: negotiations,
            evidence: []
        )
    }

    fileprivate static func membership(_ role: AcquisitionRole) -> AcquisitionMembership {
        AcquisitionMembership(
            id: UUID(),
            environmentID: environmentID,
            profileID: profileID,
            supplierID: role == .provider ? supplierID : nil,
            role: role
        )
    }
}

@MainActor
struct AcquisitionNegotiationFlowTests {
    @Test func doriLoadsANewProposalWithItsAuthorizedAssessment() async {
        let assessment = AcquisitionOfferAssessment(
            suggestedAmountMxn: 268_000,
            recommendation: .negotiate,
            evidenceStatus: "complete",
            summary: "La unidad cumple los parámetros principales."
        )
        let repository = Repository(detail: AcquisitionNegotiationModelTests.detail(assessment: assessment))
        let model = makeModel(role: .doriAdmin, repository: repository)

        await model.load()

        #expect(model.state == .content)
        #expect(model.detail?.assessment?.recommendation == .negotiate)
        #expect(model.detail?.assessment?.suggestedAmountMxn == 268_000)
    }

    @Test func doriSendsACounterofferThroughTheRepositoryCommand() async {
        let repository = Repository(detail: AcquisitionNegotiationModelTests.detail())
        let model = makeModel(role: .doriAdmin, repository: repository)

        await model.load()
        await model.sendCounteroffer(amountText: "$268,000")

        #expect(repository.commands.last?.action == .counteroffer)
        #expect(repository.commands.last?.amountMxn == 268_000)
        #expect(model.confirmationMessage == "Oferta enviada al proveedor.")
    }

    @Test func providerAcceptsTheLastDORIOfferThroughTheRPCBoundary() async {
        let repository = Repository(
            detail: AcquisitionNegotiationModelTests.detail(lastActor: .doriAdmin, status: "negotiating")
        )
        let model = makeModel(role: .provider, repository: repository)

        await model.load()
        await model.accept()

        #expect(repository.commands.last?.action == .accept)
        #expect(model.detail?.offer.status == "price_agreed")
    }

    @Test func providerCounteroffersThroughTheSameRPCBoundary() async {
        let repository = Repository(
            detail: AcquisitionNegotiationModelTests.detail(lastActor: .doriAdmin, status: "negotiating")
        )
        let model = makeModel(role: .provider, repository: repository)

        await model.load()
        await model.sendCounteroffer(amountText: "271000")

        #expect(repository.commands.last?.action == .counteroffer)
        #expect(repository.commands.last?.amountMxn == 271_000)
        #expect(model.confirmationMessage == "Contraoferta enviada a DORI.")
    }

    @Test func doriAwardsThroughTheRPCBoundary() async {
        let repository = Repository(
            detail: AcquisitionNegotiationModelTests.detail(lastActor: .provider, status: "negotiating")
        )
        let model = makeModel(role: .doriAdmin, repository: repository)

        await model.load()
        await model.award()

        #expect(repository.commands.last?.action == .award)
        #expect(repository.commands.last?.amountMxn == 268_000)
        #expect(model.detail?.offer.status == "awarded")
    }

    @Test func doriClosesAProposalThroughTheRejectTransition() async {
        let repository = Repository(detail: AcquisitionNegotiationModelTests.detail())
        let model = makeModel(role: .doriAdmin, repository: repository)

        await model.load()
        await model.reject()

        #expect(repository.commands.last?.action == .reject)
        #expect(model.detail?.offer.status == "rejected")
    }

    @Test func aFreshLoadReconstructsStateWithoutRealtimeHistory() async {
        let repository = Repository(detail: AcquisitionNegotiationModelTests.detail())
        let model = makeModel(role: .provider, repository: repository)
        await model.load()

        repository.detail = AcquisitionNegotiationModelTests.detail(
            lastActor: .doriAdmin,
            status: "negotiating"
        )
        await model.load()

        #expect(model.detail?.offer.status == "negotiating")
        #expect(model.detail?.lastCounteroffer?.amountMxn == 268_000)
        #expect(repository.detailLoads == 2)
    }

    private static func makeModel(
        role: AcquisitionRole,
        repository: Repository
    ) -> AcquisitionOfferDetailViewModel {
        AcquisitionOfferDetailViewModel(
            offerID: AcquisitionNegotiationModelTests.offerID,
            membership: AcquisitionNegotiationModelTests.membership(role),
            repository: repository
        )
    }

    private final class Repository: AcquisitionRepository {
        var detail: AcquisitionOfferDetail
        var commands: [AcquisitionOfferCommand] = []
        var detailLoads = 0

        init(detail: AcquisitionOfferDetail) {
            self.detail = detail
        }

        func loadMembership(profileID: UUID) async throws -> AcquisitionMembership {
            AcquisitionNegotiationModelTests.membership(.doriAdmin)
        }

        func loadRequests() async throws -> [AcquisitionRequest] { [] }
        func loadOffers() async throws -> [AcquisitionOfferSummary] { [detail.offer] }

        func loadOfferDetail(
            offerID: UUID,
            membership: AcquisitionMembership
        ) async throws -> AcquisitionOfferDetail {
            detailLoads += 1
            if membership.role == .provider {
                return AcquisitionOfferDetail(
                    offer: detail.offer,
                    assessment: nil,
                    negotiations: detail.negotiations,
                    evidence: detail.evidence
                )
            }
            return detail
        }

        func submitOffer(
            _ submission: AcquisitionOfferSubmission,
            membership: AcquisitionMembership
        ) async throws -> AcquisitionOfferSummary {
            detail.offer
        }

        func respondToOffer(
            _ command: AcquisitionOfferCommand
        ) async throws -> AcquisitionOfferCommandResult {
            commands.append(command)
            let status: String
            switch command.action {
            case .counteroffer:
                status = "negotiating"
                detail = AcquisitionNegotiationModelTests.detail(
                    lastActor: command.message == "Oferta de DORI" ? .doriAdmin : .provider,
                    status: status,
                    assessment: detail.assessment
                )
            case .accept:
                status = "price_agreed"
                detail = AcquisitionNegotiationModelTests.detail(
                    lastActor: detail.lastCounteroffer?.actorRole,
                    status: status,
                    assessment: detail.assessment
                )
            case .award:
                status = "awarded"
                detail = AcquisitionNegotiationModelTests.detail(
                    lastActor: detail.lastCounteroffer?.actorRole,
                    status: status,
                    assessment: detail.assessment
                )
            case .reject:
                status = "rejected"
                detail = AcquisitionNegotiationModelTests.detail(
                    status: status,
                    assessment: detail.assessment
                )
            }
            return AcquisitionOfferCommandResult(
                offerID: command.offerID,
                status: status,
                agreedPriceMxn: status == "price_agreed" ? 268_000 : nil,
                orderID: status == "awarded" ? UUID() : nil
            )
        }
    }
}
