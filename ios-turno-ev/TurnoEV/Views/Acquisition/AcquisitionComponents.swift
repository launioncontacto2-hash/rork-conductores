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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(Palette.text)
            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textMuted)
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
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.text)
        }
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

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AcquisitionDockDestination.allCases) { destination in
                Button {
                    selection = destination
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: destination.symbol)
                            .font(.system(size: 16, weight: .semibold))
                        Text(destination.title(for: role))
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == destination ? Palette.volt : Palette.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(selection == destination ? "Seleccionado" : "")
            }
        }
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().overlay(Palette.hairline) }
    }
}
