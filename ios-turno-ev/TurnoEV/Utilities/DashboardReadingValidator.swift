import Foundation
import UIKit
import Vision

/// The only states a dashboard reading may have. An unreadable image is never
/// downgraded to a mismatch because that would falsely attribute a camera problem
/// to the driver's typed value.
nonisolated enum DashboardReadingStatus: Equatable, Sendable {
    case pending
    case matched(Int)
    case mismatch(manual: Int, detected: Int)
    case unreadable

    func isMatched(manual: String) -> Bool {
        guard case .matched(let detected) = self,
              let value = Int(manual.trimmingCharacters(in: .whitespaces)), value > 0 else { return false }
        return value == detected
    }
}

nonisolated struct DashboardTextLine: Sendable, Equatable {
    let text: String
    let boundingBox: CGRect

    init(text: String, boundingBox: CGRect = .zero) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// On-device OCR contract for the two start-of-shift dashboard readings.
/// No remote service or generative model is involved.
nonisolated enum DashboardReadingValidator {
    private static let batteryRegion = CGRect(x: 0.35, y: 0.18, width: 0.65, height: 0.72)

    static func readOdometer(from data: Data) async -> Int? {
        let lines = await recognizeLines(from: data)
        return extractODO(from: lines.map(\.text))
    }

    static func readBattery(from data: Data) async -> Int? {
        let lines = await recognizeLines(from: data)
        return extractBattery(from: lines)
    }

    /// ODO is mandatory context. TRIP and bare numbers are intentionally rejected.
    static func extractODO(from lines: [String]) -> Int? {
        let pattern = #"(?i)\bODO\s*([0-9][0-9,\.\s]{2,})\s*KM\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let digitsRange = Range(match.range(at: 1), in: line) else { continue }
            let digits = line[digitsRange].filter(\.isNumber)
            guard let value = Int(digits), value > 0 else { continue }
            return value
        }
        return nil
    }

    /// Battery percentage is accepted only from the expected dashboard region.
    /// The segmented bar is intentionally not parsed as a numeric source.
    static func extractBattery(from lines: [DashboardTextLine]) -> Int? {
        let pattern = #"(?<![0-9])(100|[0-9]{1,2})\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        for line in lines where batteryRegion.intersects(line.boundingBox) {
            let range = NSRange(line.text.startIndex..., in: line.text)
            guard let match = regex.firstMatch(in: line.text, range: range),
                  let valueRange = Range(match.range(at: 1), in: line.text),
                  let value = Int(line.text[valueRange]), (0...100).contains(value) else { continue }
            return value
        }
        return nil
    }

    private static func recognizeLines(from data: Data) async -> [DashboardTextLine] {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data), let cgImage = image.cgImage else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["es-MX", "es", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return []
            }

            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return DashboardTextLine(text: candidate.string, boundingBox: observation.boundingBox)
            }
        }.value
    }
}
