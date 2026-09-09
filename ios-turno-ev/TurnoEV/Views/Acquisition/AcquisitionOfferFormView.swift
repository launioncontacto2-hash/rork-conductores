import SwiftUI
import UIKit

struct AcquisitionOfferFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AcquisitionOfferFormViewModel

    init(
        request: AcquisitionRequest,
        membership: AcquisitionMembership,
        repository: any AcquisitionRepository,
        onSubmitted: @escaping (AcquisitionOfferSummary) -> Void
    ) {
        _model = State(
            initialValue: AcquisitionOfferFormViewModel(
                request: request,
                membership: membership,
                repository: repository,
                onSubmitted: onSubmitted
            )
        )
    }

    var body: some View {
        @Bindable var form = model

        ZStack {
            StationBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Registra una unidad")
                        .font(.system(.title2, weight: .black))
                    Text("Completa los datos y toma las tres fotografías solicitadas.")
                        .foregroundStyle(Palette.textMuted)

                    VStack(spacing: 14) {
                        field("VIN", text: $form.form.vin, keyboard: .asciiCapable)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        field("Año", text: $form.form.year, keyboard: .numberPad)
                        field("Kilometraje", text: $form.form.mileage, keyboard: .numberPad)
                        field("Precio", text: $form.form.price, keyboard: .numberPad)
                        field("Color", text: $form.form.color, keyboard: .default)

                        Picker("¿Incluye traslado a Puebla?", selection: $form.form.transferIncluded) {
                            Text("Sí").tag(true)
                            Text("No").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(18)
                    .panel()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Estado de batería")
                            .font(.headline)
                        Picker("Estado de batería", selection: $form.form.batteryKnowledge) {
                            ForEach(AcquisitionBatteryKnowledge.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()

                        if model.form.batteryKnowledge == .diagnosed {
                            field("Diagnóstico SOH (%)", text: $form.form.soh, keyboard: .numberPad)
                        }
                    }
                    .padding(18)
                    .panel()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fotografías requeridas")
                            .font(.headline)
                        Text("Usaremos la cámara cuando esté disponible. En el simulador puedes elegir una foto.")
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)

                        ForEach(AcquisitionEvidenceKind.allCases) { kind in
                            PhotoSlotView(
                                title: kind.title,
                                hint: kind.hint,
                                data: model.form.evidence[kind],
                                onCapture: { model.capture($0, for: kind) }
                            )
                        }
                    }

                    if let message = model.feedbackMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.state == .failed
                                 ? "No pudimos enviar la propuesta"
                                 : "Necesitamos un dato más")
                                .font(.headline)
                            Text(message)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Palette.danger.opacity(0.12), in: .rect(cornerRadius: 18))
                    }

                    Button {
                        Task { await model.submit() }
                    } label: {
                        HStack {
                            if model.isSubmitting { ProgressView() }
                            Text(model.isSubmitting ? "Enviando propuesta…" : "Enviar propuesta")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.volt)
                    .disabled(model.isSubmitting)
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Tengo unidades")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Propuesta enviada", isPresented: successBinding) {
            Button("Listo") { dismiss() }
        } message: {
            Text("DORI está revisando tu unidad.")
        }
    }

    private var successBinding: Binding<Bool> {
        Binding(
            get: {
                if case .succeeded = model.state { return true }
                return false
            },
            set: { _ in }
        )
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.textMuted)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .padding(12)
                .background(Palette.surfaceRaised.opacity(0.7), in: .rect(cornerRadius: 12))
        }
    }
}
