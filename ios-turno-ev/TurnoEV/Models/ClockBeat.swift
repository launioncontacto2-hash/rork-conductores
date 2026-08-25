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

    /// Counter of discontinuous jumps. Content whose *structure* depends on the clock —
    /// not its reading — watches this instead of a cadence.
    private(set) var phaseEpoch: Int = 0

    /// Whole logical seconds since the reference date. The comparison key for `second`.
    @ObservationIgnored private var secondStamp: Int

    /// Whole logical minutes since the reference date. The comparison key for `minute`.
    @ObservationIgnored private var minuteStamp: Int

    /// Shape of the clock as last observed, so an echo of a state already in force does
    /// not count as a jump.
    @ObservationIgnored private var signature: PhaseSignature

    /// The one and only periodic producer. `nil` whenever the app is not in the
    /// foreground.
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Real seconds between recomputations. Fixed by design: the cap of one update per
    /// real second is what keeps an accelerated simulation from flooding the run loop.
    private static let cadence: Duration = .seconds(1)

    /// Identity of a clock state, ignoring `updatedAt`.
    ///
    /// Deliberately excludes the timestamp so the device's own echo — the Realtime UPDATE
    /// coming back from a change made here — is recognised as the state already in force
    /// and does not raise a phantom jump.
    private struct PhaseSignature: Equatable {
        var anchor: Date
        var pinnedAt: Date
        var speed: SimulationSpeed
        var revision: Int64
        var isTest: Bool

        static func current() -> PhaseSignature {
            let state = SimulationClock.load()
            return PhaseSignature(
                anchor: state.anchor,
                pinnedAt: state.pinnedAt,
                speed: state.speed,
                revision: state.revision,
                isTest: LabRuntime.isTest
            )
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
        guard incoming != signature else {
            // Same state arriving twice: the local echo of our own publication. The hour
            // did not move, so nothing is invalidated.
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
