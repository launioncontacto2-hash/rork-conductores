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
            maximum_unit_price_mxn: 290_000,
            delivery_city: "Puebla",
            destination_station_name: "DORI Puebla",
            deadline_at: nil,
            target_delivery_date: "2026-10-15",
            fiscal_period: "2026-09-01",
            minimum_soh: 90,
            soh_diagnosis_max_age_days: 30,
            delivery_terms_document_path: "env/admin/document/terms.pdf",
            status: "published"
        )
        let request = SupabaseAcquisitionRepository.request(from: row)
        #expect(request.modelAndVersions == "Dolphin Mini / Plus")
        #expect(request.yearRange == "2024–2026")
        #expect(request.maximumMileageText == "30,000")
        #expect(request.targetDeliveryDate != nil)
        if let targetDeliveryDate = request.targetDeliveryDate {
            let deliveryParts = Calendar(identifier: .gregorian).dateComponents(
                [.year, .month, .day],
                from: targetDeliveryDate
            )
            #expect(deliveryParts.year == 2026)
            #expect(deliveryParts.month == 10)
            #expect(deliveryParts.day == 15)
        }
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

    @Test func deduplicatesByOfferIDAndVinInsideOnePresentationSource() {
        let repeatedID = UUID()
        let requestID = UUID()
        let offers = [
            AcquisitionOfferSummary(
                id: repeatedID, requestID: requestID, status: "submitted",
                year: 2025, vin: ""
            ),
            AcquisitionOfferSummary(
                id: repeatedID, requestID: requestID, status: "submitted",
                year: 2025, vin: ""
            ),
            AcquisitionOfferSummary(
                id: UUID(), requestID: requestID, status: "submitted",
                year: 2025, vin: " LGXCE6CB1S0000011 "
            ),
            AcquisitionOfferSummary(
                id: UUID(), requestID: requestID, status: "submitted",
                year: 2025, vin: "lgxce6cb1s0000011"
            ),
        ]

        let visible = AcquisitionHumanStatus.uniqueVehicles(offers)

        #expect(visible.count == 2)
        #expect(Set(visible.map(\.id)).count == visible.count)
    }

    @Test func formatsVehicleYearWithoutAThousandsSeparator() {
        let offer = AcquisitionOfferSummary(
            id: UUID(), requestID: UUID(), status: "submitted", year: 2025
        )

        #expect(offer.yearText == "2025")
        #expect(!offer.yearText.contains(","))
    }

    @Test func requestModelIsPreparedForDetailedRequirementsWithoutChangingCurrentData() {
        let requirement = AcquisitionRequestRequirement(
            id: "charger_110v", title: "Cargador 110V", value: "Incluido"
        )
        let request = AcquisitionRequest(
            id: UUID(), code: "ADQ-TEST-001", title: "Solicitud",
            targetQuantity: 15, model: "Dolphin Mini", versions: ["Plus"],
            minimumYear: 2025, maximumYear: 2026, maximumMileage: 20_000,
            deliveryCity: "Puebla", deadlineAt: nil,
            detailedRequirements: [requirement]
        )

        #expect(request.detailedRequirements == [requirement])
        #expect(request.visibleRequirements == [requirement])
    }

    @Test func newRequestKeepsFlexibleRequirementsWithoutInternalRules() throws {
        var draft = AcquisitionRequestDraft()
        draft.model = "BYD King"
        draft.versions = "GL, GS"
        draft.targetQuantity = "4"
        draft.minimumYear = "2025"
        draft.maximumYear = "2026"
        draft.maximumMileage = "15,000"
        draft.maximumUnitPrice = "500000"
        draft.deliveryTermsDocument = Data("Condiciones TEST".utf8)
        draft.deliveryTermsFilename = "condiciones-test.txt"
        draft.deliveryTermsMimeType = "text/plain"

        let publication = try draft.makePublication(idempotencyKey: "request-test")

        #expect(publication.model == "BYD King")
        #expect(publication.versions == ["GL", "GS"])
        #expect(publication.maximumMileage == 15_000)
        #expect(publication.requirements.filter { $0.category == .evidence }.count == 17)
        #expect(Set(publication.requirements.map(\.id)).count == publication.requirements.count)
        #expect(publication.deadlineAt != nil)
        #expect(publication.targetDeliveryDate != nil)
    }

    @Test func newRequestRejectsDuplicateRequirementCodesBeforeRPC() {
        var draft = AcquisitionRequestDraft()
        draft.model = "BYD King"
        draft.targetQuantity = "2"
        draft.minimumYear = "2025"
        draft.maximumYear = "2026"
        draft.maximumMileage = "20000"
        draft.maximumUnitPrice = "500000"
        draft.deliveryTermsDocument = Data("Condiciones TEST".utf8)
        draft.deliveryTermsFilename = "condiciones-test.txt"
        draft.requirements.append(draft.requirements[0])

        #expect(throws: AcquisitionRequestDraftIssue.duplicateRequirements) {
            _ = try draft.makePublication()
        }
    }

    @Test func newRequestDatesDefaultToNoon() throws {
        let fixedNow = try #require(
            Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 8))
        )
        let date = try #require(AcquisitionRequestDraft.defaultDate(daysFromNow: 14, now: fixedNow))
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        #expect(components.hour == 12)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test func publishRequestUsesCanonicalPostgresDateArgument() throws {
        let target = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 10, day: 20, hour: 12)
            )
        )
        let parameters = SupabaseAcquisitionRepository.PublishRequestParameters(
            p_model: "Dolphin Mini",
            p_versions: ["Plus"],
            p_target_quantity: 2,
            p_minimum_year: 2025,
            p_maximum_year: 2026,
            p_maximum_mileage: 20_000,
            p_maximum_unit_price_mxn: 290_000,
            p_delivery_city: "Puebla",
            p_destination_station_name: "DORI Puebla",
            p_fiscal_period: "2026-09-01",
            p_minimum_soh: 90,
            p_soh_diagnosis_max_age_days: 30,
            p_delivery_terms_document_path: "env/admin/document/terms.pdf",
            p_deadline_at: target.addingTimeInterval(-86_400),
            p_target_delivery_date: SupabaseAcquisitionRepository.postgresDateString(from: target),
            p_requirements: [],
            p_idempotency_key: "request-wire-date"
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any]
        )
        #expect(object["p_target_delivery_date"] as? String == "2026-10-20")
        #expect((object["p_target_delivery_date"] as? String)?.contains("T") == false)
    }

    @Test func acquisitionFiscalPeriodAlwaysUsesSpanishMonthNames() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let september = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        #expect(AcquisitionFiscalPeriodPresentation.monthName(8) == "Agosto")
        #expect(AcquisitionFiscalPeriodPresentation.text(for: september) == "Septiembre 2026")
        #expect(AcquisitionFiscalPeriodPresentation.monthName(10) == "Octubre")
    }

    @Test func requestRejectsUnsupportedOrOversizedDeliveryTermsBeforeStorage() {
        var draft = AcquisitionRequestDraft()
        draft.model = "BYD King"
        draft.targetQuantity = "2"
        draft.minimumYear = "2025"
        draft.maximumYear = "2026"
        draft.maximumMileage = "20000"
        draft.maximumUnitPrice = "500000"
        draft.deliveryTermsDocument = Data("Condiciones TEST".utf8)
        draft.deliveryTermsFilename = "condiciones.docx"
        draft.deliveryTermsMimeType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        #expect(throws: AcquisitionRequestDraftIssue.invalidDeliveryTermsType) {
            _ = try draft.makePublication()
        }

        draft.deliveryTermsMimeType = "application/pdf"
        draft.deliveryTermsDocument = Data(repeating: 0, count: AcquisitionRequestDraft.maximumDeliveryTermsBytes + 1)
        #expect(throws: AcquisitionRequestDraftIssue.deliveryTermsTooLarge) {
            _ = try draft.makePublication()
        }
    }

    @Test func commercialLanesAreExclusiveAcrossHomeAndPurchases() {
        #expect(AcquisitionCommercialLane.resolve(status: "submitted") == .proposal)
        #expect(AcquisitionCommercialLane.resolve(status: "negotiating") == .negotiation)
        #expect(AcquisitionCommercialLane.resolve(status: "price_agreed") == .negotiation)
        #expect(AcquisitionCommercialLane.resolve(status: "awarded") == .purchase)
        #expect(AcquisitionCommercialLane.resolve(status: "accepted_with_condition") == .purchase)
        #expect(AcquisitionCommercialLane.resolve(status: "closed") == .purchase)
        #expect(AcquisitionCommercialLane.resolve(status: "rejected") == .hidden)
    }

    @Test func requestPublicationKeepsOneIdempotencyKeyAcrossRetries() throws {
        var draft = AcquisitionRequestDraft()
        draft.model = "BYD King"
        draft.targetQuantity = "2"
        draft.minimumYear = "2025"
        draft.maximumYear = "2026"
        draft.maximumMileage = "20000"
        draft.maximumUnitPrice = "500000"
        draft.deliveryTermsDocument = Data("Condiciones TEST".utf8)
        draft.deliveryTermsFilename = "condiciones-test.txt"
        let first = try draft.makePublication()
        let retry = try draft.makePublication()
        #expect(first.idempotencyKey == retry.idempotencyKey)
    }

    @Test func requestRequirementKeepsDynamicResponseContract() {
        let requirement = AcquisitionRequestRequirement(
            id: "inspection_note", category: .condition,
            title: "Observaciones", value: "Describe el estado",
            responseType: .text, requiresDORIVerification: true
        )
        #expect(requirement.responseType == .text)
        #expect(requirement.requiresDORIVerification)
    }

    @Test func detailedEvidenceUsesTheApprovedDriverSidePrimaryKind() {
        #expect(AcquisitionEvidenceKind.detailedStandard.count == 17)
        #expect(AcquisitionEvidenceKind.detailedStandard.contains(.exteriorDriverSide))
        #expect(AcquisitionEvidenceKind.detailedStandard.contains(.originInvoice))
    }

    @Test func mapsEveryPersistedRequestStatusToHumanLanguage() {
        let expected = [
            "published": "Activa",
            "evaluating": "En evaluación",
            "partially_awarded": "Activa · Parcialmente cubierta",
            "awarded": "Completa",
            "closed": "Cerrada",
            "cancelled": "Cancelada",
        ]

        for (rawStatus, visibleTitle) in expected {
            let request = AcquisitionRequest(
                id: UUID(), code: "ADQ", title: "Solicitud", targetQuantity: 1,
                model: "Dolphin Mini", versions: [], minimumYear: 2025,
                maximumYear: 2026, maximumMileage: 20_000,
                deliveryCity: "Puebla", deadlineAt: nil, status: rawStatus
            )
            #expect(request.visibleStatus.title == visibleTitle)
            #expect(!request.visibleStatus.title.contains("_"))
        }
    }

    @Test func sharedRequestPresentationContainsTheApprovedPublicRequirements() {
        let requirements = Self.request().visibleRequirements
        #expect(requirements.count == 12)
        #expect(requirements.contains { $0.id == "charger_110v" && $0.value == "Incluido" })
        #expect(requirements.contains { $0.id == "ownership" })
        #expect(requirements.contains { $0.id == "battery" })
        #expect(requirements.contains { $0.id == "byd_warranty" && $0.value.contains("Remanente") })
        #expect(!requirements.map(\.value).joined().contains("8 años"))
    }

    @Test func providerQueriesContainNoInternalRulesOrAssessmentFields() {
        let exposed = (AcquisitionQueries.requestColumns + AcquisitionQueries.offerColumns)
            .lowercased()
        #expect(!exposed.contains("internal_price"))
        #expect(AcquisitionQueries.requestColumns.contains("minimum_soh"))
        #expect(!exposed.contains("target_soh"))
        #expect(!exposed.contains("assessment"))
        #expect(
            AcquisitionQueries.offerColumns
                == "id, request_id, supplier_id, status, model, version, year, mileage, price_mxn, transfer_included, vin, declared_soh, color, agreed_price_mxn, committed_delivery_date, request_fiscal_period, submitted_at"
        )
    }

    @Test func buildsSafeInstitutionalContactActions() {
        let contact = Self.contact(supplierID: nil)
        #expect(contact.callURL?.absoluteString == "tel:2220000000")
        #expect(contact.emailURL?.absoluteString == "mailto:adquisiciones.pue@dori.mx")
    }

    @Test func presentsOnlyTheCounterpartyContactsForEachRole() throws {
        let supplierContact = Self.contact(supplierID: Self.supplierID)
        let doriContact = Self.contact(supplierID: nil)
        let contacts = [supplierContact, doriContact]

        let admin = try Self.membership(role: "dori_admin", supplierID: nil)
        let provider = try Self.membership(role: "provider", supplierID: Self.supplierID)

        #expect(AcquisitionContactDirectory.counterpartContacts(contacts, membership: admin) == [supplierContact])
        #expect(AcquisitionContactDirectory.counterpartContacts(contacts, membership: provider) == [doriContact])
    }

    @Test func rejectsMalformedContactActions() {
        let contact = AcquisitionInstitutionalContact(
            id: UUID(), supplierID: nil, organizationName: "DORI Puebla",
            personName: "Contacto", jobTitle: "Adquisiciones", phone: "sin teléfono",
            email: "correo inválido", businessHours: "09:00 a 18:00", isPrimary: true
        )
        #expect(contact.callURL == nil)
        #expect(contact.emailURL == nil)
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

    private static func contact(supplierID: UUID?) -> AcquisitionInstitutionalContact {
        AcquisitionInstitutionalContact(
            id: UUID(uuidString: supplierID == nil
                ? "AD530000-0000-4000-8000-000000000001"
                : "AD530000-0000-4000-8000-000000000002")!,
            supplierID: supplierID,
            organizationName: supplierID == nil ? "DORI Puebla" : "Agencia Puebla Centro",
            personName: supplierID == nil ? "Jorge Ramos" : "Laura Méndez",
            jobTitle: supplierID == nil ? "Supervisor de adquisiciones" : "Gerente de seminuevos",
            phone: "222 000 0000",
            email: supplierID == nil ? "adquisiciones.pue@dori.mx" : "byd.iztacalco@dori.mx",
            businessHours: "09:00 a 18:00",
            isPrimary: true
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
        #expect(model.membership?.role == .doriAdmin)
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

    @Test func keepsDashboardContentWhenInstitutionalContactsAreUnavailable() async {
        let request = AcquisitionRequest(
            id: UUID(),
            code: "ADQ-TEST-001",
            title: "15 autos requeridos",
            targetQuantity: 15,
            model: "Dolphin Mini",
            versions: ["Plus"],
            minimumYear: 2025,
            maximumYear: 2026,
            maximumMileage: 20_000,
            deliveryCity: "Puebla",
            deadlineAt: nil
        )
        let repository = Repository(
            requests: [request],
            contactFailure: TestFailure.unavailable
        )
        let model = AcquisitionViewModel(
            principal: Self.principal(role: .doriAdmin),
            repository: repository
        )

        await model.load()

        #expect(model.state == .content)
        #expect(model.activeRequest?.code == "ADQ-TEST-001")
        #expect(model.contacts.isEmpty)
        #expect(model.organizationName == "DORI Puebla")
    }

    @Test func providerBuildsDashboardAfterResolvingItsSupplierMembership() async {
        let supplierID = UUID()
        let request = AcquisitionRequest(
            id: UUID(), code: "ADQ-TEST-001", title: "15 autos requeridos",
            targetQuantity: 15, model: "Dolphin Mini", versions: ["Plus"],
            minimumYear: 2025, maximumYear: 2026, maximumMileage: 20_000,
            deliveryCity: "Puebla", deadlineAt: nil
        )
        let repository = Repository(
            requests: [request], membershipRole: .provider,
            supplierID: supplierID,
            suppliers: [AcquisitionSupplierSummary(id: supplierID, name: "BYD Iztacalco", city: "Puebla")]
        )
        let model = AcquisitionViewModel(
            principal: Self.principal(role: .provider), repository: repository
        )

        await model.load()

        #expect(model.state == .content)
        #expect(model.membership?.role == .provider)
        #expect(model.membership?.supplierID == supplierID)
        #expect(model.organizationName == "BYD Iztacalco")
        #expect(model.activeRequest?.code == "ADQ-TEST-001")
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
        let contactFailure: Error?
        let membershipRole: AcquisitionRole
        let supplierID: UUID?
        let suppliers: [AcquisitionSupplierSummary]

        init(
            requests: [AcquisitionRequest],
            failure: Error? = nil,
            contactFailure: Error? = nil,
            membershipRole: AcquisitionRole = .doriAdmin,
            supplierID: UUID? = nil,
            suppliers: [AcquisitionSupplierSummary] = []
        ) {
            self.requests = requests
            self.failure = failure
            self.contactFailure = contactFailure
            self.membershipRole = membershipRole
            self.supplierID = supplierID
            self.suppliers = suppliers
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
                supplierID: membershipRole == .provider ? supplierID ?? UUID() : nil,
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

        func loadSuppliers() async throws -> [AcquisitionSupplierSummary] {
            suppliers
        }

        func loadContacts() async throws -> [AcquisitionInstitutionalContact] {
            if let contactFailure { throw contactFailure }
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

@MainActor
struct AcquisitionTestResetTests {
    private let environmentID = UUID(uuidString: "AD510000-0000-4000-8000-000000000002")!

    @Test func acceptsOnlyAuthorizedBucketAndEnvironmentPrefix() throws {
        let object = SupabaseAcquisitionRepository.ResetStorageObject(
            bucket: "acquisition-evidence",
            path: "ad510000-0000-4000-8000-000000000002/supplier/offer/vin.jpg"
        )
        try SupabaseAcquisitionRepository.validateTestResetObject(
            object,
            environmentID: environmentID
        )
    }

    @Test func rejectsAnObjectOutsideTheCurrentEnvironment() {
        let object = SupabaseAcquisitionRepository.ResetStorageObject(
            bucket: "acquisition-chat-attachments",
            path: "00000000-0000-4000-8000-000000000000/supplier/thread/file.jpg"
        )
        #expect(throws: SupabaseAcquisitionRepository.RepositoryError.self) {
            try SupabaseAcquisitionRepository.validateTestResetObject(
                object,
                environmentID: environmentID
            )
        }
    }

    @Test func rejectsAnUnlistedBucket() {
        let object = SupabaseAcquisitionRepository.ResetStorageObject(
            bucket: "avatars",
            path: "ad510000-0000-4000-8000-000000000002/profile.jpg"
        )
        #expect(throws: SupabaseAcquisitionRepository.RepositoryError.self) {
            try SupabaseAcquisitionRepository.validateTestResetObject(
                object,
                environmentID: environmentID
            )
        }
    }
}
