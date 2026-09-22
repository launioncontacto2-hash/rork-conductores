import Foundation
import Observation
import UIKit

enum DORICopilotMode: String, CaseIterable, Hashable, Identifiable {
    case local
    case remote
    var id: String { rawValue }
    var label: String { rawValue }
}

enum DORIEvaluationState: Equatable {
    case idle
    case evaluating
    case local(DORIDecisionResult)
    case persisted(DORIDecisionEvent)
    case failed(String)

    var result: DORIDecisionResult? {
        switch self {
        case .local(let result): result
        case .persisted(let event): event.result
        default: nil
        }
    }
}

@Observable
final class DORICopilotStore {
    var simulationCaseId: UUID?
    var simulationOffer: DORITripOffer?
    var simulationOfferImage: UIImage?
    var simulationEvaluationId: UUID?
    var simulationMessage: String?
    var fare = 240.0
    var pickupMinutes = 4.0
    var pickupKm = 1.0
    var tripMinutes = 22.0
    var tripKm = 10.0
    var hour = 10
    var demand: DORIDemand = .normal
    var batteryPercent = 80.0
    var rangeKm = 200.0
    var remainingMinutes = 360.0
    var destinationToStationKm = 8.0
    var destinationValue = 85.0
    var mode: DORICopilotMode = .local
    var state: DORIEvaluationState = .idle
    private var simulationPollingTask: Task<Void, Never>?
    private var activeCaseId: UUID?
    private var effectiveInput: DORIDecisionInput?

    static let demonstrationHours = [5, 7, 10, 14, 18, 22, 1]

    var inputFingerprint: String {
        [
            fare, pickupMinutes, pickupKm, tripMinutes, tripKm, Double(hour),
            batteryPercent, rangeKm, remainingMinutes, destinationToStationKm,
            destinationValue,
        ].map { String($0) }.joined(separator: "|") + "|\(demand.rawValue)|\(mode.rawValue)"
    }

    func invalidateResult() {
        guard case .evaluating = state else {
            state = .idle
            return
        }
    }

    func evaluate(driverId: String) async {
        state = .evaluating
        let input = makeInput(driverId: driverId)
        do {
            switch mode {
            case .local:
                state = .local(try await DORILocalCopilotService().evaluate(input))
            case .remote:
                state = .persisted(try await DORIRemoteCopilotService.evaluateAndPersist(input))
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func makeInput(driverId: String) -> DORIDecisionInput {
        DORICopilotInputFactory.make(
            fare: fare, pickupMinutes: pickupMinutes, pickupKm: pickupKm,
            tripMinutes: tripMinutes, tripKm: tripKm, hour: hour, demand: demand,
            batteryPercent: batteryPercent, rangeKm: rangeKm,
            remainingMinutes: remainingMinutes,
            destinationToStationKm: destinationToStationKm,
            destinationValue: destinationValue, driverId: driverId,
            source: mode == .local ? .simulated : .manual
        )
    }

    func startSimulationPolling() {
        guard simulationPollingTask == nil else { return }
        simulationPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.receiveSimulationCase(silent: true)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopSimulationPolling() {
        simulationPollingTask?.cancel()
        simulationPollingTask = nil
    }

    func receiveSimulationCase(silent: Bool = false) async {
        simulationMessage = nil
        do {
            let simulationCase = try await DORISimulationCopilotService.nextCase()
            guard activeCaseId != simulationCase.id else { return }
            activeCaseId = simulationCase.id
            simulationCaseId = simulationCase.id
            let input = simulationCase.inputPayload
            let offer = DORITripOffer(source: "simulation", sourceOfferId: simulationCase.testCaseId,
                product: DORITripOfferParser.normalizeProduct(input.trip.service ?? input.trip.origin), offeredEarnings: input.trip.fare,
                currency: "MXN", pickupDistanceKm: input.trip.pickupKm, pickupETAMinutes: input.trip.pickupMinutes,
                tripDistanceKm: input.trip.tripKm, tripDurationMinutes: input.trip.tripMinutes,
                riderRating: 5.0, confidence: ["product": 1, "fare": 1, "pickup": 1, "trip": 1, "rating": 1], destinationText: input.trip.destination)
            let visual = DORITripOffer(source: "simulation", sourceOfferId: simulationCase.testCaseId,
                product: DORITripOfferParser.normalizeProduct(input.trip.service ?? input.trip.origin), offeredEarnings: input.trip.fare, currency: "MXN", pickupDistanceKm: input.trip.pickupKm,
                pickupETAMinutes: input.trip.pickupMinutes, tripDistanceKm: input.trip.tripKm,
                tripDurationMinutes: input.trip.tripMinutes, riderRating: 5.0,
                confidence: ["product": 1, "fare": 1, "pickup": 1, "trip": 1, "rating": 1], destinationText: input.trip.destination)
            simulationOfferImage = DORITripOfferRenderer.render(visual)
            guard let observed = try await readVisual(simulationOfferImage!), observed.hasCriticalData else {
                simulationOffer = nil
                simulationMessage = "No pudimos leer esta oferta."
                return
            }
            simulationOffer = observed
            effectiveInput = input.withObservedOffer(observed)
            fare = input.trip.fare; pickupMinutes = input.trip.pickupMinutes; pickupKm = input.trip.pickupKm
            tripMinutes = input.trip.tripMinutes; tripKm = input.trip.tripKm; hour = input.market.hour
            demand = input.market.demand; batteryPercent = input.vehicle.batteryPercent; rangeKm = input.vehicle.rangeKm
            remainingMinutes = input.driver.remainingMinutes; destinationToStationKm = input.vehicle.destinationToStationKm
            destinationValue = input.market.destinationValue
            simulationMessage = "Oferta recibida. DORI la está analizando automáticamente."
            await evaluateSimulation()
        } catch { if !silent { simulationMessage = "No hay una oferta disponible." } }
    }

    func evaluateSimulation() async {
        guard let caseId = simulationCaseId, let effectiveInput else { simulationMessage = "No pudimos analizar esta oferta."; return }
        state = .evaluating
        do {
            let evaluation = try await DORISimulationCopilotService.evaluate(caseId: caseId, idempotencyKey: "ios-\(caseId.uuidString)", input: effectiveInput)
            simulationEvaluationId = evaluation.id
            state = .local(evaluation.resultPayload)
            simulationMessage = "Oferta analizada. Elige TOMAR o NO TOMAR."
        } catch { state = .failed("No pudimos analizar esta oferta.") }
    }

    private func readVisual(_ image: UIImage) async throws -> DORITripOffer? {
        await withCheckedContinuation { continuation in
            DORITripOfferVisionReader.read(image) { continuation.resume(returning: $0) }
        }
    }
}

private extension DORIDecisionInput {
    func withObservedOffer(_ offer: DORITripOffer) -> DORIDecisionInput {
        DORIDecisionInput(
            trip: .init(fare: offer.offeredEarnings ?? trip.fare, pickupMinutes: offer.pickupETAMinutes ?? trip.pickupMinutes,
                        pickupKm: offer.pickupDistanceKm ?? trip.pickupKm, tripMinutes: offer.tripDurationMinutes ?? trip.tripMinutes,
                        tripKm: offer.tripDistanceKm ?? trip.tripKm, origin: trip.origin, destination: trip.destination,
                        timestamp: trip.timestamp, service: offer.product == .uberX ? "UberX" : "Uber Comfort"),
            market: market, vehicle: vehicle, driver: driver, source: .simulated)
    }

}

extension DORICopilotStore {
    func confirmDecision(_ accepted: Bool) {
        simulationMessage = accepted ? "Viaje marcado como TOMAR." : "Viaje marcado como NO TOMAR."
        activeCaseId = nil
        simulationCaseId = nil
        simulationOffer = nil
        simulationOfferImage = nil
        effectiveInput = nil
        state = .idle
    }
}
