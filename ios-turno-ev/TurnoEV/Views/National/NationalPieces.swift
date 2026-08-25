import SwiftUI
import UIKit

/// Shared pieces of the national direction interface. Same muted palette as every other
/// role: sage is the accent and what is healthy, honey asks for attention, clay blocks,
/// slate is neutral. Direction reads more numbers than anyone, so nothing else is tinted.
nonisolated enum NatTone {
    static let accent = Palette.volt
    static let good = Palette.volt
    static let warn = Palette.amber
    static let bad = Palette.danger
    static let cool = Palette.info
    static let idle = Palette.textMuted
}

/// Country backdrop: the same graphite canvas with a wide neutral horizon and a faint
/// latitude grid, so the national screens feel like a map room instead of a dashboard.
struct NationalBackground: View {
    var body: some View {
        ZStack {
            Palette.canvas
            RadialGradient(
                colors: [Color.white.opacity(0.032), .clear],
                center: UnitPoint(x: 0.5, y: -0.08),
                startRadius: 0,
                endRadius: 620
            )
            RadialGradient(
                colors: [Palette.info.opacity(0.03), .clear],
                center: UnitPoint(x: 1.08, y: 1.04),
                startRadius: 0,
                endRadius: 520
            )
            LatitudeGrid()
        }
        .ignoresSafeArea()
    }
}

private struct LatitudeGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += 52
            }
            context.stroke(path, with: .color(.white.opacity(0.016)), lineWidth: 1)

            var meridians = Path()
            var x: CGFloat = 0
            while x <= size.width {
                meridians.move(to: CGPoint(x: x, y: 0))
                meridians.addLine(to: CGPoint(x: x + size.height * 0.18, y: size.height))
                x += 78
            }
            context.stroke(meridians, with: .color(.white.opacity(0.012)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Header

/// National identity: the whole country in one line, plus the exception counter.
struct NationalHeader: View {
    let account: StaffAccount
    let regionCount: Int
    let stationCount: Int
    let alertCount: Int
    let onRegenerate: () -> Void
    var onOpenAlerts: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "building.2.fill")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(NatTone.accent)
                    .frame(width: 42, height: 42)
                    .background(NatTone.accent.opacity(0.14), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(NatTone.accent.opacity(0.45), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("DIRECCIÓN NACIONAL")
                        .font(.system(.subheadline, weight: .black))
                        .tracking(0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(regionCount) regiones · \(stationCount) estaciones · red completa")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }

                Spacer(minLength: 0)

                if let onOpenAlerts {
                    Button(action: onOpenAlerts) {
                        Image(systemName: alertCount > 0 ? "bell.badge.fill" : "bell.fill")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(alertCount > 0 ? NatTone.warn : Palette.textMuted)
                            .frame(width: 32, height: 32)
                            .background(Palette.surfaceRaised, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Excepciones de la red")
                }

                DemoClockButton()

                Menu {
                    Section(account.name) {
                        Text(account.employeeNumber)
                    }
                    Button("Regenerar red simulada", systemImage: "arrow.triangle.2.circlepath", action: onRegenerate)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(NatTone.accent)
                        .frame(width: 32, height: 32)
                }

                SessionMenuButton()
            }

            HStack(spacing: 8) {
                // Two readings of the clock at two different cadences, each in its own
                // leaf. The block in force turns on a shift boundary, so it listens by the
                // minute; the date beside it turns at midnight and listens by the day.
                // Splitting them is what stops a passing minute from redrawing a date.
                HStack(spacing: 6) {
                    Circle()
                        .fill(NatTone.good)
                        .frame(width: 7, height: 7)
                    TimeScope(.minute) { now in
                        Text("BLOQUE \(RegionalRules.observedSlot(now: now).label.uppercased()) EN CURSO")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.1)
                    }
                }
                .foregroundStyle(NatTone.good)

                if alertCount > 0 {
                    Text("\(alertCount) excepciones")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(NatTone.warn)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(NatTone.warn.opacity(0.16), in: .capsule)
                }

                Spacer(minLength: 0)

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

/// Screen scaffold of every national sub-screen pushed from a module index.
struct NationalScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            NationalBackground()
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

// MARK: - Region card

/// One region of the country: money, fleet, plantilla and who answers for it.
struct RegionCard: View {
    let rank: Int
    let region: RegionRollup
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
                        .foregroundStyle(rank == 1 ? NatTone.accent : Palette.textMuted)
                        .frame(width: 28, height: 28)
                        .background(
                            (rank == 1 ? NatTone.accent : Color.white).opacity(0.1),
                            in: .rect(cornerRadius: 9)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(region.name)
                                .font(.system(.subheadline, weight: .black))
                                .lineLimit(1)
                            if region.hasLiveStation {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(NatTone.good)
                            }
                        }
                        Text("\(region.stationCount) estaciones · \(region.managementLabel)")
                            .font(.system(size: 10))
                            .foregroundStyle(region.isFullyManaged ? Palette.textMuted : NatTone.bad)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                    HealthBadge(health: region.health, compact: true)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        CapsLabel(text: "Facturación del turno")
                        Text(Fmt.mxn(region.earningsMxn))
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(region.goalRatio >= NationalRules.regionGoalFloor ? NatTone.good : NatTone.bad)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("\(Int(region.goalRatio * 100))% de \(Fmt.mxn(region.goalMxn))")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer(minLength: 0)
                    SparkBars(values: region.weekSeries, tone: NatTone.accent)
                        .frame(width: 84)
                }

                ProgressTrack(value: region.goalRatio, goal: 1, tone: NatTone.accent)
                    .frame(height: 7)

                HStack(spacing: 7) {
                    InfoChip(
                        symbol: "car.2.fill",
                        text: "\(region.operatingVehicles)/\(region.fleetSize)",
                        tone: NatTone.cool
                    )
                    InfoChip(
                        symbol: "person.3.fill",
                        text: "\(region.payrollSize)/\(region.requiredDrivers)",
                        tone: region.driverDeficit == 0 ? NatTone.good : NatTone.warn
                    )
                    if region.pendingApprovals > 0 {
                        InfoChip(
                            symbol: "checkmark.seal.fill",
                            text: "\(region.pendingApprovals)",
                            tone: region.agingApprovals > 0 ? NatTone.bad : Palette.textMuted
                        )
                    }
                    if region.criticalIncidents > 0 {
                        InfoChip(symbol: "exclamationmark.octagon.fill", text: "\(region.criticalIncidents)", tone: NatTone.bad)
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

// MARK: - Alerts

/// One exception of the country. Direction opens it or marks it reviewed; it never edits.
///
/// Nothing here follows the clock: the title, the detail and the level are all decided by
/// the rollup that raised the alert. It used to declare a `now` that no line of its body
/// ever read — an inert parameter that nonetheless made every mounted card a subscriber of
/// `NationalStore.now`.
struct NationalAlertCard: View {
    let alert: NationalAlert
    var onOpen: (() -> Void)?
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: alert.kind.symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(alert.level.tone)
                    .frame(width: 32, height: 32)
                    .background(alert.level.tone.opacity(0.14), in: .rect(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.system(.subheadline, weight: .bold))
                        .multilineTextAlignment(.leading)
                    Text(alert.kind.label)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(alert.level.tone)
                }
                Spacer(minLength: 4)
                LevelPill(level: alert.level, compact: true)
            }

            Text(alert.detail)
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.leading)

            HStack(spacing: 12) {
                if let onOpen {
                    Button("Abrir módulo", action: onOpen)
                        .font(.system(.caption, weight: .black))
                        .foregroundStyle(NatTone.accent)
                }
                Spacer(minLength: 0)
                Button("Marcar revisada", action: onReview)
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat()
    }
}

// MARK: - Expansion

/// A station that does not exist yet, with the hiring it already demands.
///
/// The clock decides one number here — the days left to open — and that number decides the
/// risk, which in turn tints the pill, the progress bar and the hiring chip. Those are
/// spread across the card, so the card is the smallest honest unit and it owns the scope
/// itself. `.day`, because a countdown of days is a calendar fact: the card is evaluated
/// once per logical midnight, not once a minute.
struct ProjectCard: View {
    let project: StationProject
    let action: () -> Void

    var body: some View {
        TimeScope(.day) { now in
            card(risk: project.risk(now: now, averageHiringDays: NationalRules.averageHiringDays), now: now)
        }
    }

    private func card(risk: OpsAlertLevel, now: Date) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Image(systemName: project.stage.symbol)
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(project.stage == .operating ? NatTone.good : NatTone.accent)
                        .frame(width: 32, height: 32)
                        .background(NatTone.accent.opacity(0.12), in: .rect(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.system(.subheadline, weight: .black))
                            .lineLimit(1)
                        Text("\(project.code) · \(project.city) · \(project.stage.label)")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if project.stage != .operating {
                        StatePill(
                            text: "\(project.daysToLaunch(now: now)) días",
                            symbol: "calendar",
                            tone: risk.demandsAction ? risk.tone : Palette.textMuted,
                            compact: true
                        )
                    }
                }

                // The whole thesis of the module: units bought are drivers owed.
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(project.targetVehicles)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(NatTone.cool)
                        CapsLabel(text: "unidades")
                    }
                    Image(systemName: "multiply")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Palette.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(HRRules.driversPerVehicle)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textMuted)
                        CapsLabel(text: "turnos")
                    }
                    Image(systemName: "equal")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Palette.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(project.requiredDrivers)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(project.driverDeficit == 0 ? NatTone.good : NatTone.warn)
                        CapsLabel(text: "conductores")
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }

                ProgressTrack(
                    value: Double(project.hiredDrivers),
                    goal: Double(max(1, project.requiredDrivers)),
                    tone: project.driverDeficit == 0 ? NatTone.good : risk.tone
                )
                .frame(height: 7)

                HStack(spacing: 7) {
                    InfoChip(
                        symbol: "person.badge.plus.fill",
                        text: "\(project.hiredDrivers)/\(project.requiredDrivers)",
                        tone: project.driverDeficit == 0 ? NatTone.good : risk.tone
                    )
                    InfoChip(symbol: "banknote.fill", text: Fmt.mxn(project.investmentMxn), tone: Palette.textMuted)
                    Spacer(minLength: 0)
                    Text(project.stage.label.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.7)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .padding(14)
            .panel(cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Directory

extension StaffRole {
    /// Colour of the role inside the directory. Everything shares the lime accent;
    /// only the symbol changes, because the network has one identity.
    var directoryTone: Color {
        switch self {
        case .national, .manager: NatTone.accent
        case .supervisor: NatTone.cool
        case .recruiter: NatTone.cool
        case .maintenance: Palette.textMuted
        case .driver: Palette.textMuted
        case .lab: Palette.amber
        }
    }
}

/// One credential of the network, with the scope it can reach.
struct CredentialRow: View {
    let credential: NetworkCredential
    var isGenerated: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: credential.role.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(credential.role.directoryTone)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceRaised, in: .circle)
                    .overlay {
                        Circle().stroke(credential.role.directoryTone.opacity(0.45), lineWidth: 1.5)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(credential.name)
                            .font(.system(.subheadline, weight: .bold))
                            .lineLimit(1)
                        if isGenerated {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(NatTone.accent)
                        }
                    }
                    Text("\(credential.role.shortLabel) · \(credential.scopeLabel)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if credential.status == .suspended {
                    StatePill(text: "Suspendida", symbol: "pause.circle.fill", tone: NatTone.bad, compact: true)
                } else if let slot = credential.slot, credential.role != .manager {
                    Text(slot.label.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(Palette.textMuted)
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

// MARK: - Policy

/// One rule of the network with its current value and a control to move it.
struct PolicyRow: View {
    let title: String
    let detail: String
    let value: String
    var isEditable: Bool = true
    var tone: Color = NatTone.accent
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.footnote, weight: .bold))
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.subheadline, weight: .black))
                .monospacedDigit()
                .foregroundStyle(isEditable ? tone : Palette.textMuted)
            if isEditable {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat()

        if isEditable, let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// Compact key figure used by the national grids.
struct NatFigure: View {
    let value: String
    let caption: String
    var detail: String?
    var tone: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            CapsLabel(text: caption)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tone)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .panelFlat()
    }
}
