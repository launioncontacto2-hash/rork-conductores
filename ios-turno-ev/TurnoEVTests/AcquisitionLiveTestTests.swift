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
        let adminSession = try await client.auth.signIn(
            email: "adquisiciones.pue@dori.mx",
            password: password
        )
        #expect((try await client.auth.session).user.id == adminSession.user.id)
        let adminProfile = try await SupabaseAuthProbe.loadProfile(authUserId: adminSession.user.id)
        let adminMembership = try await repository.loadMembership(
            profileID: adminProfile.id,
            environmentID: adminProfile.environment_id
        )
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
        let publishedRequest = try await repository.publishRequest(requestDraft)
        #expect(publishedRequest.model == requestDraft.model)
        #expect(publishedRequest.fiscalPeriodText == "Septiembre 2026")
        #expect(publishedRequest.targetDeliveryDate != nil)
        #expect(try await repository.requestDocumentURL(for: publishedRequest) != nil)
        let adminRequests = try await repository.loadRequests()
        #expect(adminRequests.contains(where: { $0.id == publishedRequest.id }))

        try await client.auth.signOut()
        let providerSession = try await client.auth.signIn(
            email: "byd.iztacalco@dori.mx",
            password: password
        )
        #expect((try await client.auth.session).user.id == providerSession.user.id)
        let providerProfile = try await SupabaseAuthProbe.loadProfile(authUserId: providerSession.user.id)
        let providerMembership = try await repository.loadMembership(
            profileID: providerProfile.id,
            environmentID: providerProfile.environment_id
        )
        #expect(providerMembership.role == .provider)
        let providerRequests = try await repository.loadRequests()
        let request = try #require(providerRequests.first(where: { $0.id == publishedRequest.id }))
        #expect(request.fiscalPeriodText == "Septiembre 2026")
        #expect(request.detailedRequirements.count == requestDraft.requirements.count)

        let jpeg = try #require(makeJPEG())
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

        let offer = try await repository.submitOffer(submission, membership: providerMembership)
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
        let adminOffers = try await repository.loadOffers()
        let submitted = try #require(adminOffers.first(where: { $0.id == offerID }))
        #expect(AcquisitionCommercialLane.resolve(status: submitted.status) == .proposal)

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

        let doriCounter = try await repository.respondToOffer(
            AcquisitionOfferCommand(
                offerID: offerID, action: .counteroffer, amountMxn: 490_000,
                idempotencyKey: "swift-live-dori-counter-\(offerID.uuidString.lowercased())"
            )
        )
        #expect(doriCounter.status == "negotiating")
        #expect(AcquisitionCommercialLane.resolve(status: doriCounter.status) == .negotiation)

        try await client.auth.signOut()
        _ = try await client.auth.signIn(
            email: "byd.iztacalco@dori.mx",
            password: password
        )
        let providerCounter = try await repository.respondToOffer(
            AcquisitionOfferCommand(
                offerID: offerID, action: .counteroffer, amountMxn: 495_000,
                idempotencyKey: "swift-live-provider-counter-\(offerID.uuidString.lowercased())"
            )
        )
        #expect(providerCounter.status == "negotiating")
        #expect(AcquisitionCommercialLane.resolve(status: providerCounter.status) == .negotiation)

        try await client.auth.signOut()
        _ = try await client.auth.signIn(email: "adquisiciones.pue@dori.mx", password: password)
        let purchase = try await repository.respondToOffer(
            AcquisitionOfferCommand(
                offerID: offerID, action: .award, amountMxn: 495_000,
                idempotencyKey: "swift-live-award-\(offerID.uuidString.lowercased())"
            )
        )
        #expect(purchase.status == "awarded")
        #expect(purchase.orderID != nil)
        #expect(AcquisitionCommercialLane.resolve(status: purchase.status) == .purchase)

        try await client.auth.signOut()
        _ = try await client.auth.signIn(email: "byd.iztacalco@dori.mx", password: password)
        let purchasedOffers = try await repository.loadOffers()
        let providerPurchasedOffer = try #require(purchasedOffers.first(where: { $0.id == offerID }))
        #expect(providerPurchasedOffer.status == "awarded")
        #expect(AcquisitionCommercialLane.resolve(status: providerPurchasedOffer.status) == .purchase)
    }

    private func makeJPEG() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
        let image = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        return image.jpegData(compressionQuality: 0.7)
    }
}
