import Foundation
import UberTestCore

extension UberTestStore {
    static func previewStore() -> UberTestStore {
        let store = UberTestStore()
        let offers = [UberTestOffer(id: "preview-1", service: "UberX", fare: 185, pickup: "Av. Reforma 120", pickupDistanceKm: 1.4, tripDurationMinutes: 28, tripDistanceKm: 11.2, riderRating: 4.96)]
        if let batch = try? UberTestOfferBatch(id: "preview-batch", offers: offers) { store.receive(batch) }
        return store
    }
}
