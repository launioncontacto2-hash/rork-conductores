import SwiftUI

/// Shared reading of cobertura de turnos. Every role — driver, supervisor, laboratory —
/// looks at the same states with the same colours, so a seat means the same thing on
/// every screen.
nonisolated enum CovTone {
    /// A seat that is covered and a decision that is signed.
    static let good = Palette.volt
    /// Something is moving but nothing is settled yet.
    static let pending = Palette.amber
    /// A seat nobody is driving, or a person who did not show up.
    static let blocking = Palette.danger
    /// Neutral information and closed records.
    static let closed = Palette.info
    static let quiet = Palette.neutral
}

extension AbsenceStatus {
    var tone: Color {
        switch self {
        case .requested, .searching: CovTone.pending
        case .covered, .awaitingAuthorization: CovTone.closed
        case .approved: CovTone.good
        case .rejected, .uncovered: CovTone.blocking
        case .cancelled: CovTone.quiet
        }
    }
}

extension VacancyStatus {
    var tone: Color {
        switch self {
        case .searching: CovTone.pending
        case .reserved: CovTone.closed
        case .confirmed, .completed: CovTone.good
        case .uncovered, .noShow: CovTone.blocking
        case .cancelled: CovTone.quiet
        }
    }
}

extension SwapStatus {
    var tone: Color {
        switch self {
        case .proposed, .accepted, .awaitingSupervisor: CovTone.pending
        case .approved: CovTone.good
        case .declined, .rejected: CovTone.blocking
        case .cancelled: CovTone.quiet
        }
    }
}

extension CoverageDayKind {
    var tone: Color {
        switch self {
        case .regular: CovTone.quiet
        case .rest: Palette.textMuted
        case .guardConfirmed, .absenceApproved: CovTone.good
        case .guardReserved, .absenceRequested: CovTone.pending
        case .swap: CovTone.closed
        case .extraordinary: CovTone.good
        case .noShow: CovTone.blocking
        }
    }
}

// MARK: - Status pill

/// One-word state badge used in every list of the module.
struct CoveragePill: View {
    let text: String
    var symbol: String?
    var tone: Color = CovTone.quiet
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(filled ? Palette.canvas : tone)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(filled ? tone : tone.opacity(0.13), in: .capsule)
        .overlay { Capsule().stroke(tone.opacity(filled ? 0 : 0.4), lineWidth: 1) }
    }
}

// MARK: - Pipeline rail

/// The five steps of an absence, drawn so the driver can never confuse "sent" with
/// "authorized". The rail stops before the last dot until somebody signs.
struct AbsencePipelineRail: View {
    let status: AbsenceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(AbsenceStatus.pipeline.enumerated()), id: \.element) { index, step in
                    let reached = isReached(step)
                    Circle()
                        .fill(reached ? tone(for: step) : Palette.surfaceRaised)
                        .frame(width: 11, height: 11)
                        .overlay {
                            Circle().stroke(reached ? tone(for: step) : Palette.hairline, lineWidth: 1)
                        }
                    if index < AbsenceStatus.pipeline.count - 1 {
                        Rectangle()
                            .fill(isReached(AbsenceStatus.pipeline[index + 1]) ? tone(for: step) : Palette.surfaceRaised)
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: status.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(status.tone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.label)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(status.tone)
                    Text(status.detail)
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func isReached(_ step: AbsenceStatus) -> Bool {
        switch status {
        case .rejected, .cancelled, .uncovered:
            // A broken process lights only what actually happened.
            return step == .requested || (step == .searching && status != .cancelled)
        default:
            return step.pipelineIndex <= status.pipelineIndex
        }
    }

    private func tone(for step: AbsenceStatus) -> Color {
        switch status {
        case .rejected, .uncovered: CovTone.blocking
        case .cancelled: CovTone.quiet
        default: step == .approved ? CovTone.good : CovTone.pending
        }
    }
}

// MARK: - Vacancy card

/// A seat, read the same way by everybody: when it is, where it is, who is missing,
/// what it pays and how far along it is.
///
/// The card owns the freshness of its own temporal data. Exactly one line of it follows
/// the clock — the urgency of a critical seat — so that line carries the `TimeScope` and
/// the caller hands over no `now` at all. A section listing thirty vacancies therefore
/// invalidates at most thirty small labels on the minute, never thirty whole cards.
struct VacancyCard: View {
    let vacancy: CoverageVacancy
    var showsTitular: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Fmt.dateShort(vacancy.date).capitalized)
                        .font(.system(.subheadline, weight: .black))
                    Text("\(vacancy.slot.label) · \(vacancy.slot.rangeLabel)")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                CoveragePill(
                    text: vacancy.status.shortLabel,
                    symbol: vacancy.status.symbol,
                    tone: vacancy.status.tone
                )
            }

            if vacancy.isCritical && vacancy.status.isOpen {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 10, weight: .bold))
                    TimeScope(.minute) { now in
                        Text(CoverageRules.urgencyLabel(hoursUntilStart: vacancy.hoursUntilStart(now: now)))
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .foregroundStyle(CovTone.blocking)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CovTone.blocking.opacity(0.12), in: .rect(cornerRadius: 11))
            }

            HStack(spacing: 8) {
                CoverageFact(label: "Estación", value: vacancy.stationCode)
                CoverageFact(label: "Duración", value: "\(vacancy.durationHours) h")
                CoverageFact(
                    label: "Bono",
                    value: vacancy.bonusLabel,
                    tone: vacancy.bonusMode == .none ? Palette.textMuted : CovTone.good
                )
            }

            if showsTitular, let titular = vacancy.titularName {
                CoverageLine(label: "Titular", value: titular, symbol: "person.fill")
            }
            if let substitute = vacancy.substituteName {
                CoverageLine(label: "Sustituto", value: substitute, symbol: "person.fill.checkmark", tone: CovTone.good)
            }
            if !vacancy.waitlist.isEmpty {
                CoverageLine(
                    label: "Lista de espera",
                    value: "\(vacancy.waitlist.count) conductor\(vacancy.waitlist.count == 1 ? "" : "es")",
                    symbol: "person.3.fill",
                    tone: CovTone.closed
                )
            }

            Text(vacancy.reason.isEmpty ? vacancy.origin.label : vacancy.reason)
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .panelFlat()
    }
}

struct CoverageFact: View {
    let label: String
    let value: String
    var tone: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CapsLabel(text: label)
            Text(value)
                .font(.system(.caption, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CoverageLine: View {
    let label: String
    let value: String
    var symbol: String
    var tone: Color = .primary

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tone.opacity(0.9))
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tone)
                .lineLimit(1)
        }
    }
}

// MARK: - Eligibility checklist

/// The thirteen rules, shown as the supervisor reads them before signing. Grouped so a
/// single glance answers "why is this person allowed to drive that unit".
struct EligibilityChecklist: View {
    let verdict: EligibilityVerdict
    var isCompact: Bool = false

    private var families: [String] {
        var seen: [String] = []
        for check in verdict.checks where !seen.contains(check.rule.family) {
            seen.append(check.rule.family)
        }
        return seen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 9) {
            ForEach(families, id: \.self) { family in
                let checks = verdict.checks.filter { $0.rule.family == family }
                let passed = checks.allSatisfy(\.passed)

                if isCompact {
                    HStack(spacing: 6) {
                        Image(systemName: passed ? "checkmark" : "xmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(passed ? CovTone.good : CovTone.blocking)
                        Text(family)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(passed ? .primary : CovTone.blocking)
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(passed ? CovTone.good : CovTone.blocking)
                            Text(family)
                                .font(.system(.caption, weight: .bold))
                            Spacer(minLength: 0)
                        }
                        ForEach(checks) { check in
                            HStack(alignment: .top, spacing: 6) {
                                Text("·")
                                    .foregroundStyle(check.passed ? Palette.textMuted : CovTone.blocking)
                                Text("\(check.rule.label): \(check.detail)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(check.passed ? Palette.textMuted : CovTone.blocking)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        (passed ? CovTone.good : CovTone.blocking).opacity(0.07),
                        in: .rect(cornerRadius: 12)
                    )
                }
            }
        }
    }
}

// MARK: - Coverage meter

/// Seats covered against seats required, for one block of the day.
struct CoverageMeter: View {
    let board: CoverageSlotBoard

    private var tone: Color {
        board.missing == 0 ? CovTone.good : board.missing > 2 ? CovTone.blocking : CovTone.pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(board.label)
                    .font(.system(.caption, weight: .bold))
                Spacer(minLength: 6)
                Text("\(board.covered) / \(board.required)")
                    .font(.system(.subheadline, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(tone)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceRaised)
                    Capsule()
                        .fill(tone)
                        .frame(width: proxy.size.width * min(1, board.ratio))
                        .animation(.smooth(duration: 0.6), value: board.ratio)
                }
            }
            .frame(height: 7)

            HStack(spacing: 10) {
                Text(board.missing == 0 ? "Sin faltantes" : "Faltantes: \(board.missing)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(board.missing == 0 ? Palette.textMuted : tone)
                if board.confirmedGuards > 0 {
                    Text("· \(board.confirmedGuards) por guardia")
                        .font(.system(size: 10))
                        .foregroundStyle(CovTone.good)
                }
                if board.openVacancies > 0 {
                    Text("· \(board.openVacancies) en búsqueda")
                        .font(.system(size: 10))
                        .foregroundStyle(CovTone.pending)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .panelFlat()
    }
}

// MARK: - Empty state

struct CoverageEmpty: View {
    let title: String
    let message: String
    var symbol: String = "calendar.badge.clock"
    var tone: Color = CovTone.quiet

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(tone.opacity(0.7))
            Text(title)
                .font(.system(.subheadline, weight: .bold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .panelFlat()
    }
}
