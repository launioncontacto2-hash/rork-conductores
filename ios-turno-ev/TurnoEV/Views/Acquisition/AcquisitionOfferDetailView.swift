import SwiftUI
import UIKit

struct AcquisitionOfferDetailView: View {
    @State private var model: AcquisitionOfferDetailViewModel
    @State private var showsNegotiation = false
    @State private var showsAward = false
    @State private var showsRejection = false

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
        if model.membership.role == .doriAdmin {
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

nonisolated enum AcquisitionStatusText {
    static func visible(_ status: String) -> String {
        switch status {
        case "submitted": "Propuesta enviada"
        case "negotiating": "Negociación en curso"
        case "price_agreed": "Precio acordado"
        case "awarded": "Compra confirmada"
        case "rejected": "DORI decidió no continuar"
        default: "Operación actualizada"
        }
    }
}
