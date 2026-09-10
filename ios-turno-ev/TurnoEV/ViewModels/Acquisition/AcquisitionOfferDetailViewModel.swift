import Foundation
import Observation

nonisolated enum AcquisitionOfferDetailLoadState: Equatable, Sendable {
    case idle
    case loading
    case content
    case failed
}

@MainActor
@Observable
final class AcquisitionOfferDetailViewModel {
    let offerID: UUID
    let membership: AcquisitionMembership
    private let repository: any AcquisitionRepository
    private let realtime = AcquisitionRealtimeObserver()
    private let onChanged: () -> Void

    var state: AcquisitionOfferDetailLoadState = .idle
    var detail: AcquisitionOfferDetail?
    var isWorking = false
    var feedbackMessage: String?
    var confirmationMessage: String?

    init(
        offerID: UUID,
        membership: AcquisitionMembership,
        repository: any AcquisitionRepository,
        onChanged: @escaping () -> Void = {}
    ) {
        self.offerID = offerID
        self.membership = membership
        self.repository = repository
        self.onChanged = onChanged
    }

    func load() async {
        if detail == nil { state = .loading }
        do {
            detail = try await repository.loadOfferDetail(
                offerID: offerID,
                membership: membership
            )
            state = .content
            realtime.startForOffer(
                environmentID: membership.environmentID,
                offerID: offerID
            ) { [weak self] in
                Task { await self?.reloadFromSourceOfTruth() }
            }
        } catch {
            if detail == nil { state = .failed }
            feedbackMessage = "No pudimos actualizar esta propuesta."
        }
    }

    func stopObserving() {
        realtime.stop()
    }

    func sendCounteroffer(amountText: String) async {
        guard let amount = Self.amount(from: amountText), amount > 0 else {
            feedbackMessage = "Captura un importe válido."
            return
        }
        await perform(
            AcquisitionOfferCommand(
                offerID: offerID,
                action: .counteroffer,
                amountMxn: amount,
                message: membership.role == .doriAdmin
                    ? "Oferta de DORI"
                    : "Contraoferta del proveedor"
            ),
            confirmation: membership.role == .doriAdmin
                ? "Oferta enviada al proveedor."
                : "Contraoferta enviada a DORI."
        )
    }

    func accept() async {
        await perform(
            AcquisitionOfferCommand(
                offerID: offerID,
                action: .accept,
                message: "Oferta aceptada"
            ),
            confirmation: "Precio acordado."
        )
    }

    func award() async {
        await perform(
            AcquisitionOfferCommand(
                offerID: offerID,
                action: .award,
                amountMxn: detail?.commercialPriceMxn,
                message: "Compra confirmada"
            ),
            confirmation: "Compra confirmada."
        )
    }

    func reject() async {
        await perform(
            AcquisitionOfferCommand(
                offerID: offerID,
                action: .reject,
                message: "DORI decidió no continuar"
            ),
            confirmation: "La propuesta se cerró sin compra."
        )
    }

    func markReady() async {
        guard let orderID = detail?.delivery?.orderID else { return }
        await performDelivery(
            AcquisitionDeliveryCommand(
                orderID: orderID,
                action: .ready,
                note: "Unidad y documentos listos para entrega."
            ),
            confirmation: "DORI ya puede preparar la recepción."
        )
    }

    func receive(_ form: AcquisitionReceptionFormData) async {
        guard let orderID = detail?.delivery?.orderID else { return }
        do {
            let checklist = try form.checklist()
            await performDelivery(
                AcquisitionDeliveryCommand(
                    orderID: orderID,
                    action: .receive,
                    checklist: checklist,
                    note: form.note.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                confirmation: nil
            )
        } catch let issue as AcquisitionDeliveryIssue {
            feedbackMessage = issue.message
        } catch {
            feedbackMessage = "Revisa el checklist para continuar."
        }
    }

    func resolveCondition() async {
        guard let orderID = detail?.delivery?.orderID else { return }
        let reason = detail?.delivery?.hold?.reason ?? "Condición pendiente"
        await performDelivery(
            AcquisitionDeliveryCommand(
                orderID: orderID,
                action: .resolveCondition,
                note: "Condición resuelta: \(reason)"
            ),
            confirmation: "DORI ya puede confirmar la resolución."
        )
    }

    func closeCondition() async {
        guard let orderID = detail?.delivery?.orderID else { return }
        await performDelivery(
            AcquisitionDeliveryCommand(
                orderID: orderID,
                action: .closeCondition,
                note: "Condición verificada por DORI."
            ),
            confirmation: "Condición resuelta. Adquisición cerrada."
        )
    }

    private func perform(
        _ command: AcquisitionOfferCommand,
        confirmation: String
    ) async {
        guard !isWorking else { return }
        isWorking = true
        feedbackMessage = nil
        confirmationMessage = nil
        do {
            _ = try await repository.respondToOffer(command)
            await reloadFromSourceOfTruth()
            confirmationMessage = confirmation
            onChanged()
        } catch {
            feedbackMessage = "No pudimos completar la acción. La propuesta no cambió."
        }
        isWorking = false
    }

    private func performDelivery(
        _ command: AcquisitionDeliveryCommand,
        confirmation: String?
    ) async {
        guard !isWorking else { return }
        isWorking = true
        feedbackMessage = nil
        confirmationMessage = nil
        do {
            let result = try await repository.completeDelivery(command)
            await reloadFromSourceOfTruth()
            confirmationMessage = confirmation
                ?? result.receptionResult?.visibleLabel
                ?? "Operación actualizada."
            onChanged()
        } catch {
            feedbackMessage = "No pudimos completar la acción. La operación no cambió."
        }
        isWorking = false
    }

    private func reloadFromSourceOfTruth() async {
        do {
            detail = try await repository.loadOfferDetail(
                offerID: offerID,
                membership: membership
            )
            state = .content
        } catch {
            feedbackMessage = "No pudimos actualizar esta propuesta."
        }
    }

    nonisolated static func amount(from text: String) -> Int? {
        Int(
            text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
        )
    }
}
