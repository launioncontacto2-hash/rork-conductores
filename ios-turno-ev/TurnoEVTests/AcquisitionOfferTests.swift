import Foundation
import Testing
@testable import TurnoEV

struct AcquisitionOfferFormTests {
    @Test func responseRPCIncludesNullableArgumentsAsExplicitNulls() throws {
        let parameters = SupabaseAcquisitionRepository.RespondOfferParameters(
            p_offer_id: UUID(),
            p_action: "accept",
            p_amount_mxn: nil,
            p_message: nil,
            p_idempotency_key: "accept-null-contract"
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters))
                as? [String: Any]
        )
        #expect(object.keys.count == 5)
        #expect(object["p_amount_mxn"] is NSNull)
        #expect(object["p_message"] is NSNull)
    }

    @Test func offerRPCIncludesNullableArgumentsAsExplicitNulls() throws {
        let parameters = SupabaseAcquisitionRepository.SubmitOfferParameters(
            p_offer_id: UUID(),
            p_request_id: UUID(),
            p_vin: "LGXCE6CB1S0000011",
            p_model: "Dolphin Mini",
            p_version: nil,
            p_year: 2025,
            p_mileage: 8_400,
            p_declared_soh: nil,
            p_color: "Blanco",
            p_price_mxn: 274_000,
            p_transfer_included: true,
            p_committed_delivery_date: Date(timeIntervalSince1970: 1_800_000_000),
            p_evidence: [],
            p_idempotency_key: "offer-null-contract"
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters))
                as? [String: Any]
        )
        #expect(object.keys.count == 14)
        #expect(object["p_version"] is NSNull)
        #expect(object["p_declared_soh"] is NSNull)
    }

    @Test func acceptsAValidFormWithoutKnownBatteryHealth() throws {
        let submission = try Self.validForm().makeSubmission(
            request: Self.request,
            offerID: Self.offerID,
            idempotencyKey: "offer-test-valid"
        )

        #expect(submission.vin == "LGXCE6CB1S0000011")
        #expect(submission.year == 2025)
        #expect(submission.mileage == 8_400)
        #expect(submission.priceMxn == 274_000)
        #expect(submission.declaredSoh == nil)
        #expect(submission.evidence.map(\.kind) == AcquisitionEvidenceKind.detailedStandard)
    }

    @Test func refusesAnEmptyVin() {
        var form = Self.validForm()
        form.vin = ""
        #expect(throws: AcquisitionOfferFormIssue.vinRequired) {
            try form.makeSubmission(request: Self.request)
        }
    }

    @Test func refusesInvalidMileage() {
        var form = Self.validForm()
        form.mileage = "-1"
        #expect(throws: AcquisitionOfferFormIssue.invalidMileage) {
            try form.makeSubmission(request: Self.request)
        }
    }

    @Test func refusesInvalidPrice() {
        var form = Self.validForm()
        form.price = "0"
        #expect(throws: AcquisitionOfferFormIssue.invalidPrice) {
            try form.makeSubmission(request: Self.request)
        }
    }

    @Test func refusesAnOfferUntilAllPublicRequirementsAreConfirmed() {
        var form = Self.validForm()
        form.confirmedRequirements.remove(.charger220)
        #expect(throws: AcquisitionOfferFormIssue.requirementsRequired) {
            try form.makeSubmission(request: Self.request)
        }
    }

    @Test func buildsTheImmutablePrivateStoragePath() {
        let path = AcquisitionEvidencePath.make(
            environmentID: Self.environmentID,
            supplierID: Self.supplierID,
            offerID: Self.offerID,
            kind: .dashboard
        )
        #expect(
            path == "ad610000-0000-4000-8000-000000000001/"
                + "ad610000-0000-4000-8000-000000000002/"
                + "ad610000-0000-4000-8000-000000000003/dashboard.jpg"
        )
    }

    @Test func transformsTheRpcResponseIntoThePublicOffer() {
        let row = SupabaseAcquisitionRepository.OfferRow(
            id: Self.offerID,
            request_id: Self.request.id,
            supplier_id: Self.supplierID,
            status: "submitted",
            model: "Dolphin Mini",
            version: "Plus",
            year: 2025,
            mileage: 8_400,
            price_mxn: 274_000,
            transfer_included: true,
            vin: "LGXCE6CB1S0000011",
            declared_soh: 96,
            color: "Blanco",
            agreed_price_mxn: nil,
            submitted_at: nil
        )
        let offer = SupabaseAcquisitionRepository.offer(from: row)

        #expect(offer.modelAndVersion == "Dolphin Mini Plus")
        #expect(offer.year == 2025)
        #expect(offer.mileage == 8_400)
        #expect(offer.priceMxn == 274_000)
        #expect(offer.transferIncluded)
    }

    @Test func offerProjectionKeepsItsSupplierIdentityButExcludesInternalAssessment() {
        let columns = AcquisitionQueries.offerColumns.lowercased()
        #expect(columns.contains("supplier_id"))
        #expect(!columns.contains("recommendation"))
        #expect(!columns.contains("risk"))
        #expect(!columns.contains("internal"))
    }

    fileprivate static let environmentID = UUID(
        uuidString: "AD610000-0000-4000-8000-000000000001"
    )!
    fileprivate static let supplierID = UUID(
        uuidString: "AD610000-0000-4000-8000-000000000002"
    )!
    fileprivate static let offerID = UUID(
        uuidString: "AD610000-0000-4000-8000-000000000003"
    )!
    fileprivate static let profileID = UUID(
        uuidString: "AD610000-0000-4000-8000-000000000004"
    )!
    fileprivate static let request = AcquisitionRequest(
        id: UUID(uuidString: "AD610000-0000-4000-8000-000000000005")!,
        code: "ADQ-TEST-001",
        title: "15 autos requeridos",
        targetQuantity: 15,
        model: "Dolphin Mini",
        versions: ["Plus"],
        minimumYear: 2024,
        maximumYear: 2026,
        maximumMileage: 30_000,
        deliveryCity: "Puebla",
        deadlineAt: nil
    )

    fileprivate static func validForm() -> AcquisitionOfferFormData {
        var form = AcquisitionOfferFormData()
        form.vin = "lgxce6cb1s0000011"
        form.year = "2025"
        form.mileage = "8,400"
        form.price = "$274,000"
        form.color = "Blanco"
        form.transferIncluded = true
        form.batteryKnowledge = .requiresDORIVerification
        form.confirmedRequirements = Set(AcquisitionOfferRequirement.allCases)
        form.evidence = Dictionary(
            uniqueKeysWithValues: AcquisitionEvidenceKind.detailedStandard.enumerated().map {
                ($0.element, Data([UInt8($0.offset + 1)]))
            }
        )
        return form
    }
}

@MainActor
struct AcquisitionOfferSubmissionTests {
    @Test func uploadsTheFourteenRequiredEvidenceItemsAndReportsSuccess() async {
        let repository = Repository()
        var received: AcquisitionOfferSummary?
        let model = Self.model(repository: repository) { received = $0 }
        model.form = AcquisitionOfferFormTests.validForm()

        await model.submit()

        #expect(repository.submission?.evidence.count == 14)
        #expect(repository.submission?.evidence.map(\.kind) == AcquisitionEvidenceKind.detailedStandard)
        #expect(received?.id == repository.submission?.offerID)
        if case .succeeded(let offer) = model.state {
            #expect(offer.status == "submitted")
        } else {
            Issue.record("La propuesta válida debía terminar en éxito.")
        }
    }

    @Test func keepsTheFormAndShowsSimpleFeedbackAfterFailure() async {
        let repository = Repository(fails: true)
        let model = Self.model(repository: repository)
        model.form = AcquisitionOfferFormTests.validForm()

        await model.submit()

        #expect(model.state == .failed)
        #expect(model.form.vin == "lgxce6cb1s0000011")
        #expect(model.feedbackMessage == "Intenta nuevamente. Tus datos siguen en el formulario.")
    }

    @Test func identifiesTheExactFailedSubmissionStageWithoutClearingTheForm() async {
        let failure = AcquisitionOfferSubmissionError(
            stage: .evidenceUpload,
            evidenceKind: .dashboard,
            technicalDescription: "network_connection_lost"
        )
        let repository = Repository(failure: failure)
        let model = Self.model(repository: repository)
        model.form = AcquisitionOfferFormTests.validForm()

        await model.submit()

        #expect(model.failureStage == .evidenceUpload)
        #expect(model.feedbackMessage?.contains("tablero") == true)
        #expect(model.form.evidence.count == 14)
    }

    @Test func storageAuthorizationFailureDoesNotPretendToBeAConnectionProblem() {
        let error = AcquisitionOfferSubmissionError(
            stage: .evidenceUpload,
            evidenceKind: .vin,
            technicalDescription: "http_status=403 code=42501 message=row-level security policy"
        )

        #expect(error.localizedDescription.contains("sesión"))
        #expect(!error.localizedDescription.contains("conexión"))
    }

    private static func model(
        repository: Repository,
        onSubmitted: @escaping (AcquisitionOfferSummary) -> Void = { _ in }
    ) -> AcquisitionOfferFormViewModel {
        AcquisitionOfferFormViewModel(
            request: AcquisitionOfferFormTests.request,
            membership: AcquisitionMembership(
                id: UUID(),
                environmentID: AcquisitionOfferFormTests.environmentID,
                profileID: AcquisitionOfferFormTests.profileID,
                supplierID: AcquisitionOfferFormTests.supplierID,
                role: .provider
            ),
            repository: repository,
            onSubmitted: onSubmitted
        )
    }

    private enum Failure: Error { case unavailable }

    private final class Repository: AcquisitionRepository {
        let fails: Bool
        let failure: (any Error)?
        var submission: AcquisitionOfferSubmission?

        init(fails: Bool = false, failure: (any Error)? = nil) {
            self.fails = fails
            self.failure = failure
        }

        func loadMembership(
            profileID: UUID,
            environmentID: UUID
        ) async throws -> AcquisitionMembership {
            throw Failure.unavailable
        }
        func loadRequests() async throws -> [AcquisitionRequest] { [] }
        func loadOffers() async throws -> [AcquisitionOfferSummary] { [] }
        func loadOfferDetail(
            offerID: UUID,
            membership: AcquisitionMembership
        ) async throws -> AcquisitionOfferDetail {
            throw Failure.unavailable
        }

        func submitOffer(
            _ submission: AcquisitionOfferSubmission,
            membership: AcquisitionMembership
        ) async throws -> AcquisitionOfferSummary {
            self.submission = submission
            if let failure { throw failure }
            if fails { throw Failure.unavailable }
            return AcquisitionOfferSummary(
                id: submission.offerID,
                requestID: submission.requestID,
                status: "submitted",
                model: submission.model,
                version: submission.version,
                year: submission.year,
                mileage: submission.mileage,
                priceMxn: submission.priceMxn,
                transferIncluded: submission.transferIncluded
            )
        }

        func respondToOffer(
            _ command: AcquisitionOfferCommand
        ) async throws -> AcquisitionOfferCommandResult {
            throw Failure.unavailable
        }

        func completeDelivery(
            _ command: AcquisitionDeliveryCommand
        ) async throws -> AcquisitionDeliveryCommandResult {
            throw Failure.unavailable
        }
    }
}
