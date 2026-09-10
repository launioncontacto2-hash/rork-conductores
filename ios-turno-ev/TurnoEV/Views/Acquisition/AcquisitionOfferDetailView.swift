import SwiftUI
import UIKit

struct AcquisitionOfferDetailView: View {
    @State private var model: AcquisitionOfferDetailViewModel
    @State private var showsNegotiation = false
    @State private var showsAward = false
    @State private var showsRejection = false
    @State private var showsPreparation = false
    @State private var showsReception = false

    init(
        offerID: UUID,
        membership: AcquisitionMembership,
        repository: any AcquisitionRepository,
        onChanged: @escaping () -> Void
    ) {
        _model = State(
            initialValue: AcquisitionOfferDetailViewModel(
                offerID: offerID,
                membership: membership,
                repository: repository,
                onChanged: onChanged
            )
        )
    }

    var body: some View {
        ZStack {
            StationBackground()
            switch model.state {
            case .idle, .loading:
                ProgressView("Cargando propuesta…")
            case .failed:
                ContentUnavailableView(
                    "No pudimos cargar la propuesta",
                    systemImage: "wifi.exclamationmark",
                    description: Text("Intenta nuevamente.")
                )
            case .content:
                if let detail = model.detail {
                    detailContent(detail)
                }
            }
        }
        .navigationTitle("Propuesta")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { model.stopObserving() }
        .refreshable { await model.load() }
        .sheet(isPresented: $showsNegotiation) {
            if let detail = model.detail {
                AcquisitionNegotiationSheet(
                    detail: detail,
                    role: model.membership.role,
                    onSubmit: { amount in
                        showsNegotiation = false
                        Task { await model.sendCounteroffer(amountText: "\(amount)") }
                    }
                )
            }
        }
        .sheet(isPresented: $showsAward) {
            if let detail = model.detail {
                AcquisitionAwardSheet(
                    detail: detail,
                    onConfirm: {
                        showsAward = false
                        Task { await model.award() }
                    }
                )
            }
        }
        .sheet(isPresented: $showsPreparation) {
            AcquisitionPreparationSheet {
                showsPreparation = false
                Task { await model.markReady() }
            }
        }
        .sheet(isPresented: $showsReception) {
            AcquisitionReceptionSheet { form in
                showsReception = false
                Task { await model.receive(form) }
            }
        }
        .confirmationDialog(
            "¿No continuar con esta propuesta?",
            isPresented: $showsRejection,
            titleVisibility: .visible
        ) {
            Button("No continuar", role: .destructive) {
                Task { await model.reject() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La propuesta se cerrará sin compra.")
        }
        .alert("Listo", isPresented: confirmationBinding) {
            Button("Aceptar") { model.confirmationMessage = nil }
        } message: {
            Text(model.confirmationMessage ?? "")
        }
    }

    private func detailContent(_ detail: AcquisitionOfferDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                vehicleCard(detail.offer)

                if model.membership.role == .doriAdmin, let assessment = detail.assessment {
                    assessmentCard(assessment)
                }

                evidenceCard(detail.evidence)

                if let delivery = detail.delivery {
                    deliveryCard(delivery, offer: detail.offer)
                }

                if let last = detail.lastCounteroffer {
                    negotiationCard(detail: detail, last: last)
                }

                if let feedback = model.feedbackMessage {
                    Text(feedback)
                        .font(.subheadline)
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Palette.danger.opacity(0.12), in: .rect(cornerRadius: 14))
                }

                actions(detail)
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
    }

    private func vehicleCard(_ offer: AcquisitionOfferSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vehículo")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.textMuted)
            Text("\(offer.modelAndVersion) \(offer.year)")
                .font(.title2.weight(.black))
            Text("\(offer.mileageText) km")
            Text("Precio del proveedor: \(offer.priceText)")
                .font(.headline)
            Text(offer.declaredSoh.map { "Estado de batería: \($0) %" }
                 ?? "Estado de batería: DORI deberá verificarla")
                .foregroundStyle(Palette.textMuted)
            Text("VIN: \(offer.abbreviatedVin)")
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    private func assessmentCard(_ assessment: AcquisitionOfferAssessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(assessment.recommendation.visibleLabel)
                .font(.title3.weight(.black))
            Text(assessment.evidenceLabel)
                .font(.subheadline.weight(.semibold))
            Text(assessment.summary)
                .font(.subheadline)
                .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    private func evidenceCard(_ evidence: [AcquisitionEvidenceItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fotografías")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(evidence) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Group {
                                if let data = item.imageData, let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "photo")
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .foregroundStyle(Palette.textMuted)
                                }
                            }
                            .frame(width: 150, height: 105)
                            .background(Palette.surfaceRaised)
                            .clipShape(.rect(cornerRadius: 14))
                            Text(item.visibleTitle)
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func negotiationCard(
        detail: AcquisitionOfferDetail,
        last: AcquisitionNegotiation
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(last.actorRole == .doriAdmin ? "DORI hizo una oferta" : "El proveedor contraofertó")
                .font(.headline)
            Text("Precio original: \(detail.offer.priceText)")
            if let amount = last.amountText {
                Text("Última oferta: \(amount)")
                    .font(.title3.weight(.black))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    @ViewBuilder
    private func actions(_ detail: AcquisitionOfferDetail) -> some View {
        if let delivery = detail.delivery {
            deliveryActions(delivery)
        } else if model.membership.role == .doriAdmin {
            if !["awarded", "rejected"].contains(detail.offer.status) {
                Button("Comprar") { showsAward = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.volt)
                    .frame(maxWidth: .infinity)

                Button("Negociar") { showsNegotiation = true }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button("No continuar", role: .destructive) { showsRejection = true }
                    .frame(maxWidth: .infinity)
            } else {
                finalStatus(detail.offer.status)
            }
        } else if detail.hasPendingCounteroffer(for: .provider) {
            Button("Aceptar") {
                Task { await model.accept() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.volt)
            .disabled(model.isWorking)

            Button("Contraofertar") { showsNegotiation = true }
                .buttonStyle(.bordered)
                .disabled(model.isWorking)
        } else {
            finalStatus(detail.offer.status)
        }
    }

    private func deliveryCard(
        _ delivery: AcquisitionDeliveryJourney,
        offer: AcquisitionOfferSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.membership.role == .provider ? "Unidad confirmada" : "Unidad por recibir")
                .font(.title3.weight(.black))
            Text("\(offer.modelAndVersion) \(offer.year)")
            Text("VIN: \(offer.abbreviatedVin)")
                .foregroundStyle(Palette.textMuted)
            if let supplierName = delivery.supplierName {
                Text("Proveedor: \(supplierName)")
            }
            Text("Precio acordado: \(delivery.finalPriceText)")
            if let reception = delivery.reception {
                Text(reception.result.visibleLabel)
                    .font(.headline)
                if let summary = reception.issueSummary, !summary.isEmpty {
                    Text(summary)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            if let hold = delivery.hold {
                Divider()
                Text("Condición pendiente")
                    .font(.headline)
                Text(hold.reason)
                Text("Retención simulada: \(hold.amountText)")
                    .font(.subheadline.weight(.semibold))
                if hold.status == .readyForReview {
                    Text("El proveedor informó que ya resolvió la condición.")
                        .foregroundStyle(Palette.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel()
    }

    @ViewBuilder
    private func deliveryActions(_ delivery: AcquisitionDeliveryJourney) -> some View {
        if model.membership.role == .provider, delivery.canProviderMarkReady {
            Button("Preparar entrega") { showsPreparation = true }
                .buttonStyle(.borderedProminent)
                .tint(Palette.volt)
                .disabled(model.isWorking)
        } else if model.membership.role == .doriAdmin, delivery.canDORIReceive {
            Button("Preparar recepción") { showsReception = true }
                .buttonStyle(.borderedProminent)
                .tint(Palette.volt)
                .disabled(model.isWorking)
        } else if model.membership.role == .provider, delivery.canProviderResolve {
            VStack(alignment: .leading, spacing: 8) {
                Text("Segunda llave")
                    .font(.headline)
                Text("Entrega la llave pendiente y avisa a DORI.")
                    .foregroundStyle(Palette.textMuted)
                Button("Marcar como entregada") {
                    Task { await model.resolveCondition() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.volt)
                .disabled(model.isWorking)
            }
        } else if model.membership.role == .doriAdmin, delivery.canDORIClose {
            Button("Confirmar") {
                Task { await model.closeCondition() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.volt)
            .disabled(model.isWorking)
        } else {
            finalStatus(delivery.orderStatus)
        }
    }

    private func finalStatus(_ status: String) -> some View {
        Text(AcquisitionStatusText.visible(status))
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(16)
            .panelFlat()
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { model.confirmationMessage != nil },
            set: { if !$0 { model.confirmationMessage = nil } }
        )
    }
}

private struct AcquisitionNegotiationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let detail: AcquisitionOfferDetail
    let role: AcquisitionRole
    let onSubmit: (Int) -> Void
    @State private var customAmount = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Precio del proveedor", value: detail.offer.priceText)
                    if role == .doriAdmin,
                       let suggested = detail.assessment?.suggestedAmountMxn {
                        LabeledContent(
                            "Oferta sugerida DORI",
                            value: AcquisitionOfferSummary.currencyText(suggested)
                        )
                        Button("Enviar oferta") { onSubmit(suggested) }
                    }
                }

                Section("Otro importe") {
                    TextField("Importe", text: $customAmount)
                        .keyboardType(.numberPad)
                    Button(role == .doriAdmin ? "Enviar oferta" : "Enviar contraoferta") {
                        if let amount = AcquisitionOfferDetailViewModel.amount(from: customAmount), amount > 0 {
                            onSubmit(amount)
                        }
                    }
                }
            }
            .navigationTitle(role == .doriAdmin ? "Negociar" : "Contraofertar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

private struct AcquisitionAwardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let detail: AcquisitionOfferDetail
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Vehículo", value: "\(detail.offer.modelAndVersion) \(detail.offer.year)")
                LabeledContent("VIN", value: detail.offer.abbreviatedVin)
                LabeledContent(
                    "Precio acordado",
                    value: AcquisitionOfferSummary.currencyText(detail.commercialPriceMxn)
                )
                LabeledContent("Modalidad de pago", value: "Sin pago real en esta versión")

                Button("Confirmar compra") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.volt)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
            .padding(20)
            .navigationTitle("Confirmar compra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

private struct AcquisitionPreparationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onReady: () -> Void
    @State private var unitReady = false
    @State private var chargers = false
    @State private var keys = false
    @State private var documents = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Preparar entrega") {
                    Toggle("Unidad lista", isOn: $unitReady)
                    Toggle("Cargadores", isOn: $chargers)
                    Toggle("Llaves", isOn: $keys)
                    Toggle("Documentos", isOn: $documents)
                }
                Button("Lista para entregar", action: onReady)
                    .disabled(!(unitReady && chargers && keys && documents))
            }
            .navigationTitle("Unidad confirmada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

private struct AcquisitionReceptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (AcquisitionReceptionFormData) -> Void
    @State private var form = AcquisitionReceptionFormData()
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Checklist de recepción") {
                    answer("VIN correcto", value: $form.vinCorrect)
                    answer("Kilometraje correcto", value: $form.mileageCorrect)
                    answer("Cargadores completos", value: $form.chargersComplete)
                    answer("Llaves completas", value: $form.keysComplete)
                    answer("Daños nuevos", value: $form.newDamage)
                }
                Section("Observación opcional") {
                    TextField("Describe brevemente cualquier diferencia", text: $form.note, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(Palette.danger)
                }
                Button("Finalizar recepción") {
                    do {
                        _ = try form.checklist()
                        validationMessage = nil
                        onSubmit(form)
                    } catch let issue as AcquisitionDeliveryIssue {
                        validationMessage = issue.message
                    } catch {
                        validationMessage = "Revisa el checklist para continuar."
                    }
                }
            }
            .navigationTitle("Preparar recepción")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func answer(_ title: String, value: Binding<Bool?>) -> some View {
        Picker(title, selection: value) {
            Text("Sin responder").tag(Bool?.none)
            Text("Sí").tag(Bool?.some(true))
            Text("No").tag(Bool?.some(false))
        }
    }
}

nonisolated enum AcquisitionStatusText {
    static func visible(_ status: String) -> String {
        switch status {
        case "submitted": "Propuesta enviada"
        case "negotiating": "Negociación en curso"
        case "price_agreed": "Precio acordado"
        case "awarded": "Compra confirmada"
        case "ready_for_delivery": "Lista para entregar"
        case "accepted": "Aceptada"
        case "accepted_with_observations": "Aceptada con observaciones"
        case "accepted_with_condition": "Aceptada con condición"
        case "closed": "Adquisición cerrada"
        case "rejected": "DORI decidió no continuar"
        default: "Operación actualizada"
        }
    }
}
