import SwiftUI
import UIKit

struct AcquisitionOfferFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AcquisitionOfferFormViewModel
    @FocusState private var focusedField: String?

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
                    Text("Ofrecer un vehículo")
                        .font(.system(.title, weight: .black))
                    Text("Comparte los detalles de tu unidad")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.textMuted)

                    HStack(spacing: 0) {
                        step(1, "Requisitos", active: true)
                        Divider().overlay(Palette.volt)
                        step(2, "Información", active: true)
                        Divider().overlay(Palette.volt)
                        step(3, "Fotos y envío", active: true)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Revisa todos los requisitos", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Palette.info)
                        Text("DORI validará la información y la evidencia antes de continuar con la compra.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textMuted)
                    }
                    .padding(16)
                    .background(Palette.info.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Unidad solicitada")
                            .font(.headline)
                        Text(model.request.modelAndVersions)
                            .font(.title3.weight(.bold))
                        Text("\(model.request.yearRange) · Máx. \(model.request.maximumMileageText) km")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .panel()

                    VStack(spacing: 14) {
                        field("VIN", text: $form.form.vin, keyboard: .asciiCapable)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        field("Año", text: $form.form.year, keyboard: .numberPad)
                        field("Kilometraje", text: $form.form.mileage, keyboard: .numberPad)
                        field("Precio", text: $form.form.price, keyboard: .numberPad)
                        field("Color", text: $form.form.color, keyboard: .default)

                        Picker("¿Incluye traslado a \(model.request.deliveryCity)?", selection: $form.form.transferIncluded) {
                            Text("Sí").tag(true)
                            Text("No").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(18)
                    .panel()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Confirma los requisitos")
                            .font(.headline)
                        Text("Marca cada punto que incluye esta unidad.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textMuted)
                        ForEach(AcquisitionOfferRequirement.allCases) { requirement in
                            Button {
                                model.toggleRequirement(requirement)
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: model.form.confirmedRequirements.contains(requirement)
                                          ? "checkmark.square.fill" : "square")
                                        .font(.title3)
                                        .foregroundStyle(model.form.confirmedRequirements.contains(requirement)
                                                         ? Palette.volt : Palette.textMuted)
                                    Text(requirement.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Palette.text)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
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
                    .padding(18)
                    .panel()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resumen")
                            .font(.headline)
                        summaryLine("VIN", value: model.form.vin.isEmpty ? "Pendiente" : model.form.vin.uppercased())
                        summaryLine("Unidad", value: model.request.modelAndVersions)
                        summaryLine("Fotos", value: "\(model.form.evidence.count) de 3")
                        summaryLine(
                            "Requisitos",
                            value: "\(model.form.confirmedRequirements.count) de \(AcquisitionOfferRequirement.allCases.count)"
                        )
                    }
                    .padding(18)
                    .panel()

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

                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                focusedField = nil
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
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Palette.surface.opacity(0.98))
        }
        .navigationTitle("Tengo unidades")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Propuesta enviada", isPresented: successBinding) {
            Button("Listo") { dismiss() }
        } message: {
            Text("DORI está revisando tu unidad.")
        }
    }

    private func step(_ number: Int, _ title: String, active: Bool) -> some View {
        VStack(spacing: 6) {
            Text("\(number)")
                .font(.caption.weight(.black))
                .frame(width: 28, height: 28)
                .foregroundStyle(active ? Color.black : Palette.textMuted)
                .background(active ? Palette.volt : Palette.surfaceRaised, in: Circle())
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryLine(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(Palette.textMuted)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
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
                .focused($focusedField, equals: title)
                .submitLabel(.next)
                .padding(12)
                .background(Palette.surfaceRaised.opacity(0.7), in: .rect(cornerRadius: 12))
        }
    }
}
