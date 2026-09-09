import Foundation
import Testing
@testable import TurnoEV

struct AcquisitionOfferFormTests {
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
        #expect(submission.evidence.map(\.kind) == AcquisitionEvidenceKind.allCases)
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
            status: "submitted",
            model: "Dolphin Mini",
            version: "Plus",
            year: 2025,
            mileage: 8_400,
            price_mxn: 274_000,
            transfer_included: true,
            submitted_at: nil
        )
        let offer = SupabaseAcquisitionRepository.offer(from: row)

        #expect(offer.modelAndVersion == "Dolphin Mini Plus")
        #expect(offer.year == 2025)
        #expect(offer.mileage == 8_400)
        #expect(offer.priceMxn == 274_000)
        #expect(offer.transferIncluded)
    }

    @Test func providerProjectionExcludesInternalAssessmentAndOtherSupplierFields() {
        let columns = AcquisitionQueries.offerColumns.lowercased()
        #expect(!columns.contains("recommendation"))
        #expect(!columns.contains("risk"))
        #expect(!columns.contains("declared_soh"))
        #expect(!columns.contains("supplier_id"))
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
        form.evidence = [
            .vin: Data([1]),
            .dashboard: Data([2]),
            .front: Data([3]),
        ]
        return form
    }
}

@MainActor
struct AcquisitionOfferSubmissionTests {
    @Test func uploadsThreeEvidenceItemsAndReportsSuccess() async {
        let repository = Repository()
        var received: AcquisitionOfferSummary?
        let model = Self.model(repository: repository) { received = $0 }
        model.form = AcquisitionOfferFormTests.validForm()

        await model.submit()

        #expect(repository.submission?.evidence.count == 3)
        #expect(repository.submission?.evidence.map(\.kind) == AcquisitionEvidenceKind.allCases)
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
        var submission: AcquisitionOfferSubmission?

        init(fails: Bool = false) { self.fails = fails }

        func loadMembership(profileID: UUID) async throws -> AcquisitionMembership {
            throw Failure.unavailable
        }
        func loadRequests() async throws -> [AcquisitionRequest] { [] }
        func loadOffers() async throws -> [AcquisitionOfferSummary] { [] }

        func submitOffer(
            _ submission: AcquisitionOfferSubmission,
            membership: AcquisitionMembership
        ) async throws -> AcquisitionOfferSummary {
            self.submission = submission
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
    }
}
