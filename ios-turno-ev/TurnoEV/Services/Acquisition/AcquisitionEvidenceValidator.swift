import Foundation
import UIKit
import Vision

nonisolated enum AcquisitionEvidenceValidator {
    private struct Reading: Sendable {
        let text: String
        let confidence: Float
    }

    static func normalizedJPEG(_ data: Data, maximumDimension: CGFloat = 2_048) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let size = image.size
        let scale = min(1, maximumDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.78) ?? data
    }

    static func validateOdometer(_ data: Data, expectedMileage: Int?) async -> AcquisitionEvidenceValidationStatus {
        guard let expectedMileage else { return .pending }
        let readings = (try? await recognize(data)) ?? []
        let values = readings.flatMap { reading -> [(Int, Float)] in
            let normalized = reading.text.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            guard let value = Int(normalized), value <= 2_000_000 else { return [] }
            return [(value, reading.confidence)]
        }
        if values.contains(where: { $0.0 == expectedMileage && $0.1 >= 0.55 }) { return .match }
        if values.contains(where: { abs($0.0 - expectedMileage) > 10 && $0.1 >= 0.85 }) { return .mismatch }
        return .manualReview
    }

    static func validateVIN(_ data: Data, expectedVIN: String) async -> AcquisitionEvidenceValidationStatus {
        guard expectedVIN.count == 17 else { return .pending }
        let readings = (try? await recognize(data)) ?? []
        let candidates = readings.compactMap { reading -> (String, Float)? in
            let normalized = reading.text.uppercased()
                .replacingOccurrences(of: "[^A-HJ-NPR-Z0-9]", with: "", options: .regularExpression)
            guard normalized.count == 17 else { return nil }
            return (normalized, reading.confidence)
        }
        if candidates.contains(where: { $0.0 == expectedVIN && $0.1 >= 0.55 }) { return .match }
        if candidates.contains(where: { $0.0 != expectedVIN && $0.1 >= 0.85 }) { return .mismatch }
        return .manualReview
    }

    private static func recognize(_ data: Data) async throws -> [Reading] {
        guard let image = UIImage(data: data)?.cgImage else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let readings = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { observation in
                    observation.topCandidates(1).first.map { Reading(text: $0.string, confidence: $0.confidence) }
                }
                continuation.resume(returning: readings)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es-MX", "en-US"]
            request.usesLanguageCorrection = false
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
