import Foundation

/// Structural state of the shift screen, derived from the clock but not made of it.
///
/// The screen used to be composed against a `Date` that advanced every second, so the
/// editor stack was rebuilt sixty times a minute to produce, almost always, the exact same
/// arrangement of blocks. This type is the answer: it collapses the continuous hour into
/// the handful of booleans that genuinely change *what the screen is made of*.
///
/// Two of them per day, typically. The composition depends on this value; the reading of
/// the clock stays where it belongs, inside the leaves that display it.
///
/// It derives no rules of its own. Every field comes from `ShiftRules`, the active shift or
/// a figure the store already computes — there are no hours, tolerances or windows written
/// here.
nonisolated struct ShiftPhase: Equatable, Sendable {
    /// A shift is running.
    var isActive: Bool
    /// The start window is open right now, so the shift may be started.
    var canStart: Bool
    /// The workday of a running shift is over and the unit must be handed back.
    var isPastClose: Bool
    /// The running shift was started late.
    var isLate: Bool
    /// The payback window of this driver's block is open.
    var isPaybackOpen: Bool
    /// There is late time still owed this week.
    var hasLateDebt: Bool
    /// Where the clock stands against the block. Carries the boundary instants, which
    /// change by the day and never by the second.
    var window: ShiftRules.WindowState
    /// Definitive close of the workday, for the copy under the clock.
    var closesAt: Date

    /// Reads the rules once and freezes the outcome.
    ///
    /// `lateDebtMinutes` is supplied by the caller rather than computed here: the tally
    /// lives in `FleetStore.weeklyLateDebt(reference:)` and must not be duplicated.
    static func resolve(
        driver: Driver,
        activeShift: ActiveShift?,
        lateDebtMinutes: Int,
        now: Date
    ) -> ShiftPhase {
        let window = ShiftRules.windowState(driver: driver, now: now)
        return ShiftPhase(
            isActive: activeShift != nil,
            canStart: window.isOpen,
            isPastClose: ShiftRules.isPastClose(slot: driver.slot, now: now),
            isLate: (activeShift?.lateMinutes ?? 0) > 0,
            isPaybackOpen: ShiftRules.isPaybackWindow(driver: driver, now: now),
            hasLateDebt: lateDebtMinutes > 0,
            window: window,
            closesAt: ShiftRules.startWindow(slot: driver.slot, now: now).closesAt
        )
    }
}
