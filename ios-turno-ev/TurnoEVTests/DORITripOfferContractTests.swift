import Testing
import UIKit
@testable import TurnoEV

struct DORITripOfferContractTests {
    @Test func normalizesSupportedAndUnsupportedProducts() {
        #expect(DORITripOfferParser.normalizeProduct("UberX") == .uberX)
        #expect(DORITripOfferParser.normalizeProduct("Uber Comfort") == .uberComfort)
        #expect(DORITripOfferParser.normalizeProduct("Uber Priority") == .unsupported)
    }

    @Test func commaAndPointDecimalsAreAccepted() {
        #expect(DORITripOfferParser.parseNumber("97,04 MXN") == 97.04)
        #expect(DORITripOfferParser.parseNumber("6.85/km") == 6.85)
    }

    @Test func incompleteOfferDoesNotBecomeRecommendation() {
        let offer = DORITripOffer(source: "test", sourceOfferId: "incomplete", product: .uberX,
                                  offeredEarnings: 206.21, currency: "MXN", pickupDistanceKm: nil,
                                  pickupETAMinutes: 4, tripDistanceKm: 18, tripDurationMinutes: 35,
                                  riderRating: 4.96, confidence: ["fare": 0.99], destinationText: nil)
        #expect(offer.readiness == "DATOS INSUFICIENTES")
    }

    @Test func rendererProducesStablePixelsForSameOffer() {
        let offer = DORITripOffer(source: "test", sourceOfferId: "stable", product: .uberX,
                                  offeredEarnings: 206.21, currency: "MXN", pickupDistanceKm: 1.2,
                                  pickupETAMinutes: 4, tripDistanceKm: 18, tripDurationMinutes: 35,
                                  riderRating: 4.96, confidence: ["fare": 0.99, "pickup": 0.99, "trip": 0.99, "rating": 0.99], destinationText: "Centro")
        let first = DORITripOfferRenderer.render(offer).pngData()
        let second = DORITripOfferRenderer.render(offer).pngData()
        #expect(first != nil)
        #expect(first == second)
    }
}
