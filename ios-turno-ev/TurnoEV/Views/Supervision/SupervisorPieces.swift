import SwiftUI
import UIKit

/// Shared building blocks of the supervisor interface. One palette across the whole
/// product, all of it muted: sage is the accent and "healthy", honey asks for
/// attention, clay blocks, slate is neutral or closed. These screens are dense, so
/// anything not being decided right now stays grey.
nonisolated enum SupTone {
    static let accent = Palette.volt
    static let good = Palette.volt
    static let warn = Palette.amber
    static let bad = Palette.danger
    static let cool = Palette.info
    static let idle = Palette.textMuted
}

/// Control-room backdrop: graphite with a neutral pool of light and a service grid.
struct SupervisionBackground: View {
    var body: some View {
        ZStack {
            Palette.canvas
            RadialGradient(
                colors: [Color.white.opacity(0.035), .clear],
                center: UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [Palette.volt.opacity(0.03), .clear],
                center: UnitPoint(x: 1.05, y: 1.04),
                startRadius: 0,
                endRadius: 420
            )
            SupervisionGrid()
        }
        .ignoresSafeArea()
    }
}

private struct SupervisionGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 38
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(.white.opacity(0.016)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Header

/// The one header of the whole supervisor interface. Every window uses this same
/// component and only changes its title, so the top of the app is always the same three
/// answers: where I am, which shift I supervise, and what is asking for attention.
///
/// The station is no longer printed on every screen — it lives one tap away behind the
/// avatar. Nothing about the data changed: this is only how it is shown.
struct SupervisorHeader: View {
    let account: StaffAccount
    let station: Station
    let slot: ShiftSlot
    let pendingCount: Int
    /// Everything the exception board is holding right now.
    var alertCount: Int = 0
    let onSignOut: () -> Void
    let onRegenerate: () -> Void
    var onOpenAlerts: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    /// Name of the window this header is sitting on.
    var title: String = ""
    /// Set on secondary screens: the left slot becomes a back chevron.
    var onBack: (() -> Void)?

    @State private var isIdentityPresented: Bool = false

    /// Same header, named for the window that is showing it.
    func titled(_ title: String) -> SupervisorHeader {
        var copy = self
        copy.title = title
        return copy
    }

    /// Secondary screen: the menu is replaced by a way back.
    func titled(_ title: String, onBack: @escaping () -> Void) -> SupervisorHeader {
        var copy = self
        copy.title = title
        copy.onBack = onBack
        return copy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 10) {
                leading

                Text(title.uppercased())
                    .font(.system(.subheadline, weight: .black))
                    .tracking(0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4)

                // The clock of the simulation lives here, one tap from any window. In
                // production it is inert and takes no space beyond the hour.
                DemoClockButton()

                if let onOpenAlerts {
                    bell(action: onOpenAlerts)
                }

                avatar
            }

            // Which shift I supervise, and nothing else.
            Text("\(slot.label) · \(slot.rangeLabel)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textMuted)
                .monospacedDigit()
                .padding(.leading, 38)
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
        .sheet(isPresented: $isIdentityPresented) {
            SupervisorIdentityPanel(
                account: account,
                station: station,
                slot: slot,
                onRegenerate: onRegenerate,
                onSignOut: onSignOut
            )
        }
    }

    @ViewBuilder
    private var leading: some View {
        if let onBack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(.footnote, weight: .black))
                    .foregroundStyle(SupTone.accent)
                    .frame(width: 30, height: 30)
                    .background(Palette.surfaceRaised, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Volver")
        } else {
            Menu {
                if let onOpenHistory {
                    Button("Historial de la estación", systemImage: "list.clipboard.fill", action: onOpenHistory)
                }
                if let onOpenAlerts {
                    Button("Alertas de la estación", systemImage: "bell.fill", action: onOpenAlerts)
                }
                Button("Datos de la estación", systemImage: "building.2.fill") {
                    isIdentityPresented = true
                }
                Divider()
                Button("Regenerar estación simulada", systemImage: "arrow.triangle.2.circlepath", action: onRegenerate)
                Button("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: onSignOut)
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(.footnote, weight: .black))
                    .foregroundStyle(Palette.textMuted)
                    .frame(width: 30, height: 30)
                    .background(Palette.surfaceRaised, in: .circle)
            }
            .accessibilityLabel("Menú del supervisor")
        }
    }

    private func bell(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: alertCount > 0 ? "bell.badge.fill" : "bell.fill")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(alertCount > 0 ? SupTone.warn : Palette.textMuted)
                .frame(width: 30, height: 30)
                .background(Palette.surfaceRaised, in: .circle)
                .overlay(alignment: .topTrailing) {
                    if alertCount > 0 {
                        Text("\(min(99, alertCount))")
                            .font(.system(size: 8, weight: .black))
                            .monospacedDigit()
                            .foregroundStyle(Palette.canvas)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(SupTone.warn, in: .capsule)
                            .offset(x: 3, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(alertCount > 0 ? "\(alertCount) alertas de la estación" : "Alertas de la estación")
    }

    private var avatar: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            isIdentityPresented = true
        } label: {
            Text(account.initials)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(SupTone.accent)
                .frame(width: 30, height: 30)
                .background(Palette.surfaceRaised, in: .circle)
                .overlay { Circle().stroke(SupTone.accent.opacity(0.5), lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Perfil de \(account.name)")
    }
}

/// The station left the top of every screen, so this is where it can be checked. It reads
/// the credential and the station the supervisor already belongs to — nothing new is
/// stored for it.
private struct SupervisorIdentityPanel: View {
    let account: StaffAccount
    let station: Station
    let slot: ShiftSlot
    let onRegenerate: () -> Void
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsCredential: Bool = false

    var body: some View {
        ZStack {
            SupervisionBackground()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(account.initials)
                        .font(.system(.subheadline, weight: .black))
                        .foregroundStyle(SupTone.accent)
                        .frame(width: 44, height: 44)
                        .background(Palette.surfaceRaised, in: .circle)
                        .overlay { Circle().stroke(SupTone.accent.opacity(0.5), lineWidth: 1.5) }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Supervisor")
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(Palette.textMuted)
                        Text(account.name)
                            .font(.system(.headline, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    DemoClockButton()
                }

                Divider().overlay(Palette.hairline)

                row(caption: "Estación", value: station.name, detail: "\(station.code) · \(station.city)", symbol: "building.2.fill")
                row(caption: "Turno", value: slot.label, detail: slot.rangeLabel, symbol: "clock.fill")

                if showsCredential {
                    row(
                        caption: "Credencial",
                        value: account.employeeNumber,
                        detail: account.email,
                        symbol: "person.text.rectangle.fill"
                    )
                }

                Button(showsCredential ? "Ocultar perfil" : "Ver perfil") {
                    withAnimation(.smooth(duration: 0.25)) { showsCredential.toggle() }
                }
                .font(.system(.footnote, weight: .black))
                .foregroundStyle(SupTone.accent)
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button("Regenerar estación") {
                        onRegenerate()
                        dismiss()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button("Cerrar sesión") {
                        onSignOut()
                        dismiss()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SupTone.bad)
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .presentationDetents([.height(showsCredential ? 400 : 330)])
        .presentationBackground(Palette.canvas)
    }

    private func row(caption: String, value: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(SupTone.accent)
                .frame(width: 32, height: 32)
                .background(SupTone.accent.opacity(0.12), in: .rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 1) {
                Text(caption.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(Palette.textMuted)
                Text(value)
                    .font(.system(.subheadline, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Metric card

/// Big interactive dashboard tile. Tapping it drills into the matching module.
struct MetricCard: View {
    let label: String
    let value: String
    let symbol: String
    var detail: String?
    var tone: Color = SupTone.accent
    var isAlarming: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(tone)
                        .frame(width: 30, height: 30)
                        .background(tone.opacity(0.14), in: .rect(cornerRadius: 10))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }

                Text(value)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tone)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .shadow(color: isAlarming ? tone.opacity(0.55) : .clear, radius: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(.caption, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.surface.opacity(0.92), in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(isAlarming ? tone.opacity(0.55) : Palette.hairline, lineWidth: isAlarming ? 1.5 : 1)
            }
        }
        .buttonStyle(PressableCardStyle())
    }
}

/// Press feedback that never fights the scroll view: the style reports the press
/// state, so a drag that becomes a scroll simply cancels it instead of latching.
struct PressableCardStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Small pieces

struct StatePill: View {
    let text: String
    let symbol: String
    let tone: Color
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 9 : 11, weight: .bold))
            Text(text.uppercased())
                .font(.system(size: compact ? 9 : 10, weight: .black))
                .tracking(0.8)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 4 : 5)
        .background(tone.opacity(0.14), in: .capsule)
        .overlay { Capsule().stroke(tone.opacity(0.4), lineWidth: 1) }
    }
}

extension StationDriverState {
    var tone: Color {
        switch self {
        case .operating: SupTone.good
        case .late: SupTone.warn
        case .absent: SupTone.bad
        case .awaitingHandover: SupTone.cool
        case .finished: SupTone.idle
        }
    }
}

extension FleetVehicleState {
    var tone: Color {
        switch self {
        case .available: SupTone.good
        case .operating: SupTone.cool
        case .maintenance: SupTone.warn
        case .outOfService: SupTone.bad
        }
    }
}

extension MaintenanceState {
    var tone: Color {
        switch self {
        case .ok: SupTone.good
        case .dueSoon: SupTone.warn
        case .overdue: SupTone.bad
        case .inWorkshop: SupTone.cool
        }
    }
}

extension StationAsset.State {
    var tone: Color {
        switch self {
        case .operational: SupTone.good
        case .degraded: SupTone.warn
        case .down: SupTone.bad
        }
    }
}

extension IncidentSeverity {
    var tone: Color {
        switch self {
        case .low: SupTone.idle
        case .medium: SupTone.cool
        case .high: SupTone.warn
        case .critical: SupTone.bad
        }
    }
}

extension DriverCreditState {
    var tone: Color {
        switch self {
        case .none: SupTone.idle
        case .current: SupTone.good
        case .behind: SupTone.bad
        case .delivered: SupTone.cool
        }
    }

    var symbol: String {
        switch self {
        case .none: "creditcard"
        case .current: "creditcard.fill"
        case .behind: "creditcard.trianglebadge.exclamationmark"
        case .delivered: "key.fill"
        }
    }
}

/// Driver portrait when the record has one, monogram otherwise.
struct DriverAvatar: View {
    let driver: StationDriver
    var size: CGFloat = 54

    var body: some View {
        Color(Palette.surfaceRaised)
            .frame(width: size, height: size)
            .overlay {
                if let asset = driver.photoAsset {
                    Image(asset)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    Text(driver.initials)
                        .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                        .foregroundStyle(driver.state.tone)
                }
            }
            .clipShape(.circle)
            .overlay {
                Circle().stroke(driver.state.tone.opacity(0.65), lineWidth: 2)
            }
            .overlay(alignment: .bottomTrailing) {
                if driver.isLiveSession {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: size * 0.2, weight: .black))
                        .foregroundStyle(Palette.canvas)
                        .padding(4)
                        .background(SupTone.good, in: .circle)
                        .offset(x: 2, y: 2)
                }
            }
    }
}

/// Horizontal filter selector reused by drivers, fleet and the regional inbox.
struct FilterScroller<T: Hashable & Identifiable>: View {
    let items: [T]
    let title: (T) -> String
    let symbol: (T) -> String
    let count: (T) -> Int
    @Binding var selection: T
    /// Accent of the interface using the scroller.
    var accent: Color = SupTone.accent

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let isSelected = item == selection
                    Button {
                        selection = item
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: symbol(item))
                                .font(.system(size: 11, weight: .bold))
                            Text(title(item))
                                .font(.system(.footnote, weight: .bold))
                            Text("\(count(item))")
                                .font(.system(size: 10, weight: .black))
                                .monospacedDigit()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    (isSelected ? Palette.canvas.opacity(0.25) : Palette.surfaceRaised),
                                    in: .capsule
                                )
                        }
                        .foregroundStyle(isSelected ? Palette.canvas : Palette.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(isSelected ? accent : Palette.surface.opacity(0.85), in: .capsule)
                        .overlay {
                            Capsule().stroke(isSelected ? .clear : Palette.hairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 18, for: .scrollContent)
    }
}

/// Section title with an optional trailing action.
struct SupSectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var accent: Color = SupTone.accent
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, weight: .black))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
    }
}

/// One of the five validations of a handover.
struct ChecklistRow: View {
    let check: HandoverCheck
    let isDone: Bool
    var isBlocked: Bool = false
    var blockedReason: String?
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : check.symbol)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(isDone ? SupTone.good : (isBlocked ? SupTone.bad : Palette.textMuted))
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(check.title)
                        .font(.system(.subheadline, weight: .bold))
                        .multilineTextAlignment(.leading)
                    Text(isBlocked ? (blockedReason ?? check.hint) : check.hint)
                        .font(.caption2)
                        .foregroundStyle(isBlocked ? SupTone.bad : Palette.textMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isDone ? SupTone.good.opacity(0.1) : Palette.surfaceRaised.opacity(0.7)),
                in: .rect(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isDone ? SupTone.good.opacity(0.45) : Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Odometer / damage evidence thumbnail, from a real capture or a stand-in asset.
struct EvidenceThumb: View {
    let caption: String
    var data: Data?
    var asset: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.black
                .frame(height: 104)
                .overlay {
                    if let data, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    } else if let asset {
                        Image(asset)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    } else {
                        Palette.surfaceRaised
                            .overlay {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.title3)
                                    .foregroundStyle(Palette.textMuted)
                            }
                    }
                }
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14).stroke(Palette.hairline, lineWidth: 1)
                }

            Text(caption)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.textMuted)
        }
    }
}

/// Empty state used by every filtered list.
struct SupEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var accent: Color = SupTone.accent

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(accent.opacity(0.8))
            Text(title)
                .font(.system(.subheadline, weight: .bold))
            Text(message)
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .panelFlat()
    }
}
