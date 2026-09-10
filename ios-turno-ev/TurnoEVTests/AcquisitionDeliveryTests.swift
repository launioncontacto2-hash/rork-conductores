import Foundation
import Testing
@testable import TurnoEV

struct AcquisitionDeliveryModelTests {
    @Test func translatesEveryReceptionResultIntoSpanish() {
        #expect(AcquisitionReceptionResult.accepted.visibleLabel == "Aceptada")
        #expect(AcquisitionReceptionResult.acceptedWithObservations.visibleLabel == "Aceptada con observaciones")
        #expect(AcquisitionReceptionResult.acceptedWithCondition.visibleLabel == "Aceptada con condición")
        #expect(AcquisitionReceptionResult.rejected.visibleLabel == "No aceptada")
    }

    @Test func createsACompleteReceptionChecklist() throws {
        let checklist = try Self.form().checklist()
        #expect(checklist.vinCorrect)
        #expect(checklist.mileageCorrect)
        #expect(checklist.chargersComplete)
        #expect(checklist.keysComplete)
        #expect(!checklist.newDamage)
    }

    @Test func rejectsAnIncompleteChecklist() {
        #expect(throws: AcquisitionDeliveryIssue.incompleteChecklist) {
            _ = try AcquisitionReceptionFormData().checklist()
        }
    }

    @Test func requiresANoteForMaterialRejection() {
        var form = Self.form()
        form.vinCorrect = false
        #expect(throws: AcquisitionDeliveryIssue.noteRequired) {
            _ = try form.checklist()
        }
    }

    @Test func exposesOnlyThePersistedHoldState() {
        let journey = Self.journey(
            status: "accepted_with_condition",
            hold: AcquisitionHold(
                amountMxn: 6_000,
                reason: "Falta segunda llave.",
                status: .pendingSupplier,
                supplierResolutionNote: nil
            )
        )
        #expect(journey.canProviderResolve)
        #expect(!journey.canDORIClose)
        #expect(journey.hold?.amountText.contains("6,000") == true)
    }

    static func form() -> AcquisitionReceptionFormData {
        AcquisitionReceptionFormData(
            vinCorrect: true,
            mileageCorrect: true,
            chargersComplete: true,
            keysComplete: true,
            newDamage: false
        )
    }

    static func journey(
        status: String,
        hold: AcquisitionHold? = nil,
        reception: AcquisitionReception? = nil
    ) -> AcquisitionDeliveryJourney {
        AcquisitionDeliveryJourney(
            orderID: AcquisitionDeliveryFlowTests.orderID,
            supplierName: "Agencia Puebla Centro",
            finalPriceMxn: 268_000,
            orderStatus: status,
            deliveryStatus: status == "awarded" ? "preparing" : "ready",
            reception: reception,
            hold: hold
        )
    }
}

@MainActor
struct AcquisitionDeliveryFlowTests {
    static let offerID = UUID(uuidString: "AD720000-0000-4000-8000-000000000001")!
    static let orderID = UUID(uuidString: "AD720000-0000-4000-8000-000000000002")!

    @Test func providerMarksTheAwardedUnitReadyThroughTheRPCBoundary() async {
        let repository = Repository(journey: AcquisitionDeliveryModelTests.journey(status: "awarded"))
        let model = Self.model(role: .provider, repository: repository)
        await model.load()
        await model.markReady()

        #expect(repository.commands.last?.action == .ready)
        #expect(model.detail?.delivery?.orderStatus == "ready_for_delivery")
        #expect(model.confirmationMessage == "DORI ya puede preparar la recepción.")
    }

    @Test func doriSeesTheSharedUnitReadyForReception() async {
        let repository = Repository(journey: AcquisitionDeliveryModelTests.journey(status: "ready_for_delivery"))
        let model = Self.model(role: .doriAdmin, repository: repository)
        await model.load()

        #expect(model.detail?.delivery?.canDORIReceive == true)
        #expect(model.detail?.delivery?.supplierName == "Agencia Puebla Centro")
    }

    @Test func doriReceivesANormalUnitWithoutSendingAResultRule() async {
        let repository = Repository(journey: AcquisitionDeliveryModelTests.journey(status: "ready_for_delivery"))
        let model = Self.model(role: .doriAdmin, repository: repository)
        await model.load()
        await model.receive(AcquisitionDeliveryModelTests.form())

        #expect(repository.commands.last?.action == .receive)
        #expect(model.detail?.delivery?.reception?.result == .accepted)
        #expect(model.confirmationMessage == "Aceptada")
    }

    @Test func doriReceivesAUnitWithObservations() async {
        let repository = Repository(journey: AcquisitionDeliveryModelTests.journey(status: "ready_for_delivery"))
        let model = Self.model(role: .doriAdmin, repository: repository)
        var form = AcquisitionDeliveryModelTests.form()
        form.newDamage = true
        form.note = "Rayón menor en defensa."
        await model.load()
        await model.receive(form)

        #expect(model.detail?.delivery?.reception?.result == .acceptedWithObservations)
        #expect(model.confirmationMessage == "Aceptada con observaciones")
    }

    @Test func missingSecondKeyCreatesTheServerHold() async {
        let repository = Repository(journey: AcquisitionDeliveryModelTests.journey(status: "ready_for_delivery"))
        let model = Self.model(role: .doriAdmin, repository: repository)
        var form = AcquisitionDeliveryModelTests.form()
        form.keysComplete = false
        form.note = "Falta segunda llave."
        await model.load()
        await model.receive(form)

        #expect(model.detail?.delivery?.reception?.result == .acceptedWithCondition)
        #expect(model.detail?.delivery?.hold?.amountMxn == 6_000)
        #expect(model.detail?.delivery?.hold?.status == .pendingSupplier)
    }

    @Test func providerReportsTheSecondKeyAsDelivered() async {
        let repository = Repository(journey: Self.conditionalJourney(status: .pendingSupplier))
        let model = Self.model(role: .provider, repository: repository)
        await model.load()
        await model.resolveCondition()

        #expect(repository.commands.last?.action == .resolveCondition)
        #expect(model.detail?.delivery?.hold?.status == .readyForReview)
    }

    @Test func doriConfirmsResolutionAndClosesTheOperation() async {
        let repository = Repository(journey: Self.conditionalJourney(status: .readyForReview))
        let model = Self.model(role: .doriAdmin, repository: repository)
        await model.load()
        await model.closeCondition()

        #expect(repository.commands.last?.action == .closeCondition)
        #expect(model.detail?.delivery?.orderStatus == "closed")
        #expect(model.detail?.delivery?.hold?.status == .resolved)
    }

    @Test func aRejectedCommandLeavesSimpleSpanishFeedback() async {
        let repository = Repository(
            journey: AcquisitionDeliveryModelTests.journey(status: "awarded"),
            shouldFail: true
        )
        let model = Self.model(role: .provider, repository: repository)
        await model.load()
        await model.markReady()

        #expect(model.feedbackMessage == "No pudimos completar la acción. La operación no cambió.")
        #expect(model.detail?.delivery?.orderStatus == "awarded")
    }

    @Test func authoritativeReloadRebuildsStateWithoutRealtimeHistory() async {
        let repository = Repository(journey: AcquisitionDeliveryModelTests.journey(status: "awarded"))
        let model = Self.model(role: .provider, repository: repository)
        await model.load()
        repository.journey = AcquisitionDeliveryModelTests.journey(status: "ready_for_delivery")
        await model.load()

        #expect(model.detail?.delivery?.orderStatus == "ready_for_delivery")
        #expect(repository.loads == 2)
    }

    private static func conditionalJourney(status: AcquisitionHoldStatus) -> AcquisitionDeliveryJourney {
        AcquisitionDeliveryModelTests.journey(
            status: "accepted_with_condition",
            hold: AcquisitionHold(
                amountMxn: 6_000,
                reason: "Falta segunda llave.",
                status: status,
                supplierResolutionNote: status == .pendingSupplier ? nil : "Segunda llave entregada."
            )
        )
    }

    private static func model(role: AcquisitionRole, repository: Repository) -> AcquisitionOfferDetailViewModel {
        AcquisitionOfferDetailViewModel(
            offerID: offerID,
            membership: AcquisitionMembership(
                id: UUID(),
                environmentID: UUID(),
                profileID: UUID(),
                supplierID: role == .provider ? UUID() : nil,
                role: role
            ),
            repository: repository
        )
    }

    private final class Repository: AcquisitionRepository {
        var journey: AcquisitionDeliveryJourney
        var commands: [AcquisitionDeliveryCommand] = []
        var loads = 0
        let shouldFail: Bool

        init(journey: AcquisitionDeliveryJourney, shouldFail: Bool = false) {
            self.journey = journey
            self.shouldFail = shouldFail
        }

        func loadMembership(profileID: UUID) async throws -> AcquisitionMembership { throw CancellationError() }
        func loadRequests() async throws -> [AcquisitionRequest] { [] }
        func loadOffers() async throws -> [AcquisitionOfferSummary] { [Self.detail(journey).offer] }
        func submitOffer(_ submission: AcquisitionOfferSubmission, membership: AcquisitionMembership) async throws -> AcquisitionOfferSummary { throw CancellationError() }
        func respondToOffer(_ command: AcquisitionOfferCommand) async throws -> AcquisitionOfferCommandResult { throw CancellationError() }

        func loadOfferDetail(
            offerID: UUID,
            membership: AcquisitionMembership
        ) async throws -> AcquisitionOfferDetail {
            loads += 1
            var detail = Self.detail(journey)
            if membership.role == .provider {
                detail = AcquisitionOfferDetail(
                    offer: detail.offer,
                    assessment: nil,
                    negotiations: detail.negotiations,
                    evidence: detail.evidence,
                    delivery: AcquisitionDeliveryJourney(
                        orderID: journey.orderID,
                        supplierName: nil,
                        finalPriceMxn: journey.finalPriceMxn,
                        orderStatus: journey.orderStatus,
                        deliveryStatus: journey.deliveryStatus,
                        reception: journey.reception,
                        hold: journey.hold
                    )
                )
            }
            return detail
        }

        func completeDelivery(
            _ command: AcquisitionDeliveryCommand
        ) async throws -> AcquisitionDeliveryCommandResult {
            commands.append(command)
            if shouldFail { throw CancellationError() }

            let result: AcquisitionReceptionResult?
            switch command.action {
            case .ready:
                journey = AcquisitionDeliveryModelTests.journey(status: "ready_for_delivery")
                result = nil
            case .receive:
                guard let checklist = command.checklist else { throw CancellationError() }
                if !checklist.vinCorrect {
                    result = .rejected
                } else if !checklist.keysComplete || !checklist.chargersComplete {
                    result = .acceptedWithCondition
                } else if !checklist.mileageCorrect || checklist.newDamage {
                    result = .acceptedWithObservations
                } else {
                    result = .accepted
                }
                let reception = AcquisitionReception(
                    checklist: checklist,
                    result: result!,
                    issueSummary: command.note,
                    holdAmountMxn: result == .acceptedWithCondition ? 6_000 : 0
                )
                let hold = result == .acceptedWithCondition
                    ? AcquisitionHold(
                        amountMxn: 6_000,
                        reason: command.note ?? "Condición pendiente.",
                        status: .pendingSupplier,
                        supplierResolutionNote: nil
                    )
                    : nil
                journey = AcquisitionDeliveryModelTests.journey(
                    status: result!.rawValue,
                    hold: hold,
                    reception: reception
                )
            case .resolveCondition:
                journey = AcquisitionDeliveryFlowTests.conditionalJourney(status: .readyForReview)
                result = nil
            case .closeCondition:
                let resolvedHold = AcquisitionHold(
                    amountMxn: 6_000,
                    reason: "Falta segunda llave.",
                    status: .resolved,
                    supplierResolutionNote: "Segunda llave entregada."
                )
                journey = AcquisitionDeliveryModelTests.journey(status: "closed", hold: resolvedHold)
                result = nil
            }
            return AcquisitionDeliveryCommandResult(
                orderID: command.orderID,
                status: journey.orderStatus,
                receptionResult: result,
                holdAmountMxn: journey.hold?.amountMxn ?? 0
            )
        }

        private static func detail(_ journey: AcquisitionDeliveryJourney) -> AcquisitionOfferDetail {
            AcquisitionOfferDetail(
                offer: AcquisitionOfferSummary(
                    id: AcquisitionDeliveryFlowTests.offerID,
                    requestID: UUID(),
                    status: journey.orderStatus,
                    model: "Dolphin Mini",
                    version: "Plus",
                    year: 2025,
                    mileage: 8_400,
                    priceMxn: 274_000,
                    transferIncluded: true,
                    vin: "LGXCE6CB1S0000011",
                    agreedPriceMxn: 268_000
                ),
                assessment: nil,
                negotiations: [],
                evidence: [],
                delivery: journey
            )
        }
    }
}
