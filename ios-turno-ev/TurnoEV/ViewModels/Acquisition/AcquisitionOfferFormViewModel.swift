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
    typealias OdometerEvidenceValidator = (Data, Int?) async -> AcquisitionEvidenceValidationStatus
    typealias VINEvidenceValidator = (Data, String) async -> AcquisitionEvidenceValidationStatus

    let request: AcquisitionRequest
    let membership: AcquisitionMembership
    private let repository: any AcquisitionRepository
    private let onSubmitted: (AcquisitionOfferSummary) -> Void
    private let odometerEvidenceValidator: OdometerEvidenceValidator
    private let vinEvidenceValidator: VINEvidenceValidator

    var form = AcquisitionOfferFormData()
    var state: AcquisitionOfferSubmissionState = .editing
    private(set) var evidenceMessages: [AcquisitionEvidenceKind: String] = [:]
    private(set) var validatingEvidence: Set<AcquisitionEvidenceKind> = []
    private(set) var validationIssue: AcquisitionOfferFormIssue?
    private(set) var failureStage: AcquisitionOfferSubmissionStage?
    private var pendingOfferID: UUID
    private var pendingIdempotencyKey: String

    init(
        request: AcquisitionRequest,
        membership: AcquisitionMembership,
        repository: any AcquisitionRepository,
        odometerEvidenceValidator: @escaping OdometerEvidenceValidator = AcquisitionEvidenceValidator.validateOdometer,
        vinEvidenceValidator: @escaping VINEvidenceValidator = AcquisitionEvidenceValidator.validateVIN,
        onSubmitted: @escaping (AcquisitionOfferSummary) -> Void = { _ in }
    ) {
        let attemptID = UUID()
        self.request = request
        self.membership = membership
        self.repository = repository
        self.odometerEvidenceValidator = odometerEvidenceValidator
        self.vinEvidenceValidator = vinEvidenceValidator
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

    func deliveryTermsURL() async throws -> URL? {
        try await repository.requestDocumentURL(for: request)
    }

    func capture(_ data: Data, for kind: AcquisitionEvidenceKind) {
        let normalized = AcquisitionEvidenceValidator.normalizedJPEG(data)
        Task { await acceptCapture(normalized, for: kind) }
        if case .needsData = state { state = .editing }
    }

    private func acceptCapture(_ data: Data, for kind: AcquisitionEvidenceKind) async {
        validatingEvidence.insert(kind)
        defer { validatingEvidence.remove(kind) }
        evidenceMessages[kind] = nil

        switch kind {
        case .odometer, .dashboard:
            let mileage = Int(form.mileage.replacingOccurrences(of: ",", with: ""))
            let result = await odometerEvidenceValidator(
                data,
                mileage
            )
            form.validationResults.odometer = result
            guard result == .match else {
                form.evidence[kind] = nil
                evidenceMessages[kind] = result == .mismatch
                    ? AcquisitionOfferFormIssue.odometerMismatch.message
                    : AcquisitionOfferFormIssue.odometerNotDetected.message
                return
            }
        case .vin, .originInvoice:
            let result = await vinEvidenceValidator(
                data,
                form.vin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            )
            form.validationResults.vin = result
            guard result == .match else {
                form.evidence[kind] = nil
                evidenceMessages[kind] = result == .mismatch
                    ? AcquisitionOfferFormIssue.vinMismatch.message
                    : AcquisitionOfferFormIssue.vinNotDetected.message
                return
            }
        default:
            break
        }
        form.evidence[kind] = data
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

        await refreshAutomaticValidations()

        let submission: AcquisitionOfferSubmission
        do {
            submission = try form.makeSubmission(
                request: request,
                offerID: pendingOfferID,
                idempotencyKey: pendingIdempotencyKey
            )
        } catch let issue as AcquisitionOfferFormIssue {
            validationIssue = issue
            state = .needsData(issue.message)
            return
        } catch {
            state = .needsData("Revisa la información capturada.")
            return
        }

        state = .submitting
        validationIssue = nil
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

    private func refreshAutomaticValidations() async {
        let mileage = Int(form.mileage.replacingOccurrences(of: ",", with: ""))
        if let data = form.evidence[.odometer] ?? form.evidence[.dashboard] {
            form.validationResults.odometer = await odometerEvidenceValidator(
                data,
                mileage
            )
        }
        if let data = form.evidence[.vin] ?? form.evidence[.originInvoice] {
            form.validationResults.vin = await vinEvidenceValidator(
                data,
                form.vin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            )
        }
    }

    private func resetAttemptIdentity() {
        pendingOfferID = UUID()
        pendingIdempotencyKey = "ios-acquisition-offer-\(pendingOfferID.uuidString.lowercased())"
    }
}
