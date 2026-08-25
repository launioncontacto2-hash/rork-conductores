import Foundation
import Observation

/// Granular publisher of logical time.
///
/// `ClockSignal` has a single indiscriminate counter: every adopted state bumps it, and
/// every reader of `store.now` — the seven roles — is invalidated at once. This type is
/// its replacement, split into the three cadences the interface actually distinguishes:
///
/// - `second`  — changes when the **logical second** changes. Stopwatches, clock chips.
/// - `minute`  — changes when the **logical minute** changes. Almost everything else.
/// - `day`     — changes when the **calendar day** of logical time changes. Expiry dates,
///   day boards, "today" headings: everything whose answer is decided by a date rather
///   than by an hour.
/// - `phaseEpoch` — changes only on a **discontinuous jump**: set, shift, setSpeed, reset
///   or a state adopted from another device. Never on the mere passage of time.
///
/// Two invariants make it safe:
///
/// 1. **It never accumulates.** Nothing is added to a running total. Every value is
///    recomputed from `AppClock.now()`, which stays the single source of truth. A missed
///    tick therefore cannot drift the reading — the next recomputation is already correct.
/// 2. **It compares before publishing.** `@Observable` invalidates on assignment, not on
///    change, so every property is written only after the new value is proven different.
///    At x30 the loop still runs once per real second: it publishes one second stamp that
///    happens to have advanced by thirty, never thirty updates.
@MainActor
@Observable
final class ClockBeat {
    static let shared = ClockBeat()

    /// Logical time truncated to the second.
    private(set) var second: Date

    /// Logical time truncated to the minute.
    private(set) var minute: Date

    /// Logical time as it stood the moment the calendar day last changed.
    ///
    /// Not `startOfDay`: the cadence decides *when* consumers are invalidated, never what
    /// instant they are handed. A scope reading this gets the true logical hour — a second
    /// or two past midnight on a normal rollover, the exact hour landed on after a jump —
    /// which is what date comparisons and expiry rules need.
    private(set) var day: Date

    /// Counter of discontinuous jumps. Content whose *structure* depends on the clock —
    /// not its reading — watches this instead of a cadence.
    private(set) var phaseEpoch: Int = 0

    /// Whole logical seconds since the reference date. The comparison key for `second`.
    @ObservationIgnored private var secondStamp: Int

    /// Whole logical minutes since the reference date. The comparison key for `minute`.
    @ObservationIgnored private var minuteStamp: Int

    /// Midnight of the logical day last observed. The comparison key for `day`.
    ///
    /// A `Date` rather than an `Int` on purpose: only the calendar knows where a day
    /// begins, and it is the app's own calendar — the one `ShiftRules` uses for every other
    /// temporal rule — that has to answer, not arithmetic on epochs.
    @ObservationIgnored private var dayStart: Date

    /// Shape of the clock as last observed, so an echo of a state already in force does
    /// not count as a jump.
    @ObservationIgnored private var signature: PhaseSignature

    /// The one and only periodic producer. `nil` whenever the app is not in the
    /// foreground.
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Real seconds between recomputations. Fixed by design: the cap of one update per
    /// real second is what keeps an accelerated simulation from flooding the run loop.
    private static let cadence: Duration = .seconds(1)

    /// Largest gap between two instants that still counts as the same instant.
    ///
    /// Sized against the round trip of this exact route, not guessed:
    ///
    /// - **Write** — `SupabaseCoding.text(from:)` formats with `.SSS`, quantising to whole
    ///   milliseconds. Worst case error: **0.5 ms**.
    /// - **Store** — Postgres `timestamptz` keeps microseconds, so a millisecond value
    ///   survives exactly. Adds **0**.
    /// - **Read** — `SupabaseCoding.timestamp(from:)` splits the fraction off as a decimal
    ///   string and adds it back as a `TimeInterval`. `Date` is a `Double` of seconds since
    ///   2001 (~8×10⁸ s), and a `Double` holds ~15–16 significant digits, so the
    ///   representation floor is ~10⁻⁷ s. Adds **< 1 µs**.
    ///
    /// Total worst case: **0.5 ms + 1 µs < 0.502 ms**.
    ///
    /// Deterministic normalisation was preferred and rejected: quantising locally to the
    /// same millisecond grid only works if our rounding rule matches the formatter's, and
    /// ICU does not contractually specify how `.SSS` breaks a halfway value. At an exact
    /// `x.xxx5` boundary the two rules can disagree by one whole millisecond, which is the
    /// ambiguity that normalisation was supposed to remove.
    ///
    /// So: 2 ms. Roughly **4×** the worst-case serialisation error, and **500×** smaller
    /// than the finest change the app can express — one second, from the picker's second
    /// wheel. Nothing a human can ask of this clock lands inside the window.
    private static let instantTolerance: TimeInterval = 0.002

    /// Identity of a clock state, in the only terms that decide what hour it is.
    ///
    /// Excludes `updatedAt` **and `revision`**. Both are write bookkeeping — who wrote
    /// last, in what order — never a statement about the hour.
    ///
    /// Keeping `revision` was an outright bug. Postgres appends a revision to every
    /// accepted write under a row lock, so the state coming back from our own RPC always
    /// carries `K+1` against the local `K`, and a signature holding it declared the reply
    /// to be a brand-new clock.
    ///
    /// Correction to the earlier audit, recorded here on purpose: the phantom second jump
    /// does **not** come from the Realtime echo. `SharedClockSync.send` adopts the RPC
    /// response directly (`applyRealtime(row)`), which advances the local revision to
    /// `K+1`; the Realtime UPDATE that follows carries the same `K+1` and is normally
    /// dropped by `guard row.revision > revision`. The duplicate was the reply, not the
    /// echo.
    private struct PhaseSignature {
        var anchor: Date
        var pinnedAt: Date
        var speed: SimulationSpeed
        /// A different test environment is a different clock, even on identical anchors.
        var environmentId: String
        /// Production and simulation are two clocks; `AppClock` picks between them.
        var isTest: Bool

        static func current() -> PhaseSignature {
            let state = SimulationClock.load()
            return PhaseSignature(
                anchor: state.anchor,
                pinnedAt: state.pinnedAt,
                speed: state.speed,
                environmentId: state.environmentId,
                isTest: LabRuntime.isTest
            )
        }

        /// Same clock? Discrete fields exactly, instants within the serialisation window.
        ///
        /// Not `Equatable` on purpose: `==` on raw `Date`s is precisely the comparison that
        /// fails here, and leaving it available invites the bug back.
        func matches(_ other: PhaseSignature) -> Bool {
            speed == other.speed
                && isTest == other.isTest
                && environmentId == other.environmentId
                && abs(anchor.timeIntervalSince(other.anchor)) <= ClockBeat.instantTolerance
                && abs(pinnedAt.timeIntervalSince(other.pinnedAt)) <= ClockBeat.instantTolerance
        }
    }

    private init() {
        let now = AppClock.now()
        let seconds = Self.secondStamp(of: now)
        let minutes = Self.minuteStamp(ofSecond: seconds)
        secondStamp = seconds
        minuteStamp = minutes
        second = Self.date(fromSecondStamp: seconds)
        minute = Self.date(fromMinuteStamp: minutes)
        dayStart = ShiftRules.calendar.startOfDay(for: now)
        day = Self.date(fromSecondStamp: seconds)
        signature = PhaseSignature.current()
        watchDiscontinuities()
    }

    // MARK: - Lifecycle

    /// Starts — or resumes — the beat.
    ///
    /// Idempotent by contract. The guard on `ticker` is what guarantees a single producer
    /// no matter how many times it is called or how many screens are mounted.
    func resume() {
        // Coming back from the background the correct hour is *derived*, never replayed:
        // the anchored clock already knows where it stands, so one recomputation lands on
        // the right instant regardless of how long the app was away.
        refresh()

        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.cadence)
                if Task.isCancelled { return }
                self?.refresh()
            }
        }
    }

    /// Stops all periodic activity. Nothing ticks behind a locked screen.
    func suspend() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Recomputation

    /// Reads the logical hour once and publishes only what genuinely moved.
    private func refresh() {
        let now = AppClock.now()
        let seconds = Self.secondStamp(of: now)
        let minutes = Self.minuteStamp(ofSecond: seconds)

        if seconds != secondStamp {
            secondStamp = seconds
            second = Self.date(fromSecondStamp: seconds)
        }

        if minutes != minuteStamp {
            minuteStamp = minutes
            minute = Self.date(fromMinuteStamp: minutes)

            // Nested on purpose, and this is the whole argument for `.day` living here
            // rather than being derived by its consumers.
            //
            // A calendar day begins at midnight, and midnight is always a minute boundary:
            // every zone this app can run in offsets UTC by a whole number of minutes. So
            // the day cannot change without the minute stamp changing first. Asking the
            // calendar inside this branch is therefore not an optimisation with a hole in
            // it — it is the same condition, evaluated once per logical minute instead of
            // once per real second.
            //
            // The comparison is `startOfDay(previous) != startOfDay(current)`, which is
            // what makes acceleration and jumps fall out for free: it never watches for
            // 00:00 to be observed, only for the day to have become a different one.
            let start = ShiftRules.calendar.startOfDay(for: now)
            if start != dayStart {
                dayStart = start
                day = Self.date(fromSecondStamp: seconds)
            }
        }
    }

    /// Re-arming observer of the existing global signal.
    ///
    /// During the transition `ClockSignal` remains the notifier of every adopted state, so
    /// this is where a discontinuity is detected without touching it. When the signal is
    /// finally retired, only this method changes: `SimulationClock` will call
    /// `registerJump()` directly.
    private func watchDiscontinuities() {
        withObservationTracking {
            _ = ClockSignal.shared.generation
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.registerJump()
                self.watchDiscontinuities()
            }
        }
    }

    /// Raises `phaseEpoch` if — and only if — the clock really landed somewhere new.
    private func registerJump() {
        let incoming = PhaseSignature.current()
        guard !incoming.matches(signature) else {
            // The state already in force, arriving a second time: the reply to our own RPC
            // carrying the server's revision, or its Realtime echo. The hour did not move,
            // so nothing is invalidated.
            return
        }
        signature = incoming
        phaseEpoch &+= 1
        // A jump normally lands on a different second and minute; `refresh` decides.
        refresh()
    }

    // MARK: - Stamps

    private static func secondStamp(of date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate.rounded(.down))
    }

    private static func minuteStamp(ofSecond seconds: Int) -> Int {
        Int((Double(seconds) / 60).rounded(.down))
    }

    private static func date(fromSecondStamp stamp: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(stamp))
    }

    private static func date(fromMinuteStamp stamp: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(stamp) * 60)
    }
}
