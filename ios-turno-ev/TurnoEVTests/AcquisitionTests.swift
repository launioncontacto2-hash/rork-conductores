import Foundation
import Testing
@testable import TurnoEV

struct AcquisitionRoleAndPresentationTests {
    private static let profileID = UUID(uuidString: "AD520000-0000-4000-8000-000000000001")!
    private static let environmentID = UUID(uuidString: "AD520000-0000-4000-8000-000000000002")!
    private static let supplierID = UUID(uuidString: "AD520000-0000-4000-8000-000000000003")!
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func traditionalMembershipKeepsTraditionalRoute() throws {
        let route = try SupabaseSessionResolver.preferredRoute(
            hasStaffMembership: true,
            acquisitionMembership: nil
        )
        #expect(route == .staff)
    }

    @Test func acquisitionAdminWithoutTraditionalMembershipUsesAcquisition() throws {
        let membership = try Self.membership(
            role: "dori_admin",
            supplierID: nil
        )
        let route = try SupabaseSessionResolver.preferredRoute(
            hasStaffMembership: false,
            acquisitionMembership: membership
        )
        #expect(
            route == SessionMembershipRoute.acquisition(AcquisitionRole.doriAdmin)
        )
    }

    @Test func providerWithoutTraditionalMembershipUsesAcquisition() throws {
        let membership = try Self.membership(
            role: "provider",
            supplierID: Self.supplierID
        )
        let route = try SupabaseSessionResolver.preferredRoute(
            hasStaffMembership: false,
            acquisitionMembership: membership
        )
        #expect(
            route == SessionMembershipRoute.acquisition(AcquisitionRole.provider)
        )
    }

    @Test func accountWithoutAnyMembershipIsDenied() {
        #expect(throws: (any Error).self) {
            try SupabaseSessionResolver.preferredRoute(
                hasStaffMembership: false,
                acquisitionMembership: nil
            )
        }
    }

    @Test func membershipFromAnotherEnvironmentIsDenied() {
        #expect(throws: (any Error).self) {
            try Self.membership(
                role: "provider",
                supplierID: Self.supplierID,
                environmentID: UUID()
            )
        }
    }

    @Test func inactiveMembershipIsDenied() {
        #expect(throws: (any Error).self) {
            try Self.membership(
                role: "provider",
                supplierID: Self.supplierID,
                status: "inactive"
            )
        }
    }

    @Test func resolvesOnlyTheTwoAcquisitionRoles() {
        #expect(StaffRole(backendValue: "dori_admin") == .doriAdmin)
        #expect(StaffRole(backendValue: "provider") == .provider)
        #expect(AcquisitionRole(rawValue: "dori_admin") == .doriAdmin)
        #expect(AcquisitionRole(rawValue: "provider") == .provider)
    }

    @Test func keepsExistingNavigationOutsideAcquisition() {
        #expect(AcquisitionNavigation.destination(for: .doriAdmin) == .administrator)
        #expect(AcquisitionNavigation.destination(for: .provider) == .provider)

        for role in StaffRole.operationalRoles + [.lab] {
            #expect(AcquisitionNavigation.destination(for: role) == nil)
        }
    }

    @Test func transformsBackendFieldsIntoSimpleSpanishPresentation() {
        let row = SupabaseAcquisitionRepository.RequestRow(
            id: UUID(uuidString: "AD500000-0000-4000-8000-000000000001")!,
            code: "ADQ-TEST-001",
            title: "15 autos requeridos",
            target_quantity: 15,
            model: "Dolphin Mini",
            versions: ["Plus"],
            minimum_year: 2024,
            maximum_year: 2026,
            maximum_mileage: 30_000,
            delivery_city: "Puebla",
            deadline_at: nil,
            status: "published"
        )
        let request = SupabaseAcquisitionRepository.request(from: row)
        #expect(request.modelAndVersions == "Dolphin Mini / Plus")
        #expect(request.yearRange == "2024–2026")
        #expect(request.maximumMileageText == "30,000")
    }

    @Test func derivesOnlyActionableDashboardCounts() {
        let request = Self.request()
        let offers = [
            AcquisitionOfferSummary(id: UUID(), requestID: request.id, status: "submitted"),
            AcquisitionOfferSummary(id: UUID(), requestID: request.id, status: "negotiating"),
            AcquisitionOfferSummary(id: UUID(), requestID: request.id, status: "awarded"),
            AcquisitionOfferSummary(id: UUID(), requestID: request.id, status: "rejected"),
        ]
        let summary = AcquisitionRequestSummary(request: request, offers: offers)

        #expect(summary.securedCount == 1)
        #expect(summary.decidingCount == 2)
        #expect(summary.missingCount == 14)
    }

    @Test func presentsBackendStatesAsHumanActions() {
        #expect(AcquisitionHumanStatus.title(for: "negotiating", role: .provider) == "DORI hizo una oferta")
        #expect(AcquisitionHumanStatus.title(for: "awarded", role: .doriAdmin) == "Compra confirmada")
        #expect(AcquisitionHumanStatus.title(for: "ready_for_delivery", role: .doriAdmin) == "Esperando entrega")
        #expect(
            AcquisitionHumanStatus.title(for: "accepted_with_condition", role: .provider)
                == "Falta resolver un detalle"
        )
        #expect(AcquisitionHumanStatus.title(for: "closed", role: .provider) == "Operación terminada")
    }

    @Test func groupsTheDashboardByTheNextDecision() {
        #expect(AcquisitionHumanStatus.group(for: "submitted", role: .doriAdmin) == .attention)
        #expect(AcquisitionHumanStatus.group(for: "submitted", role: .provider) == .inProgress)
        #expect(AcquisitionHumanStatus.group(for: "negotiating", role: .provider) == .attention)
        #expect(AcquisitionHumanStatus.group(for: "awarded", role: .doriAdmin) == .inProgress)
        #expect(AcquisitionHumanStatus.group(for: "closed", role: .provider) == .finished)
    }

    @Test func showsEachVinOnlyOnce() {
        let vin = "LGXCE6CB1S0000011"
        let offers = [
            AcquisitionOfferSummary(id: UUID(), requestID: UUID(), status: "negotiating", vin: vin),
            AcquisitionOfferSummary(id: UUID(), requestID: UUID(), status: "submitted", vin: vin.lowercased()),
            AcquisitionOfferSummary(id: UUID(), requestID: UUID(), status: "awarded", vin: "LGXCE6CB1S0000022"),
        ]

        let visible = AcquisitionHumanStatus.uniqueVehicles(offers)

        #expect(visible.count == 2)
        #expect(visible[0].status == "negotiating")
    }

    @Test func providerQueriesContainNoInternalRulesOrAssessmentFields() {
        let exposed = (AcquisitionQueries.requestColumns + AcquisitionQueries.offerColumns)
            .lowercased()
        #expect(!exposed.contains("internal_price"))
        #expect(!exposed.contains("minimum_soh"))
        #expect(!exposed.contains("target_soh"))
        #expect(!exposed.contains("assessment"))
        #expect(
            AcquisitionQueries.offerColumns
                == "id, request_id, supplier_id, status, model, version, year, mileage, price_mxn, transfer_included, vin, declared_soh, agreed_price_mxn, submitted_at"
        )
    }

    private static func request() -> AcquisitionRequest {
        AcquisitionRequest(
            id: UUID(uuidString: "AD500000-0000-4000-8000-000000000001")!,
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
    }

    private static func membership(
        role: String,
        supplierID: UUID?,
        environmentID: UUID = AcquisitionRoleAndPresentationTests.environmentID,
        status: String = "active"
    ) throws -> AcquisitionMembership {
        try SupabaseAcquisitionRepository.membership(
            from: [
                SupabaseAcquisitionRepository.MembershipRow(
                    id: UUID(),
                    environment_id: environmentID,
                    profile_id: profileID,
                    supplier_id: supplierID,
                    role: role,
                    status: status,
                    starts_at: now.addingTimeInterval(-60),
                    ends_at: nil
                ),
            ],
            profileID: profileID,
            environmentID: Self.environmentID,
            now: now
        )
    }
}

@MainActor
struct SupabaseAuthDiagnosticTests {
    @Test func classifiesInvalidCredentials() {
        #expect(
            SupabaseAuthDiagnostic.kind(
                authCode: "invalid_credentials",
                httpStatus: 400
            ) == .invalidCredentials
        )
    }

    @Test func classifiesUnconfirmedUser() {
        #expect(
            SupabaseAuthDiagnostic.kind(
                authCode: "email_not_confirmed",
                httpStatus: 400
            ) == .emailNotConfirmed
        )
    }

    @Test func classifiesNetworkFailureWithoutSensitiveValues() {
        let report = SupabaseAuthDiagnostic.classify(
            URLError(.notConnectedToInternet)
        )
        #expect(report.kind == .network)
        #expect(!report.safeLogLine.contains("password"))
        #expect(!report.safeLogLine.contains("token"))
    }

    @Test func classifiesMissingConfiguration() {
        let report = SupabaseAuthDiagnostic.classify(
            SupabaseAuthProbe.ProbeError.notConfigured
        )
        #expect(report.kind == .configuration)
    }

    @Test func distinguishesAuthenticationFromMissingMembership() {
        let report = SupabaseAuthDiagnostic.classify(
            SupabaseAuthProbe.ProbeError.noMembership
        )
        #expect(report.kind == .authenticatedWithoutMembership)
    }

    @Test func classifiesServerFailure() {
        #expect(
            SupabaseAuthDiagnostic.kind(
                authCode: "unexpected_failure",
                httpStatus: 500
            ) == .server
        )
    }
}

@MainActor
struct AcquisitionViewModelTests {
    @Test func representsAnEmptyRequestList() async {
        let repository = Repository(requests: [])
        let model = AcquisitionViewModel(
            principal: Self.principal(role: .doriAdmin),
            repository: repository
        )

        await model.load()

        #expect(model.state == .empty)
        #expect(model.activeRequest == nil)
    }

    @Test func replacesTechnicalFailuresWithTheSimpleErrorState() async {
        let repository = Repository(requests: [], failure: TestFailure.unavailable)
        let model = AcquisitionViewModel(
            principal: Self.principal(role: .provider),
            repository: repository
        )

        await model.load()

        #expect(model.state == .failed)
        #expect(model.requests.isEmpty)
        #expect(model.offers.isEmpty)
    }

    @Test func refusesAMembershipForAnotherRole() async {
        let repository = Repository(
            requests: [],
            membershipRole: .provider
        )
        let model = AcquisitionViewModel(
            principal: Self.principal(role: .doriAdmin),
            repository: repository
        )

        await model.load()

        #expect(model.state == .failed)
        #expect(model.membership == nil)
    }

    private static func principal(role: StaffRole) -> SessionPrincipal {
        SessionPrincipal(
            authUserId: UUID().uuidString,
            profileId: Repository.profileID.uuidString,
            name: role == .provider ? "Agencia Puebla Centro" : "Administrador DORI",
            employeeNumber: role == .provider ? "ADQ-TEST-PROV-001" : "ADQ-TEST-ADMIN",
            email: "cuenta@ejemplo.test",
            role: role,
            environmentId: Repository.environmentID.uuidString,
            stationId: nil,
            stationCode: nil,
            stationName: nil,
            shiftGroup: nil,
            shiftSlot: nil
        )
    }

    private enum TestFailure: Error {
        case unavailable
    }

    private final class Repository: AcquisitionRepository {
        static let profileID = UUID(uuidString: "AD510000-0000-4000-8000-000000000001")!
        static let environmentID = UUID(uuidString: "AD510000-0000-4000-8000-000000000002")!

        let requests: [AcquisitionRequest]
        let failure: Error?
        let membershipRole: AcquisitionRole

        init(
            requests: [AcquisitionRequest],
            failure: Error? = nil,
            membershipRole: AcquisitionRole = .doriAdmin
        ) {
            self.requests = requests
            self.failure = failure
            self.membershipRole = membershipRole
        }

        func loadMembership(
            profileID: UUID,
            environmentID: UUID
        ) async throws -> AcquisitionMembership {
            if let failure { throw failure }
            return AcquisitionMembership(
                id: UUID(),
                environmentID: Self.environmentID,
                profileID: profileID,
                supplierID: membershipRole == .provider ? UUID() : nil,
                role: membershipRole
            )
        }

        func loadRequests() async throws -> [AcquisitionRequest] {
            if let failure { throw failure }
            return requests
        }

        func loadOffers() async throws -> [AcquisitionOfferSummary] {
            if let failure { throw failure }
            return []
        }

        func loadOfferDetail(
            offerID: UUID,
            membership: AcquisitionMembership
        ) async throws -> AcquisitionOfferDetail {
            throw TestFailure.unavailable
        }

        func submitOffer(
            _ submission: AcquisitionOfferSubmission,
            membership: AcquisitionMembership
        ) async throws -> AcquisitionOfferSummary {
            if let failure { throw failure }
            return AcquisitionOfferSummary(
                id: submission.offerID,
                requestID: submission.requestID,
                status: "submitted",
                model: submission.model,
                version: submission.version,
                year: submission.year,
                mileage: submission.mileage,
                priceMxn: submission.priceMxn
            )
        }

        func respondToOffer(
            _ command: AcquisitionOfferCommand
        ) async throws -> AcquisitionOfferCommandResult {
            throw TestFailure.unavailable
        }

        func completeDelivery(
            _ command: AcquisitionDeliveryCommand
        ) async throws -> AcquisitionDeliveryCommandResult {
            throw TestFailure.unavailable
        }
    }
}
