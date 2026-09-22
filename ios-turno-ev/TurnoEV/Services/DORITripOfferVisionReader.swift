import Foundation
import UIKit
import Vision

/// TEST-only bridge from rendered offer pixels to the canonical TripOffer contract.
/// The reader never receives the source JSON; it consumes OCR observations from the bitmap.
enum DORITripOfferVisionReader {
    static func read(_ image: UIImage, completion: @escaping (DORITripOffer?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        let observations: [VNRecognizedTextObservation] = request.results ?? []
        let lines: [String] = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        completion(parse(lines))
    }

    static func parse(_ lines: [String]) -> DORITripOffer? {
        let joined = lines.joined(separator: " ")
        let product = DORITripOfferParser.normalizeProduct(joined)
        guard product != .unsupported else {
            return DORITripOffer(source: "vision", sourceOfferId: "ocr", product: product,
                                  offeredEarnings: nil, currency: "MXN", pickupDistanceKm: nil,
                                  pickupETAMinutes: nil, tripDistanceKm: nil, tripDurationMinutes: nil,
                                  riderRating: nil, confidence: ["product": 0.95], destinationText: nil)
        }
        let fare = value(after: "$", in: joined)
        let pickup = segment(after: "recogida:", before: "viaje:", in: joined)
        let trip = segment(after: "viaje:", before: "rating:", in: joined)
        let rating = value(after: "rating:", in: joined)
        let pickupParts = pickup?.split(separator: "·").map(String.init) ?? []
        let tripParts = trip?.split(separator: "·").map(String.init) ?? []
        let confidence: [String: Double] = [
            "product": product == .unsupported ? 0.95 : 0.9,
            "fare": fare == nil ? 0.0 : 0.9,
            "pickup": pickupParts.count == 2 ? 0.9 : 0.0,
            "trip": tripParts.count == 2 ? 0.9 : 0.0,
            "rating": rating == nil ? 0.0 : 0.9
        ]
        return DORITripOffer(source: "vision", sourceOfferId: "ocr", product: product,
                             offeredEarnings: fare, currency: "MXN",
                             pickupDistanceKm: pickupParts.dropFirst().first.flatMap(DORITripOfferParser.parseNumber),
                             pickupETAMinutes: pickupParts.first.flatMap(DORITripOfferParser.parseNumber),
                             tripDistanceKm: tripParts.dropFirst().first.flatMap(DORITripOfferParser.parseNumber),
                             tripDurationMinutes: tripParts.first.flatMap(DORITripOfferParser.parseNumber),
                             riderRating: rating,
                             confidence: confidence, destinationText: nil)
    }

    private static func value(after marker: String, in text: String) -> Double? {
        let normalized = text.lowercased()
        guard let range = normalized.range(of: marker) else { return nil }
        return DORITripOfferParser.parseNumber(String(normalized[range.upperBound...]))
    }

    private static func segment(after marker: String, before next: String, in text: String) -> String? {
        let normalized = text.lowercased()
        guard let start = normalized.range(of: marker) else { return nil }
        let tail = normalized[start.upperBound...]
        if let endRange = tail.range(of: next) {
            return String(tail[..<endRange.lowerBound])
        }
        return String(tail)
    }
}
