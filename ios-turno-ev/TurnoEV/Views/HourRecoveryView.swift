import SwiftUI

/// Driver-facing recovery contract. The server remains authoritative for any actual
/// attendance change; this screen makes the three approved recovery bands explicit and
/// gives the prototype a usable path instead of a dead “Historial” instruction.
struct HourRecoveryView: View {
    @Environment(FleetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBand: RecoveryBand?
    @State private var submittedBand: RecoveryBand?

    private enum RecoveryBand: String, CaseIterable, Identifiable {
        case short = "15 minutos"
        case partial = "1–5 horas"
        case full = "Más de 5 horas"

        var id: Self { self }
        var symbol: String {
            switch self {
            case .short: "timer"
            case .partial: "clock.badge.checkmark"
            case .full: "calendar.badge.exclamationmark"
            }
        }
        var detail: String {
            switch self {
            case .short: "Elige si podrás asistir o si debes avisar que no podrás."
            case .partial: "Se recupera de forma fraccionada en los turnos autorizados."
            case .full: "Corresponde a una jornada completa de recuperación."
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        debtCard
                        options
                        weeklyRule
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Recuperación de horas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            CapsLabel(text: "Tiempo pendiente")
            Text("Recupera tus horas sin mezclar este proceso con bonos.")
                .font(.system(.title3, weight: .black))
            Text("La asistencia y cualquier cambio operativo se confirman en el servidor.")
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
        }
    }

    private var debtCard: some View {
        TimeScope(.minute) { now in
            VStack(alignment: .leading, spacing: 8) {
                SupSectionHeader(title: "Saldo de esta semana", subtitle: "Corte semanal independiente")
                Text("\(store.weeklyLateDebt(reference: now)) min")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.volt)
                Text("El saldo se reinicia al comenzar una nueva semana.")
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(16)
            .panel()
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Opciones", subtitle: "Selecciona la banda que corresponda a tu atraso")
            ForEach(RecoveryBand.allCases) { band in
                Button {
                    selectedBand = band
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: band.symbol)
                            .font(.title3)
                            .foregroundStyle(Palette.volt)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(band.rawValue)
                                .font(.system(.headline, weight: .bold))
                            Text(band.detail)
                                .font(.caption)
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer()
                        Image(systemName: selectedBand == band ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedBand == band ? Palette.volt : Palette.textMuted)
                    }
                    .padding(14)
                    .panelFlat(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }

            if let selectedBand {
                BigButton(
                    title: submittedBand == selectedBand ? "Solicitud registrada" : "Confirmar opción",
                    symbol: "checkmark.seal.fill",
                    isEnabled: submittedBand != selectedBand
                ) {
                    submittedBand = selectedBand
                }
                .accessibilityLabel("Confirmar recuperación de \(selectedBand.rawValue)")
            }
        }
        .padding(16)
        .panel()
    }

    private var weeklyRule: some View {
        NoticeBanner(
            symbol: "calendar",
            title: "Regla del corte semanal",
            message: "La deuda pertenece a la semana actual. Una nueva semana comienza con saldo cero; no se convierte en recuperación de bonos.",
            tone: .info
        )
    }
}

#Preview {
    HourRecoveryView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
