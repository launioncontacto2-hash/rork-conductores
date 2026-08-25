import SwiftUI
import UIKit

/// Shared pieces of the recruitment interface. Same muted palette as every other role:
/// sage is the accent and what is healthy, honey asks for attention, clay blocks, slate
/// is neutral. Recruitment reads a funnel, so the only extra language here is proportion.
nonisolated enum RecTone {
    static let accent = Palette.volt
    static let good = Palette.volt
    static let warn = Palette.amber
    static let bad = Palette.danger
    static let cool = Palette.info
    static let idle = Palette.textMuted
}

// MARK: - Tones

extension RecruitStage {
    var tone: Color {
        switch self {
        case .lead: Palette.info
        case .contacted, .prequalified: Palette.info
        case .interviewed, .documents: Palette.amber
        case .readyToHire: Palette.amber
        case .approved, .hired: Palette.volt
        case .lost: Palette.danger
        }
    }
}

extension ScreeningOutcome {
    var tone: Color {
        switch self {
        case .fit: Palette.volt
        case .review: Palette.amber
        case .unfit: Palette.danger
        }
    }
}

extension AppointmentStatus {
    var tone: Color {
        switch self {
        case .scheduled: Palette.info
        case .confirmed: Palette.volt
        case .rescheduled: Palette.amber
        case .attended: Palette.volt
        case .noShow: Palette.danger
        case .cancelled: Palette.textMuted
        }
    }
}

extension HiringVerdict {
    var tone: Color {
        switch self {
        case .approved: Palette.volt
        case .secondInterview: Palette.amber
        case .rejected: Palette.danger
        }
    }
}

extension InterviewSuggestion {
    var tone: Color {
        switch self {
        case .recommended: Palette.volt
        case .secondReview: Palette.amber
        case .notRecommended: Palette.danger
        }
    }
}

// MARK: - Background

/// Acquisition backdrop: the graphite canvas with a neutral pool at the top and a funnel
/// of converging lines, because everything in this module narrows from lead to driver.
struct RecruitmentBackground: View {
    var body: some View {
        ZStack {
            Palette.canvas
            RadialGradient(
                colors: [Color.white.opacity(0.034), .clear],
                center: UnitPoint(x: 0.5, y: -0.06),
                startRadius: 0,
                endRadius: 560
            )
            RadialGradient(
                colors: [Palette.volt.opacity(0.028), .clear],
                center: UnitPoint(x: -0.05, y: 1.02),
                startRadius: 0,
                endRadius: 460
            )
            FunnelGrid()
        }
        .ignoresSafeArea()
    }
}

private struct FunnelGrid: View {
    var body: some View {
        Canvas { context, size in
            var funnel = Path()
            let steps = 9
            for step in 0...steps {
                let ratio = CGFloat(step) / CGFloat(steps)
                let inset = size.width * 0.06 * ratio
                let y = size.height * ratio
                funnel.move(to: CGPoint(x: inset, y: y))
                funnel.addLine(to: CGPoint(x: size.width - inset, y: y))
            }
            context.stroke(funnel, with: .color(.white.opacity(0.02)), lineWidth: 1)

            var sides = Path()
            sides.move(to: CGPoint(x: 0, y: 0))
            sides.addLine(to: CGPoint(x: size.width * 0.06, y: size.height))
            sides.move(to: CGPoint(x: size.width, y: 0))
            sides.addLine(to: CGPoint(x: size.width * 0.94, y: size.height))
            context.stroke(sides, with: .color(Palette.volt.opacity(0.035)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Header

/// Identity of the recruitment desk. Each station has its own, so the header names the
/// station it belongs to instead of a coverage count.
struct RecruitHeader: View {
    let account: StaffAccount
    let station: Station?
    let vacancies: Int
    let alertCount: Int
    let onRegenerate: () -> Void
    var onOpenAlerts: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(RecTone.accent)
                    .frame(width: 42, height: 42)
                    .background(RecTone.accent.opacity(0.14), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(RecTone.accent.opacity(0.45), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.map { "RECLUTAMIENTO \($0.code)" } ?? "RECLUTAMIENTO")
                        .font(.system(.subheadline, weight: .black))
                        .tracking(0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(station.map { "\($0.name) · \(Fmt.firstName(account.name))" }
                        ?? "Sin estación asignada")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)

                if let onOpenAlerts {
                    Button(action: onOpenAlerts) {
                        Image(systemName: alertCount > 0 ? "bell.badge.fill" : "bell.fill")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(alertCount > 0 ? RecTone.warn : Palette.textMuted)
                            .frame(width: 32, height: 32)
                            .background(Palette.surfaceRaised, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Alertas de reclutamiento")
                }

                DemoClockButton()

                Menu {
                    Section(account.name) {
                        Text(account.employeeNumber)
                    }
                    Button("Regenerar base simulada", systemImage: "arrow.triangle.2.circlepath", action: onRegenerate)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(RecTone.accent)
                        .frame(width: 32, height: 32)
                }

                SessionMenuButton()
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(vacancies > 0 ? RecTone.warn : RecTone.good)
                        .frame(width: 7, height: 7)
                    Text(vacancies > 0 ? "\(vacancies) VACANTES ABIERTAS" : "COBERTURA COMPLETA")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.1)
                }
                .foregroundStyle(vacancies > 0 ? RecTone.warn : RecTone.good)

                Spacer(minLength: 0)

                // The only reading of the clock in the header, and it is a date: it turns
                // at midnight and at nothing else. The station line, the vacancy strip,
                // the bell, the menu and the session control never hear from the clock.
                TimeScope(.day) { now in
                    Text(Fmt.dateShort(now))
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                }
            }
        }
        .padding(14)
        .panel(cornerRadius: 22)
    }
}

/// Screen scaffold of every recruitment sub-screen pushed from an index.
struct RecruitScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RecruitmentBackground()
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

// MARK: - Ring

/// Compact coverage ring: one number, one meaning.
struct RecRing: View {
    let ratio: Double
    let headline: String
    let caption: String
    var tone: Color = RecTone.accent
    var size: CGFloat = 76

    var body: some View {
        let clamped = min(1, max(0, ratio))
        ZStack {
            Circle()
                .stroke(Palette.surfaceRaised, lineWidth: 9)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tone, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tone.opacity(0.45), radius: 7)
                .animation(.smooth(duration: 0.8), value: clamped)
            VStack(spacing: 0) {
                Text(headline)
                    .font(.system(size: size * 0.26, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(caption.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(size * 0.22)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Prospect row

/// One person in the funnel: who, for which station and block, and how long they wait.
///
/// The row keeps its own temporal freshness. One line of it follows the clock — the detail
/// caption and the colour it turns when a lead goes past its contact window — so that line
/// carries the scope and the caller hands over no `now`. A funnel of two hundred prospects
/// invalidates two hundred captions, never two hundred rows.
///
/// The cadence is `.minute` and not `.day` even though the caption sometimes counts days:
/// for a lead it reports minutes of waiting and crosses the service level at an arbitrary
/// hour. When two semantics share one leaf, the finer one governs.
struct ProspectRow: View {
    let prospect: Prospect
    var showStation: Bool = true
    let action: () -> Void

    private var station: Station? { StaffDirectory.station(id: prospect.stationId) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(prospect.initials)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(prospect.stage.tone)
                    .frame(width: 42, height: 42)
                    .background(Palette.surfaceRaised, in: .circle)
                    .overlay {
                        Circle().stroke(prospect.stage.tone.opacity(0.5), lineWidth: 1.5)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: prospect.source.symbol)
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Palette.canvas)
                            .padding(3)
                            .background(Palette.textMuted, in: .circle)
                            .offset(x: 3, y: 2)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(prospect.shortName)
                        .font(.system(.subheadline, weight: .bold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(prospect.requestedBlock.shortLabel)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Palette.textMuted)
                        if showStation, let station {
                            Text("· \(station.code)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.textMuted)
                        }
                        Text("· \(prospect.source.shortLabel)")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                    TimeScope(.minute) { now in
                        Text(detail(now: now))
                            .font(.system(size: 10))
                            .foregroundStyle(prospect.isOverdueContact(now: now) ? RecTone.bad : Palette.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    StatePill(text: prospect.stage.shortLabel, symbol: prospect.stage.symbol, tone: prospect.stage.tone, compact: true)
                    if let score = prospect.interviewScorePct {
                        Text("\(score)")
                            .font(.system(size: 11, weight: .black))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textMuted)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelFlat()
        }
        .buttonStyle(.plain)
    }
}

private extension ProspectRow {
    func detail(now: Date) -> String {
        if prospect.stage == .lead {
            let minutes = prospect.waitingMinutes(now: now)
            return minutes > RecruitRules.contactSlaMinutes
                ? "Sin contactar · \(Fmt.durationText(minutes)) de espera"
                : "Nuevo · \(Fmt.relative(prospect.createdAt, from: now))"
        }
        if prospect.stage == .lost, let reason = prospect.lossReason {
            return "Perdido · \(reason.label)"
        }
        if prospect.stage == .hired {
            return "Contratado en \(prospect.daysInProcess(now: now)) días"
        }
        return "\(prospect.daysInProcess(now: now)) días en proceso · \(prospect.experienceYears) años de experiencia"
    }
}

// MARK: - Funnel board

/// The pipeline drawn as proportional bars with the conversion between each pair.
struct FunnelBoard: View {
    let funnel: RecruitFunnel
    var highlight: RecruitStage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(funnel.stages.enumerated()), id: \.offset) { index, entry in
                let previous = index == 0 ? nil : funnel.stages[index - 1].value
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: entry.stage.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(entry.stage.tone)
                            .frame(width: 18)
                        Text(entry.stage.label)
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 96, alignment: .leading)
                        GeometryReader { proxy in
                            let base = Double(max(1, funnel.leads))
                            let ratio = min(1, Double(entry.value) / base)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.surfaceRaised)
                                Capsule()
                                    .fill(entry.stage == .hired ? Palette.volt : entry.stage.tone.opacity(0.55))
                                    .frame(width: max(16, proxy.size.width * ratio))
                                    .animation(.smooth(duration: 0.65), value: ratio)
                            }
                        }
                        .frame(height: 16)
                        Text("\(entry.value)")
                            .font(.system(size: 13, weight: .black))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                            .foregroundStyle(highlight == entry.stage ? Palette.volt : .primary)
                    }

                    if let previous, previous > 0 {
                        let drop = previous - entry.value
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .black))
                            Text("\(Int((Double(entry.value) / Double(previous) * 100).rounded())) % avanza · \(drop) se quedan")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Palette.textMuted)
                        .padding(.leading, 28)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Alerts

struct RecruitAlertCard: View {
    let alert: RecruitAlert
    var onOpen: (() -> Void)?
    var onReview: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: alert.kind.symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(alert.level.tone)
                    .frame(width: 30, height: 30)
                    .background(alert.level.tone.opacity(0.14), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.system(.subheadline, weight: .bold))
                        .multilineTextAlignment(.leading)
                    Text(alert.kind.label.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .tracking(1)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 4)
                LevelPill(level: alert.level, compact: true)
            }

            Text(alert.detail)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if let onOpen {
                    Button(alert.actionLabel, action: onOpen)
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(Palette.canvas)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(alert.level.tone, in: .capsule)
                }
                if let onReview {
                    Button("Revisada", action: onReview)
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface.opacity(0.92), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(alert.level.demandsAction ? alert.level.tone.opacity(0.5) : Palette.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Demand

/// One station: units, plantilla required, available drivers and the resulting vacancies.
///
/// Units, plantilla and coverage are all store facts. The single line that moves on its own
/// is the countdown to the next incorporation, and it counts days — so that line carries a
/// `.day` scope and the card takes no clock from its caller.
struct StationDemandCard: View {
    let demand: StationDemand
    var action: (() -> Void)?

    private var tone: Color {
        if demand.vacancies == 0 { return RecTone.good }
        return demand.coverageRatio >= 0.9 ? RecTone.warn : RecTone.bad
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(demand.station.name.uppercased())
                        .font(.system(.subheadline, weight: .black))
                        .tracking(0.5)
                    Text("\(demand.station.city) · \(demand.station.code)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(demand.vacancies)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tone)
                    Text("VACANTES")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1)
                        .foregroundStyle(Palette.textMuted)
                }
            }

            HStack(spacing: 8) {
                DemandFigure(value: "\(demand.activeVehicles)", caption: "Unidades")
                DemandFigure(value: "\(demand.requiredDrivers)", caption: "Requeridos")
                DemandFigure(value: "\(demand.availableDrivers)", caption: "Disponibles", tone: RecTone.cool)
                DemandFigure(value: "\(demand.coveragePct) %", caption: "Cobertura", tone: tone)
            }

            ProgressTrack(
                value: Double(demand.availableDrivers),
                goal: Double(max(1, demand.requiredDrivers)),
                tone: tone
            )
            .frame(height: 8)

            if demand.incomingVehicles > 0 {
                TimeScope(.day) { now in
                    if let days = demand.daysToNextIncorporation(now: now) {
                        Text("\(demand.incomingVehicles) unidades por incorporarse · \(demand.futureDrivers) conductores adicionales · la más próxima opera en \(max(0, days)) días")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(RecTone.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(cornerRadius: 22)

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

struct DemandFigure: View {
    let value: String
    let caption: String
    var tone: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tone)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption.uppercased())
                .font(.system(size: 8, weight: .black))
                .tracking(0.8)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .panelFlat(cornerRadius: 13)
    }
}

// MARK: - Appointments

/// One appointment of the desk agenda.
///
/// Nothing here follows the clock: the hour, the day number, the person, the kind and the
/// status are all read straight off the record. It used to declare a `now` that no line of
/// its body ever read — an inert parameter that nonetheless made every mounted row a
/// subscriber of `RecruitmentStore.now`.
struct AppointmentRow: View {
    let appointment: Appointment
    var action: (() -> Void)?

    private var station: Station? { StaffDirectory.station(id: appointment.stationId) }

    var body: some View {
        let content = HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(Fmt.clock(appointment.date))
                    .font(.system(.footnote, weight: .black))
                    .monospacedDigit()
                Text(Fmt.dayNumber(appointment.date))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
            .frame(width: 54)
            .padding(.vertical, 8)
            .background(Palette.surfaceRaised, in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(appointment.prospectName)
                    .font(.system(.subheadline, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: appointment.kind.symbol)
                        .font(.system(size: 9, weight: .bold))
                    Text(appointment.kind.label)
                        .font(.system(size: 10, weight: .bold))
                    if let station {
                        Text("· \(station.code)")
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(Palette.textMuted)
                Text(appointment.owner)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            StatePill(
                text: appointment.status.label,
                symbol: appointment.status.symbol,
                tone: appointment.status.tone,
                compact: true
            )
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat()

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Campaigns

/// One campaign with what it spent and what it produced.
///
/// Only the subtitle moves on its own, and only while the campaign is still active: it
/// counts the days left to its end date. A count of days is a calendar fact, so the leaf
/// listens by the day.
struct CampaignCard: View {
    let performance: CampaignPerformance

    private var campaign: RecruitCampaign { performance.campaign }
    private var station: Station? { StaffDirectory.station(id: campaign.stationId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: campaign.platform.symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(campaign.isActive ? RecTone.accent : Palette.textMuted)
                    .frame(width: 32, height: 32)
                    .background(
                        (campaign.isActive ? RecTone.accent : Palette.textMuted).opacity(0.14),
                        in: .rect(cornerRadius: 11)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(campaign.name)
                        .font(.system(.subheadline, weight: .bold))
                        .multilineTextAlignment(.leading)
                    Group {
                        if campaign.isActive {
                            TimeScope(.day) { now in
                                Text("\(station?.code ?? "—") · activa, termina en \(max(0, campaign.daysLeft(now: now))) días")
                            }
                        } else {
                            Text("\(station?.code ?? "—") · finalizada")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                DemandFigure(value: Fmt.mxn(campaign.spentMxn), caption: "Inversión")
                DemandFigure(value: "\(performance.leads)", caption: "Leads", tone: RecTone.cool)
                DemandFigure(value: "\(performance.hires)", caption: "Contratados", tone: RecTone.good)
            }

            HStack(spacing: 8) {
                DemandFigure(
                    value: performance.costPerLead > 0 ? Fmt.mxn(performance.costPerLead) : "—",
                    caption: "Costo por lead"
                )
                DemandFigure(
                    value: performance.costPerHire > 0 ? Fmt.mxn(performance.costPerHire) : "—",
                    caption: "Costo por contratación",
                    tone: performance.hires > 0 ? RecTone.warn : Palette.textMuted
                )
                DemandFigure(
                    value: "\(Int((performance.conversion * 100).rounded())) %",
                    caption: "Conversión"
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                ProgressTrack(
                    value: Double(campaign.spentMxn),
                    goal: Double(max(1, campaign.budgetMxn)),
                    tone: campaign.spentRatio > 0.9 ? RecTone.warn : RecTone.accent
                )
                .frame(height: 7)
                Text("Presupuesto \(Fmt.mxn(campaign.budgetMxn)) · ejercido \(Int((campaign.spentRatio * 100).rounded())) %")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(cornerRadius: 22)
    }
}

// MARK: - Small pieces

/// One metric line: what it is, what it is worth and what it means.
struct MetricLine: View {
    let label: String
    let value: String
    var detail: String?
    var tone: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(.footnote, weight: .bold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tone)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat(cornerRadius: 14)
    }
}

/// Conversion between two steps of the funnel, written as a sentence, not a number alone.
struct ConversionRow: View {
    let title: String
    let ratio: Double
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(.footnote, weight: .bold))
                Spacer(minLength: 6)
                Text("\(Int((ratio * 100).rounded())) %")
                    .font(.system(.footnote, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(ratio >= 0.5 ? RecTone.good : (ratio >= 0.25 ? RecTone.warn : RecTone.bad))
            }
            ProgressTrack(
                value: min(1, max(0, ratio)),
                goal: 1,
                tone: ratio >= 0.5 ? RecTone.good : (ratio >= 0.25 ? RecTone.warn : RecTone.bad)
            )
            .frame(height: 7)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(12)
        .panelFlat()
    }
}

/// Empty state shared by the recruitment lists.
struct RecEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Palette.textMuted)
            Text(title)
                .font(.system(.subheadline, weight: .bold))
            Text(message)
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .panelFlat()
    }
}
