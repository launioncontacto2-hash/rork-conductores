import Foundation
import UIKit
import Vision

/// Reads the amount printed on a deposit slip. The station cannot take the driver's word
/// for the figure: the photo has to say the same number he typed, and this is what
/// compares them before the manager is notified.
nonisolated enum DepositSlipReader {
    struct Reading: Sendable {
        let detectedMxn: Int?
        /// Day printed on the slip. The station compares it against the day the cash
        /// was collected: a slip from yesterday does not settle today's money.
        let detectedDate: Date?
        /// Long digit runs printed on the slip: CLABE, account, card. The destination
        /// has to be the account of the network, not any account the driver chose.
        let detectedAccounts: [String]
        let lines: [String]

        var isReadable: Bool { detectedMxn != nil }
    }

    /// Recognizes text on the slip and keeps the most plausible amount.
    /// Runs off the main actor: OCR on a full-resolution photo is not cheap.
    static func read(_ data: Data) async -> Reading {
        await Task.detached(priority: .userInitiated) { () -> Reading in
            guard let image = UIImage(data: data), let cgImage = image.cgImage else {
                return Reading(detectedMxn: nil, detectedDate: nil, detectedAccounts: [], lines: [])
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["es-MX", "es", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                // A slip that cannot be processed is treated as unreadable, never as valid.
                return Reading(detectedMxn: nil, detectedDate: nil, detectedAccounts: [], lines: [])
            }

            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return Reading(
                detectedMxn: amount(in: lines),
                detectedDate: date(in: lines),
                detectedAccounts: accounts(in: lines),
                lines: lines
            )
        }.value
    }

    /// Words that mark the line carrying the deposited figure on Mexican slips.
    private static let amountHints = ["importe", "monto", "deposito", "depósito", "efectivo", "total", "abono"]

    /// Picks the amount: prefers a line that names it, falls back to the largest figure.
    static func amount(in lines: [String]) -> Int? {
        var hinted: [Int] = []
        var all: [Int] = []

        for line in lines {
            let normalized = line.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX")).lowercased()
            let values = amounts(in: line)
            guard !values.isEmpty else { continue }
            all.append(contentsOf: values)
            if amountHints.contains(where: { normalized.contains($0.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))) }) {
                hinted.append(contentsOf: values)
            }
        }

        return hinted.max() ?? all.max()
    }

    /// Currency-shaped figures of one line, rounded to whole pesos.
    private static func amounts(in line: String) -> [Int] {
        let pattern = #"\$?\s?\d{1,3}(?:[,\s]\d{3})*(?:\.\d{1,2})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)

        return regex.matches(in: line, range: range).compactMap { match -> Int? in
            guard let matched = Range(match.range, in: line) else { return nil }
            let raw = line[matched]
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
            guard let value = Double(raw) else { return nil }
            // Slips also print folios and dates; only plausible money is kept.
            guard value >= 20, value <= 100_000 else { return nil }
            return Int(value.rounded())
        }
    }

    // MARK: - Date on the slip

    private static let monthAbbreviations: [String: Int] = [
        "ene": 1, "jan": 1, "feb": 2, "mar": 3, "abr": 4, "apr": 4, "may": 5,
        "jun": 6, "jul": 7, "ago": 8, "aug": 8, "sep": 9, "set": 9, "oct": 10,
        "nov": 11, "dic": 12, "dec": 12,
    ]

    /// Finds the day the slip was printed. Handles 12/08/2026, 12-08-26 and 12 AGO 2026.
    static func date(in lines: [String]) -> Date? {
        for line in lines {
            let normalized = line.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX")).lowercased()
            if let found = numericDate(in: normalized) ?? writtenDate(in: normalized) {
                return found
            }
        }
        return nil
    }

    private static func numericDate(in line: String) -> Date? {
        let pattern = #"(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }

        guard let day = intValue(match, at: 1, in: line),
              let month = intValue(match, at: 2, in: line),
              let year = intValue(match, at: 3, in: line) else { return nil }
        return makeDate(day: day, month: month, year: year)
    }

    private static func writtenDate(in line: String) -> Date? {
        let pattern = #"(\d{1,2})\s?[/\-]?\s?([a-z]{3})[a-z]*\.?\s?[/\-]?\s?(\d{2,4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let day = intValue(match, at: 1, in: line),
              let year = intValue(match, at: 3, in: line),
              let monthRange = Range(match.range(at: 2), in: line),
              let month = monthAbbreviations[String(line[monthRange])] else { return nil }
        return makeDate(day: day, month: month, year: year)
    }

    private static func intValue(_ match: NSTextCheckingResult, at index: Int, in line: String) -> Int? {
        guard let range = Range(match.range(at: index), in: line) else { return nil }
        return Int(line[range])
    }

    private static func makeDate(day: Int, month: Int, year: Int) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        let fullYear = year < 100 ? 2_000 + year : year
        guard (2_020...2_100).contains(fullYear) else { return nil }

        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = fullYear
        components.hour = 12
        return ShiftRules.calendar.date(from: components)
    }

    // MARK: - Destination account on the slip

    /// Every long digit run the slip carries, normalized. Convenience stores print the
    /// CLABE spaced, hyphenated or masked with asterisks, so separators are dropped and
    /// runs made only of mask characters are discarded.
    static func accounts(in lines: [String]) -> [String] {
        var found: [String] = []

        for line in lines {
            let compact = line
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ".", with: "")

            let pattern = #"[0-9*xX]{8,24}"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(compact.startIndex..., in: compact)

            for match in regex.matches(in: compact, range: range) {
                guard let matched = Range(match.range, in: compact) else { continue }
                let token = String(compact[matched])
                guard token.contains(where: \.isNumber) else { continue }
                found.append(token)
            }
        }
        return found
    }

    /// Compares the destination printed on the slip against the account of the network.
    /// Convenience stores mask the middle of the CLABE, so a slip is accepted when the
    /// visible part lines up with the registered account.
    static func accountMatch(expected: CashDepositAccount, reading: Reading) -> DepositMatch {
        let targets = [expected.clabe, expected.accountNumber]
            .map { $0.filter(\.isNumber) }
            .filter { $0.count >= 8 }
        guard !targets.isEmpty else { return .notChecked }

        let candidates = reading.detectedAccounts
        guard !candidates.isEmpty else { return .unreadable }

        for candidate in candidates where targets.contains(where: { matches(candidate: candidate, target: $0) }) {
            return .matched
        }

        // Long digit runs were printed, but none of them is the account of the network.
        return .mismatched
    }

    /// A candidate matches when it has the length of the account and every visible
    /// character agrees, or when its digits are contained in the account.
    private static func matches(candidate: String, target: String) -> Bool {
        let normalized = candidate.lowercased()
        guard normalized.count >= 8 else { return false }

        if normalized.count == target.count {
            let visibleAgree = zip(normalized, target).allSatisfy { pair in
                pair.0 == "*" || pair.0 == "x" || pair.0 == pair.1
            }
            if visibleAgree { return true }
        }

        let digits = normalized.filter(\.isNumber)
        guard digits.count >= 8 else { return false }
        return target.contains(digits) || digits.contains(target)
    }

    /// Tolerance in pesos: OCR may drop the cents of a slip.
    static let toleranceMxn = 1

    static func match(declared: Int, detected: Int?) -> DepositMatch {
        guard let detected else { return .unreadable }
        return abs(declared - detected) <= toleranceMxn ? .matched : .mismatched
    }
}
