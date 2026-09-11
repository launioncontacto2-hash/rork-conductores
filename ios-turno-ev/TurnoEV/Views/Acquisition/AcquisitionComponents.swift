import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .foregroundStyle(Palette.text)
                    Text(subtitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Label("Modo prueba", systemImage: "testtube.2")
                        .font(.caption.weight(.bold))
                    Text("Datos ficticios")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(Palette.amber)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Palette.amber.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Palette.amber.opacity(0.35), lineWidth: 1)
                }
            }

            if let stationName {
                HStack(spacing: 11) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Palette.volt)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stationName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.text)
                        Text("Compra segura. Más unidades en ruta.")
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AcquisitionSectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.text)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.textMuted)
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
                .foregroundStyle(Palette.text)
            if audience == .doriAdmin {
                Text(request.modelAndVersions)
                    .font(.headline)
            }
            Text("\(request.yearRange) · Máx. \(request.maximumMileageText) km")
                .font(.subheadline)
                .foregroundStyle(Palette.textMuted)
            if audience == .provider {
                Text("Entrega en \(request.deliveryCity)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.info)
            }
            if let progressText {
                Divider().overlay(Palette.hairline)
                Text(progressText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.volt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
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
                        .stroke(Palette.volt.opacity(0.18), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: max(progress, 0.06))
                        .stroke(
                            Palette.volt,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Palette.volt)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.request.targetQuantity) vehículos requeridos")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.text)
                    Text(summary.request.modelAndVersions)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.text)
                    Text("\(summary.request.yearRange) · Máx. \(summary.request.maximumMileageText) km")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
            }

            ProgressView(value: progress)
                .tint(Palette.volt)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)

            HStack(spacing: 10) {
                Text("\(summary.securedCount) confirmado\(summary.securedCount == 1 ? "" : "s") · \(summary.missingCount) por conseguir")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 6)
                Label("Ver solicitud", systemImage: "arrow.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(Palette.volt, in: RoundedRectangle(cornerRadius: 11))
            }
        }
        .padding(18)
        .background {
            LinearGradient(
                colors: [Palette.volt.opacity(0.16), Palette.surface.opacity(0.97)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Palette.volt.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: Palette.volt.opacity(0.08), radius: 18, y: 8)
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
                .foregroundStyle(Palette.text)
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
                    .foregroundStyle(count > 0 ? Color.black : Palette.textMuted)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(count > 0 ? tint : Palette.surfaceRaised, in: Circle())
            }
        }
    }
}

struct AcquisitionVehicleVisual: View {
    var compact = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.20), Palette.info.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "car.side.fill")
                .font(.system(size: compact ? 30 : 39, weight: .semibold))
                .foregroundStyle(Palette.text)
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

    private var group: AcquisitionHomeGroup {
        AcquisitionHumanStatus.group(for: offer.status, role: role)
    }

    private var statusTint: Color {
        if group == .attention { return Palette.amber }
        if ["awarded", "received", "accepted", "closed"].contains(offer.status) {
            return Palette.volt
        }
        return Palette.info
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
            HStack(alignment: .top, spacing: 13) {
                AcquisitionVehicleVisual(compact: group == .attention)
                VStack(alignment: .leading, spacing: 4) {
                    if let supplierName, role == .doriAdmin {
                        Text(supplierName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.textMuted)
                    }
                    Text("\(offer.modelAndVersion) \(offer.year)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                    if group == .attention {
                        Text("\(offer.mileageText) km · \(offer.agreedPriceText ?? offer.priceText)")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textMuted)
                    } else {
                        Text("VIN \(offer.abbreviatedVin)")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textMuted)
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
                    .foregroundStyle(Palette.text)
                    .frame(minHeight: 66)
            }

            if let recommendation {
                Label("DORI recomienda: \(recommendation)", systemImage: "sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.amber)
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
        .background(Palette.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(statusTint.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 13, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el detalle de la unidad")
    }
}

struct AcquisitionHumanStatusIndicator: View {
    let title: String
    let group: AcquisitionHomeGroup

    private var tint: Color {
        switch group {
        case .attention: Palette.amber
        case .inProgress: Palette.info
        case .finished: Palette.neutral
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
                    .foregroundStyle(Palette.textMuted)
            }
            Text("\(offer.modelAndVersion) \(offer.year)")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.text)
            Text("\(offer.mileageText) km · VIN \(offer.abbreviatedVin)")
                .font(.subheadline)
                .foregroundStyle(Palette.textMuted)
            Text(offer.agreedPriceText ?? offer.priceText)
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.text)
            AcquisitionHumanStatusIndicator(
                title: AcquisitionHumanStatus.title(for: offer.status, role: role),
                group: group
            )
            if let recommendation {
                Text("DORI recomienda: \(recommendation)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.amber)
            }
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
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
                .foregroundStyle(Palette.amber)
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
                .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
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
                    .foregroundStyle(Palette.volt)
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
                .tint(Palette.volt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    private func contactLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Palette.text)
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
        .tint(Palette.volt)
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
        .tint(Palette.volt)
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
                                    .background(Palette.danger, in: Circle())
                                    .offset(x: 8, y: -7)
                            }
                        }
                        Text(destination.title(for: role))
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == destination ? Palette.volt : Palette.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selection == destination ? Palette.volt.opacity(0.08) : Color.clear,
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
                .stroke(Palette.hairline.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .background(Palette.canvas.opacity(0.94))
    }
}
