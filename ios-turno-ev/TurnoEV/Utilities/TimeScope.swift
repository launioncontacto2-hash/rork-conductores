import SwiftUI

/// How often a piece of interface needs to hear from the clock.
///
/// Hoisted out of `TimeScope` so that anything else needing to name a cadence — the
/// `ClockAnchor` badges depend on, a future modifier — can do so without reaching through a
/// generic type. Call sites are unaffected: `TimeScope(.day) { ... }` still infers this.
enum ClockCadence {
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

/// The instant a cadence is currently reporting, and the place its dependency is
/// registered. Shared by `TimeScope` and `ClockAnchor` so both observe identically.
@MainActor
private func reading(for cadence: ClockCadence) -> Date {
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
    let cadence: ClockCadence
    @ViewBuilder let content: (Date) -> Content

    init(_ cadence: ClockCadence, @ViewBuilder content: @escaping (Date) -> Content) {
        self.cadence = cadence
        self.content = content
    }

    var body: some View {
        content(reading(for: cadence))
    }
}

/// Invisible leaf that keeps a `Date` in step with a cadence.
///
/// For the handful of places that need logical time but cannot receive it as a view — a tab
/// `.badge(_:)` takes a number, not a builder, so there is nowhere to put a `TimeScope`.
///
/// The anchor holds the **instant**, never the derived value. That distinction is the whole
/// point: a badge written as `.badge(office.capacityPlan(now: dayAnchor).deficit)` is
/// recomputed both when the day rolls over — because this leaf writes a new anchor — and
/// when the underlying data changes, because the store is `@Observable` and the badge reads
/// it directly. Caching the count instead would have frozen it on every data event.
///
/// Zero size, so it can be mounted in a `.background` without touching layout, and it never
/// invalidates its host on a tick: the dependency is registered here, and the write is
/// guarded so a cadence that reports the same instant publishes nothing.
struct ClockAnchor: View {
    let cadence: ClockCadence
    @Binding var date: Date

    init(_ cadence: ClockCadence, date: Binding<Date>) {
        self.cadence = cadence
        _date = date
    }

    var body: some View {
        let instant = reading(for: cadence)
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: instant, initial: true) { _, resolved in
                guard resolved != date else { return }
                date = resolved
            }
    }
}
