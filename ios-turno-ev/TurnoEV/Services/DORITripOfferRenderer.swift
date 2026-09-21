import UIKit

/// TEST renderer: the visual reader receives this bitmap, never the source JSON.
enum DORITripOfferRenderer {
    static let canvas = CGSize(width: 390, height: 520)

    static func render(_ offer: DORITripOffer) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            let title = offer.product == .uberX ? "UberX" : offer.product == .uberComfort ? "Uber Comfort" : "Uber Priority"
            draw(title, at: CGPoint(x: 24, y: 28), font: .boldSystemFont(ofSize: 28), color: .label)
            draw(offer.offeredEarnings.map { String(format: "$%.2f MXN", $0) } ?? "DATOS INSUFICIENTES", at: CGPoint(x: 24, y: 82), font: .boldSystemFont(ofSize: 24), color: .systemGreen)
            draw("Recogida: (offer.pickupETAMinutes.map { String(format: "%.0f min", $0) } ?? "—") · (offer.pickupDistanceKm.map { String(format: "%.2f km", $0) } ?? "—")", at: CGPoint(x: 24, y: 140), font: .systemFont(ofSize: 18), color: .label)
            draw("Viaje: (offer.tripDurationMinutes.map { String(format: "%.0f min", $0) } ?? "—") · (offer.tripDistanceKm.map { String(format: "%.2f km", $0) } ?? "—")", at: CGPoint(x: 24, y: 180), font: .systemFont(ofSize: 18), color: .label)
            draw("Rating: (offer.riderRating.map { String(format: "%.2f", $0) } ?? "—")", at: CGPoint(x: 24, y: 220), font: .systemFont(ofSize: 18), color: .label)
            draw(offer.readiness, at: CGPoint(x: 24, y: 290), font: .boldSystemFont(ofSize: 22), color: offer.readiness == "LISTO" ? .systemBlue : .systemOrange)
        }
    }

    private static func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
}
