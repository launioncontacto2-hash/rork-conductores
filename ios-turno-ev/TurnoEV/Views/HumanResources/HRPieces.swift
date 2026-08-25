import SwiftUI

/// Shared reading pieces of the people, banking and workshop modules. They all follow
/// the same rule: lime means healthy, amber asks for attention, red blocks, steel blue
/// is neutral. No extra colours, because these screens carry a lot of numbers.

// MARK: - Tones

extension OpsAlertLevel {
    var tone: Color {
        switch self {
        case .informative: Palette.textMuted
        case .preventive: Palette.info
        case .important: Palette.amber
        case .critical: Palette.danger
        }
    }
}

extension CandidateStage {
    var tone: Color {
        switch self {
        case .lead, .interview, .documents: Palette.info
        case .approved, .toHire: Palette.amber
        case .hired: Palette.volt
        case .rejected: Palette.danger
        }
    }
}

extension DocumentStatus {
    var tone: Color {
        switch self {
        case .delivered: Palette.volt
        case .pending: Palette.textMuted
        case .expiringSoon: Palette.amber
        case .rejected, .expired: Palette.danger
        }
    }
}

extension EmploymentStatus {
    var tone: Color {
        switch self {
        case .active: Palette.volt
        case .onboarding: Palette.info
        case .vacation, .medicalLeave: Palette.amber
        case .suspended, .terminated: Palette.danger
        }
    }
}

extension BankAccountStatus {
    var tone: Color {
        switch self {
        case .verified: Palette.volt
        case .pending: Palette.amber
        case .rejected, .blocked: Palette.danger
        }
    }
}

extension BankRequestStatus {
    var tone: Color {
        switch self {
        case .requested: Palette.amber
        case .review: Palette.info
        case .approved, .applied: Palette.volt
        case .rejected: Palette.danger
        }
    }
}

extension WorkOrderStatus {
    var tone: Color {
        switch self {
        case .pending: Palette.amber
        case .inProgress: Palette.info
        case .waiting: Palette.textMuted
        case .finished: Palette.amber
        case .returned: Palette.danger
        case .closed: Palette.volt
        case .cancelled: Palette.textMuted
        }
    }
}

extension WorkOrderPriority {
    var tone: Color {
        switch self {
        case .low: Palette.textMuted
        case .medium: Palette.info
        case .high: Palette.amber
        case .critical: Palette.danger
        }
    }
}

extension IncorporationStage {
    var tone: Color {
        switch self {
        case .purchasing, .purchaseConfirmed: Palette.textMuted
        case .inTransit, .preparing: Palette.info
        case .arrivingSoon: Palette.amber
        case .active: Palette.volt
        }
    }
}

// MARK: - Level pill

struct LevelPill: View {
    let level: OpsAlertLevel
    var compact: Bool = false

    var body: some View {
        StatePill(text: level.label, symbol: level.symbol, tone: level.tone, compact: compact)
    }
}

// MARK: - Coverage

/// One block of the week: required, available and what is missing, in one line.
struct CoverageRow: View {
    let coverage: BlockCoverage
    var action: (() -> Void)?

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: coverage.block.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(coverage.deficit == 0 ? Palette.volt : coverage.level.tone)
                Text(coverage.block.label)
                    .font(.system(.footnote, weight: .bold))
                Spacer(minLength: 4)
                Text("\(coverage.available)/\(coverage.required)")
                    .font(.system(.footnote, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(coverage.deficit == 0 ? Palette.volt : coverage.level.tone)
            }

            ProgressTrack(
                value: Double(coverage.available),
                goal: Double(max(1, coverage.required)),
                tone: coverage.deficit == 0 ? Palette.volt : coverage.level.tone
            )
            .frame(height: 8)

            HStack(spacing: 10) {
                if coverage.deficit > 0 {
                    Text("Faltan \(coverage.deficit)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(coverage.level.tone)
                } else {
                    Text("Cobertura completa")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Palette.volt)
                }
                Text("\(coverage.hired) contratados · \(coverage.onboarding) en proceso")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .panelFlat()

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Funnel

/// Recruitment funnel drawn as proportional bars, with the conversion at the end.
struct PipelineFunnel: View {
    let pipeline: HiringPipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(pipeline.stages.enumerated()), id: \.offset) { _, stage in
                HStack(spacing: 10) {
                    Text(stage.label)
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 96, alignment: .leading)
                        .foregroundStyle(Palette.textMuted)
                    GeometryReader { proxy in
                        let maxValue = Double(max(1, pipeline.candidates))
                        let ratio = min(1, Double(stage.value) / maxValue)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.surfaceRaised)
                            Capsule()
                                .fill(Palette.volt.opacity(stage.label == "Contratados" ? 1 : 0.55))
                                .frame(width: max(18, proxy.size.width * ratio))
                                .animation(.smooth(duration: 0.6), value: ratio)
                        }
                    }
                    .frame(height: 18)
                    Text("\(stage.value)")
                        .font(.system(size: 12, weight: .black))
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Documents

/// One document of a file, with its resolved state.
///
/// A document expires on a date, so both the state and the caption underneath it change on
/// their own — and they change *together*, which makes the row the smallest honest unit.
/// It registers that dependency itself so the file screen around it does not have to.
struct DocumentRow: View {
    let document: StaffDocument
    var action: (() -> Void)?

    var body: some View {
        TimeScope(.minute) { now in
            row(status: document.resolvedStatus(now: now), now: now)
        }
    }

    @ViewBuilder
    private func row(status: DocumentStatus, now: Date) -> some View {
        let content = HStack(spacing: 12) {
            Image(systemName: status.symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(status.tone)
                .frame(width: 28, height: 28)
                .background(status.tone.opacity(0.14), in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(document.kind.label)
                    .font(.system(.footnote, weight: .bold))
                    .multilineTextAlignment(.leading)
                Text(detail(now: now))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Text(status.label.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.6)
                .foregroundStyle(status.tone)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat(cornerRadius: 14)

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func detail(now: Date) -> String {
        if let days = document.daysToExpiry(now: now) {
            if days < 0 { return "Venció hace \(-days) días" }
            if days < HRRules.documentWarningDays { return "Vence en \(days) días" }
            return "Vigente · vence \(Fmt.dateShort(document.expiresAt ?? now))"
        }
        if let uploaded = document.uploadedAt {
            return "Cargado \(Fmt.dateShort(uploaded))\(document.versions.isEmpty ? "" : " · \(document.versions.count) versiones")"
        }
        return "Sin entregar"
    }
}

// MARK: - Rows

/// Compact person row reused by candidates, files and coverage lists.
struct PersonRow: View {
    let title: String
    let subtitle: String
    let initials: String
    let tone: Color
    var trailing: String?
    var trailingTone: Color = Palette.textMuted
    var isLive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(initials)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(tone)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceRaised, in: .circle)
                    .overlay { Circle().stroke(tone.opacity(0.5), lineWidth: 1.5) }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(.subheadline, weight: .bold))
                            .lineLimit(1)
                        if isLive {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Palette.volt)
                        }
                    }
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(trailingTone)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelFlat()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Score stepper

/// 1–5 rating used by the interview sheet, sized for thumbs.
struct ScoreStepper: View {
    let criterion: InterviewCriterion
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(criterion.label)
                    .font(.system(.footnote, weight: .bold))
                Text(criterion.hint)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        onChange(score)
                    } label: {
                        Text("\(score)")
                            .font(.system(.footnote, weight: .black))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(score <= value ? Palette.canvas : Palette.textMuted)
                            .background(
                                score <= value ? Palette.volt : Palette.surfaceRaised.opacity(0.8),
                                in: .rect(cornerRadius: 11)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(score <= value ? .clear : Palette.hairline, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .panelFlat()
    }
}

// MARK: - Big number

/// Headline figure with its meaning underneath. Used by capacity and settlement.
struct HeadlineFigure: View {
    let value: String
    let caption: String
    var tone: Color = Palette.volt
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tone)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            CapsLabel(text: caption)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Section navigation

/// Entry of a module index (Recursos Humanos, Mantenimiento).
struct ModuleLink<Destination: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    var badge: Int = 0
    var badgeTone: Color = Palette.amber
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Palette.volt)
                    .frame(width: 34, height: 34)
                    .background(Palette.volt.opacity(0.12), in: .rect(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, weight: .bold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(Palette.canvas)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeTone, in: .capsule)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelFlat()
        }
        .buttonStyle(.plain)
    }
}

/// Screen scaffold shared by every people / workshop sub-screen.
struct OfficeScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            SupervisionBackground()
            ScrollView {
                VStack(spacing: 14) {
                    content()
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.canvas, for: .navigationBar)
    }
}
