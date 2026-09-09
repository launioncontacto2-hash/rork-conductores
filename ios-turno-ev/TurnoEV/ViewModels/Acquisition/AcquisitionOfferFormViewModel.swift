import Foundation
import Observation

nonisolated enum AcquisitionOfferSubmissionState: Equatable, Sendable {
    case editing
    case submitting
    case succeeded(AcquisitionOfferSummary)
    case needsData(String)
    case failed
}

@MainActor
@Observable
final class AcquisitionOfferFormViewModel {
    let request: AcquisitionRequest
    let membership: AcquisitionMembership
    private let repository: any AcquisitionRepository
    private let onSubmitted: (AcquisitionOfferSummary) -> Void

    var form = AcquisitionOfferFormData()
    var state: AcquisitionOfferSubmissionState = .editing

    init(
        request: AcquisitionRequest,
        membership: AcquisitionMembership,
        repository: any AcquisitionRepository,
        onSubmitted: @escaping (AcquisitionOfferSummary) -> Void = { _ in }
    ) {
        self.request = request
        self.membership = membership
        self.repository = repository
        self.onSubmitted = onSubmitted
    }

    var isSubmitting: Bool {
        if case .submitting = state { return true }
        return false
    }

    var feedbackMessage: String? {
        switch state {
        case .needsData(let message): message
        case .failed: "Intenta nuevamente. Tus datos siguen en el formulario."
        default: nil
        }
    }

    func capture(_ data: Data, for kind: AcquisitionEvidenceKind) {
        form.evidence[kind] = data
        if case .needsData = state { state = .editing }
    }

    func submit() async {
        guard !isSubmitting else { return }

        let submission: AcquisitionOfferSubmission
        do {
            submission = try form.makeSubmission(request: request)
        } catch let issue as AcquisitionOfferFormIssue {
            state = .needsData(issue.message)
            return
        } catch {
            state = .needsData("Revisa la información capturada.")
            return
        }

        state = .submitting
        do {
            let result = try await repository.submitOffer(submission, membership: membership)
            state = .succeeded(result)
            onSubmitted(result)
        } catch {
            state = .failed
            print("[Adquisiciones] No se pudo enviar la propuesta: \(error.localizedDescription)")
        }
    }
}
