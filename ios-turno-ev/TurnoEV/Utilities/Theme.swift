import SwiftUI

/// One palette for the whole network, built on a graphite base so colour is never
/// decoration. The interface is read while driving: almost everything is neutral, and
/// a tint only appears when it changes what the person has to do.
///
/// Sage = accent and healthy · honey = needs attention · clay = blocking ·
/// slate = neutral or closed. All four are muted on purpose; nothing glows.
nonisolated enum Palette {
    static let canvas = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let surface = Color(red: 0.078, green: 0.086, blue: 0.098)
    static let surfaceRaised = Color(red: 0.110, green: 0.118, blue: 0.133)
    static let hairline = Color(red: 0.169, green: 0.180, blue: 0.196)

    /// Accent of the product and the colour of anything that is going well.
    /// Muted sage: legible over graphite without vibrating like neon.
    static let volt = Color(red: 0.553, green: 0.706, blue: 0.545)
    /// Needs attention, but nothing is stopped.
    static let amber = Color(red: 0.831, green: 0.671, blue: 0.376)
    /// Blocking: the shift, the unit or the record cannot continue. The only colour
    /// allowed to be the loudest thing on screen.
    static let danger = Color(red: 0.839, green: 0.416, blue: 0.384)
    /// Neutral information and closed records.
    static let info = Color(red: 0.478, green: 0.588, blue: 0.667)

    /// Primary reading colour: plain, slightly warm white.
    static let text = Color(red: 0.918, green: 0.925, blue: 0.933)
    /// Secondary reading colour, for labels and anything not being decided right now.
    static let textMuted = Color(red: 0.529, green: 0.553, blue: 0.588)
    /// Neutral chrome for counters, chips and inactive controls, so a number that is
    /// merely informative never competes with one that is critical.
    static let neutral = Color(red: 0.647, green: 0.671, blue: 0.706)

    /// Legacy role accents kept as aliases: every interface shares the same accent.
    static let blaze = volt
    static let ember = volt
    static let royal = volt
}

/// Station floor backdrop: graphite with a barely-there wash of light and a faint
/// service grid. It gives depth without adding a colour the eye has to interpret.
struct StationBackground: View {
    var body: some View {
        ZStack {
            Palette.canvas
            RadialGradient(
                colors: [Color.white.opacity(0.035), .clear],
                center: UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 460
            )
            RadialGradient(
                colors: [Palette.volt.opacity(0.035), .clear],
                center: UnitPoint(x: 1.05, y: 1.02),
                startRadius: 0,
                endRadius: 380
            )
            ServiceGrid()
        }
        .ignoresSafeArea()
    }
}

private struct ServiceGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 44
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
            context.stroke(path, with: .color(.white.opacity(0.018)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Elevated operational card.
    func panel(cornerRadius: CGFloat = 26) -> some View {
        background(Palette.surface.opacity(0.9), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Palette.hairline, lineWidth: 1)
            }
    }

    /// Flat inner block used for stats and rows.
    func panelFlat(cornerRadius: CGFloat = 18) -> some View {
        background(Palette.surfaceRaised.opacity(0.75), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Palette.hairline.opacity(0.8), lineWidth: 1)
            }
    }

    /// Depth instead of glow: the accent no longer bleeds light over the canvas.
    func voltGlow(_ radius: CGFloat = 18) -> some View {
        shadow(color: .black.opacity(0.45), radius: radius * 0.7, x: 0, y: 6)
    }
}

/// Uppercase micro-label used across every screen.
struct CapsLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Palette.textMuted)
    }
}
