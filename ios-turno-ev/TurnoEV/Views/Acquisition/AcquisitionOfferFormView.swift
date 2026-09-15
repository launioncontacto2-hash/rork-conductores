import SwiftUI
import UIKit

struct AcquisitionOfferFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AcquisitionOfferFormViewModel
    @FocusState private var focusedField: String?
    @State private var showsTerms = false
    @State private var termsURL: URL?

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
            AcquisitionBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.request.modelAndVersions)
                            .font(.acquisition(.title3, weight: .bold))
                        Text("Periodo: \(model.request.fiscalPeriodText)")
                            .font(.acquisition(.caption, weight: .bold))
                            .foregroundStyle(AcquisitionTheme.accent)
                        Text("\(model.request.yearRange) · Máx. \(model.request.maximumMileageText) km · \(model.request.maximumUnitPriceText)")
                            .font(.acquisition(.subheadline))
                            .foregroundStyle(AcquisitionTheme.textSecondary)
                        if let target = model.request.targetDeliveryDate {
                            summaryLine("Fecha límite de entrega", value: target.formatted(date: .abbreviated, time: .omitted))
                        }
                        summaryLine("Estación destino", value: model.request.destinationStationName)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .acquisitionGlass()

                    VStack(spacing: 14) {
                        field("VIN", placeholder: "17 caracteres", text: $form.form.vin, keyboard: .asciiCapable)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        field("Año", placeholder: model.request.yearRange, text: $form.form.year, keyboard: .numberPad)
                        field(
                            "Kilometraje",
                            placeholder: "Máximo \(model.request.maximumMileageText) km",
                            text: $form.form.mileage,
                            keyboard: .numberPad,
                            error: mileageError
                        )
                        field(
                            "Precio",
                            placeholder: "Máximo \(model.request.maximumUnitPriceText)",
                            text: $form.form.price,
                            keyboard: .numberPad,
                            error: priceError
                        )
                        field("Color", placeholder: "Color exterior", text: $form.form.color, keyboard: .default)
                        field(
                            "Diagnóstico SOH",
                            placeholder: "Mínimo \(model.request.minimumSoh) %",
                            text: $form.form.soh,
                            keyboard: .numberPad
                        )
                        ForEach(AcquisitionOfferRequirement.allCases) { requirement in
                            checkbox(requirement.title, isOn: model.form.confirmedRequirements.contains(requirement)) {
                                model.toggleRequirement(requirement)
                            }
                        }
                        checkbox("Envío a estación \(model.request.destinationStationName)", isOn: model.form.transferIncluded) {
                            model.form.transferIncluded.toggle()
                        }
                    }
                    .padding(18)
                    .acquisitionGlass()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cargar evidencias")
                            .font(.acquisition(.headline))
                        Text("Un supervisor de DORI verificará que las fotos capturadas coincidan con la unidad recibida.")
                            .font(.acquisition(.caption))
                            .foregroundStyle(AcquisitionTheme.textSecondary)

                        ForEach(model.request.requiredEvidenceKinds) { kind in
                            PhotoSlotView(
                                title: kind.title,
                                hint: kind.hint,
                                data: model.form.evidence[kind],
                                onCapture: { model.capture($0, for: kind) }
                            )
                        }
                    }
                    .padding(18)
                    .acquisitionGlass()

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Penalizaciones por incumplimiento") {
                            Task {
                                termsURL = try? await model.deliveryTermsURL()
                                showsTerms = true
                            }
                        }
                        .font(.acquisition(.subheadline, weight: .bold))
                        checkbox(
                            "Acepto cumplir la fecha límite de entrega y las condiciones de entrega de esta solicitud.",
                            isOn: model.form.deliveryTermsAccepted
                        ) { model.form.deliveryTermsAccepted.toggle() }
                    }
                    .padding(18)
                    .acquisitionGlass()

                    if let message = model.feedbackMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.state == .failed
                                 ? "No pudimos enviar la propuesta"
                                 : "Necesitamos un dato más")
                                .font(.acquisition(.headline))
                            Text(message)
                                .font(.acquisition(.subheadline))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(AcquisitionTheme.danger.opacity(0.12), in: .rect(cornerRadius: 18))
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
                        .font(.acquisition(.headline))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AcquisitionTheme.accent)
            .disabled(model.isSubmitting)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(AcquisitionTheme.surface.opacity(0.98))
        }
        .navigationTitle("Ofrecer una unidad")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsTerms) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Condiciones aplicables")
                        .font(.acquisition(.title2, weight: .bold))
                    Text("Estas condiciones pertenecen a \(model.request.modelAndVersions), periodo \(model.request.fiscalPeriodText).")
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                    if let termsURL {
                        Link("Abrir documento", destination: termsURL)
                            .buttonStyle(.borderedProminent)
                        ShareLink(item: termsURL) { Label("Compartir o descargar", systemImage: "square.and.arrow.up") }
                    } else {
                        Text("Información de condiciones pendiente.")
                            .foregroundStyle(AcquisitionTheme.attention)
                    }
                    Spacer()
                }
                .padding(20)
                .navigationTitle("Penalizaciones")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Propuesta enviada", isPresented: successBinding) {
            Button("Listo") { dismiss() }
        } message: {
            Text("DORI está revisando tu unidad.")
        }
    }

    private func summaryLine(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(AcquisitionTheme.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.acquisition(.subheadline))
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
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        error: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.acquisition(.caption, weight: .bold))
                .foregroundStyle(AcquisitionTheme.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .focused($focusedField, equals: title)
                .submitLabel(.next)
                .padding(12)
                .background(AcquisitionTheme.surfaceRaised.opacity(0.7), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(error == nil ? Color.clear : AcquisitionTheme.danger, lineWidth: 1)
                }
            if let error {
                Text(error).font(.acquisition(.caption)).foregroundStyle(AcquisitionTheme.danger)
            }
        }
    }

    private func checkbox(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.acquisition(.title3))
                    .foregroundStyle(isOn ? AcquisitionTheme.accent : AcquisitionTheme.textSecondary)
                Text(title)
                    .font(.acquisition(.subheadline, weight: .semibold))
                    .foregroundStyle(AcquisitionTheme.text)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var mileageError: String? {
        guard let value = Int(model.form.mileage.replacingOccurrences(of: ",", with: "")),
              value > model.request.maximumMileage else { return nil }
        return "Excede el máximo solicitado de \(model.request.maximumMileageText) km."
    }

    private var priceError: String? {
        let clean = model.form.price.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        guard let value = Int(clean), value > model.request.maximumUnitPriceMxn else { return nil }
        return "Excede el máximo solicitado de \(model.request.maximumUnitPriceText)."
    }
}
