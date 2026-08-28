import SwiftUI

/// The driver's "Más" tab: the two screens that do not fit in the bar, and the account.
///
/// Until now this tab was the one iOS generates by itself when a `TabView` overflows.
/// That list is built by the system and cannot be added to, which is why the app had no
/// visible way out of a session: the only sign-out control lives in `SessionMenuButton`,
/// and that button renders nothing for a backend identity because it is drawn from
/// `StaffAccount` — a directory entry a proved identity deliberately does not have.
///
/// So the overflow is now a real screen. Cartera and Historial are reached exactly as
/// before — one tap from this tab — and the account gets its own section underneath,
/// separated from them, where closing the session is plainly visible.
struct MoreView: View {
    @Environment(FleetStore.self) private var store

    @State private var isSigningOutPresented: Bool = false

    private enum Destination: Hashable {
        case wallet
        case history
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        operationSection
                        accountSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Más")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DemoClockButton()
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .wallet:
                    WalletView()
                        .navigationTitle("Cartera")
                        .navigationBarTitleDisplayMode(.inline)
                case .history:
                    HistoryView()
                }
            }
        }
        // Deliberately one question with two answers. Signing out of this app does not
        // destroy anything — the operational state stays under the key of whoever is
        // leaving — so there is nothing here to warn about beyond leaving.
        .confirmationDialog(
            "Cerrar sesión",
            isPresented: $isSigningOutPresented,
            titleVisibility: .visible
        ) {
            Button("Cerrar sesión", role: .destructive) {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                // The single implementation, shared with `SessionMenuButton`. A second
                // one would be a second set of rules about what a sign-out clears.
                store.signOut()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("¿Quieres salir de esta cuenta?")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Operation

    private var operationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Tu operación")

            VStack(spacing: 0) {
                NavigationLink(value: Destination.wallet) {
                    row(
                        symbol: "banknote.fill",
                        tint: Palette.volt,
                        title: "Cartera",
                        detail: "Liquidación de la semana, retenciones y pago"
                    )
                }
                .buttonStyle(.plain)

                Divider().overlay(Palette.hairline).padding(.leading, 62)

                NavigationLink(value: Destination.history) {
                    row(
                        symbol: "list.clipboard.fill",
                        tint: Palette.info,
                        title: "Historial",
                        detail: "Turnos, ingresos e incidencias"
                    )
                }
                .buttonStyle(.plain)
            }
            .panel()
        }
    }

    private func row(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Cuenta")

            VStack(spacing: 0) {
                identityBlock

                Divider().overlay(Palette.hairline)

                Button {
                    isSigningOutPresented = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(Palette.danger)
                            .frame(width: 34, height: 34)
                            .background(Palette.danger.opacity(0.12), in: .rect(cornerRadius: 12))
                        Text("Cerrar sesión")
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(Palette.danger)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar sesión")
            }
            .panel()
        }
    }

    /// Who the session belongs to, said with what the session already knows.
    ///
    /// A backend session is described by the principal the server proved; a
    /// demonstration one by its directory account. Neither is invented for the other:
    /// when there is nothing to show — which no open session should reach — the block
    /// simply is not drawn, and the way out stays visible anyway.
    @ViewBuilder
    private var identityBlock: some View {
        if let principal = store.currentPrincipal {
            identityRow(
                name: principal.name,
                role: "\(principal.role.label) · \(principal.employeeNumber)",
                detail: principal.email,
                station: principal.stationName
            )
        } else if let account = store.currentAccount {
            identityRow(
                name: account.name,
                role: "\(account.role.label) · \(account.employeeNumber)",
                detail: account.email,
                station: StaffDirectory.station(id: account.stationId)?.name
            )
        }
    }

    private func identityRow(name: String, role: String, detail: String?, station: String?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.fill")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Palette.neutral)
                .frame(width: 34, height: 34)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(.subheadline, weight: .black))
                    .foregroundStyle(Palette.text)
                Text(role)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                }
                if let station, !station.isEmpty {
                    Text(station)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

#Preview {
    MoreView()
        .environment(FleetStore())
        .environment(LabStore())
        .preferredColorScheme(.dark)
}
