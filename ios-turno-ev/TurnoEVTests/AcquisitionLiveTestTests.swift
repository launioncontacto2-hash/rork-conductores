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
    @Test func providerUploadsThreeRealJpegsAndBothRolesPersistChat() async throws {
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

        let providerSession = try await client.auth.signIn(
            email: "byd.iztacalco@dori.mx",
            password: password
        )
        let activeProviderSession = try await client.auth.session
        #expect(activeProviderSession.user.id == providerSession.user.id)
        let providerProfile = try await SupabaseAuthProbe.loadProfile(
            authUserId: providerSession.user.id
        )
        let repository = SupabaseAcquisitionRepository()
        let providerMembership = try await repository.loadMembership(
            profileID: providerProfile.id,
            environmentID: providerProfile.environment_id
        )
        #expect(providerMembership.role == .provider)
        #expect(providerMembership.environmentID.uuidString.lowercased()
            == "9f8d4a52-0f0e-4a3f-9a1e-2c6f5b8d7e10")

        let requests = try await repository.loadRequests()
        let request = try #require(requests.first(where: { $0.code == "ADQ-TEST-001" }))
        let offerID = UUID()
        let suffix = offerID.uuidString.replacingOccurrences(of: "-", with: "").prefix(5).uppercased()
        let jpeg = try #require(makeJPEG())
        var form = AcquisitionOfferFormData()
        form.vin = "TESTSDK25PUE\(suffix)"
        form.year = "2025"
        form.mileage = "8400"
        form.price = "274000"
        form.color = "Blanco"
        form.transferIncluded = true
        form.confirmedRequirements = Set(AcquisitionOfferRequirement.allCases)
        form.evidence = [.vin: jpeg, .dashboard: jpeg, .front: jpeg]
        let submission = try form.makeSubmission(
            request: request,
            offerID: offerID,
            idempotencyKey: "swift-live-offer-\(offerID.uuidString.lowercased())"
        )

        let offer = try await repository.submitOffer(submission, membership: providerMembership)
        #expect(offer.id == offerID)

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
        let adminSession = try await client.auth.signIn(
            email: "adquisiciones.pue@dori.mx",
            password: password
        )
        let activeAdminSession = try await client.auth.session
        #expect(activeAdminSession.user.id == adminSession.user.id)
        let adminProfile = try await SupabaseAuthProbe.loadProfile(authUserId: adminSession.user.id)
        let adminMembership = try await repository.loadMembership(
            profileID: adminProfile.id,
            environmentID: adminProfile.environment_id
        )
        #expect(adminMembership.role == .doriAdmin)
        let adminOffers = try await repository.loadOffers()
        #expect(adminOffers.contains(where: { $0.id == offerID }))

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
