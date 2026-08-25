import SwiftUI

/// Localised consumer of logical time.
///
/// Wrap **only** the few elements that genuinely have to follow the clock:
///
/// ```swift
/// TimeScope(.minute) { now in
///     Text(Fmt.clock(now))
/// }
/// ```
///
/// The point is where the dependency is registered. `TimeScope` is a view of its own, so
/// reading the beat happens inside *its* body: when the cadence advances, SwiftUI
/// invalidates this view and its content, and stops there. The screen hosting it — its
/// `ScrollView`, its list, its toolbar, its `Canvas` — is never re-evaluated.
///
/// Because `ClockBeat` publishes each cadence separately, a `.minute` scope is untouched
/// by the fifty-nine seconds that do not change the minute, even at x30 — and a `.day`
/// scope is untouched by the one thousand four hundred and thirty-nine minutes that do not
/// change the date.
struct TimeScope<Content: View>: View {
    /// How often this piece of interface needs to hear from the clock.
    enum Cadence {
        /// Once per logical second. Stopwatches and clock readouts only.
        case second
        /// Once per logical minute. The right default for almost everything.
        case minute
        /// Once per calendar day of logical time. For content decided by a date rather
        /// than an hour: expiry, completion of a file, the board of the day, a heading
        /// that reads "today".
        ///
        /// It is a real boundary, not a 24-hour interval: it fires when
        /// `startOfDay` changes, so it survives acceleration and lands once on a jump of
        /// any size.
        case day
        /// Only on a discontinuous jump — set, shift, speed change, reset, remote
        /// adoption. For content whose *structure* depends on time rather than its
        /// reading.
        case phase
    }

    let cadence: Cadence
    @ViewBuilder let content: (Date) -> Content

    init(_ cadence: Cadence, @ViewBuilder content: @escaping (Date) -> Content) {
        self.cadence = cadence
        self.content = content
    }

    /// The instant handed to the content, and — more importantly — the place where this
    /// view's dependencies are registered. Kept out of `body` because a `ViewBuilder`
    /// cannot hold a bare read.
    private var reading: Date {
        let beat = ClockBeat.shared

        // Every cadence *but* `.day` also observes `phaseEpoch`, so a jump to another hour
        // always lands even when it happens to keep the same second or minute stamp.
        //
        // `.day` is excluded deliberately. Its comparison key is the calendar day, and
        // `ClockBeat.refresh()` recomputes that on every jump — so the value is already
        // correct by the time it is read here. Watching the epoch as well would make an
        // hour shifted inside the same date, a change of pace, or leaving the test
        // environment at the same date invalidate content that only shows a date.
        if cadence != .day {
            _ = beat.phaseEpoch
        }

        switch cadence {
        case .second:
            return beat.second
        case .minute:
            return beat.minute
        case .day:
            return beat.day
        case .phase:
            // No cadence is observed at all. `AppClock` is a plain static enum, so
            // reading it registers nothing: this subtree moves only when the clock jumps,
            // and when it does it picks up the true hour it landed on.
            return AppClock.now()
        }
    }

    var body: some View {
        content(reading)
    }
}
