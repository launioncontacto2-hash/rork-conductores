import SwiftUI
import UIKit

struct AcquisitionOfferDetailView: View {
    @State private var model: AcquisitionOfferDetailViewModel
    @State private var showsNegotiation = false
    @State private var showsAward = false
    @State private var showsRejection = false
    @State private var showsPreparation = false
    @State private var showsReception = false
    private let repository: any AcquisitionRepository

    init(
        offerID: UUID,
        membership: AcquisitionMembership,
        repository: any AcquisitionRepository,
        onChanged: @escaping () -> Void
    ) {
        self.repository = repository
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
                ProgressView("Cargando unidad…")
            case .failed:
                ContentUnavailableView(
                    "No pudimos cargar la unidad",
                    systemImage: "wifi.exclamationmark",
                    description: Text("Intenta nuevamente.")
                )
            case .content:
                if let detail = model.detail {
                    detailContent(detail)
                }
            }
        }
        .navigationTitle("Unidad")
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
            "¿No continuar con esta unidad?",
            isPresented: $showsRejection,
            titleVisibility: .visible
        ) {
            Button("No continuar", role: .destructive) {
                Task { await model.stopWithoutPurchase() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("El proceso de esta unidad terminará sin compra.")
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
                currentStateCard(detail)

                if model.membership.role == .doriAdmin, let assessment = detail.assessment {
                    assessmentCard(assessment)
                }

                evidenceCard(detail.evidence)

                NavigationLink {
                    AcquisitionUnitChatLauncherView(
                        offerID: detail.offer.id,
                        membership: model.membership,
                        profileID: model.membership.profileID,
                        repository: repository
                    )
                } label: {
                    Label("Chat de esta unidad", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.bordered)
                .tint(Palette.volt)

                if let delivery = detail.delivery {
                    deliveryCard(delivery, offer: detail.offer)
                }

                if let last = detail.lastCounteroffer {
                    negotiationCard(detail: detail, last: last)
                }

                if ["submitted", "negotiating"].contains(detail.offer.status) {
                    negotiationLimitCard(detail)
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
            Text("Unidad")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.textMuted)
            Text("\(offer.modelAndVersion) \(offer.yearText)")
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

    private func currentStateCard(_ detail: AcquisitionOfferDetail) -> some View {
        let role = model.membership.role
        let title = AcquisitionHumanStatus.title(for: detail.offer.status, role: role)
        return VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Estado actual")
            AcquisitionHumanStatusIndicator(
                title: title,
                group: AcquisitionHumanStatus.group(for: detail.offer.status, role: role)
            )
            if role == .doriAdmin, let assessment = detail.assessment {
                Text("DORI recomienda: \(assessment.recommendation.visibleLabel)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textMuted)
            }
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

    private func negotiationLimitCard(_ detail: AcquisitionOfferDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Límite de negociación", systemImage: "arrow.left.arrow.right")
                .font(.headline)
            Text("La negociación permite hasta 2 contraofertas por cada parte.")
                .font(.subheadline)
                .foregroundStyle(Palette.textMuted)
            Text("DORI \(detail.counterofferCount(for: .doriAdmin))/2 · Proveedor \(detail.counterofferCount(for: .provider))/2")
            .font(.subheadline.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panelFlat()
    }

    @ViewBuilder
    private func actions(_ detail: AcquisitionOfferDetail) -> some View {
        if let delivery = detail.delivery {
            deliveryActions(delivery)
        } else if model.membership.role == .doriAdmin {
            if !["awarded", "rejected"].contains(detail.offer.status) {
                if detail.offer.status == "price_agreed" {
                    Button("Confirmar compra") { showsAward = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.volt)
                        .frame(maxWidth: .infinity)
                } else if detail.hasPendingCounteroffer(for: .doriAdmin) {
                    Button("Aceptar") { Task { await model.accept() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.volt)
                        .disabled(model.isWorking)
                } else if detail.offer.status == "submitted" {
                    Button("Comprar") { showsAward = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.volt)
                        .frame(maxWidth: .infinity)
                }

                if detail.canCounteroffer(as: .doriAdmin),
                   detail.offer.status == "submitted"
                    || detail.hasPendingCounteroffer(for: .doriAdmin) {
                    Button("Negociar") { showsNegotiation = true }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }

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

            if detail.canCounteroffer(as: .provider) {
                Button("Contraofertar") { showsNegotiation = true }
                    .buttonStyle(.bordered)
                    .disabled(model.isWorking)
            }

            Button("No continuar", role: .destructive) { showsRejection = true }
                .disabled(model.isWorking)
        } else if model.membership.role == .provider,
                  ["submitted", "negotiating", "price_agreed"].contains(detail.offer.status) {
            Button("No continuar", role: .destructive) { showsRejection = true }
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
            Text("\(offer.modelAndVersion) \(offer.yearText)")
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
                Text(delivery.hold?.visibleConditionTitle ?? "Condición pendiente")
                    .font(.headline)
                Text("Entrega lo pendiente y avisa a DORI.")
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
        AcquisitionHumanStatusIndicator(
            title: AcquisitionHumanStatus.title(for: status, role: model.membership.role),
            group: AcquisitionHumanStatus.group(for: status, role: model.membership.role)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("La negociación permite hasta 2 contraofertas por cada parte.")
                    LabeledContent(
                        "Tus contraofertas",
                        value: "\(detail.counterofferCount(for: role))/2"
                    )
                }

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
                LabeledContent("Vehículo", value: "\(detail.offer.modelAndVersion) \(detail.offer.yearText)")
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
        case "negotiating": "DORI hizo una oferta"
        case "price_agreed": "Precio acordado"
        case "awarded": "Compra confirmada"
        case "ready_for_delivery": "Esperando entrega"
        case "accepted": "Aceptada"
        case "accepted_with_observations": "Aceptada con observaciones"
        case "accepted_with_condition": "Recibida; falta resolver un detalle"
        case "closed": "Operación terminada"
        case "rejected": "Proceso terminado sin compra"
        default: "Operación actualizada"
        }
    }
}
