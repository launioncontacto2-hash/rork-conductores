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
        let joined = normalizeSeparators(lines.joined(separator: " "))
        let product = DORITripOfferParser.normalizeProduct(joined)
        guard product != .unsupported else {
            return DORITripOffer(source: "vision", sourceOfferId: "ocr", product: product,
                                  offeredEarnings: nil, currency: "MXN", pickupDistanceKm: nil,
                                  pickupETAMinutes: nil, tripDistanceKm: nil, tripDurationMinutes: nil,
                                  riderRating: nil, confidence: ["product": 0.95], destinationText: nil)
        }
        let fare = firstNumber(matching: #"\$\s*([0-9]+(?:[.,][0-9]+)?)"#, in: joined)
        let pickupMinutes = firstNumber(matching: #"(?i)recogida\s*:\s*([0-9]+(?:[.,][0-9]+)?)\s*min"#, in: joined)
        let pickupKm = firstNumber(matching: #"(?i)recogida\s*:[^|\n]*?([0-9]+(?:[.,][0-9]+)?)\s*km"#, in: joined)
        let tripMinutes = firstNumber(matching: #"(?i)viaje\s*:\s*([0-9]+(?:[.,][0-9]+)?)\s*min"#, in: joined)
        let tripKm = firstNumber(matching: #"(?i)viaje\s*:[^|\n]*?([0-9]+(?:[.,][0-9]+)?)\s*km"#, in: joined)
        let rating = firstNumber(matching: #"(?i)rating\s*:\s*([0-9]+(?:[.,][0-9]+)?)"#, in: joined)
        let confidence: [String: Double] = [
            "product": product == .unsupported ? 0.95 : 0.9,
            "fare": fare == nil ? 0.0 : 0.9,
            "pickup": pickupMinutes != nil && pickupKm != nil ? 0.9 : 0.0,
            "trip": tripMinutes != nil && tripKm != nil ? 0.9 : 0.0,
            "rating": rating == nil ? 0.0 : 0.9
        ]
        return DORITripOffer(source: "vision", sourceOfferId: "ocr", product: product,
                             offeredEarnings: fare, currency: "MXN",
                             pickupDistanceKm: pickupKm,
                             pickupETAMinutes: pickupMinutes,
                             tripDistanceKm: tripKm,
                             tripDurationMinutes: tripMinutes,
                             riderRating: rating,
                             confidence: confidence, destinationText: nil)
    }

    private static func value(after marker: String, in text: String) -> Double? {
        guard let range = text.range(of: marker, options: .caseInsensitive) else { return nil }
        return DORITripOfferParser.parseNumber(String(text[range.upperBound...]))
    }

    private static func firstNumber(matching pattern: String, in text: String) -> Double? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return DORITripOfferParser.parseNumber(String(text[range]))
    }

    private static func normalizeSeparators(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "•", with: "·")
            .replacingOccurrences(of: "|", with: "·")
            .replacingOccurrences(of: "—", with: "·")
            .replacingOccurrences(of: "-", with: "·")
        normalized = normalized.replacingOccurrences(
            of: #"(?i)(min|km)\s+(?=\d)"#, with: "$1 · ", options: .regularExpression)
        while normalized.contains("  ") {
            normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        }
        normalized = normalized.replacingOccurrences(of: #"(?i)(recogida|viaje|rating)\s*:\s*"#, with: "$1: ", options: .regularExpression)
        return normalized
    }

    private static func segment(after marker: String, before next: String, in text: String) -> String? {
        guard let start = text.range(of: marker, options: .caseInsensitive) else { return nil }
        let tail = text[start.upperBound...]
        if let endRange = tail.range(of: next, options: .caseInsensitive) {
            return String(tail[..<endRange.lowerBound])
        }
        return String(tail)
    }
}
