import SwiftUI
import UIKit

/// Big statistic block used across the operational screens.
struct StatTile: View {
    enum Tone {
        case neutral, volt, amber, danger, info

        var color: Color {
            switch self {
            case .neutral: .primary
            case .volt: Palette.volt
            case .amber: Palette.amber
            case .danger: Palette.danger
            case .info: Palette.info
            }
        }
    }

    let label: String
    let value: String
    var hint: String?
    var tone: Tone = .neutral
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CapsLabel(text: label)
                Spacer(minLength: 4)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            Text(value)
                .font(.system(.title2, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tone.color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panelFlat()
    }
}

/// Narrow reading block: three of these fit across a phone without wrapping the label.
struct ReadingTile: View {
    let label: String
    let value: String
    var hint: String?
    var tone: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 22, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 12)
        .panelFlat(cornerRadius: 16)
    }
}

struct BatteryPill: View {
    let level: Int

    private var tone: Color {
        if level > 70 { return Palette.volt }
        if level > 40 { return Palette.amber }
        return Palette.danger
    }

    private var symbol: String {
        if level > 70 { return "battery.100percent" }
        if level > 40 { return "battery.50percent" }
        return "battery.25percent"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text("\(level)%")
                .monospacedDigit()
        }
        .font(.system(.subheadline, weight: .bold))
        .foregroundStyle(tone)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.surfaceRaised, in: .capsule)
        .overlay { Capsule().stroke(Palette.hairline, lineWidth: 1) }
    }
}

struct ProgressTrack: View {
    let value: Double
    let goal: Double
    var tone: Color = Palette.volt
    var marker: Double?

    var body: some View {
        GeometryReader { proxy in
            let ratio = goal > 0 ? min(1, max(0, value / goal)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceRaised)
                Capsule()
                    .fill(tone)
                    .frame(width: proxy.size.width * ratio)
                    .animation(.smooth(duration: 0.7), value: ratio)
                if let marker, goal > 0 {
                    let markerRatio = min(1, max(0, marker / goal))
                    Rectangle()
                        .fill(.white.opacity(0.75))
                        .frame(width: 2)
                        .offset(x: proxy.size.width * markerRatio)
                }
            }
        }
        .frame(height: 12)
    }
}

/// Circular gauge for the daily money goal.
struct RingGauge: View {
    let value: Double
    let goal: Double
    let headline: String
    let caption: String

    var body: some View {
        let ratio = goal > 0 ? min(1, max(0, value / goal)) : 0
        ZStack {
            Circle()
                .stroke(Palette.surfaceRaised, lineWidth: 14)
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(Palette.volt, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Palette.volt.opacity(0.5), radius: 8)
                .animation(.smooth(duration: 0.9), value: ratio)
            VStack(spacing: 4) {
                Text(headline)
                    .font(.system(.title, weight: .black))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                CapsLabel(text: caption)
            }
            .padding(28)
        }
        .frame(width: 176, height: 176)
    }
}

/// Primary full-width action, sized for use with gloves on.
struct BigButton: View {
    enum Tone {
        case volt, outline, danger
    }

    let title: String
    var symbol: String?
    var tone: Tone = .volt
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(.body, weight: .bold))
                }
                Text(title)
                    .font(.system(.body, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(foreground)
            .background(background, in: .rect(cornerRadius: 18))
            .overlay {
                if tone == .outline {
                    RoundedRectangle(cornerRadius: 18).stroke(Palette.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private var foreground: Color {
        switch tone {
        case .volt: Palette.canvas
        case .outline: .primary
        case .danger: .white
        }
    }

    private var background: Color {
        switch tone {
        case .volt: Palette.volt
        case .outline: Palette.surfaceRaised.opacity(0.8)
        case .danger: Palette.danger
        }
    }
}

/// Inline banner used for late starts, pending inspections and payback windows.
struct NoticeBanner: View {
    enum Tone {
        case volt, amber, info, danger

        var color: Color {
            switch self {
            case .volt: Palette.volt
            case .amber: Palette.amber
            case .info: Palette.info
            case .danger: Palette.danger
            }
        }
    }

    let symbol: String
    let title: String
    var message: String?
    var tone: Tone = .amber

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(tone.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, weight: .bold))
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tone.color.opacity(0.1), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).stroke(tone.color.opacity(0.4), lineWidth: 1)
        }
    }
}

/// The fixed billing goal of a station, stated the same way for every role: authorized
/// units by the driver goal of the day. Management, supervision and drivers all read
/// this panel, so nobody chases a different number.
struct StationGoalPanel: View {
    let board: StationGoalBoard
    /// Line that explains who is reading it: "tu estación", "tu turno", "tu parte".
    var caption: String
    var accent: Color = Palette.volt
    /// Drivers see the goal of the whole shift but act on their own share.
    var showsShare: Bool = true

    private var isOnTrack: Bool { board.ratio >= RegionalRules.goalFloor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    CapsLabel(text: caption)
                    Text(Fmt.mxn(board.shiftGoalMxn))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("\(board.formulaLabel) · turno \(board.slot.label.lowercased())")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(board.ratio * 100))%")
                        .font(.system(.title3, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(isOnTrack ? Palette.volt : Palette.amber)
                    Text(Fmt.mxn(board.earningsMxn))
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textMuted)
                    Text("facturado")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textMuted)
                }
            }

            ProgressTrack(
                value: Double(board.earningsMxn),
                goal: Double(board.shiftGoalMxn),
                tone: isOnTrack ? accent : Palette.amber
            )
            .frame(height: 10)

            HStack(spacing: 10) {
                GoalFigure(
                    label: "Entre semana",
                    value: Fmt.mxn(board.weekdayShiftGoalMxn),
                    hint: "\(Fmt.mxn(ShiftRules.goals(for: .weekday).dailyMxn)) por unidad",
                    isCurrent: board.group == .weekday,
                    accent: accent
                )
                GoalFigure(
                    label: "Fin de semana",
                    value: Fmt.mxn(board.weekendShiftGoalMxn),
                    hint: "\(Fmt.mxn(ShiftRules.goals(for: .weekend).dailyMxn)) por unidad",
                    isCurrent: board.group == .weekend,
                    accent: accent
                )
            }

            if showsShare {
                Divider().overlay(Palette.hairline)
                HStack(spacing: 10) {
                    StatTile(
                        label: "Falta hoy",
                        value: Fmt.mxn(board.gapMxn),
                        hint: board.gapMxn == 0 ? "Meta del turno cubierta" : "Para cerrar el turno",
                        tone: board.gapMxn == 0 ? .volt : .amber
                    )
                    StatTile(
                        label: "Meta de la semana",
                        value: Fmt.mxn(board.weekGoalMxn),
                        hint: "5 días entre semana + 2 de fin de semana",
                        tone: .neutral
                    )
                }
            }
        }
        .padding(16)
        .panel()
    }
}

/// One side of the weekday/weekend pair inside the goal panel.
private struct GoalFigure: View {
    let label: String
    let value: String
    let hint: String
    let isCurrent: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .textCase(.uppercase)
                    .kerning(0.7)
                    .foregroundStyle(isCurrent ? accent : Palette.textMuted)
                if isCurrent {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                }
            }
            Text(value)
                .font(.system(.subheadline, weight: .black))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Palette.text : Palette.neutral)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(hint)
                .font(.system(size: 9))
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            isCurrent ? accent.opacity(0.08) : Palette.surfaceRaised.opacity(0.5),
            in: .rect(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isCurrent ? accent.opacity(0.35) : Palette.hairline, lineWidth: 1)
        }
    }
}

/// Numeric capture field used for odometer and battery readings.
struct BigNumberField: View {
    let title: String
    let symbol: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                CapsLabel(text: title)
            }
            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(.title, weight: .black))
                .monospacedDigit()
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .panelFlat()
        }
    }
}

/// Account control present in every interface. It closes the session and returns to the
/// Face ID access screen, where a driver or supervisor credential can be identified again.
struct SessionMenuButton: View {
    @Environment(FleetStore.self) private var store
    @Environment(LabStore.self) private var lab

    @State private var isSigningOut: Bool = false
    @State private var isUnlinking: Bool = false
    @State private var isEnvironmentPresented: Bool = false

    private var canSwitch: Bool { EnvironmentControl.canSwitchEnvironment(account: store.currentAccount) }

    var body: some View {
        Group {
            if let account = store.currentAccount {
                Menu {
                    Section(account.name) {
                        Text("\(account.role.label) · \(account.employeeNumber)")
                    }
                    Section("Entorno") {
                        Text(lab.mode.label)
                        if canSwitch {
                            Button("Cambiar entorno", systemImage: "arrow.triangle.2.circlepath") {
                                isEnvironmentPresented = true
                            }
                        }
                    }
                    Button("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        isSigningOut = true
                    }
                    Button("Desvincular este dispositivo", systemImage: "faceid") {
                        isUnlinking = true
                    }
                } label: {
                    Text(account.initials)
                        .font(.system(.caption, weight: .black))
                        .foregroundStyle(account.role.accent)
                        .frame(width: 32, height: 32)
                        .background(Palette.surfaceRaised, in: .circle)
                        .overlay { Circle().stroke(account.role.accent.opacity(0.55), lineWidth: 1.5) }
                        .overlay(alignment: .topTrailing) {
                            // The simulation is never silent: whoever is inside it sees it.
                            if EnvironmentControl.showsTestBadge(mode: lab.mode) {
                                Circle()
                                    .fill(Palette.amber)
                                    .frame(width: 9, height: 9)
                                    .overlay { Circle().stroke(Palette.canvas, lineWidth: 1.5) }
                                    .offset(x: 1, y: -1)
                            }
                        }
                }
                .accessibilityLabel("Cuenta, entorno y cierre de sesión")
            }
        }
        .sheet(isPresented: $isEnvironmentPresented) {
            EnvironmentSheet()
        }
        .confirmationDialog(
            "¿Cerrar sesión?",
            isPresented: $isSigningOut,
            titleVisibility: .visible
        ) {
            Button("Cerrar sesión", role: .destructive) { store.signOut() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Volverás a la pantalla de acceso con Face ID para entrar como conductor, supervisor u otro rol.")
        }
        .confirmationDialog(
            "¿Desvincular el dispositivo?",
            isPresented: $isUnlinking,
            titleVisibility: .visible
        ) {
            Button("Desvincular", role: .destructive) { store.forgetDevice() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borra la credencial ligada a Face ID: el siguiente acceso pedirá correo y contraseña.")
        }
    }
}

/// The clock of every interface, and the only door into the simulation.
///
/// One button, two destinations, decided by the environment it is standing in:
/// production opens the environment switch, so test mode can be turned on from the very
/// screen being tested; test mode opens the clock controller. Neither of them ever
/// requires walking into the laboratory.
struct DemoClockButton: View {
    @Environment(FleetStore.self) private var store
    @Environment(LabStore.self) private var lab

    @State private var isClockPresented: Bool = false
    @State private var isEnvironmentPresented: Bool = false

    private var isTest: Bool { EnvironmentControl.showsTestBadge(mode: lab.mode) }

    /// Turning the simulation on happens *from* production, so this must not depend on
    /// the environment. It is what keeps the button alive on a production screen.
    private var canSwitchEnvironment: Bool {
        EnvironmentControl.canSwitchEnvironment(account: store.currentAccount)
    }

    private var canControlClock: Bool {
        EnvironmentControl.canControlClock(account: store.currentAccount, mode: lab.mode)
    }

    /// An unauthorised device still reads the hour; it simply cannot open anything.
    private var isInteractive: Bool { canSwitchEnvironment }

    private var badge: String? {
        guard canSwitchEnvironment else { return nil }
        return isTest ? "PRUEBA" : "PROD"
    }

    private var tint: Color { isTest ? Palette.amber : Palette.textMuted }

    var body: some View {
        Button {
            guard isInteractive else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if canControlClock {
                isClockPresented = true
            } else {
                // Production: the tap is the way into the simulation.
                isEnvironmentPresented = true
            }
        } label: {
            // The reading — and everything that has to keep pace with it — lives inside a
            // leaf of its own. The hour is read there and nowhere else, so a repaint of the
            // chip cannot reach the toolbar, the screen behind it, or this button.
            DemoClockChip(isTest: isTest, badge: badge)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isClockPresented) {
            SimulationClockSheet()
        }
        .sheet(isPresented: $isEnvironmentPresented) {
            EnvironmentSheet()
        }
    }
}

/// The visible face of `DemoClockButton`, isolated on purpose.
///
/// It exists so the hour is read at the very tip of the view tree. Its heartbeat is a
/// private `@State` that nothing else observes, so an advancing clock repaints these few
/// glyphs and stops there — it does not invalidate the toolbar item, the navigation bar,
/// or the screen hosting them, which is what an enclosing `TimelineView` used to do.
private struct DemoClockChip: View {
    let isTest: Bool
    let badge: String?

    @Environment(FleetStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    /// Heartbeat. Its only job is to invalidate *this* view; the value is never displayed.
    @State private var pulse: Date = .now

    /// Observable mirror of the clock, so the chip follows a pause or a pace change made
    /// on another device. Read here, at the leaf, instead of on the hosting screen.
    private var signal: ClockSignal { ClockSignal.shared }

    /// Local repaint cadence, matched to the simulated pace so acceleration stays visible.
    /// A paused or production clock still refreshes, just at the pace it actually needs.
    private var cadence: Double {
        guard isTest, !signal.speed.isPaused else { return 30 }
        return max(0.1, 1.0 / Double(signal.speed.rawValue))
    }

    /// Restarting key: the loop is rebuilt when the pace changes and torn down when the
    /// app leaves the foreground, so nothing ticks behind a locked screen.
    private var tickerKey: String { "\(cadence)-\(scenePhase == .active)" }

    /// Seconds are shown throughout the simulation: a boundary test is decided in them.
    private var reading: String {
        isTest ? Fmt.clockSeconds(store.now) : Fmt.clock(store.now)
    }

    /// Colour of the shared-clock dot. Only meaningful inside the simulation.
    private var syncTint: Color {
        switch SharedClockSync.shared.status {
        case .synced: return Palette.volt
        case .connecting: return Palette.info
        case .offline: return Palette.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isTest ? "clock.badge.exclamationmark" : "clock")
            Text(reading)
                .monospacedDigit()
            if let badge {
                Text(badge)
                    .font(.system(size: 8, weight: .black))
            }
            // Whether a second device is standing on this same hour.
            if isTest {
                Circle()
                    .fill(syncTint)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(.caption, weight: .semibold))
        .foregroundStyle(isTest ? Palette.amber : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.surfaceRaised, in: .capsule)
        .overlay {
            Capsule().stroke(isTest ? Palette.amber.opacity(0.5) : Palette.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isTest
                ? "Reloj de prueba, \(reading). Abrir controles de tiempo."
                : "Producción, \(reading). Abrir selector de entorno."
        )
        .task(id: tickerKey) {
            guard scenePhase == .active else { return }
            let interval = cadence
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                pulse = AppClock.realNow()
            }
        }
    }
}
