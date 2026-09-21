import Foundation

/// Canonical offer contract used by the TEST reader and the Copilot decision input.
/// Values are intentionally optional until the visual reader has enough evidence.
nonisolated struct DORITripOffer: Codable, Equatable, Sendable {
    enum Product: String, Codable, Sendable {
        case uberX = "uber_x"
        case uberComfort = "uber_comfort"
        case unsupported
    }

    let source: String
    let sourceOfferId: String
    let product: Product
    let offeredEarnings: Double?
    let currency: String
    let pickupDistanceKm: Double?
    let pickupETAMinutes: Double?
    let tripDistanceKm: Double?
    let tripDurationMinutes: Double?
    let riderRating: Double?
    let confidence: [String: Double]
    let destinationText: String?

    var hasCriticalData: Bool {
        offeredEarnings != nil && pickupDistanceKm != nil && pickupETAMinutes != nil &&
            tripDistanceKm != nil && tripDurationMinutes != nil && riderRating != nil &&
            confidence.values.allSatisfy { $0 >= 0.8 }
    }

    var readiness: String {
        if product == .unsupported { return "SERVICIO NO SOPORTADO" }
        return hasCriticalData ? "LISTO" : "DATOS INSUFICIENTES"
    }
}

enum DORITripOfferParser {
    static func normalizeProduct(_ text: String) -> DORITripOffer.Product {
        let value = text.lowercased()
        if value.contains("comfort") { return .uberComfort }
        if value.contains("uberx") || value.contains("uber x") { return .uberX }
        return .unsupported
    }

    static func parseNumber(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        return Double(normalized)
    }
}
