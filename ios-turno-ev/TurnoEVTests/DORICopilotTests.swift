import Foundation
import Testing
@testable import TurnoEV

@MainActor
struct DORICopilotContractTests {
    private let driverId = "16000000-0000-4000-8000-000000000001"

    @Test func inputEncodingKeepsUnknownReservedFieldsAsExplicitNulls() throws {
        let input = makeInput(hour: 10, demand: .normal)
        let data = try JSONEncoder().encode(input)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let market = try #require(object["market"] as? [String: Any])

        #expect(market.keys.contains("historicalDemand"))
        #expect(market.keys.contains("forecastDemand"))
        #expect(market.keys.contains("traffic"))
        #expect(market.keys.contains("events"))
        #expect(market.keys.contains("weather"))
        #expect(market["historicalDemand"] is NSNull)
        #expect(market["traffic"] is NSNull)
    }

    @Test func remoteRequestContainsInputButNoClientRecommendation() throws {
        let request = DORIRemoteCopilotService.DecisionRequest(
            idempotencyKey: "ios-dori-contract-test",
            input: makeInput(hour: 10, demand: .normal)
        )
        let data = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(object.keys) == Set(["kind", "idempotencyKey", "input"]))
        #expect(object["recommendation"] == nil)
        #expect(object["result"] == nil)
    }

    @Test func localServiceExecutesTheBundledCanonicalEngine() throws {
        let result = try DORILocalCopilotService().evaluate(makeInput(hour: 10, demand: .normal))
        #expect(result.recommendation == .recommended)
        #expect((1...3).contains(result.reasons.count))
        #expect(result.modelVersion == "deterministic-0.1")
        #expect(result.rulesVersion == "0.1.0")
    }

    @Test func fixedDemandDoesNotCreateArtificialHourlyChanges() throws {
        let service = DORILocalCopilotService()
        let results = try DORICopilotStore.demonstrationHours.map {
            try service.evaluate(makeInput(hour: $0, demand: .normal))
        }
        #expect(Set(results.map(\.recommendation)).count == 1)
        #expect(Set(results.map(\.total)).count == 1)
        #expect(Set(results.map(\.threshold)).count == 1)
    }

    @Test func automaticDemandUsesTheVersionedHourlyContext() throws {
        let service = DORILocalCopilotService()
        let expected: [Int: DORIDemand] = [
            5: .low, 7: .high, 10: .normal, 14: .normal,
            18: .high, 22: .low, 1: .low,
        ]
        for hour in DORICopilotStore.demonstrationHours {
            let result = try service.evaluate(makeInput(hour: hour, demand: .automatic))
            #expect(result.demand == expected[hour])
        }
    }

    private func makeInput(hour: Int, demand: DORIDemand) -> DORIDecisionInput {
        DORICopilotInputFactory.make(
            fare: 240, pickupMinutes: 4, pickupKm: 1,
            tripMinutes: 22, tripKm: 10, hour: hour, demand: demand,
            batteryPercent: 80, rangeKm: 200, remainingMinutes: 360,
            destinationToStationKm: 8, destinationValue: 85,
            driverId: driverId, source: .simulated
        )
    }
}
