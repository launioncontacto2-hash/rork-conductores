import SwiftUI

/// Shift log with the weekly late-time record, plus income and incident history.
/// The credit contract lives in its own panel (`CreditView`).
struct HistoryView: View {
    @Environment(FleetStore.self) private var store

    private enum Section: String, CaseIterable {
        case shifts
        case incomes
        case incidents

        var label: String {
            switch self {
            case .shifts: "Turnos"
            case .incomes: "Ingresos"
            case .incidents: "Incidencias"
            }
        }
    }

    @State private var section: Section = .shifts
    @State private var paybackMessage: String?

    /// Pushed from the "Más" tab, so the surrounding `NavigationStack` is the one that
    /// draws the bar. Owning a second one here would stack two navigation bars on top of
    /// each other and swallow the back button.
    var body: some View {
        Group {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        lateLog

                        Picker("Sección", selection: $section) {
                            ForEach(Section.allCases, id: \.self) { item in
                                Text(item.label).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch section {
                        case .shifts: shiftList
                        case .incomes: incomeList
                        case .incidents: incidentList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SessionMenuButton()
                }
            }
        }
    }

    // MARK: - Late log

    private var lateLog: some View {
        let now = store.now
        let days = store.weeklyLateBreakdown(reference: now)
        let debt = store.weeklyLateDebt(reference: now)
        let paybackOpen = ShiftRules.isPaybackWindow(driver: store.driver, now: now)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Atrasos de la semana", systemImage: "timer")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                    Text("\(debt) min")
                        .font(.system(.title, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(debt > 0 ? Palette.amber : Palette.volt)
                }
                Spacer()
                Text(store.driver.slot.label.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Palette.textMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Palette.surfaceRaised, in: .capsule)
            }

            HStack(spacing: 6) {
                ForEach(days) { day in
                    VStack(spacing: 5) {
                        Text(day.hasShift ? "\(day.pendingMinutes)" : "—")
                            .font(.system(.subheadline, weight: .black))
                            .monospacedDigit()
                            .foregroundStyle(dayTone(day))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(dayTone(day).opacity(day.hasShift ? 0.12 : 0.04), in: .rect(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(dayTone(day).opacity(day.hasShift ? 0.45 : 0.15), lineWidth: 1)
                            }
                        Text(day.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
            }

            Text("Minutos pendientes por día. Ventana de pago \(store.driver.slot.paybackWindowLabel) · las horas fuera de esa ventana no se descuentan.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)

            if let paybackMessage {
                NoticeBanner(symbol: "checkmark.seal.fill", title: paybackMessage, tone: .volt)
            }

            BigButton(
                title: paybackOpen ? "Abonar 30 min de atraso" : "Disponible \(store.driver.slot.paybackWindowLabel)",
                symbol: "arrow.counterclockwise.circle.fill",
                isEnabled: paybackOpen && debt > 0
            ) {
                let applied = store.payLateTime(minutes: 30)
                paybackMessage = applied > 0
                    ? "\(applied) minutos abonados dentro de la ventana autorizada"
                    : "No tienes atrasos pendientes esta semana"
            }
        }
        .padding(18)
        .panel()
    }

    private func dayTone(_ day: FleetStore.LateDay) -> Color {
        guard day.hasShift else { return Palette.textMuted }
        return day.pendingMinutes > 0 ? Palette.amber : Palette.volt
    }

    // MARK: - Lists

    private var shiftList: some View {
        VStack(spacing: 12) {
            ForEach(store.history.prefix(12)) { record in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.dateShort(record.startedAt).capitalized)
                                .font(.system(.subheadline, weight: .bold))
                            Text("\(Fmt.clock(record.startedAt)) — \(Fmt.clock(record.endedAt)) · \(record.vehicleInternalNumber)")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer(minLength: 8)
                        Text(record.pendingLateMinutes > 0 ? "ATRASO \(Fmt.lateText(record.pendingLateMinutes))" : "A TIEMPO")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1)
                            .foregroundStyle(record.pendingLateMinutes > 0 ? Palette.amber : Palette.volt)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background((record.pendingLateMinutes > 0 ? Palette.amber : Palette.volt).opacity(0.13), in: .capsule)
                    }

                    HStack(spacing: 8) {
                        historyCell("Km", Fmt.km(record.kmDriven))
                        historyCell("Duración", Fmt.durationText(record.durationMinutes))
                        historyCell("Viajes", "\(record.trips)")
                        historyCell("Ingresos", Fmt.mxn(record.earningsMxn))
                    }

                    // Readings of the unit, kept turn by turn for later analysis.
                    HStack(spacing: 8) {
                        historyCell("Bat. inicio", "\(record.startBatteryPct)%")
                        historyCell("Bat. fin", "\(record.endBatteryPct)%")
                        historyCell("Consumo", "\(max(0, record.startBatteryPct - record.endBatteryPct)) pts")
                        historyCell("Odómetro", Fmt.km(record.endOdometerKm))
                    }
                }
                .padding(14)
                .panelFlat(cornerRadius: 20)
            }
        }
    }

    private func historyCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            CapsLabel(text: label)
            Text(value)
                .font(.system(.caption2, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Palette.canvas.opacity(0.6), in: .rect(cornerRadius: 12))
    }

    private var incomeList: some View {
        VStack(spacing: 12) {
            ForEach(store.incomes.prefix(15)) { entry in
                HStack(spacing: 12) {
                    Image(systemName: "banknote.fill")
                        .foregroundStyle(Palette.volt)
                        .frame(width: 42, height: 42)
                        .background(Palette.volt.opacity(0.12), in: .rect(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.dateShort(entry.date).capitalized)
                            .font(.system(.subheadline, weight: .bold))
                        Text("\(entry.platform.label) · \(entry.trips) viajes\(entry.note.map { " · \($0)" } ?? "")")
                            .font(.caption2)
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if let evidence = entry.evidence, let image = UIImage(data: evidence) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(.rect(cornerRadius: 8))
                    }

                    Text(Fmt.mxn(entry.amountMxn))
                        .font(.system(.subheadline, weight: .black))
                        .monospacedDigit()
                }
                .padding(14)
                .panelFlat(cornerRadius: 20)
            }
        }
    }

    private var incidentList: some View {
        VStack(spacing: 12) {
            if store.incidents.isEmpty {
                Text("Sin incidencias registradas.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .panelFlat(cornerRadius: 20)
            }

            ForEach(store.incidents) { incident in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(incident.kind.label, systemImage: incident.kind.symbol)
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(Palette.danger)
                        Spacer()
                        Text(incident.status.label.uppercased())
                            .font(.system(size: 9, weight: .black))
                            .tracking(1)
                            .foregroundStyle(statusTone(incident.status))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(statusTone(incident.status).opacity(0.13), in: .capsule)
                    }

                    Text(incident.description)
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)

                    HStack(spacing: 12) {
                        Label(incident.vehicleInternalNumber, systemImage: "car.side.fill")
                        Text(Fmt.dateShort(incident.createdAt).capitalized)
                        if !incident.photos.isEmpty {
                            Label("\(incident.photos.count)", systemImage: "photo.stack")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)

                    if !incident.photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(incident.photos.enumerated()), id: \.offset) { item in
                                    if let image = UIImage(data: item.element) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 64, height: 64)
                                            .clipShape(.rect(cornerRadius: 12))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .panelFlat(cornerRadius: 20)
            }
        }
    }

    private func statusTone(_ status: IncidentStatus) -> Color {
        switch status {
        case .open: Palette.danger
        case .review: Palette.amber
        case .closed: Palette.volt
        }
    }

}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .environment(FleetStore())
    .preferredColorScheme(.dark)
}
