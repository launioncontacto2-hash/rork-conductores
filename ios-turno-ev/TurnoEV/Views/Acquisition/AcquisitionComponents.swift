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

    static let microDuration = 0.15
    static let cardDuration = 0.24
    static let sheetDuration = 0.34

    static var standardAnimation: Animation {
        .timingCurve(0.22, 0.75, 0.30, 1, duration: cardDuration)
    }
}

struct AcquisitionBackground: View {
    var body: some View {
        ZStack {
            AcquisitionTheme.canvas
            RadialGradient(
                colors: [AcquisitionTheme.accent.opacity(0.10), .clear],
                center: UnitPoint(x: 0.14, y: -0.08),
                startRadius: 0,
                endRadius: 430
            )
            RadialGradient(
                colors: [AcquisitionTheme.info.opacity(0.055), .clear],
                center: UnitPoint(x: 1.08, y: 0.60),
                startRadius: 0,
                endRadius: 390
            )
            LinearGradient(
                colors: [Color.white.opacity(0.018), .clear, Color.black.opacity(0.20)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
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
    func acquisitionGlass(cornerRadius: CGFloat = 22, emphasized: Bool = false) -> some View {
        modifier(AcquisitionSystemGlassPanelModifier(cornerRadius: cornerRadius, emphasized: emphasized))
    }

    func acquisitionDisplayTitle() -> some View {
        font(.system(.largeTitle, design: .serif, weight: .semibold))
            .foregroundStyle(AcquisitionTheme.text)
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
        case .vehicles: role == .doriAdmin ? "Operaciones" : "Vehículos"
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
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text(subtitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Label("Modo prueba", systemImage: "testtube.2")
                        .font(.caption.weight(.bold))
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
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AcquisitionTheme.text)
                        if let contextLine {
                            Text(contextLine)
                                .font(.caption)
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
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text("\(summary.request.yearRange) · Máx. \(summary.request.maximumMileageText) km")
                        .font(.subheadline)
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Label(
                    summary.request.visibleStatus.title,
                    systemImage: summary.request.visibleStatus.systemImage
                )
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(requestStatusColor(summary.request.visibleStatus.tone))
            }

            HStack(spacing: 13) {
                AcquisitionVehicleVisual(compact: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.request.targetQuantity) vehículos requeridos")
                        .font(.headline.weight(.bold))
                    Text("\(summary.securedCount) confirmado\(summary.securedCount == 1 ? "" : "s") · \(summary.missingCount) por conseguir")
                        .font(.subheadline)
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

struct AcquisitionRequirementsGrid: View {
    let request: AcquisitionRequest

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(request.visibleRequirements) { requirement in
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: symbol(for: requirement.id))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(tint(for: requirement.id))
                    Text(requirement.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text(requirement.value)
                        .font(.caption)
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
                    .font(.caption.weight(.bold))
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
        VStack(alignment: .leading, spacing: 10) {
            Text(audience == .doriAdmin
                 ? "\(request.targetQuantity) vehículos requeridos"
                 : "DORI \(request.deliveryCity) busca \(request.modelAndVersions)")
                .font(.title3.weight(.bold))
                .foregroundStyle(AcquisitionTheme.text)
            if audience == .doriAdmin {
                Text(request.modelAndVersions)
                    .font(.headline)
            }
            Text("\(request.yearRange) · Máx. \(request.maximumMileageText) km")
                .font(.subheadline)
                .foregroundStyle(AcquisitionTheme.textSecondary)
            if audience == .provider {
                Text("Entrega en \(request.deliveryCity)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AcquisitionTheme.info)
            }
            if let progressText {
                Divider().overlay(AcquisitionTheme.subtleBorder)
                Text(progressText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AcquisitionTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .acquisitionGlass()
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
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text(summary.request.modelAndVersions)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text("\(summary.request.yearRange) · Máx. \(summary.request.maximumMileageText) km")
                        .font(.caption)
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
            }

            ProgressView(value: progress)
                .tint(AcquisitionTheme.accent)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)

            HStack(spacing: 10) {
                Text("\(summary.securedCount) confirmado\(summary.securedCount == 1 ? "" : "s") · \(summary.missingCount) por conseguir")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AcquisitionTheme.text)
                Spacer(minLength: 6)
                Label("Ver solicitud", systemImage: "arrow.right")
                    .font(.subheadline.weight(.bold))
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
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AcquisitionTheme.text)
            Spacer()
            if let trailingTitle {
                Text(trailingTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            } else {
                Text("\(count)")
                    .font(.subheadline.weight(.black))
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
                        .font(.caption2.weight(.black))
                    Spacer()
                    Text(activity.requiresResponse(for: role, offerStatus: offer.status)
                         ? "Requiere tu respuesta" : "Actualización nueva")
                        .font(.caption2.weight(.bold))
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
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AcquisitionTheme.textSecondary)
                    }
                    Text("\(offer.modelAndVersion) \(offer.yearText)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AcquisitionTheme.text)
                        .lineLimit(2)
                    if group == .attention {
                        Text("\(offer.mileageText) km · \(offer.agreedPriceText ?? offer.priceText)")
                            .font(.subheadline)
                            .foregroundStyle(AcquisitionTheme.textSecondary)
                    } else {
                        Text("VIN \(offer.abbreviatedVin)")
                            .font(.subheadline)
                            .foregroundStyle(AcquisitionTheme.textSecondary)
                    }
                    Label(
                        AcquisitionHumanStatus.title(for: offer.status, role: role),
                        systemImage: statusSymbol
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(statusTint.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AcquisitionTheme.text)
                    .frame(minHeight: 66)
            }

            if group == .inProgress {
                AcquisitionOperationProgress(status: offer.status)
            }

            if let recommendation {
                Label("DORI recomienda: \(recommendation)", systemImage: "sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AcquisitionTheme.attention)
            }

            HStack {
                Spacer()
                Text(actionTitle)
                    .font(.subheadline.weight(.bold))
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
        ("Compra", "cart.fill"),
        ("Preparación", "wrench.and.screwdriver.fill"),
        ("Entrega", "truck.box.fill"),
        ("Recepción", "checklist"),
        ("Resolución", "shield.checkered"),
        ("Final", "checkmark.seal.fill"),
    ]

    private var currentIndex: Int {
        switch status {
        case "awarded": 0
        case "ready_for_delivery": 2
        case "received", "accepted", "accepted_with_observations": 3
        case "accepted_with_condition": 4
        case "closed": 5
        default: 0
        }
    }

    private var currentText: String { steps[currentIndex].0 }
    private var nextText: String? {
        steps.indices.contains(currentIndex + 1) ? steps[currentIndex + 1].0 : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Image(systemName: step.1)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(index <= currentIndex ? AcquisitionTheme.accent : AcquisitionTheme.textSecondary)
                        .frame(width: 22, height: 22)
                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(index < currentIndex ? AcquisitionTheme.accent : AcquisitionTheme.subtleBorder)
                            .frame(height: 2)
                    }
                }
            }
            Text("Ahora: \(currentText)")
                .font(.caption.weight(.bold))
            if let nextText {
                Text("Siguiente: \(nextText)")
                    .font(.caption2)
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
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.bold))
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
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AcquisitionTheme.textSecondary)
            }
            Text("\(offer.modelAndVersion) \(offer.yearText)")
                .font(.title3.weight(.bold))
                .foregroundStyle(AcquisitionTheme.text)
            Text("\(offer.mileageText) km · VIN \(offer.abbreviatedVin)")
                .font(.subheadline)
                .foregroundStyle(AcquisitionTheme.textSecondary)
            Text(offer.agreedPriceText ?? offer.priceText)
                .font(.headline.weight(.bold))
                .foregroundStyle(AcquisitionTheme.text)
            AcquisitionHumanStatusIndicator(
                title: AcquisitionHumanStatus.title(for: offer.status, role: role),
                group: group
            )
            if let recommendation {
                Text("DORI recomienda: \(recommendation)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AcquisitionTheme.attention)
            }
            if let detail {
                Text(detail)
                    .font(.subheadline)
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
                .font(.headline.weight(.bold))
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
                .font(.headline.weight(.bold))
            if let personName { Text(personName) }
            Text(roleDescription)
                .font(.subheadline)
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
                    .font(.headline.weight(.bold))
                Text(contact.jobTitle)
                    .font(.subheadline.weight(.semibold))
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
                        .font(.subheadline.weight(.semibold))
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
                .font(.caption)
                .foregroundStyle(AcquisitionTheme.textSecondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AcquisitionTheme.text)
                .textSelection(.enabled)
        }
    }

    private func contactAction(_ title: String, symbol: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
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
                .font(.headline)
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
