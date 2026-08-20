import CoreImage.CIFilterBuiltins
import SwiftUI

/// Visual identity of the laboratory. The operational network is sage on graphite; the
/// test rig is warm ochre on a brown-black ink with hazard striping, so nobody can
/// confuse a test screen with the real product even from across a room. Muted like the
/// rest of the app — the difference is temperature, not brightness.
nonisolated enum LabTone {
    static let canvas = Color(red: 0.055, green: 0.047, blue: 0.039)
    static let surface = Color(red: 0.106, green: 0.094, blue: 0.075)
    static let raised = Color(red: 0.145, green: 0.129, blue: 0.102)
    static let hairline = Color(red: 0.235, green: 0.208, blue: 0.161)
    static let accent = Color(red: 0.847, green: 0.686, blue: 0.404)
    static let accentSoft = Color(red: 0.898, green: 0.804, blue: 0.612)
    static let good = Color(red: 0.565, green: 0.714, blue: 0.553)
    static let bad = Color(red: 0.839, green: 0.435, blue: 0.396)
    static let cool = Color(red: 0.518, green: 0.616, blue: 0.678)
    static let muted = Color(red: 0.600, green: 0.573, blue: 0.522)

    static func tone(for result: LabResult) -> Color {
        switch result {
        case .success: good
        case .warning: accent
        case .failure: bad
        }
    }

    static func tone(for level: OpsAlertLevel) -> Color {
        switch level {
        case .informative: cool
        case .preventive: accentSoft
        case .important: accent
        case .critical: bad
        }
    }
}

// MARK: - Backdrop

struct LabBackground: View {
    var body: some View {
        ZStack {
            LabTone.canvas
            RadialGradient(
                colors: [LabTone.accent.opacity(0.05), .clear],
                center: UnitPoint(x: 0.5, y: -0.08),
                startRadius: 0,
                endRadius: 500
            )
            RadialGradient(
                colors: [LabTone.cool.opacity(0.028), .clear],
                center: UnitPoint(x: 1.1, y: 1.05),
                startRadius: 0,
                endRadius: 400
            )
            LabBlueprintGrid()
        }
        .ignoresSafeArea()
    }
}

private struct LabBlueprintGrid: View {
    var body: some View {
        Canvas { context, size in
            var minor = Path()
            let step: CGFloat = 28
            var x: CGFloat = 0
            while x <= size.width {
                minor.move(to: CGPoint(x: x, y: 0))
                minor.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                minor.move(to: CGPoint(x: 0, y: y))
                minor.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(minor, with: .color(.white.opacity(0.02)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Diagonal hazard striping used by the test banner.
struct LabHazardStripes: View {
    var phase: CGFloat = 0
    var opacity: Double = 0.35

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 16
            let width: CGFloat = 7
            var offset = -size.height - spacing + (phase.truncatingRemainder(dividingBy: spacing * 2))
            while offset < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: offset, y: size.height))
                path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                path.addLine(to: CGPoint(x: offset + size.height + width, y: 0))
                path.addLine(to: CGPoint(x: offset + width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(LabTone.accent.opacity(opacity)))
                offset += spacing * 2
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Global banner

/// Permanent strip shown on top of every interface while the test environment is live.
/// It is deliberately loud: it is the difference between a test and a real record.
struct LabModeBanner: View {
    @Environment(LabStore.self) private var lab
    @State private var phase: CGFloat = 0

    var body: some View {
        if lab.isTest {
            HStack(spacing: 10) {
                Image(systemName: "testtube.2")
                    .font(.system(.caption, weight: .black))
                Text("MODO PRUEBA")
                    .font(.system(.caption2, weight: .black))
                    .tracking(2.2)
                Text("· datos ficticios")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(LabTone.canvas.opacity(0.7))
                Spacer(minLength: 0)
                if lab.world.clockOffsetMinutes != 0 {
                    Label(
                        Fmt.clock(lab.now),
                        systemImage: "clock.badge.exclamationmark.fill"
                    )
                    .font(.system(.caption2, weight: .bold))
                    .monospacedDigit()
                }
            }
            .foregroundStyle(LabTone.canvas)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    LabTone.accent
                    LabHazardStripes(phase: phase, opacity: 0.16)
                        .blendMode(.multiply)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    phase = 320
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

extension View {
    /// Adds the test strip above any role interface.
    func labModeBanner() -> some View {
        modifier(LabBannerModifier())
    }
}

private struct LabBannerModifier: ViewModifier {
    @Environment(LabStore.self) private var lab

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            LabModeBanner()
            content
        }
        .animation(.smooth(duration: 0.3), value: lab.isTest)
    }
}

// MARK: - Surfaces

extension View {
    func labPanel(cornerRadius: CGFloat = 22) -> some View {
        background(LabTone.surface.opacity(0.92), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(LabTone.hairline, lineWidth: 1)
            }
    }

    func labFlat(cornerRadius: CGFloat = 16) -> some View {
        background(LabTone.raised.opacity(0.7), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(LabTone.hairline.opacity(0.7), lineWidth: 1)
            }
    }
}

struct LabCaps: View {
    let text: String
    var tint: Color = LabTone.muted

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, weight: .bold))
            .tracking(1.7)
            .foregroundStyle(tint)
    }
}

struct LabSectionTitle: View {
    let title: String
    var subtitle: String?
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(LabTone.accent)
                }
                Text(title)
                    .font(.system(.title3, weight: .black))
                    .foregroundStyle(.white)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Data display

struct LabStat: View {
    let label: String
    let value: String
    var tint: Color = .white
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LabTone.muted)
                }
                LabCaps(text: label)
            }
            Text(value)
                .font(.system(.title3, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .labFlat()
    }
}

struct LabChip: View {
    let text: String
    var symbol: String?
    var tint: Color = LabTone.accent
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(.caption2, weight: .bold))
        }
        .foregroundStyle(filled ? LabTone.canvas : tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(filled ? tint : tint.opacity(0.13), in: .capsule)
        .overlay {
            Capsule().stroke(tint.opacity(filled ? 0 : 0.45), lineWidth: 1)
        }
    }
}

struct LabResultBadge: View {
    let result: LabResult

    var body: some View {
        LabChip(text: result.label, symbol: result.symbol, tint: LabTone.tone(for: result))
    }
}

/// Standard row of any list inside the console.
struct LabRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var detail: String?
    var symbol: String
    var tint: Color = LabTone.accent
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                        .lineLimit(2)
                }
                if let detail {
                    Text(detail)
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.9))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(12)
        .labFlat()
    }
}

extension LabRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, detail: String? = nil, symbol: String, tint: Color = LabTone.accent) {
        self.init(title: title, subtitle: subtitle, detail: detail, symbol: symbol, tint: tint) { EmptyView() }
    }
}

/// What the console shows before the administrator has created anything. Every module
/// starts here, on purpose.
struct LabEmptyState: View {
    let title: String
    let message: String
    var symbol: String = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(LabTone.accent.opacity(0.55))
            Text(title)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(LabTone.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(LabButtonStyle(kind: .soft))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 22)
        .background(LabTone.surface.opacity(0.45), in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(
                    LabTone.hairline,
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                )
        }
    }
}

// MARK: - Controls

struct LabButtonStyle: ButtonStyle {
    enum Kind {
        case solid
        case soft
        case danger
        case ghost
    }

    var kind: Kind = .solid
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(isCompact ? .caption : .subheadline, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, isCompact ? 12 : 18)
            .padding(.vertical, isCompact ? 8 : 13)
            .frame(maxWidth: kind == .solid && !isCompact ? .infinity : nil)
            .background(background, in: .capsule)
            .overlay {
                Capsule().stroke(border, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .solid: LabTone.canvas
        case .soft: LabTone.accent
        case .danger: LabTone.bad
        case .ghost: LabTone.muted
        }
    }

    private var background: Color {
        switch kind {
        case .solid: LabTone.accent
        case .soft: LabTone.accent.opacity(0.14)
        case .danger: LabTone.bad.opacity(0.14)
        case .ghost: .clear
        }
    }

    private var border: Color {
        switch kind {
        case .solid: .clear
        case .soft: LabTone.accent.opacity(0.45)
        case .danger: LabTone.bad.opacity(0.5)
        case .ghost: LabTone.hairline
        }
    }
}

struct LabField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabCaps(text: label)
            TextField(placeholder, text: $text)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .labFlat(cornerRadius: 13)
        }
    }
}

struct LabNumberField: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...1_000_000
    var step: Int = 1
    var suffix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabCaps(text: label)
            HStack(spacing: 10) {
                Button {
                    value = max(range.lowerBound, value - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(.caption, weight: .black))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LabTone.accent)
                .background(LabTone.accent.opacity(0.12), in: .circle)

                Text("\(value)\(suffix.map { " \($0)" } ?? "")")
                    .font(.system(.headline, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                Button {
                    value = min(range.upperBound, value + step)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(.caption, weight: .black))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LabTone.accent)
                .background(LabTone.accent.opacity(0.12), in: .circle)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .labFlat(cornerRadius: 13)
        }
    }
}

/// Horizontal option strip; the console never uses system pickers so the ink theme holds.
struct LabOptionRow<Value: Hashable>: View {
    let label: String
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var symbol: ((Value) -> String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabCaps(text: label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            selection = option
                        } label: {
                            LabChip(
                                text: title(option),
                                symbol: symbol?(option),
                                tint: LabTone.accent,
                                filled: option == selection
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }
}

struct LabToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(LabTone.muted)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(LabTone.accent)
        }
        .padding(12)
        .labFlat()
    }
}

// MARK: - Toast

struct LabToastView: View {
    let message: LabMessage

    private var tint: Color {
        switch message.tone {
        case .success: LabTone.good
        case .warning: LabTone.accent
        case .failure: LabTone.bad
        }
    }

    private var symbol: String {
        switch message.tone {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(tint)
            Text(message.text)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(LabTone.raised, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .padding(.horizontal, 18)
    }
}

/// Attaches the console toast to any lab screen.
struct LabToastLayer: ViewModifier {
    @Environment(LabStore.self) private var lab

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = lab.lastMessage {
                    LabToastView(message: message)
                        .padding(.bottom, 22)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: message.id) {
                            try? await Task.sleep(for: .seconds(3.4))
                            withAnimation(.smooth) { lab.lastMessage = nil }
                        }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: lab.lastMessage?.id)
    }
}

extension View {
    func labToasts() -> some View { modifier(LabToastLayer()) }
}

// MARK: - QR

/// Renders the sticker code of a unit so it can be scanned from another device during a
/// test run.
struct LabQrCode: View {
    let text: String

    var body: some View {
        Group {
            if let image = Self.render(text) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(LabTone.canvas)
            }
        }
        .accessibilityLabel("Código QR \(text)")
    }

    private static func render(_ value: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Sheet scaffold

/// Every editor of the console shares the same frame: ink background, title, cancel and
/// a single primary action.
struct LabSheet<Content: View>: View {
    let title: String
    var subtitle: String?
    var confirmTitle: String = "Guardar"
    var isConfirmEnabled: Bool = true
    let onConfirm: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(LabTone.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LabBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(LabTone.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) { onConfirm() }
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(isConfirmEnabled ? LabTone.accent : LabTone.muted)
                        .disabled(!isConfirmEnabled)
                }
            }
            .toolbarBackground(LabTone.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(LabTone.canvas)
        .preferredColorScheme(.dark)
    }
}

/// Scaffold shared by every section screen of the console.
struct LabScreen<Content: View>: View {
    let section: LabSection
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 46)
        }
        .background(LabBackground())
        .navigationTitle(section.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(LabTone.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .labToasts()
    }
}
