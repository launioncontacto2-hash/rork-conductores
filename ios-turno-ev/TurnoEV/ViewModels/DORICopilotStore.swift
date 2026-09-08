import Foundation
import Observation

enum DORICopilotMode: String, CaseIterable, Hashable, Identifiable {
    case local
    case remote

    var id: String { rawValue }
    var label: String { self == .local ? "Prueba local" : "Guardar en Supabase" }
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
                state = .local(try DORILocalCopilotService().evaluate(input))
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
}
