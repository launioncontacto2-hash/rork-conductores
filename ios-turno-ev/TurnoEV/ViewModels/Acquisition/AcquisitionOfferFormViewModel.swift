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
    private(set) var failureStage: AcquisitionOfferSubmissionStage?
    private var pendingOfferID: UUID
    private var pendingIdempotencyKey: String

    init(
        request: AcquisitionRequest,
        membership: AcquisitionMembership,
        repository: any AcquisitionRepository,
        onSubmitted: @escaping (AcquisitionOfferSummary) -> Void = { _ in }
    ) {
        let attemptID = UUID()
        self.request = request
        self.membership = membership
        self.repository = repository
        self.onSubmitted = onSubmitted
        self.pendingOfferID = attemptID
        self.pendingIdempotencyKey = "ios-acquisition-offer-\(attemptID.uuidString.lowercased())"
    }

    var isSubmitting: Bool {
        if case .submitting = state { return true }
        return false
    }

    var feedbackMessage: String? {
        switch state {
        case .needsData(let message): message
        case .failed:
            failureMessage ?? "Intenta nuevamente. Tus datos siguen en el formulario."
        default: nil
        }
    }

    private var failureMessage: String?

    func capture(_ data: Data, for kind: AcquisitionEvidenceKind) {
        form.evidence[kind] = data
        if case .needsData = state { state = .editing }
    }

    func toggleRequirement(_ requirement: AcquisitionOfferRequirement) {
        if form.confirmedRequirements.contains(requirement) {
            form.confirmedRequirements.remove(requirement)
        } else {
            form.confirmedRequirements.insert(requirement)
        }
        if case .needsData = state { state = .editing }
    }

    func submit() async {
        guard !isSubmitting else { return }

        let submission: AcquisitionOfferSubmission
        do {
            submission = try form.makeSubmission(
                request: request,
                offerID: pendingOfferID,
                idempotencyKey: pendingIdempotencyKey
            )
        } catch let issue as AcquisitionOfferFormIssue {
            state = .needsData(issue.message)
            return
        } catch {
            state = .needsData("Revisa la información capturada.")
            return
        }

        state = .submitting
        failureStage = nil
        failureMessage = nil
        do {
            let result = try await repository.submitOffer(submission, membership: membership)
            state = .succeeded(result)
            onSubmitted(result)
        } catch let submissionError as AcquisitionOfferSubmissionError {
            failureStage = submissionError.stage
            failureMessage = submissionError.localizedDescription
            if submissionError.stage == .evidenceUpload {
                // An interrupted upload may have left an immutable object at
                // the attempted path. A fresh attempt receives a fresh path;
                // successful/uncertain RPC retries retain their original key.
                resetAttemptIdentity()
            }
            state = .failed
            print(
                "[Adquisiciones][TEST] envío fallido etapa=\(submissionError.stage.rawValue) "
                    + "tipo=\(String(describing: type(of: submissionError))) "
                    + "detalle=\(submissionError.technicalDescription)"
            )
        } catch {
            failureMessage = "Intenta nuevamente. Tus datos siguen en el formulario."
            state = .failed
            print("[Adquisiciones][TEST] envío fallido etapa=desconocida tipo=\(String(describing: type(of: error)))")
        }
    }

    private func resetAttemptIdentity() {
        pendingOfferID = UUID()
        pendingIdempotencyKey = "ios-acquisition-offer-\(pendingOfferID.uuidString.lowercased())"
    }
}
