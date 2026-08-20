import SwiftUI

extension StaffRole {
    /// One accent for the whole product. The role is identified by its badge and its
    /// modules, not by a different colour scheme in every interface.
    var accent: Color { Palette.volt }
}

/// Badge with the identified role, reused by the login handoff and every workspace header.
struct RoleBadge: View {
    let role: StaffRole
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: role.symbol)
                .font(.system(size: compact ? 11 : 13, weight: .bold))
            Text(role.label.uppercased())
                .font(.system(size: compact ? 10 : 11, weight: .black))
                .tracking(1.1)
        }
        .foregroundStyle(role.accent)
        .padding(.horizontal, compact ? 9 : 12)
        .padding(.vertical, compact ? 5 : 7)
        .background(role.accent.opacity(0.14), in: .capsule)
        .overlay { Capsule().stroke(role.accent.opacity(0.45), lineWidth: 1) }
    }
}

/// Label / value line used inside the role cards.
struct DetailRow: View {
    let label: String
    let value: String
    /// Highlights the value when it carries a state (available, blocked, expired…).
    var tone: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(tone)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Interface reserved for a role whose modules are not published yet.
/// It renders only the scope the credential is entitled to, never driver data.
struct RoleWorkspaceView: View {
    @Environment(FleetStore.self) private var store

    let account: StaffAccount

    private var role: StaffRole { account.role }

    var body: some View {
        ZStack {
            StationBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    scopeCard
                    capabilitiesCard
                    hierarchyCard
                    roadmapCard
                    signOutRow
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: role.symbol)
                    .font(.title3)
                    .foregroundStyle(role.accent)
                    .frame(width: 46, height: 46)
                    .background(role.accent.opacity(0.14), in: .rect(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 3) {
                    Text(role.workspaceTitle)
                        .font(.system(.title3, weight: .black))
                    CapsLabel(text: "Turno EV · red nacional")
                }
                Spacer(minLength: 0)
                DemoClockButton()
                SessionMenuButton()
            }
            .padding(.top, 8)

            RoleBadge(role: role)
        }
    }

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(account.initials)
                    .font(.system(.headline, weight: .black))
                    .foregroundStyle(role.accent)
                    .frame(width: 52, height: 52)
                    .background(Palette.surfaceRaised, in: .circle)
                    .overlay { Circle().stroke(role.accent.opacity(0.5), lineWidth: 1.5) }

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.system(.headline, weight: .bold))
                    Text("\(account.employeeNumber) · \(account.status.label)")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Palette.hairline)

            DetailRow(label: "Alcance", value: role.scopeLabel)
            DetailRow(label: "Asignación", value: StaffDirectory.scopeDescription(for: account))
            if let slot = account.slot {
                DetailRow(label: "Cobertura", value: "\(slot.label) · \(slot.rangeLabel)")
            }
            if let station = StaffDirectory.station(id: account.stationId) {
                DetailRow(label: "Código de estación", value: station.code)
                DetailRow(label: "Capacidad", value: "\(station.vehicleCapacity) unidades · 4 turnos")
            }
            if let method = store.session?.method {
                DetailRow(label: "Acceso", value: method.label)
            }
        }
        .padding(16)
        .panel()
    }

    private var capabilitiesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Permisos de esta credencial")
            ForEach(Array(role.capabilities.enumerated()), id: \.offset) { _, capability in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(role.accent)
                        .padding(.top, 2)
                    Text(capability)
                        .font(.subheadline)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private var hierarchyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Jerarquía de registros")
            Text(role.registrationNote)
                .font(.subheadline)

            if !role.canRegister.isEmpty {
                HStack(spacing: 8) {
                    ForEach(role.canRegister, id: \.self) { target in
                        RoleBadge(role: target, compact: true)
                    }
                }
                .padding(.top, 2)
            }

            if let creator = StaffDirectory.account(id: account.createdById) {
                DetailRow(label: "Registrado por", value: "\(creator.name) · \(creator.role.shortLabel)")
            }
            if let authorizer = StaffDirectory.account(id: account.authorizedById) {
                DetailRow(label: "Autorizado por", value: "\(authorizer.name) · \(authorizer.role.shortLabel)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private var roadmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoticeBanner(
                symbol: "hammer.fill",
                title: "Interfaz en construcción",
                message: "Tu sesión ya está identificada y protegida. Los módulos de \(role.shortLabel.lowercased()) se publican en la siguiente entrega.",
                tone: .info
            )
            Text("Ningún dato de otra interfaz se carga en esta sesión: la app solo resuelve las pantallas del rol autenticado.")
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    private var signOutRow: some View {
        VStack(spacing: 10) {
            BigButton(title: "Cerrar sesión", symbol: "rectangle.portrait.and.arrow.right", tone: .outline) {
                store.signOut()
            }
            Button("Desvincular este dispositivo") {
                store.forgetDevice()
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Palette.textMuted)
        }
    }
}

/// Shown if a session ever tries to render an interface outside its role.
struct AccessDeniedView: View {
    @Environment(FleetStore.self) private var store

    var body: some View {
        ZStack {
            StationBackground()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Palette.danger)
                Text("Acceso no permitido")
                    .font(.system(.title2, weight: .black))
                Text("Tu credencial no tiene permisos para abrir esta interfaz. Inicia sesión con la cuenta correspondiente.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
                BigButton(title: "Volver al acceso", symbol: "arrow.left", tone: .outline) {
                    store.signOut()
                }
            }
            .padding(28)
        }
    }
}

#Preview {
    RoleWorkspaceView(account: StaffDirectory.accounts[2])
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
