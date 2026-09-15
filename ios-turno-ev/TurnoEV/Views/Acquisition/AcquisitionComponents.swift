import CoreText
import SwiftUI

/// Visual language scoped to DORI Adquisición. Keeping these tokens outside the
/// global Palette prevents the premium treatment from leaking into the operational
/// driver, maintenance and supervision workspaces.
nonisolated enum AcquisitionTheme {
    static let canvas = Color(red: 0.039, green: 0.039, blue: 0.043)
    static let accent = Color(red: 0.788, green: 0.722, blue: 0.588)
    static let attention = Color(red: 0.851, green: 0.725, blue: 0.475)
    static let danger = Color(red: 0.788, green: 0.486, blue: 0.455)
    static let info = Color(red: 0.561, green: 0.639, blue: 0.690)
    static let text = Color(red: 0.945, green: 0.937, blue: 0.918)
    static let textSecondary = text.opacity(0.58)
    static let textTertiary = text.opacity(0.34)
    static let surface = Color.white.opacity(0.045)
    static let surfaceRaised = Color.white.opacity(0.07)
    static let border = Color.white.opacity(0.10)
    static let subtleBorder = Color.white.opacity(0.06)

    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 20
    static let spacingXXL: CGFloat = 24
    static let radiusControl: CGFloat = 12
    static let radiusCard: CGFloat = 18
    static let radiusPanel: CGFloat = 20
    static let borderWidth: CGFloat = 1

    static let microDuration = 0.15
    static let cardDuration = 0.24
    static let sheetDuration = 0.34

    static var standardAnimation: Animation {
        .timingCurve(0.22, 0.75, 0.30, 1, duration: cardDuration)
    }

    static var microAnimation: Animation {
        .timingCurve(0.22, 0.75, 0.30, 1, duration: microDuration)
    }

    static var sheetAnimation: Animation {
        .timingCurve(0.22, 0.75, 0.30, 1, duration: sheetDuration)
    }
}

private enum AcquisitionFontRegistrar {
    static let register: Void = {
        guard let url = Bundle.main.url(forResource: "InterVariable", withExtension: "ttf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
}

extension Font {
    static func acquisition(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular
    ) -> Font {
        _ = AcquisitionFontRegistrar.register
        return .custom("Inter Variable", size: acquisitionPointSize(style), relativeTo: style)
            .weight(weight)
    }

    static func acquisitionFixed(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        _ = AcquisitionFontRegistrar.register
        return .custom("Inter Variable", fixedSize: size).weight(weight)
    }

    private static func acquisitionPointSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .subheadline: 15
        case .callout: 16
        case .caption: 12
        case .caption2: 11
        case .footnote: 13
        default: 17
        }
    }
}

struct AcquisitionBackground: View {
    var body: some View {
        AcquisitionTheme.canvas
        .ignoresSafeArea()
    }
}

private struct AcquisitionSystemGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                Color.white.opacity(emphasized ? 0.055 : 0.035),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(emphasized ? AcquisitionTheme.border : AcquisitionTheme.subtleBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(emphasized ? 0.30 : 0.18), radius: emphasized ? 24 : 14, y: emphasized ? 12 : 7)
    }
}

extension View {
    func acquisitionGlass(cornerRadius: CGFloat = AcquisitionTheme.radiusPanel, emphasized: Bool = false) -> some View {
        modifier(AcquisitionSystemGlassPanelModifier(cornerRadius: cornerRadius, emphasized: emphasized))
    }

    func acquisitionDisplayTitle() -> some View {
        font(.acquisition(.largeTitle, weight: .bold))
            .foregroundStyle(AcquisitionTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

nonisolated enum AcquisitionDockDestination: String, CaseIterable, Identifiable, Sendable {
    case home
    case requests
    case vehicles
    case contact
    case account

    var id: String { rawValue }

    func title(for role: AcquisitionRole) -> String {
        switch self {
        case .home: "Inicio"
        case .requests: "Solicitudes"
        case .vehicles: "Compras"
        case .contact: "Contacto"
        case .account: "Cuenta"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .requests: "doc.text.fill"
        case .vehicles: "car.fill"
        case .contact: "bubble.left.and.bubble.right.fill"
        case .account: "person.crop.circle.fill"
        }
    }
}

struct AcquisitionIdentityHeader: View {
    let name: String
    let subtitle: String
    var stationName: String? = nil
    var contextLine: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.acquisition(.largeTitle, weight: .bold))
                        .foregroundStyle(AcquisitionTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(subtitle)
                        .font(.acquisition(.subheadline, weight: .medium))
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Label("Modo prueba", systemImage: "testtube.2")
                        .font(.acquisition(.caption, weight: .bold))
                    Text("Datos ficticios")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(AcquisitionTheme.attention)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(AcquisitionTheme.attention.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(AcquisitionTheme.attention.opacity(0.35), lineWidth: 1)
                }
            }

            if let stationName {
                HStack(spacing: 11) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(AcquisitionTheme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stationName)
                            .font(.acquisition(.subheadline, weight: .semibold))
                            .foregroundStyle(AcquisitionTheme.text)
                        if let contextLine {
                            Text(contextLine)
                                .font(.acquisition(.caption))
                                .foregroundStyle(AcquisitionTheme.textSecondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AcquisitionScreenHeader: View {
    let eyebrow: String?
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eyebrow, !eyebrow.isEmpty {
                Text(eyebrow)
                    .font(.acquisitionFixed(9.5, weight: .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(AcquisitionTheme.textTertiary)
            }
            Text(title)
                .font(.acquisitionFixed(title == "Operaciones" ? 19 : 27, weight: .bold))
                .foregroundStyle(AcquisitionTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AcquisitionProviderRequestCard: View {
    let summary: AcquisitionRequestSummary

    private var progress: Double {
        guard summary.request.targetQuantity > 0 else { return 0 }
        return min(Double(summary.securedCount) / Double(summary.request.targetQuantity), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "doc.text.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AcquisitionTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AcquisitionTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text("DORI \(summary.request.deliveryCity) busca \(summary.request.modelAndVersions)")
                        .font(.acquisition(.headline, weight: .bold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text("\(summary.request.yearRange) · Máx. \(summary.request.maximumMileageText) km")
                        .font(.acquisition(.subheadline))
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Label(
                    summary.request.visibleStatus.title,
                    systemImage: summary.request.visibleStatus.systemImage
                )
                    .font(.acquisition(.caption2, weight: .bold))
                    .foregroundStyle(requestStatusColor(summary.request.visibleStatus.tone))
            }

            HStack(spacing: 13) {
                AcquisitionVehicleVisual(compact: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.request.targetQuantity) vehículos requeridos")
                        .font(.acquisition(.headline, weight: .bold))
                    Text("\(summary.securedCount) confirmado\(summary.securedCount == 1 ? "" : "s") · \(summary.missingCount) por conseguir")
                        .font(.acquisition(.subheadline))
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
            }

            ProgressView(value: progress)
                .tint(AcquisitionTheme.accent)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)
        }
        .padding(18)
        .background {
            LinearGradient(
                colors: [AcquisitionTheme.accent.opacity(0.14), AcquisitionTheme.surface.opacity(0.97)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AcquisitionTheme.accent.opacity(0.34), lineWidth: 1)
        }
    }

    private func requestStatusColor(_ tone: AcquisitionRequestStatusTone) -> Color {
        switch tone {
        case .active, .complete: AcquisitionTheme.accent
        case .waiting: AcquisitionTheme.info
        case .neutral: AcquisitionTheme.textSecondary
        case .cancelled: AcquisitionTheme.danger
        }
    }
}

struct AcquisitionStatChip: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(count)")
                .font(.acquisitionFixed(18, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AcquisitionTheme.text)
            Text(label)
                .font(.acquisitionFixed(8.5, weight: .medium))
                .foregroundStyle(AcquisitionTheme.textTertiary)
                .lineSpacing(1)
        }
        .frame(minWidth: 86, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .acquisitionGlass(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}

struct AcquisitionRequirementsGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let request: AcquisitionRequest

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(request.visibleRequirements) { requirement in
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: symbol(for: requirement.id))
                        .font(.acquisition(.title3, weight: .bold))
                        .foregroundStyle(tint(for: requirement.id))
                    Text(requirement.title)
                        .font(.acquisition(.caption, weight: .bold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text(requirement.value)
                        .font(.acquisition(.caption))
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                .padding(12)
                .background(AcquisitionTheme.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AcquisitionTheme.subtleBorder, lineWidth: 1)
                }
            }
        }
    }

    private func symbol(for id: String) -> String {
        switch id {
        case "model_year": "calendar"
        case "mileage": "gauge.with.dots.needle.67percent"
        case "color": "paintpalette.fill"
        case "charger_110v", "condition_charger_110v": "powerplug.fill"
        case "charger_220v", "condition_charger_220v": "bolt.fill"
        case "condition_keys": "key.fill"
        case "battery": "battery.75percent"
        case "original_invoice": "doc.text.fill"
        case "reinvoice": "doc.badge.arrow.up.fill"
        case "plates": "rectangle.and.text.magnifyingglass"
        case "ownership": "arrow.left.arrow.right"
        case "byd_warranty": "shield.lefthalf.filled"
        case "used_warranty": "checkmark.shield.fill"
        default: "checkmark.circle.fill"
        }
    }

    private func tint(for id: String) -> Color {
        id == "color" ? AcquisitionTheme.attention : AcquisitionTheme.accent
    }
}

struct AcquisitionSectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(AcquisitionTheme.textSecondary)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.acquisition(.caption, weight: .bold))
                    .foregroundStyle(AcquisitionTheme.textSecondary)
            }
        }
    }
}

struct AcquisitionRequestCard: View {
    let request: AcquisitionRequest
    let progressText: String?
    let audience: AcquisitionRole

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(audience == .doriAdmin ? request.modelAndVersions : "DORI \(request.deliveryCity)")
                        .font(.acquisitionFixed(13.5, weight: .semibold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text(audience == .doriAdmin
                         ? "Periodo: \(request.fiscalPeriodText) · \(request.yearRange)"
                         : "\(request.modelAndVersions) · Periodo: \(request.fiscalPeriodText)")
                        .font(.acquisitionFixed(10.5, weight: .regular))
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
                Spacer(minLength: 8)
                AcquisitionRequestStatusBadge(status: request.visibleStatus)
            }

            HStack(spacing: 16) {
                AcquisitionRequestMetric(
                    label: audience == .doriAdmin ? "Cantidad" : "Kilometraje",
                    value: audience == .doriAdmin ? "\(request.targetQuantity)" : "0–\(request.maximumMileageText)"
                )
                AcquisitionRequestMetric(
                    label: audience == .doriAdmin ? "Progreso" : "Pendientes",
                    value: progressText ?? "—"
                )
            }
            Text("\(request.maximumUnitPriceText) · \(request.destinationStationName)")
                .font(.acquisitionFixed(10.5, weight: .regular))
                .foregroundStyle(AcquisitionTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .acquisitionGlass(cornerRadius: 20)
    }
}

private struct AcquisitionRequestMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.acquisitionFixed(9.5, weight: .semibold))
                .foregroundStyle(AcquisitionTheme.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.acquisitionFixed(12.5, weight: .semibold))
                .foregroundStyle(AcquisitionTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct AcquisitionRequestStatusBadge: View {
    let status: AcquisitionRequestStatusPresentation

    private var tint: Color {
        switch status.tone {
        case .active, .complete: AcquisitionTheme.accent
        case .waiting: AcquisitionTheme.attention
        case .neutral: AcquisitionTheme.textSecondary
        case .cancelled: AcquisitionTheme.danger
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 4, height: 4)
            Text(status.title)
        }
        .font(.acquisitionFixed(8.5, weight: .semibold))
        .tracking(0.3)
        .textCase(.uppercase)
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay { Capsule().stroke(tint.opacity(0.22)) }
        .accessibilityElement(children: .combine)
    }
}

struct AcquisitionAdminRequestCard: View {
    let summary: AcquisitionRequestSummary

    private var progress: Double {
        guard summary.request.targetQuantity > 0 else { return 0 }
        return min(Double(summary.securedCount) / Double(summary.request.targetQuantity), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(AcquisitionTheme.accent.opacity(0.18), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: max(progress, 0.06))
                        .stroke(
                            AcquisitionTheme.accent,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(AcquisitionTheme.accent)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.request.targetQuantity) vehículos requeridos")
                        .font(.acquisition(.title3, weight: .bold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text(summary.request.modelAndVersions)
                        .font(.acquisition(.subheadline, weight: .semibold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text("\(summary.request.yearRange) · Máx. \(summary.request.maximumMileageText) km")
                        .font(.acquisition(.caption))
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
            }

            ProgressView(value: progress)
                .tint(AcquisitionTheme.accent)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)

            HStack(spacing: 10) {
                Text("\(summary.securedCount) confirmado\(summary.securedCount == 1 ? "" : "s") · \(summary.missingCount) por conseguir")
                    .font(.acquisition(.subheadline, weight: .bold))
                    .foregroundStyle(AcquisitionTheme.text)
                Spacer(minLength: 6)
                Label("Ver solicitud", systemImage: "arrow.right")
                    .font(.acquisition(.subheadline, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(AcquisitionTheme.accent, in: RoundedRectangle(cornerRadius: 11))
            }
        }
        .padding(18)
        .acquisitionGlass(cornerRadius: 24, emphasized: true)
        .accessibilityElement(children: .combine)
    }
}

struct AcquisitionOperationalSectionHeader: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int
    var trailingTitle: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.acquisition(.title3, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.acquisition(.title3, weight: .bold))
                .foregroundStyle(AcquisitionTheme.text)
            Spacer()
            if let trailingTitle {
                Text(trailingTitle)
                    .font(.acquisition(.subheadline, weight: .semibold))
                    .foregroundStyle(tint)
                Image(systemName: "chevron.right")
                    .font(.acquisition(.caption, weight: .bold))
                    .foregroundStyle(tint)
            } else {
                Text("\(count)")
                    .font(.acquisition(.subheadline, weight: .bold))
                    .foregroundStyle(count > 0 ? Color.black : AcquisitionTheme.textSecondary)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(count > 0 ? tint : AcquisitionTheme.surfaceRaised, in: Circle())
            }
        }
    }
}

struct AcquisitionVehicleVisual: View {
    var compact = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.20), AcquisitionTheme.info.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "car.side.fill")
                .font(.system(size: compact ? 30 : 39, weight: .semibold))
                .foregroundStyle(AcquisitionTheme.text)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 4)
        }
        .frame(width: compact ? 78 : 96, height: compact ? 65 : 82)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct AcquisitionDashboardVehicleCard: View {
    let offer: AcquisitionOfferSummary
    let role: AcquisitionRole
    let supplierName: String?
    let actionTitle: String
    var recommendation: String? = nil
    var activity: AcquisitionOfferActivity? = nil
    var showsNewActivity = false

    private var group: AcquisitionHomeGroup {
        AcquisitionHumanStatus.group(for: offer.status, role: role)
    }

    private var statusTint: Color {
        if group == .attention { return AcquisitionTheme.attention }
        if ["awarded", "received", "accepted", "closed"].contains(offer.status) {
            return AcquisitionTheme.accent
        }
        return AcquisitionTheme.info
    }

    private var statusSymbol: String {
        if group == .attention { return "exclamationmark.circle.fill" }
        if ["awarded", "received", "accepted", "closed"].contains(offer.status) {
            return "checkmark.circle.fill"
        }
        return "clock.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if showsNewActivity, let activity {
                HStack(spacing: 7) {
                    Text(activity.title(for: role))
                        .font(.acquisition(.caption2, weight: .bold))
                    Spacer()
                    Text(activity.requiresResponse(for: role, offerStatus: offer.status)
                         ? "Requiere tu respuesta" : "Actualización nueva")
                        .font(.acquisition(.caption2, weight: .bold))
                }
                .foregroundStyle(
                    activity.requiresResponse(for: role, offerStatus: offer.status)
                        ? AcquisitionTheme.attention : AcquisitionTheme.info
                )
                if let change = activity.amountChangeText {
                    Text(change)
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(AcquisitionTheme.text)
                }
            }
            HStack(alignment: .top, spacing: 13) {
                AcquisitionVehicleVisual(compact: group == .attention)
                VStack(alignment: .leading, spacing: 4) {
                    if let supplierName, role == .doriAdmin {
                        Text(supplierName)
                            .font(.acquisition(.caption, weight: .bold))
                            .foregroundStyle(AcquisitionTheme.textSecondary)
                    }
                    Text("\(offer.modelAndVersion) \(offer.yearText)")
                        .font(.acquisition(.headline, weight: .bold))
                        .foregroundStyle(AcquisitionTheme.text)
                        .lineLimit(2)
                    if let fiscalPeriod = offer.fiscalPeriodText {
                        Text("Periodo: \(fiscalPeriod)")
                            .font(.acquisition(.caption2, weight: .semibold))
                            .foregroundStyle(AcquisitionTheme.accent)
                    }
                    if group == .attention {
                        Text("\(offer.mileageText) km · \(offer.agreedPriceText ?? offer.priceText)")
                            .font(.acquisition(.subheadline))
                            .foregroundStyle(AcquisitionTheme.textSecondary)
                    } else {
                        Text("VIN \(offer.abbreviatedVin)")
                            .font(.acquisition(.subheadline))
                            .foregroundStyle(AcquisitionTheme.textSecondary)
                    }
                    Label(
                        AcquisitionHumanStatus.title(for: offer.status, role: role),
                        systemImage: statusSymbol
                    )
                    .font(.acquisition(.caption, weight: .bold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(statusTint.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.acquisition(.headline, weight: .semibold))
                    .foregroundStyle(AcquisitionTheme.text)
                    .frame(minHeight: 66)
            }

            if group == .inProgress {
                AcquisitionOperationProgress(status: offer.status)
            }

            if let recommendation {
                Label("DORI recomienda: \(recommendation)", systemImage: "sparkles")
                    .font(.acquisition(.subheadline, weight: .bold))
                    .foregroundStyle(AcquisitionTheme.attention)
            }

            HStack {
                Spacer()
                Text(actionTitle)
                    .font(.acquisition(.subheadline, weight: .bold))
                    .foregroundStyle(group == .attention ? Color.black : statusTint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        group == .attention ? statusTint : statusTint.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
        }
        .padding(14)
        .acquisitionGlass(cornerRadius: 20, emphasized: group == .attention)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(statusTint.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el detalle de la unidad")
    }
}

struct AcquisitionOperationProgress: View {
    let status: String

    private let steps = [
        ("Compra", true),
        ("Anticipo", false),
        ("Preparación", true),
        ("Lista p/entrega", true),
        ("Traslado", false),
        ("Llegada", false),
        ("Recepción + inspección", true),
        ("Aceptación", true),
        ("Saldo", false),
        ("Retención (si aplica)", true),
        ("Reembolso (si aplica)", false),
        ("Terminada", true),
    ]

    private var currentIndex: Int {
        switch status {
        case "awarded": 2
        case "ready_for_delivery": 3
        case "received", "accepted", "accepted_with_observations": 7
        case "accepted_with_condition": 9
        case "closed": 11
        default: 0
        }
    }

    private var currentText: String { steps[currentIndex].0 }
    private var nextText: String? {
        steps.indices.contains(currentIndex + 1) ? steps[currentIndex + 1].0 : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .stroke(
                                        step.1
                                            ? (index == currentIndex ? AcquisitionTheme.attention : AcquisitionTheme.border)
                                            : AcquisitionTheme.danger.opacity(0.5),
                                        style: StrokeStyle(lineWidth: 1.5, dash: step.1 ? [] : [3, 2])
                                    )
                                    .background(
                                        Circle().fill(index < currentIndex && step.1
                                            ? AcquisitionTheme.accent
                                            : Color.white.opacity(0.02))
                                    )
                                if index < currentIndex && step.1 {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 6.8, weight: .bold))
                                        .foregroundStyle(AcquisitionTheme.canvas)
                                } else if !step.1 {
                                    Text("?")
                                        .font(.acquisitionFixed(7, weight: .semibold))
                                        .foregroundStyle(AcquisitionTheme.danger.opacity(0.7))
                                }
                            }
                            .frame(width: 12, height: 12)
                            Text(step.0)
                                .font(.acquisitionFixed(6.8, weight: .semibold))
                                .foregroundStyle(step.1 ? AcquisitionTheme.textTertiary : AcquisitionTheme.danger.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(width: 41)
                        }
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(index < currentIndex ? AcquisitionTheme.accent.opacity(0.45) : AcquisitionTheme.subtleBorder)
                                .frame(width: 11, height: 1)
                                .offset(y: -8)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text("Ahora: \(currentText)")
                .font(.acquisitionFixed(11, weight: .semibold))
            if let nextText {
                Text("Siguiente: \(nextText)")
                    .font(.acquisitionFixed(10, weight: .regular))
                    .foregroundStyle(AcquisitionTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AcquisitionHumanStatusIndicator: View {
    let title: String
    let group: AcquisitionHomeGroup

    private var tint: Color {
        switch group {
        case .attention: AcquisitionTheme.attention
        case .inProgress: AcquisitionTheme.info
        case .finished: AcquisitionTheme.textTertiary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group == .attention ? "exclamationmark.circle.fill" : "clock.fill")
                .font(.acquisition(.caption, weight: .bold))
            Text(title)
                .font(.acquisition(.caption, weight: .bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.13), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct AcquisitionVehicleCard: View {
    let offer: AcquisitionOfferSummary
    let role: AcquisitionRole
    let supplierName: String?
    var recommendation: String? = nil
    var detail: String? = nil

    var body: some View {
        let group = AcquisitionHumanStatus.group(for: offer.status, role: role)
        VStack(alignment: .leading, spacing: 10) {
            if let supplierName, role == .doriAdmin {
                Text(supplierName)
                    .font(.acquisition(.caption, weight: .bold))
                    .foregroundStyle(AcquisitionTheme.textSecondary)
            }
            Text("\(offer.modelAndVersion) \(offer.yearText)")
                .font(.acquisition(.title3, weight: .bold))
                .foregroundStyle(AcquisitionTheme.text)
            Text("\(offer.mileageText) km · VIN \(offer.abbreviatedVin)")
                .font(.acquisition(.subheadline))
                .foregroundStyle(AcquisitionTheme.textSecondary)
            Text(offer.agreedPriceText ?? offer.priceText)
                .font(.acquisition(.headline, weight: .bold))
                .foregroundStyle(AcquisitionTheme.text)
            AcquisitionHumanStatusIndicator(
                title: AcquisitionHumanStatus.title(for: offer.status, role: role),
                group: group
            )
            if let recommendation {
                Text("DORI recomienda: \(recommendation)")
                    .font(.acquisition(.subheadline, weight: .semibold))
                    .foregroundStyle(AcquisitionTheme.attention)
            }
            if let detail {
                Text(detail)
                    .font(.acquisition(.subheadline))
                    .foregroundStyle(AcquisitionTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .acquisitionGlass()
    }
}

struct AcquisitionAttentionCard: View {
    let title: String
    let offer: AcquisitionOfferSummary
    let role: AcquisitionRole
    let supplierName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.acquisition(.headline, weight: .bold))
                .foregroundStyle(AcquisitionTheme.attention)
            AcquisitionVehicleCard(
                offer: offer,
                role: role,
                supplierName: supplierName
            )
        }
    }
}

struct AcquisitionContactCard: View {
    let organization: String
    let roleDescription: String
    var personName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(organization)
                .font(.acquisition(.headline, weight: .bold))
            if let personName { Text(personName) }
            Text(roleDescription)
                .font(.acquisition(.subheadline))
                .foregroundStyle(AcquisitionTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .acquisitionGlass()
    }
}

struct AcquisitionInstitutionalContactCard: View {
    @Environment(\.openURL) private var openURL
    let contact: AcquisitionInstitutionalContact
    var openChat: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(contact.organizationName)
                    .font(.acquisition(.headline, weight: .bold))
                Text(contact.jobTitle)
                    .font(.acquisition(.subheadline, weight: .semibold))
                    .foregroundStyle(AcquisitionTheme.accent)
            }

            contactLine(label: "Nombre", value: contact.personName)
            contactLine(label: "Teléfono", value: contact.phone)
            contactLine(label: "Correo", value: contact.email)
            contactLine(label: "Horario", value: contact.businessHours)

            HStack(spacing: 10) {
                contactAction("Llamar", symbol: "phone.fill", url: contact.callURL)
                contactAction("Enviar correo", symbol: "envelope.fill", url: contact.emailURL)
            }
            if let openChat {
                Button(action: openChat) {
                    Label("Abrir chat", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.acquisition(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AcquisitionTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .acquisitionGlass()
    }

    private func contactLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.acquisition(.caption))
                .foregroundStyle(AcquisitionTheme.textSecondary)
            Text(value)
                .font(.acquisition(.subheadline))
                .foregroundStyle(AcquisitionTheme.text)
                .textSelection(.enabled)
        }
    }

    private func contactAction(_ title: String, symbol: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Label(title, systemImage: symbol)
                .font(.acquisition(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(AcquisitionTheme.accent)
        .disabled(url == nil)
    }
}

struct AcquisitionPrimaryAction: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.acquisition(.headline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(AcquisitionTheme.accent)
    }
}

struct AcquisitionDock: View {
    @Binding var selection: AcquisitionDockDestination
    let role: AcquisitionRole
    var badges: [AcquisitionDockDestination: Int] = [:]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AcquisitionDockDestination.allCases) { destination in
                Button {
                    selection = destination
                } label: {
                    VStack(spacing: 5) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: destination.symbol)
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 32, height: 25)
                            if let badge = badges[destination], badge > 0 {
                                Text("\(min(badge, 99))")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 17, minHeight: 17)
                                    .background(AcquisitionTheme.danger, in: Circle())
                                    .offset(x: 8, y: -7)
                            }
                        }
                        Text(destination.title(for: role))
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == destination ? AcquisitionTheme.accent : AcquisitionTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selection == destination ? AcquisitionTheme.accent.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(selection == destination ? "Seleccionado" : "")
            }
        }
        .padding(7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(AcquisitionTheme.subtleBorder.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .background(.ultraThinMaterial)
        .background(AcquisitionTheme.canvas.opacity(0.78))
    }
}
