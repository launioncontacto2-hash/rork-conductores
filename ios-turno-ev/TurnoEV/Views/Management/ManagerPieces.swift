import SwiftUI
import UIKit

/// Shared building blocks of the station management interface. Same muted palette as the
/// driver app: sage accent over graphite, honey for attention, clay for blocking.
nonisolated enum MgTone {
    static let accent = Palette.volt
    static let good = Palette.volt
    static let warn = Palette.amber
    static let bad = Palette.danger
    static let cool = Palette.info
    static let premium = Palette.info
}

/// Office backdrop: graphite with a neutral pool of light and faint ledger rules.
struct ManagementBackground: View {
    var body: some View {
        ZStack {
            Palette.canvas
            RadialGradient(
                colors: [Color.white.opacity(0.034), .clear],
                center: UnitPoint(x: 0.5, y: -0.06),
                startRadius: 0,
                endRadius: 540
            )
            RadialGradient(
                colors: [Palette.volt.opacity(0.03), .clear],
                center: UnitPoint(x: -0.05, y: 1.05),
                startRadius: 0,
                endRadius: 460
            )
            LedgerRules()
        }
        .ignoresSafeArea()
    }
}

private struct LedgerRules: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += 30
            }
            context.stroke(path, with: .color(.white.opacity(0.018)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Header

/// Station identity plus the manager's split-block clock. A manager runs one station,
/// so the header names that station and never a region.
struct ManagerHeader: View {
    let account: StaffAccount
    let station: Station
    let fleetSize: Int
    let now: Date
    let pendingCount: Int
    let onRegenerate: () -> Void

    private var block: RegionalRules.DutyBlock { RegionalRules.dutyBlock(now: now) }
    private var progress: Double { RegionalRules.blockProgress(now: now) }
    private var isOnDuty: Bool { block != .off }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(MgTone.accent)
                    .frame(width: 42, height: 42)
                    .background(MgTone.accent.opacity(0.14), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(MgTone.accent.opacity(0.45), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name.uppercased())
                        .font(.system(.subheadline, weight: .black))
                        .tracking(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(station.code) · \(station.city) · \(fleetSize) unidades")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }

                Spacer(minLength: 0)

                DemoClockButton()

                Menu {
                    Section(account.name) {
                        Text(account.employeeNumber)
                    }
                    Button("Regenerar estación simulada", systemImage: "arrow.triangle.2.circlepath", action: onRegenerate)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(MgTone.accent)
                        .frame(width: 32, height: 32)
                }

                SessionMenuButton()
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isOnDuty ? MgTone.good : Palette.textMuted)
                        .frame(width: 7, height: 7)
                    Text(isOnDuty ? block.label.uppercased() : "FUERA DE BLOQUE")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.1)
                }
                .foregroundStyle(isOnDuty ? MgTone.good : Palette.textMuted)

                if pendingCount > 0 {
                    Text("\(pendingCount) por autorizar")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MgTone.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(MgTone.accent.opacity(0.16), in: .capsule)
                }

                Spacer(minLength: 0)

                Text(block.rangeLabel)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                    .monospacedDigit()
            }

            ProgressTrack(value: progress, goal: 1, tone: MgTone.accent)
                .frame(height: 6)
        }
        .padding(14)
        .panel(cornerRadius: 22)
    }
}

// MARK: - Health

extension StationHealth {
    var tone: Color {
        switch self {
        case .strong: MgTone.good
        case .steady: MgTone.cool
        case .watch: MgTone.accent
        case .critical: MgTone.bad
        }
    }
}

struct HealthBadge: View {
    let health: StationHealth
    var compact: Bool = false

    var body: some View {
        StatePill(text: health.label, symbol: health.symbol, tone: health.tone, compact: compact)
    }
}

// MARK: - Ring meter

/// Circular meter used for the station goal, tinted by the interface accent.
struct MgRing: View {
    let ratio: Double
    let headline: String
    let caption: String
    var tone: Color = MgTone.accent
    var size: CGFloat = 168

    var body: some View {
        let clamped = min(1, max(0, ratio))
        ZStack {
            Circle().stroke(Palette.surfaceRaised, lineWidth: 13)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tone, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tone.opacity(0.5), radius: 9)
                .animation(.smooth(duration: 0.9), value: clamped)
            VStack(spacing: 3) {
                Text(headline)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tone)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                CapsLabel(text: caption)
            }
            .padding(26)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Meters and charts

/// Horizontal meter with a label, used to compare stations at a glance.
struct MeterRow: View {
    let label: String
    let value: String
    let ratio: Double
    var tone: Color = MgTone.accent
    var marker: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(.caption, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(.caption, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(tone)
            }
            ProgressTrack(value: min(1.15, max(0, ratio)), goal: 1.15, tone: tone, marker: marker)
                .frame(height: 8)
        }
    }
}

/// Monday to Sunday billing of the region against its daily goal.
struct WeekBarsChart: View {
    let points: [RegionDayPoint]
    var tone: Color = MgTone.accent

    private var peak: Int {
        max(1, points.map { max($0.amountMxn, $0.goalMxn) }.max() ?? 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(points) { point in
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Palette.surfaceRaised.opacity(0.85))
                            .frame(height: 106)

                        // Goal marker of the day, so weekends read differently.
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.white.opacity(0.28))
                            .frame(height: 1.5)
                            .offset(y: -106 * CGFloat(Double(point.goalMxn) / Double(peak)))

                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: point.isFuture
                                        ? [Palette.hairline, Palette.hairline]
                                        : [barTone(point).opacity(0.55), barTone(point)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(3, 106 * CGFloat(Double(point.amountMxn) / Double(peak))))
                            .animation(.smooth(duration: 0.8), value: point.amountMxn)
                    }
                    .frame(height: 106)

                    Text(Fmt.dayShort(point.date))
                        .font(.system(size: 9, weight: point.isToday ? .black : .semibold))
                        .foregroundStyle(point.isToday ? tone : Palette.textMuted)
                }
            }
        }
    }

    private func barTone(_ point: RegionDayPoint) -> Color {
        if point.ratio >= 1 { return MgTone.good }
        if point.ratio >= RegionalRules.goalFloor { return tone }
        return MgTone.bad
    }
}

/// Compact 7-day sparkline shown inside each station card.
struct SparkBars: View {
    let values: [Int]
    var tone: Color = MgTone.accent

    private var peak: Int { max(1, values.max() ?? 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(value == 0 ? Palette.hairline : tone.opacity(0.85))
                    .frame(height: max(2, 26 * CGFloat(Double(value) / Double(peak))))
            }
        }
        .frame(height: 26)
    }
}

// MARK: - Station card

/// Ranked station card of the regional board.
struct StationRankCard: View {
    let rank: Int
    let card: StationScorecard
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("\(rank)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(rank == 1 ? MgTone.accent : Palette.textMuted)
                        .frame(width: 28, height: 28)
                        .background(
                            (rank == 1 ? MgTone.accent : Color.white).opacity(0.1),
                            in: .rect(cornerRadius: 9)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(card.name)
                                .font(.system(.subheadline, weight: .black))
                                .lineLimit(1)
                            if card.isLive {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(MgTone.good)
                            }
                        }
                        Text("\(card.code) · \(card.city) · turno \(card.slot.label.lowercased())")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                    HealthBadge(health: card.health, compact: true)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        CapsLabel(text: "Facturación del día")
                        Text(Fmt.mxn(card.earningsMxn))
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(card.goalRatio >= RegionalRules.goalFloor ? MgTone.good : MgTone.bad)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("\(Int(card.goalRatio * 100))% de \(Fmt.mxn(card.goalMxn))")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer(minLength: 0)
                    SparkBars(values: card.weekEarnings, tone: MgTone.accent)
                        .frame(width: 84)
                }

                ProgressTrack(value: card.goalRatio, goal: 1, tone: MgTone.accent)
                    .frame(height: 7)

                HStack(spacing: 7) {
                    InfoChip(
                        symbol: "person.3.fill",
                        text: "\(card.presentDrivers)/\(card.rosterSize)",
                        tone: card.attendanceRatio >= 0.94 ? MgTone.good : MgTone.accent
                    )
                    InfoChip(
                        symbol: "car.2.fill",
                        text: "\(card.operatingVehicles)/\(card.fleetSize)",
                        tone: MgTone.cool
                    )
                    if card.criticalIncidents > 0 {
                        InfoChip(
                            symbol: "exclamationmark.octagon.fill",
                            text: "\(card.criticalIncidents)",
                            tone: MgTone.bad
                        )
                    }
                    if card.inMaintenance > 0 {
                        InfoChip(
                            symbol: "wrench.and.screwdriver.fill",
                            text: "\(card.inMaintenance)",
                            tone: Palette.textMuted
                        )
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .padding(14)
            .panel(cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Request row

extension RegionalRequestKind {
    var tone: Color {
        switch self {
        case .hiring: MgTone.cool
        case .credit: MgTone.premium
        case .retirement: MgTone.bad
        }
    }
}

/// One pending decision as it appears in the authorization inbox.
struct RequestRow: View {
    let request: RegionalRequest
    let now: Date
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: request.kind.symbol)
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(request.kind.tone)
                        .frame(width: 32, height: 32)
                        .background(request.kind.tone.opacity(0.14), in: .rect(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.subject)
                            .font(.system(.subheadline, weight: .black))
                            .lineLimit(1)
                        Text("\(request.kind.label) · \(request.stationCode)")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 3) {
                        if let amount = request.amountMxn {
                            Text(Fmt.mxn(amount))
                                .font(.system(.subheadline, weight: .black))
                                .monospacedDigit()
                                .foregroundStyle(request.kind.tone)
                        }
                        Text(Fmt.relative(request.createdAt, from: now))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(request.isAging(now: now) ? MgTone.bad : Palette.textMuted)
                    }
                }

                Text(request.detail)
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 7) {
                    InfoChip(
                        symbol: "checklist",
                        text: "\(request.completedChecks)/\(request.requiredChecks.count)",
                        tone: request.isReadyToAuthorize ? MgTone.good : Palette.textMuted
                    )
                    InfoChip(symbol: "person.badge.shield.checkmark", text: request.requestedByRole.shortLabel, tone: MgTone.cool)
                    if request.isLiveSession {
                        InfoChip(symbol: "antenna.radiowaves.left.and.right", text: "En vivo", tone: MgTone.good)
                    }
                    if request.isAging(now: now) {
                        InfoChip(symbol: "hourglass", text: "\(request.ageHours(now: now)) h", tone: MgTone.bad)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .padding(13)
            .panelFlat()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Alert row

struct RegionalAlertRow: View {
    let alert: RegionalAlert
    let now: Date
    var onOpen: (() -> Void)?
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: alert.kind.symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(alert.severity.tone)
                    .frame(width: 30, height: 30)
                    .background(alert.severity.tone.opacity(0.14), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.system(.subheadline, weight: .bold))
                        .multilineTextAlignment(.leading)
                    Text(alert.kind.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(alert.severity.tone)
                }
                Spacer(minLength: 0)
                Text(Fmt.relative(alert.createdAt, from: now))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
            }

            Text(alert.detail)
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.leading)

            HStack(spacing: 10) {
                if let onOpen {
                    Button("Abrir", action: onOpen)
                        .font(.system(.caption, weight: .black))
                        .foregroundStyle(MgTone.accent)
                }
                Spacer(minLength: 0)
                Button("Marcar revisada", action: onResolve)
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(13)
        .panelFlat()
    }
}

// MARK: - Staff rows

struct SupervisorRow: View {
    let card: SupervisorScorecard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Text(card.initials)
                    .font(.system(.caption, weight: .black))
                    .foregroundStyle(card.slot == .morning ? MgTone.accent : MgTone.premium)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceRaised, in: .circle)
                    .overlay {
                        Circle().stroke(
                            (card.slot == .morning ? MgTone.accent : MgTone.premium).opacity(0.55),
                            lineWidth: 1.5
                        )
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.name)
                            .font(.system(.subheadline, weight: .bold))
                            .lineLimit(1)
                        if card.isLive {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(MgTone.good)
                        }
                    }
                    Text("\(card.stationCode) · \(card.slot.label) · \(card.employeeNumber)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if card.isBacklogged {
                    StatePill(text: "Saturado", symbol: "exclamationmark.triangle.fill", tone: MgTone.bad, compact: true)
                }
            }

            HStack(spacing: 7) {
                InfoChip(symbol: "person.3.fill", text: "\(card.driversManaged)", tone: MgTone.cool)
                InfoChip(symbol: "checkmark.seal.fill", text: "\(card.approvalsToday)", tone: MgTone.good)
                InfoChip(
                    symbol: "hand.raised.fill",
                    text: "\(card.pendingHandovers)",
                    tone: card.pendingHandovers > 6 ? MgTone.bad : Palette.textMuted
                )
                InfoChip(
                    symbol: "timer",
                    text: "\(card.avgResponseMinutes) min",
                    tone: card.avgResponseMinutes >= 14 ? MgTone.bad : Palette.textMuted
                )
                Spacer(minLength: 0)
                Text("\(Int(card.punctualityPct))%")
                    .font(.system(size: 11, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(card.punctualityPct >= 90 ? MgTone.good : MgTone.accent)
            }
        }
        .padding(13)
        .panelFlat()
    }
}

/// One person of the station's plantilla with their direct line. Tapping the green
/// key opens the phone dialer with the number already loaded: the manager confirms
/// and the call is placed, without leaving the app to look for a contact.
struct StationContactRow: View {
    let contact: StationContact

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: contact.desk.symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Palette.neutral)
                .frame(width: 36, height: 36)
                .background(Palette.neutral.opacity(0.12), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(.subheadline, weight: .bold))
                    .lineLimit(1)
                Text("\(contact.desk.label) · \(contact.duty)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
                Text("\(contact.employeeNumber) · \(contact.phone)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textMuted.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let digits = contact.dialablePhone, let url = URL(string: "tel://\(digits)") {
                Link(destination: url) {
                    VStack(spacing: 2) {
                        Image(systemName: "phone.fill")
                            .font(.system(.subheadline, weight: .black))
                        Text("Llamar")
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.4)
                    }
                    .foregroundStyle(Palette.canvas)
                    .frame(width: 62, height: 46)
                    .background(MgTone.accent, in: .rect(cornerRadius: 13))
                }
                .simultaneousGesture(TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                })
            } else {
                Text("Sin línea")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Palette.textMuted)
                    .frame(width: 62, height: 46)
                    .background(Palette.surfaceRaised.opacity(0.6), in: .rect(cornerRadius: 13))
            }
        }
        .padding(12)
        .panelFlat()
    }
}

/// Read-only staff row for the maintenance technicians of a station.
struct StaffLineRow: View {
    let name: String
    let detail: String
    let symbol: String
    var tone: Color = Palette.textMuted

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(tone)
                .frame(width: 32, height: 32)
                .background(tone.opacity(0.13), in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.subheadline, weight: .bold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .panelFlat()
    }
}
