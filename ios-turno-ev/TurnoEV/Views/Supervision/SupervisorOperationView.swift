import SwiftUI
import UIKit

/// Operación: four cards, read in seconds. How the roster stands, how the goals are
/// going, how the fleet is, and what needs the supervisor right now.
///
/// Nothing here repeats what the detail screens already say: every card is a summary that
/// opens the module that resolves it.
struct SupervisorOperationView: View {
    let supervision: SupervisionStore
    /// Back office of the same station: people, banking and workshop exceptions.
    let office: StationOfficeStore
    /// Engine that recovers the capacity an absence takes away.
    let resolution: AbsenceResolutionStore
    let header: SupervisorHeader
    let onOpenDrivers: (DriverFilter) -> Void
    let onOpenVehicles: (FleetVehicleState?) -> Void
    let onOpenAlerts: (Bool) -> Void
    let onOpenTicket: (String) -> Void
    let onNewIncident: () -> Void
    let onOpenPeople: () -> Void
    let onOpenWorkshop: () -> Void

    @State private var areGoalsPresented: Bool = false
    @State private var isResolutionPresented: Bool = false

    private var metrics: StationMetrics { supervision.metrics }

    var body: some View {
        ZStack {
            SupervisionBackground()

            ScrollView {
                VStack(spacing: 12) {
                    header
                    attendanceCard
                    goalsCard
                    vehiclesCard
                    resolutionCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $areGoalsPresented) {
            SupervisorGoalDetailView(supervision: supervision)
        }
        .sheet(isPresented: $isResolutionPresented) {
            AbsenceResolutionDetailView(resolution: resolution, supervision: supervision)
        }
    }

    // MARK: - 1 · Asistencia

    private var attendanceCard: some View {
        OperationCard(
            title: "Asistencia",
            symbol: "person.3.fill",
            caption: nil,
            action: { onOpenDrivers(metrics.absentDrivers > 0 ? .absent : .all) }
        ) {
            HStack(spacing: 8) {
                StateCount(
                    value: metrics.presentDrivers,
                    label: "presentes",
                    tone: SupTone.good,
                    symbol: "checkmark.circle.fill"
                )
                StateCount(
                    value: metrics.absentDrivers,
                    label: "ausentes",
                    tone: SupTone.bad,
                    symbol: "person.fill.xmark",
                    isAlarming: metrics.absentDrivers > 0
                )
                StateCount(
                    value: metrics.lateDrivers,
                    label: "demorados",
                    tone: SupTone.warn,
                    symbol: "clock.fill",
                    isAlarming: metrics.lateDrivers > 0
                )
            }
        }
    }

    // MARK: - 2 · Metas

    private var goalsCard: some View {
        let progress = supervision.goalProgress
        return OperationCard(
            title: "Metas",
            symbol: "target",
            caption: nil,
            action: { areGoalsPresented = true }
        ) {
            HStack(spacing: 8) {
                GoalDial(label: "Día", ratio: progress.dayRatio)
                GoalDial(label: "Semana", ratio: progress.weekRatio)
                GoalDial(label: "Mes", ratio: progress.monthRatio)
            }
        }
    }

    // MARK: - 3 · Vehículos

    private var vehiclesCard: some View {
        let unavailable = metrics.outOfService + metrics.inMaintenance
        return OperationCard(
            title: "Vehículos",
            symbol: "car.2.fill",
            caption: nil,
            action: { onOpenVehicles(unavailable > 0 ? .outOfService : .operating) }
        ) {
            HStack(spacing: 8) {
                StateCount(
                    value: metrics.activeVehicles,
                    label: "en operación",
                    tone: SupTone.good,
                    symbol: "car.side.fill"
                )
                StateCount(
                    value: unavailable,
                    label: "no disponibles",
                    tone: SupTone.bad,
                    symbol: "wrench.and.screwdriver.fill",
                    isAlarming: unavailable > 0
                )
                StateCount(
                    value: supervision.availableReplacementUnits,
                    label: "reemplazo",
                    tone: SupTone.cool,
                    symbol: "arrow.triangle.2.circlepath"
                )
            }
        }
    }

    // MARK: - 4 · Resolver ausencias

    /// The engine reports here. In the ordinary path the supervisor only reads what was
    /// already solved; he is asked for something only when the rules could not close it.
    private var resolutionCard: some View {
        let headline = resolution.headline

        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            isResolutionPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: headline.symbol)
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(headline.tint)
                    Text("Resolver ausencias")
                        .font(.system(.subheadline, weight: .black))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(headline.lines) { line in
                        HStack(spacing: 8) {
                            Image(systemName: line.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(line.tint)
                                .frame(width: 16)
                            Text(line.text)
                                .font(.system(.footnote, weight: line.isLead ? .bold : .regular))
                                .foregroundStyle(line.isLead ? .primary : Palette.textMuted)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .overlay {
                if headline.isEscalated {
                    RoundedRectangle(cornerRadius: 22).stroke(SupTone.warn.opacity(0.5), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(PressableCardStyle())
    }
}

// MARK: - Card shell

/// Shared frame of the three summary cards: title, icon and one row of states. The whole
/// surface is the button — the supervisor should never have to aim.
private struct OperationCard<Content: View>: View {
    let title: String
    let symbol: String
    var caption: String?
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(SupTone.accent)
                    Text(title)
                        .font(.system(.subheadline, weight: .black))
                    if let caption {
                        Text(caption)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }

                content
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
        }
        .buttonStyle(PressableCardStyle())
    }
}

// MARK: - Pieces

/// One state of a card: a colored dot, the number and a two-word label.
private struct StateCount: View {
    let value: Int
    let label: String
    let tone: Color
    let symbol: String
    var isAlarming: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(value == 0 && !isAlarming ? Palette.textMuted.opacity(0.5) : tone)
                    .frame(width: 7, height: 7)
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }

            Text("\(value)")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value == 0 && !isAlarming ? .primary : tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .panelFlat(cornerRadius: 16)
    }
}

/// Compact ring for a goal: the percentage and nothing else.
private struct GoalDial: View {
    let label: String
    let ratio: Double

    private var tone: Color {
        if ratio >= RegionalRules.goalFloor { return SupTone.good }
        if ratio >= 0.6 { return SupTone.warn }
        return SupTone.bad
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Palette.surfaceRaised, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, ratio)))
                    .stroke(tone, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 58, height: 58)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .panelFlat(cornerRadius: 16)
    }
}

// MARK: - Goal detail

/// The goal board that used to sit on Operación. It is the detail behind the Metas card:
/// the fixed number of the shift, its arithmetic and what the empty seats cost.
struct SupervisorGoalDetailView: View {
    let supervision: SupervisionStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        let board = supervision.goalBoard
                        let progress = supervision.goalProgress

                        StationGoalPanel(
                            board: board,
                            caption: "Meta de facturación de tu turno",
                            accent: SupTone.accent
                        )

                        VStack(spacing: 9) {
                            GoalLine(
                                label: "Día",
                                earnings: progress.dayEarningsMxn,
                                goal: progress.dayGoalMxn,
                                ratio: progress.dayRatio
                            )
                            GoalLine(
                                label: "Semana",
                                earnings: progress.weekEarningsMxn,
                                goal: progress.weekGoalMxn,
                                ratio: progress.weekRatio
                            )
                            GoalLine(
                                label: "Mes",
                                earnings: progress.monthEarningsMxn,
                                goal: progress.monthGoalMxn,
                                ratio: progress.monthRatio
                            )
                        }
                        .padding(15)
                        .panel()

                        if board.uncoveredSeats > 0 {
                            NoticeBanner(
                                symbol: "person.fill.xmark",
                                title: "\(board.uncoveredSeats) unidades sin conductor",
                                message: "La meta sigue siendo \(Fmt.mxn(board.shiftGoalMxn)). Cada conductor en calle carga \(Fmt.mxn(board.overloadMxn)) extra.",
                                tone: .amber
                            )
                        } else if board.gapMxn > 0 {
                            NoticeBanner(
                                symbol: "target",
                                title: "Faltan \(Fmt.mxn(board.gapMxn)) para la meta del turno",
                                message: "Con \(board.presentDrivers) conductores en calle son \(Fmt.mxn(board.shareMxn)) por cabeza.",
                                tone: .info
                            )
                        } else {
                            NoticeBanner(
                                symbol: "checkmark.seal.fill",
                                title: "Meta del turno cubierta",
                                message: "La estación alcanzó sus \(Fmt.mxn(board.shiftGoalMxn)) \(board.groupLabel).",
                                tone: .volt
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Metas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationContentInteraction(.scrolls)
    }
}

private struct GoalLine: View {
    let label: String
    let earnings: Int
    let goal: Int
    let ratio: Double

    private var tone: Color {
        ratio >= RegionalRules.goalFloor ? SupTone.good : ratio >= 0.6 ? SupTone.warn : SupTone.bad
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(.footnote, weight: .bold))
                Spacer()
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.system(.footnote, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(tone)
            }
            ProgressTrack(value: Double(earnings), goal: Double(max(1, goal)), tone: tone)
            Text("\(Fmt.mxn(earnings)) de \(Fmt.mxn(goal))")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
        }
    }
}

// MARK: - Bay strip

/// One tick per bay of the station, colored by the state of its unit.
struct StationBayStrip: View {
    let vehicles: [StationVehicle]

    private var colors: [Color] {
        vehicles.map(\.state.tone)
    }

    var body: some View {
        let palette = colors
        Canvas { context, size in
            guard !palette.isEmpty else { return }
            let gap: CGFloat = 1.5
            let width = max(1.5, (size.width - gap * CGFloat(palette.count - 1)) / CGFloat(palette.count))
            for (index, color) in palette.enumerated() {
                let x = CGFloat(index) * (width + gap)
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color.opacity(0.9)))
            }
        }
        .frame(height: 26)
        .accessibilityLabel("Estado de las \(vehicles.count) bahías de la estación")
    }
}

// MARK: - Rows shared with other modules

/// Compact pending handover row with its progress of validations.
struct HandoverRow: View {
    let ticket: HandoverTicket
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: ticket.kind.symbol)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(ticket.kind == .delivery ? SupTone.accent : SupTone.cool)
                    .frame(width: 38, height: 38)
                    .background(
                        (ticket.kind == .delivery ? SupTone.accent : SupTone.cool).opacity(0.14),
                        in: .rect(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(ticket.vehicleNumber)
                            .font(.system(.subheadline, weight: .black))
                        if ticket.isLiveSession {
                            StatePill(text: "En vivo", symbol: "antenna.radiowaves.left.and.right", tone: SupTone.good, compact: true)
                        }
                    }
                    Text("\(ticket.kind.shortLabel) · \(ticket.driverName)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(ticket.completedChecks)/\(ticket.requiredChecks.count) validaciones")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ticket.isReadyToApprove ? SupTone.good : SupTone.accent)
                        if ticket.qrCodeRead == nil {
                            Text("· sin QR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(SupTone.bad)
                        }
                        if ticket.hasOdometerGap {
                            Text("· km desfasado")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(SupTone.bad)
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(Fmt.clock(ticket.createdAt))
                        .font(.system(.caption, weight: .bold))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .padding(13)
            .panelFlat()
        }
        .buttonStyle(.plain)
    }
}

/// Automatic alert row used by the dashboard and the alerts module.
///
/// The age of the alert is the only thing here that moves on its own, and `RelativeTime`
/// carries it, so the row takes no clock from its caller.
struct AlertRow: View {
    let alert: StationAlert
    var onResolve: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: alert.kind.symbol)
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(alert.severity.tone)
                    Text(alert.kind.label.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .tracking(1)
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: 0)
                    StatePill(text: alert.severity.label, symbol: "waveform.path.ecg", tone: alert.severity.tone, compact: true)
                }

                Text(alert.title)
                    .font(.system(.subheadline, weight: .bold))
                    .multilineTextAlignment(.leading)

                Text(alert.detail)
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.leading)

                HStack {
                    RelativeTime(date: alert.createdAt)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: 0)
                    if let onResolve {
                        Button("Marcar atendida") {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            onResolve()
                        }
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(SupTone.accent)
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(alert.severity.tone.opacity(0.08), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).stroke(alert.severity.tone.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
