import SwiftUI

struct DORICopilotView: View {
    @Environment(FleetStore.self) private var fleet
    @State private var copilot = DORICopilotStore()

    private var driverId: String {
        fleet.currentPrincipal?.profileId ?? "00000000-0000-4000-8000-000000000001"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        introduction
                        modeCard
                        if let result = copilot.state.result { resultCard(result) }
                        else if case .failed(let message) = copilot.state { errorCard(message) }
                        offerCard
                        contextCard
                        temporalCard
                        evaluateButton
                        if let result = copilot.state.result { developmentCard(result) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("DORI Copiloto")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: copilot.inputFingerprint) { _, _ in copilot.invalidateResult() }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SessionMenuButton() } }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("DORI Copiloto", systemImage: "sparkles")
                .font(.system(.title2, weight: .black))
                .foregroundStyle(Palette.text)
            Text("Tu copiloto para elegir mejor cada viaje.")
                .font(.subheadline)
                .foregroundStyle(Palette.textMuted)
            Text("Laboratorio de ofertas")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Palette.amber)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    private var modeCard: some View {
        @Bindable var form = copilot
        return VStack(alignment: .leading, spacing: 12) {
            Text("Cómo evaluar")
                .font(.headline)
            Picker("Cómo evaluar", selection: $form.mode) {
                ForEach(DORICopilotMode.allCases) { mode in Text(mode.label).tag(mode) }
            }
            .pickerStyle(.segmented)
            Text(copilot.mode == .local
                 ? "Usa el motor incluido en esta app. El resultado no se guarda."
                 : "Envía la oferta al backend para evaluarla y guardarla. Requiere una sesión y la función desplegada.")
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
            if case .local = copilot.state {
                Label("Resultado local · no guardado", systemImage: "iphone")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.amber)
            } else if case .persisted = copilot.state {
                Label("Decisión guardada", systemImage: "checkmark.icloud.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.volt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panelFlat()
    }

    private func resultCard(_ result: DORIDecisionResult) -> some View {
        let tint = result.recommendation == .recommended ? Palette.volt : Palette.danger
        return VStack(alignment: .leading, spacing: 14) {
            Text(result.recommendation.rawValue)
                .font(.system(.title, weight: .black))
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(result.reasons.prefix(3).enumerated()), id: \.offset) { _, reason in
                Label(reason.hasSuffix(".") ? reason : "\(reason).", systemImage: "circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(tint.opacity(0.10), in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(tint.opacity(0.55), lineWidth: 1) }
    }

    private var offerCard: some View {
        @Bindable var form = copilot
        return VStack(alignment: .leading, spacing: 14) {
            Text("Oferta").font(.headline)
            numericField("Tarifa", unit: "$", value: $form.fare)
            numericField("Minutos para recoger", unit: "min", value: $form.pickupMinutes)
            numericField("Distancia para recoger", unit: "km", value: $form.pickupKm)
            numericField("Duración del viaje", unit: "min", value: $form.tripMinutes)
            numericField("Distancia del viaje", unit: "km", value: $form.tripKm)
        }
        .padding(16)
        .panelFlat()
    }

    private var contextCard: some View {
        @Bindable var form = copilot
        return VStack(alignment: .leading, spacing: 14) {
            Text("Contexto").font(.headline)
            Picker("Hora", selection: $form.hour) {
                ForEach(0..<24, id: \.self) { hour in Text(String(format: "%02d:00", hour)).tag(hour) }
            }
            Picker("Demanda", selection: $form.demand) {
                ForEach(DORIDemand.allCases) { demand in Text(demand.label).tag(demand) }
            }
            numericField("Batería", unit: "%", value: $form.batteryPercent)
            numericField("Autonomía", unit: "km", value: $form.rangeKm)
            numericField("Tiempo restante del turno", unit: "min", value: $form.remainingMinutes)
            numericField("Destino a estación", unit: "km", value: $form.destinationToStationKm)
            numericField("Valor provisional del destino", unit: "/ 100", value: $form.destinationValue)
        }
        .padding(16)
        .panelFlat()
    }

    private var temporalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prueba por horario").font(.headline)
            Text("Conserva la misma oferta y cambia únicamente la hora.")
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DORICopilotStore.demonstrationHours, id: \.self) { hour in
                        Button(String(format: "%02d:00", hour)) {
                            copilot.hour = hour
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(copilot.hour == hour ? Palette.volt : Palette.surfaceRaised)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panelFlat()
    }

    private var evaluateButton: some View {
        Button {
            Task { await copilot.evaluate(driverId: driverId) }
        } label: {
            HStack {
                if case .evaluating = copilot.state { ProgressView().tint(Palette.canvas) }
                Text(copilot.mode == .local ? "Analizar oferta" : "Analizar y guardar")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.volt)
        .foregroundStyle(Palette.canvas)
        .disabled({ if case .evaluating = copilot.state { true } else { false } }())
    }

    private func developmentCard(_ result: DORIDecisionResult) -> some View {
        DisclosureGroup("Datos internos · solo pruebas") {
            VStack(spacing: 8) {
                metric("Puntuación", result.total)
                metric("Límite aplicado", result.threshold)
                metric("Valor al aceptar", result.expectedAcceptValue, currency: true)
                metric("Valor al esperar", result.expectedRejectValue, currency: true)
                metric("Costo de oportunidad", result.opportunityCost, currency: true)
                if !result.operationalBlocks.isEmpty {
                    Text(result.operationalBlocks.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 12)
        }
        .font(.subheadline.weight(.semibold))
        .padding(16)
        .panelFlat()
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(Palette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .panelFlat()
    }

    private func numericField(_ title: String, unit: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Palette.textMuted)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).font(.caption).foregroundStyle(Palette.textMuted)
                .frame(width: 38, alignment: .leading)
        }
    }

    private func metric(_ title: String, _ value: Double, currency: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.textMuted)
            Spacer()
            Text(currency ? value.formatted(.currency(code: "MXN")) : value.formatted(.number.precision(.fractionLength(0...2))))
                .monospacedDigit()
        }
        .font(.caption)
    }
}

#Preview {
    DORICopilotView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
