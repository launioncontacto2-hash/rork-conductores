import Foundation

/// Spanish (MX) formatting for money, distance, clocks and durations.
nonisolated enum Fmt {
    static let locale = Locale(identifier: "es_MX")

    static func mxn(_ value: Double) -> String {
        value.rounded().formatted(.currency(code: "MXN").precision(.fractionLength(0)).locale(locale))
    }

    static func mxn(_ value: Int) -> String { mxn(Double(value)) }

    static func km(_ value: Int) -> String {
        "\(value.formatted(.number.locale(locale))) km"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    static func clockSeconds(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
                .locale(locale)
        )
    }

    static func dateLong(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    static func dateShort(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day(.twoDigits).month(.abbreviated).locale(locale))
    }

    /// "12 ago" for the bonus week ranges.
    static func dayNumber(_ date: Date) -> String {
        date.formatted(.dateTime.day(.defaultDigits).month(.abbreviated).locale(locale))
            .replacingOccurrences(of: ".", with: "")
    }

    static func monthLong(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized
    }

    /// "2026-08", used to key monthly bonus evaluations.
    static func monthKey(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    static func rating(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    static func dayShort(_ date: Date) -> String {
        let raw = date.formatted(.dateTime.weekday(.abbreviated).locale(locale)).replacingOccurrences(of: ".", with: "")
        return raw.prefix(1).uppercased() + raw.dropFirst().prefix(2)
    }

    /// 07:32:11 for the live shift counter.
    static func stopwatch(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// Late time is always communicated as hh:mm.
    static func lateText(_ minutes: Int) -> String {
        let total = max(0, minutes)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func durationText(_ minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60
        let rest = total % 60
        return hours > 0 ? "\(hours)h \(String(format: "%02d", rest))m" : "\(rest)m"
    }

    static func firstName(_ fullName: String) -> String {
        fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    static func relative(_ date: Date, from now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "ahora" }
        if minutes < 60 { return "hace \(minutes) min" }
        if minutes < 60 * 24 { return "hace \(minutes / 60) h" }
        let days = minutes / (60 * 24)
        return days == 1 ? "ayer" : "hace \(days) días"
    }
}
