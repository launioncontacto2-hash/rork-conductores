import Foundation
import Supabase
import Testing
import UIKit
@testable import TurnoEV

/// The unsigned simulator test runner cannot write the SDK session to Keychain.
/// Keep the real Auth session in process so PostgREST and Storage receive the same
/// JWT that the signed app would persist in Keychain on an iPhone.
private final class AcquisitionTestLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = nil
    }
}

/// Opt-in integration proof for the exact Supabase Swift route used by iPhone.
/// CI injects its values into the simulator process only for an authorized TEST run.
@MainActor
struct AcquisitionLiveTestTests {
    @Test func requestOfferNegotiationPurchaseAndChatUseTheRealSwiftClientAgainstTest() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DORI_RUN_ACQUISITION_LIVE_TEST"] == "1" else { return }

        let urlString = try #require(environment["DORI_TEST_SUPABASE_URL"])
        let url = try #require(URL(string: urlString))
        let key = try #require(environment["DORI_TEST_SUPABASE_PUBLISHABLE_KEY"])
        let password = try #require(environment["DORI_TEST_ACQUISITION_PASSWORD"])
        #expect(url.host == "yyxzuiantrmoyozetswv.supabase.co")
        #expect(key.hasPrefix("sb_publishable_"))

        let client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(storage: AcquisitionTestLocalStorage())
            )
        )
        SupabaseBridge.useIntegrationTestClient(client)
        defer { SupabaseBridge.useIntegrationTestClient(nil) }

        let repository = SupabaseAcquisitionRepository()
        let adminSession = try await measured("login.admin.auth") {
            try await client.auth.signIn(
                email: "adquisiciones.pue@dori.mx",
                password: password
            )
        }
        #expect((try await client.auth.session).user.id == adminSession.user.id)
        let adminProfile = try await measured("login.admin.profile") {
            try await SupabaseAuthProbe.loadProfile(authUserId: adminSession.user.id)
        }
        let adminMembership = try await measured("login.admin.membership") {
            try await repository.loadMembership(
                profileID: adminProfile.id,
                environmentID: adminProfile.environment_id
            )
        }
        #expect(adminMembership.role == .doriAdmin)
        #expect(adminMembership.environmentID.uuidString.lowercased()
            == "9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10")

        let offerID = UUID()
        let suffix = offerID.uuidString.replacingOccurrences(of: "-", with: "").prefix(5).uppercased()
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var requestDraft = AcquisitionRequestDraft()
        requestDraft.model = "Prueba publicación Swift \(suffix)"
        requestDraft.versions = "TEST"
        requestDraft.targetQuantity = "2"
        requestDraft.minimumYear = "2025"
        requestDraft.maximumYear = "2026"
        requestDraft.maximumMileage = "20000"
        requestDraft.maximumUnitPrice = "500000"
        requestDraft.deliveryCity = "Puebla"
        requestDraft.destinationStationName = "DORI Puebla"
        requestDraft.fiscalPeriod = try #require(
            utcCalendar.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )
        requestDraft.deliveryTermsDocument = Data("%PDF-1.4\nCondiciones TEST\n%%EOF".utf8)
        requestDraft.deliveryTermsFilename = "condiciones-test.pdf"
        requestDraft.deliveryTermsMimeType = "application/pdf"
        requestDraft.deadlineAt = AcquisitionRequestDraft.defaultDate(daysFromNow: 14)
        requestDraft.targetDeliveryDate = AcquisitionRequestDraft.defaultDate(daysFromNow: 30)
        let publishedRequest = try await measured("requests.admin.publish") {
            try await repository.publishRequest(requestDraft)
        }
        #expect(publishedRequest.model == requestDraft.model)
        #expect(publishedRequest.fiscalPeriodText == "Septiembre 2026")
        #expect(publishedRequest.targetDeliveryDate != nil)
        let requestDocumentURL = try await measured("requests.admin.document_url") {
            try await repository.requestDocumentURL(for: publishedRequest)
        }
        #expect(requestDocumentURL != nil)
        let adminRequests = try await measured("requests.admin.list") {
            try await repository.loadRequests()
        }
        #expect(adminRequests.contains(where: { $0.id == publishedRequest.id }))

        try await client.auth.signOut()
        let providerSession = try await measured("login.provider.auth") {
            try await client.auth.signIn(
                email: "byd.iztacalco@dori.mx",
                password: password
            )
        }
        #expect((try await client.auth.session).user.id == providerSession.user.id)
        let providerProfile = try await measured("login.provider.profile") {
            try await SupabaseAuthProbe.loadProfile(authUserId: providerSession.user.id)
        }
        let providerMembership = try await measured("login.provider.membership") {
            try await repository.loadMembership(
                profileID: providerProfile.id,
                environmentID: providerProfile.environment_id
            )
        }
        #expect(providerMembership.role == .provider)
        let providerRequests = try await measured("requests.provider.list") {
            try await repository.loadRequests()
        }
        let request = try #require(providerRequests.first(where: { $0.id == publishedRequest.id }))
        #expect(request.fiscalPeriodText == "Septiembre 2026")
        #expect(request.detailedRequirements.count == requestDraft.requirements.count)
        let providerDashboard = AcquisitionViewModel(
            principal: principal(
                session: providerSession,
                profile: providerProfile,
                role: .provider,
                email: "byd.iztacalco@dori.mx"
            ),
            repository: repository
        )
        await measured("dashboard.provider.full") {
            await providerDashboard.load()
        }
        #expect(providerDashboard.state == .content)
        providerDashboard.stopObserving()

        let cameraJPEG = try #require(makeJPEG(size: CGSize(width: 2_048, height: 1_536)))
        let jpeg = try measuredSync("offer.image.normalize") {
            try #require(AcquisitionEvidenceValidator.normalizedJPEG(cameraJPEG))
        }
        print("DORI_PERF name=offer.image.bytes input=\(cameraJPEG.count) output=\(jpeg.count)")
        _ = await measured("offer.ocr.vin") {
            await AcquisitionEvidenceValidator.validateVIN(in: jpeg, expectedVIN: "TESTSDK25PUE\(suffix)")
        }
        _ = await measured("offer.ocr.odometer") {
            await AcquisitionEvidenceValidator.validateOdometer(in: jpeg, expectedMileage: 8_400)
        }
        var form = AcquisitionOfferFormData()
        form.vin = "TESTSDK25PUE\(suffix)"
        form.year = "2025"
        form.mileage = "8400"
        form.price = "274000"
        form.color = "Blanco"
        form.transferIncluded = true
        form.batteryKnowledge = .diagnosed
        form.soh = "95"
        form.deliveryTermsAccepted = true
        // This contract test starts after the device-side Vision validation.
        form.validationResults = .init(odometer: .match, vin: .match)
        form.confirmedRequirements = Set(AcquisitionOfferRequirement.allCases)
        form.evidence = Dictionary(
            uniqueKeysWithValues: request.requiredEvidenceKinds.map { ($0, jpeg) }
        )
        let submission = try form.makeSubmission(
            request: request,
            offerID: offerID,
            idempotencyKey: "swift-live-offer-\(offerID.uuidString.lowercased())"
        )

        let offer = try await measured("offer.provider.submit") {
            try await repository.submitOffer(submission, membership: providerMembership)
        }
        #expect(offer.id == offerID)
        #expect(offer.status == "submitted")
        #expect(AcquisitionCommercialLane.resolve(status: offer.status) == .proposal)

        let general = try await repository.ensureChatThread(
            supplierID: providerMembership.supplierID,
            offerID: nil
        )
        let providerGeneralBody = "Prueba proveedor \(suffix)"
        _ = try await repository.sendChatMessage(
            thread: general,
            body: providerGeneralBody,
            attachment: nil
        )
        let unit = try await repository.ensureChatThread(
            supplierID: providerMembership.supplierID,
            offerID: offerID
        )
        let providerUnitBody = "Prueba unidad \(suffix)"
        _ = try await repository.sendChatMessage(
            thread: unit,
            body: providerUnitBody,
            attachment: nil
        )

        try await client.auth.signOut()
        _ = try await client.auth.signIn(
            email: "adquisiciones.pue@dori.mx",
            password: password
        )
        let adminOffers = try await measured("offers.admin.list") {
            try await repository.loadOffers()
        }
        let submitted = try #require(adminOffers.first(where: { $0.id == offerID }))
        #expect(AcquisitionCommercialLane.resolve(status: submitted.status) == .proposal)
        let adminDashboard = AcquisitionViewModel(
            principal: principal(
                session: adminSession,
                profile: adminProfile,
                role: .doriAdmin,
                email: "adquisiciones.pue@dori.mx"
            ),
            repository: repository
        )
        await measured("dashboard.admin.full") {
            await adminDashboard.load()
        }
        #expect(adminDashboard.state == .content)
        adminDashboard.stopObserving()

        let adminDetail = try await measured("detail.admin.first_content") {
            try await repository.loadOfferDetail(offerID: offerID, membership: adminMembership)
        }
        let loadedEvidence = await measured("detail.admin.gallery") {
            await repository.loadOfferEvidenceData(adminDetail.evidence)
        }
        print(
            "DORI_PERF name=detail.admin.gallery_bytes count=\(loadedEvidence.count) "
                + "bytes=\(loadedEvidence.compactMap(\.imageData).reduce(0) { $0 + $1.count })"
        )

        let adminGeneral = try await repository.ensureChatThread(
            supplierID: providerMembership.supplierID,
            offerID: nil
        )
        let generalMessages = try await repository.loadChatMessages(threadID: adminGeneral.id)
        #expect(generalMessages.contains(where: { $0.body == providerGeneralBody }))
        let adminUnit = try await repository.ensureChatThread(supplierID: nil, offerID: offerID)
        let providerUnitMessages = try await repository.loadChatMessages(threadID: adminUnit.id)
        #expect(providerUnitMessages.contains(where: { $0.body == providerUnitBody }))

        let adminBody = "Respuesta DORI \(suffix)"
        _ = try await repository.sendChatMessage(
            thread: adminUnit,
            body: adminBody,
            attachment: nil
        )
        let adminUnitMessages = try await repository.loadChatMessages(threadID: adminUnit.id)
        #expect(adminUnitMessages.contains(where: { $0.body == adminBody }))

        let doriCounter = try await measured("negotiation.admin.counteroffer") {
            try await repository.respondToOffer(
                AcquisitionOfferCommand(
                    offerID: offerID, action: .counteroffer, amountMxn: 490_000,
                    idempotencyKey: "swift-live-dori-counter-\(offerID.uuidString.lowercased())"
                )
            )
        }
        #expect(doriCounter.status == "negotiating")
        #expect(AcquisitionCommercialLane.resolve(status: doriCounter.status) == .negotiation)

        try await client.auth.signOut()
        _ = try await client.auth.signIn(
            email: "byd.iztacalco@dori.mx",
            password: password
        )
        let providerCounter = try await measured("negotiation.provider.counteroffer") {
            try await repository.respondToOffer(
                AcquisitionOfferCommand(
                    offerID: offerID, action: .counteroffer, amountMxn: 495_000,
                    idempotencyKey: "swift-live-provider-counter-\(offerID.uuidString.lowercased())"
                )
            )
        }
        #expect(providerCounter.status == "negotiating")
        #expect(AcquisitionCommercialLane.resolve(status: providerCounter.status) == .negotiation)

        try await client.auth.signOut()
        _ = try await client.auth.signIn(email: "adquisiciones.pue@dori.mx", password: password)
        let purchase = try await measured("purchase.admin.award") {
            try await repository.respondToOffer(
                AcquisitionOfferCommand(
                    offerID: offerID, action: .award, amountMxn: 495_000,
                    idempotencyKey: "swift-live-award-\(offerID.uuidString.lowercased())"
                )
            )
        }
        #expect(purchase.status == "awarded")
        #expect(purchase.orderID != nil)
        #expect(AcquisitionCommercialLane.resolve(status: purchase.status) == .purchase)

        try await client.auth.signOut()
        _ = try await client.auth.signIn(email: "byd.iztacalco@dori.mx", password: password)
        let purchasedOffers = try await measured("purchases.provider.list") {
            try await repository.loadOffers()
        }
        let providerPurchasedOffer = try #require(purchasedOffers.first(where: { $0.id == offerID }))
        #expect(providerPurchasedOffer.status == "awarded")
        #expect(AcquisitionCommercialLane.resolve(status: providerPurchasedOffer.status) == .purchase)
    }

    private func measured<T>(
        _ name: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        let startedAt = ContinuousClock.now
        let value = try await operation()
        let elapsed = startedAt.duration(to: ContinuousClock.now)
        print("DORI_PERF name=\(name) ms=\(milliseconds(elapsed))")
        return value
    }

    private func measuredSync<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        let startedAt = ContinuousClock.now
        let value = try operation()
        let elapsed = startedAt.duration(to: ContinuousClock.now)
        print("DORI_PERF name=\(name) ms=\(milliseconds(elapsed))")
        return value
    }

    private func milliseconds(_ duration: Duration) -> String {
        let components = duration.components
        let value = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.2f", value)
    }

    private func principal(
        session: Session,
        profile: SupabaseAuthProbe.ProfileRow,
        role: StaffRole,
        email: String
    ) -> SessionPrincipal {
        SessionPrincipal(
            authUserId: session.user.id.uuidString,
            profileId: profile.id.uuidString,
            name: profile.display_name,
            employeeNumber: profile.employee_number,
            email: email,
            role: role,
            environmentId: profile.environment_id.uuidString,
            stationId: nil,
            stationCode: nil,
            stationName: role == .doriAdmin ? "DORI Puebla" : nil,
            shiftGroup: nil,
            shiftSlot: nil
        )
    }

    private func makeJPEG(size: CGSize = CGSize(width: 12, height: 12)) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let tile: CGFloat = max(12, min(size.width, size.height) / 32)
            for y in stride(from: CGFloat.zero, to: size.height, by: tile) {
                for x in stride(from: CGFloat.zero, to: size.width, by: tile) {
                    let seed = Int(x / tile) &* 31 &+ Int(y / tile) &* 17
                    UIColor(
                        hue: CGFloat(seed % 255) / 255,
                        saturation: 0.55,
                        brightness: 0.82,
                        alpha: 1
                    ).setFill()
                    context.fill(CGRect(x: x, y: y, width: tile, height: tile))
                }
            }
        }
        return image.jpegData(compressionQuality: 0.88)
    }
}
