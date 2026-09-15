import SwiftUI
import UIKit

private struct AcquisitionEvidenceGallerySelection: Identifiable {
    let id = UUID()
    let attachments: [AcquisitionChatAttachment]
    let initialFilename: String
}

struct AcquisitionOfferDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: AcquisitionOfferDetailViewModel
    @State private var showsNegotiation = false
    @State private var showsAward = false
    @State private var showsRejection = false
    @State private var showsPreparation = false
    @State private var showsReception = false
    @State private var showsRequirements = false
    @State private var showsNegotiationHistory = false
    @State private var selectedEvidenceID: UUID?
    @State private var evidenceGallery: AcquisitionEvidenceGallerySelection?
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
            AcquisitionBackground()
            switch model.state {
            case .idle, .loading:
                acquisitionLoadingCard
            case .failed:
                acquisitionErrorCard
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
        .fullScreenCover(item: $evidenceGallery) { selection in
            AcquisitionImageGalleryView(
                attachments: selection.attachments,
                initialFilename: selection.initialFilename
            )
        }
    }

    private func detailContent(_ detail: AcquisitionOfferDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                vehicleCard(detail)

                if model.membership.role == .doriAdmin,
                   ["submitted", "negotiating"].contains(detail.offer.status),
                   let assessment = detail.assessment {
                    assessmentCard(assessment)
                }

                negotiationHistoryCard(detail)
                requirementsCard(detail)

                if let delivery = detail.delivery,
                   delivery.reception != nil || delivery.hold != nil {
                    deliveryConditionCard(delivery)
                }

                if ["submitted", "negotiating"].contains(detail.offer.status) {
                    negotiationLimitCard(detail)
                }

                if let pending = detail.pendingCounterofferMxn {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Contraoferta pendiente")
                            .font(.acquisition(.caption, weight: .semibold))
                            .foregroundStyle(AcquisitionTheme.textSecondary)
                        Text(AcquisitionOfferSummary.currencyText(pending))
                            .font(.title3.monospacedDigit().weight(.bold))
                        Text("Precio actual: \(AcquisitionOfferSummary.currencyText(detail.commercialPriceMxn))")
                            .font(.acquisition(.caption))
                            .foregroundStyle(AcquisitionTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .acquisitionGlass()
                }

                if let feedback = model.feedbackMessage {
                    Text(feedback)
                        .font(.acquisition(.subheadline))
                        .foregroundStyle(AcquisitionTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(AcquisitionTheme.danger.opacity(0.12), in: .rect(cornerRadius: 14))
                }

                actions(detail)
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            chatButton(detail)
        }
    }

    private func vehicleCard(_ detail: AcquisitionOfferDetail) -> some View {
        let offer = detail.offer
        let selected = selectedEvidence(in: detail.evidence)
        return VStack(alignment: .leading, spacing: 14) {
            if let selected,
               let data = selected.imageData,
               let image = UIImage(data: data) {
                Button {
                    showEvidenceGallery(detail.evidence, initial: selected)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 238)
                            .clipped()
                        Text("\(selectedEvidenceIndex(in: detail.evidence) + 1) de \(availableEvidence(in: detail.evidence).count)")
                            .font(.acquisition(.caption2, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.58), in: Capsule())
                            .padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(AcquisitionTheme.subtleBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foto \(selectedEvidenceIndex(in: detail.evidence) + 1) de \(availableEvidence(in: detail.evidence).count), activar para ver en pantalla completa")
            } else {
                ZStack {
                    AcquisitionTheme.surfaceRaised
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                        Text("Fotografía no disponible")
                            .font(.acquisition(.subheadline, weight: .semibold))
                    }
                    .foregroundStyle(AcquisitionTheme.textSecondary)
                }
                .frame(height: 238)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            }

            if availableEvidence(in: detail.evidence).count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(availableEvidence(in: detail.evidence)) { item in
                            Button {
                                selectedEvidenceID = item.id
                            } label: {
                                if let data = item.imageData, let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 58, height: 58)
                                        .clipped()
                                        .clipShape(.rect(cornerRadius: 12))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(selected?.id == item.id ? AcquisitionTheme.accent : AcquisitionTheme.subtleBorder, lineWidth: selected?.id == item.id ? 2 : 1)
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Seleccionar \(item.visibleTitle)")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(offer.modelAndVersion)
                        .font(.acquisitionFixed(18, weight: .bold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Text("VIN \(offer.abbreviatedVin)")
                        .font(.caption.monospaced())
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
                Spacer(minLength: 6)
                acquisitionStatusChip(detail.offer.status)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                AcquisitionUnitFact(icon: "calendar", label: "Año", value: offer.yearText)
                AcquisitionUnitFact(icon: "gauge.with.dots.needle.50percent", label: "Kilometraje", value: "\(offer.mileageText) km")
                AcquisitionUnitFact(icon: "paintpalette", label: "Color", value: offer.color.flatMap { $0.isEmpty ? nil : $0 } ?? "Por confirmar")
                AcquisitionUnitFact(icon: "dollarsign.circle", label: "Precio", value: offer.agreedPriceText ?? offer.priceText)
                AcquisitionUnitFact(icon: "battery.75percent", label: "Batería", value: offer.declaredSoh.map { "\($0) %" } ?? "Por verificar")
                AcquisitionUnitFact(icon: "building.2", label: "Proveedor", value: detail.supplierName ?? "Información pendiente")
            }

            if model.membership.role == .provider, detail.offer.status == "price_agreed" {
                Text("Esperando confirmación de compra de DORI.")
                    .font(.acquisition(.subheadline, weight: .semibold))
                    .foregroundStyle(AcquisitionTheme.info)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .acquisitionGlassPanel(cornerRadius: 24)
        .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 10)
    }

    private func assessmentCard(_ assessment: AcquisitionOfferAssessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(assessment.recommendation.visibleLabel)
                .font(.acquisition(.title3, weight: .bold))
            Text(assessment.summary)
                .font(.acquisition(.subheadline))
                .foregroundStyle(AcquisitionTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .acquisitionGlass()
    }

    private func requirementsCard(_ detail: AcquisitionOfferDetail) -> some View {
        let requirements = detail.requirements.isEmpty
            ? AcquisitionRequestDraft.defaultRequirements
            : detail.requirements
        let commercialRequirements = requirements.filter { $0.category != .evidence }
        let photographicRequirements = requirements.filter { $0.category == .evidence }
        let capturedCount = photographicRequirements.filter { requirement in
            detail.evidence.contains { $0.kind.rawValue == requirement.id && $0.imageData != nil }
        }.count
        return AcquisitionCollapsibleSection(
            title: "Requisitos de la solicitud",
            systemImage: "checklist",
            isExpanded: $showsRequirements,
            reduceMotion: reduceMotion
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if !commercialRequirements.isEmpty {
                    CapsLabel(text: "Requisitos comerciales")
                }
                ForEach(commercialRequirements) { requirement in
                    requirementRow(
                        title: requirement.title,
                        value: requirement.value,
                        complete: nil
                    )
                }

                if !photographicRequirements.isEmpty {
                    Divider().overlay(AcquisitionTheme.subtleBorder)
                    CapsLabel(text: "Fotografías de la unidad")
                    Button {
                        if let first = availableEvidence(in: detail.evidence).first {
                            showEvidenceGallery(detail.evidence, initial: first)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: capturedCount >= photographicRequirements.count ? "checkmark.circle.fill" : "photo.stack")
                                .foregroundStyle(capturedCount >= photographicRequirements.count ? AcquisitionTheme.accent : AcquisitionTheme.attention)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(capturedCount) de \(photographicRequirements.count) fotos capturadas")
                                    .font(.acquisition(.subheadline, weight: .semibold))
                                Text("Activar para abrir la galería")
                                    .font(.acquisition(.caption))
                                    .foregroundStyle(AcquisitionTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.acquisition(.caption, weight: .bold))
                                .foregroundStyle(AcquisitionTheme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(availableEvidence(in: detail.evidence).isEmpty)
                }
            }
            .padding(.top, 12)
        }
    }

    private func requirementRow(title: String, value: String, complete: Bool?) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: complete == true ? "checkmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(complete == true ? AcquisitionTheme.accent : AcquisitionTheme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.acquisition(.subheadline, weight: .semibold))
                Text(value).font(.acquisition(.caption)).foregroundStyle(AcquisitionTheme.textSecondary)
                Text(complete == true ? "Verificado" : "Pendiente de verificación")
                    .font(.acquisition(.caption2, weight: .semibold))
                    .foregroundStyle(complete == true ? AcquisitionTheme.accent : AcquisitionTheme.textSecondary)
            }
            Spacer()
        }
    }

    private func primaryEvidence(in evidence: [AcquisitionEvidenceItem]) -> AcquisitionEvidenceItem? {
        evidence.first { $0.kind == .exteriorDriverSide }
            ?? evidence.first { $0.kind == .front }
            ?? evidence.first
    }

    private func showEvidenceGallery(
        _ evidence: [AcquisitionEvidenceItem],
        initial: AcquisitionEvidenceItem
    ) {
        let attachments = evidence.compactMap { item -> AcquisitionChatAttachment? in
            guard let data = item.imageData else { return nil }
            return AcquisitionChatAttachment(
                data: data,
                fileExtension: "jpg",
                contentType: "image/jpeg",
                filename: "\(item.kind.rawValue).jpg"
            )
        }
        evidenceGallery = AcquisitionEvidenceGallerySelection(
            attachments: attachments,
            initialFilename: "\(initial.kind.rawValue).jpg"
        )
    }

    private func negotiationHistoryCard(_ detail: AcquisitionOfferDetail) -> some View {
        AcquisitionCollapsibleSection(
            title: "Historial de negociación",
            systemImage: "scroll",
            isExpanded: $showsNegotiationHistory,
            reduceMotion: reduceMotion
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(detail.commercialHistory.enumerated()), id: \.element.id) { index, movement in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(movement.actorRole == .doriAdmin ? AcquisitionTheme.info.opacity(0.18) : AcquisitionTheme.accent.opacity(0.18))
                            Image(systemName: movement.actorRole == .doriAdmin ? "building.2.fill" : "storefront.fill")
                                .font(.acquisition(.caption, weight: .bold))
                                .foregroundStyle(movement.actorRole == .doriAdmin ? AcquisitionTheme.info : AcquisitionTheme.accent)
                        }
                        .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(movement.actorLabel) · \(movement.movementLabel)")
                                .font(.acquisition(.subheadline, weight: .semibold))
                            if index > 0 {
                                Text("\(detail.commercialHistory[index - 1].amountText) → \(movement.amountText)")
                                    .font(.subheadline.monospacedDigit().weight(.bold))
                            } else {
                                Text(movement.amountText)
                                    .font(.subheadline.monospacedDigit().weight(.bold))
                            }
                            if let createdAt = movement.createdAt {
                                Text(AcquisitionSpanishDate.dateTime(createdAt))
                                    .font(.acquisition(.caption2))
                                    .foregroundStyle(AcquisitionTheme.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    if index < detail.commercialHistory.count - 1 {
                        Divider().overlay(AcquisitionTheme.subtleBorder)
                            .padding(.leading, 46)
                    }
                }
            }
            .padding(.top, 12)
        }
    }

    private func negotiationLimitCard(_ detail: AcquisitionOfferDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Límite de negociación", systemImage: "arrow.left.arrow.right")
                .font(.acquisition(.headline))
            Text("La negociación permite hasta 2 contraofertas por cada parte.")
                .font(.acquisition(.subheadline))
                .foregroundStyle(AcquisitionTheme.textSecondary)
            Text("DORI \(detail.counterofferCount(for: .doriAdmin))/2 · Proveedor \(detail.counterofferCount(for: .provider))/2")
            .font(.acquisition(.subheadline, weight: .bold))
            if detail.bothPartiesReachedCounterofferLimit {
                Text("Se alcanzó el límite de negociación.")
                    .font(.acquisition(.subheadline, weight: .bold))
                    .foregroundStyle(AcquisitionTheme.attention)
                Text("Puedes aceptar el último precio o no continuar.")
                    .font(.acquisition(.subheadline))
                    .foregroundStyle(AcquisitionTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .acquisitionGlass()
    }

    @ViewBuilder
    private func actions(_ detail: AcquisitionOfferDetail) -> some View {
        if let delivery = detail.delivery {
            deliveryActions(delivery)
        } else if model.membership.role == .doriAdmin {
            if !["awarded", "rejected"].contains(detail.offer.status) {
                Button("Comprar · \(AcquisitionOfferSummary.currencyText(detail.commercialPriceMxn))") {
                    showsAward = true
                }
                .buttonStyle(.borderedProminent)
                .tint(AcquisitionTheme.accent)
                .frame(maxWidth: .infinity)

                if detail.hasPendingCounteroffer(for: .doriAdmin) {
                    Button(detail.bothPartiesReachedCounterofferLimit ? "Aceptar último precio" : "Aceptar") {
                        Task { await model.accept() }
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(AcquisitionTheme.accent)
                        .disabled(model.isWorking)
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
            Button(detail.bothPartiesReachedCounterofferLimit ? "Aceptar último precio" : "Aceptar") {
                Task { await model.accept() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AcquisitionTheme.accent)
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

    private func deliveryConditionCard(_ delivery: AcquisitionDeliveryJourney) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recepción y condiciones").font(.acquisition(.headline))
            if let reception = delivery.reception {
                Text(reception.result.visibleLabel)
                    .font(.acquisition(.headline))
                if let summary = reception.issueSummary, !summary.isEmpty {
                    Text(summary)
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
            }
            if let hold = delivery.hold {
                Divider()
                Text("Condición pendiente")
                    .font(.acquisition(.headline))
                Text(hold.reason)
                Text("Retención simulada: \(hold.amountText)")
                    .font(.acquisition(.subheadline, weight: .semibold))
                if hold.status == .readyForReview {
                    Text("El proveedor informó que ya resolvió la condición.")
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .acquisitionGlass()
    }

    @ViewBuilder
    private func deliveryActions(_ delivery: AcquisitionDeliveryJourney) -> some View {
        if model.membership.role == .provider, delivery.canProviderMarkReady {
            Button("Preparar entrega") { showsPreparation = true }
                .buttonStyle(.borderedProminent)
                .tint(AcquisitionTheme.accent)
                .disabled(model.isWorking)
                .frame(maxWidth: .infinity)
        } else if model.membership.role == .doriAdmin, delivery.canDORIReceive {
            Button("Preparar recepción") { showsReception = true }
                .buttonStyle(.borderedProminent)
                .tint(AcquisitionTheme.accent)
                .disabled(model.isWorking)
        } else if model.membership.role == .provider, delivery.canProviderResolve {
            VStack(alignment: .leading, spacing: 8) {
                Text(delivery.hold?.visibleConditionTitle ?? "Condición pendiente")
                    .font(.acquisition(.headline))
                Text("Entrega lo pendiente y avisa a DORI.")
                    .foregroundStyle(AcquisitionTheme.textSecondary)
                Button("Marcar como entregada") {
                    Task { await model.resolveCondition() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AcquisitionTheme.accent)
                .disabled(model.isWorking)
            }
        } else if model.membership.role == .doriAdmin, delivery.canDORIClose {
            Button("Confirmar") {
                Task { await model.closeCondition() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AcquisitionTheme.accent)
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
        .acquisitionGlass()
    }

    private var acquisitionLoadingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 19)
                .fill(AcquisitionTheme.surfaceRaised)
                .frame(height: 238)
            RoundedRectangle(cornerRadius: 8)
                .fill(AcquisitionTheme.surfaceRaised)
                .frame(width: 220, height: 25)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AcquisitionTheme.surfaceRaised)
                        .frame(height: 64)
                }
            }
            ProgressView("Cargando unidad…")
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .acquisitionGlass()
        .padding(18)
        .accessibilityLabel("Cargando unidad")
    }

    private var acquisitionErrorCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(AcquisitionTheme.attention)
            Text("No pudimos cargar la unidad")
                .font(.acquisition(.headline))
            Text("La información anterior permanece segura. Intenta nuevamente.")
                .font(.acquisition(.subheadline))
                .foregroundStyle(AcquisitionTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Reintentar") { Task { await model.load() } }
                .buttonStyle(.borderedProminent)
                .tint(AcquisitionTheme.accent)
        }
        .padding(22)
        .acquisitionGlass()
        .padding(18)
    }

    private func chatButton(_ detail: AcquisitionOfferDetail) -> some View {
        NavigationLink {
            AcquisitionUnitChatLauncherView(
                offerID: detail.offer.id,
                membership: model.membership,
                profileID: model.membership.profileID,
                repository: repository
            )
        } label: {
            Label("Chat de esta unidad", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.acquisition(.headline))
                .foregroundStyle(AcquisitionTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AcquisitionTheme.accent.opacity(0.16), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AcquisitionTheme.accent.opacity(0.30), lineWidth: 1)
                }
        }
        .buttonStyle(AcquisitionPremiumPressStyle(reduceMotion: reduceMotion))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func availableEvidence(in evidence: [AcquisitionEvidenceItem]) -> [AcquisitionEvidenceItem] {
        evidence.filter { $0.imageData != nil }
    }

    private func selectedEvidence(in evidence: [AcquisitionEvidenceItem]) -> AcquisitionEvidenceItem? {
        let available = availableEvidence(in: evidence)
        return available.first { $0.id == selectedEvidenceID }
            ?? primaryEvidence(in: available)
    }

    private func selectedEvidenceIndex(in evidence: [AcquisitionEvidenceItem]) -> Int {
        let available = availableEvidence(in: evidence)
        guard let selected = selectedEvidence(in: evidence) else { return 0 }
        return available.firstIndex(where: { $0.id == selected.id }) ?? 0
    }

    private func acquisitionStatusChip(_ status: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AcquisitionTheme.info)
                .frame(width: 6, height: 6)
            Text(AcquisitionHumanStatus.title(for: status, role: model.membership.role))
                .font(.acquisition(.caption2, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .foregroundStyle(AcquisitionTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1) }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { model.confirmationMessage != nil },
            set: { if !$0 { model.confirmationMessage = nil } }
        )
    }
}

struct AcquisitionCollapsibleSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let reduceMotion: Bool
    let content: Content

    init(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        reduceMotion: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        _isExpanded = isExpanded
        self.reduceMotion = reduceMotion
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.timingCurve(0.22, 0.75, 0.30, 1, duration: 0.24)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .foregroundStyle(AcquisitionTheme.accent)
                    Text(title)
                        .font(.acquisitionFixed(12.5, weight: .semibold))
                        .foregroundStyle(AcquisitionTheme.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.acquisition(.caption, weight: .bold))
                        .foregroundStyle(AcquisitionTheme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .acquisitionGlassPanel(cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }
}

struct AcquisitionUnitFact: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.acquisition(.caption, weight: .bold))
                .foregroundStyle(AcquisitionTheme.textSecondary)
            Text(value)
                .font(.acquisition(.footnote, weight: .semibold))
                .foregroundStyle(AcquisitionTheme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.center)
            Text(label)
                .font(.acquisition(.caption2, weight: .medium))
                .foregroundStyle(AcquisitionTheme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
        .padding(10)
        .background(Color.white.opacity(0.035), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
    }
}

struct AcquisitionSheetFactRow: View {
    let icon: String
    let label: String
    let value: String
    var drawsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(AcquisitionTheme.textSecondary.opacity(0.7))
                Text(label)
                    .font(.acquisition(.subheadline))
                    .foregroundStyle(AcquisitionTheme.textSecondary)
                Spacer()
                Text(value)
                    .font(.acquisition(.subheadline, weight: .semibold))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 11)
            if drawsDivider {
                Divider().overlay(Color.white.opacity(0.08))
            }
        }
    }
}

struct AcquisitionPremiumPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(
                reduceMotion ? nil : .timingCurve(0.22, 0.75, 0.30, 1, duration: 0.15),
                value: configuration.isPressed
            )
    }
}

private struct AcquisitionGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .background(Color.white.opacity(0.025), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.035))
                    .frame(height: 1)
                    .clipShape(.rect(cornerRadius: cornerRadius))
            }
    }
}

extension View {
    func acquisitionGlassPanel(cornerRadius: CGFloat = 20) -> some View {
        modifier(AcquisitionGlassPanelModifier(cornerRadius: cornerRadius))
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
                LabeledContent("Proveedor", value: detail.supplierName ?? "Proveedor autorizado")
                LabeledContent("Modalidad de pago", value: "Sin pago real en esta versión")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Resumen de negociación")
                        .font(.acquisition(.headline))
                    ForEach(detail.commercialHistory) { movement in
                        HStack {
                            Text("\(movement.actorLabel) · \(movement.movementLabel)")
                                .font(.acquisition(.caption))
                            Spacer()
                            Text(movement.amountText)
                                .font(.caption.monospacedDigit().weight(.bold))
                        }
                    }
                }

                Button("Confirmar compra") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .tint(AcquisitionTheme.accent)
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
                        .foregroundStyle(AcquisitionTheme.danger)
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
