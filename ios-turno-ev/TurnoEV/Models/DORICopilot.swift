import Foundation

nonisolated enum DORIDemand: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case low
    case normal
    case high
    case automatic

    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: "Baja"
        case .normal: "Normal"
        case .high: "Alta"
        case .automatic: "Automática por hora"
        }
    }
}

nonisolated enum DORIDataSource: String, Codable, Sendable {
    case simulated
    case historical
    case manual
}

nonisolated enum DORIRecommendation: String, Codable, Hashable, Sendable {
    case recommended = "RECOMENDADO"
    case notRecommended = "NO RECOMENDADO"
}

/// Required JSON null used by the reserved traffic/events/weather fields. Optional
/// properties would be omitted by Swift's synthesized encoder and the V0.1 contract
/// deliberately distinguishes a present unknown value from a missing field.
nonisolated struct DORIJSONNull: Codable, Equatable, Sendable {
    init() {}
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        guard value.decodeNil() else {
            throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected null"))
        }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encodeNil()
    }
}

nonisolated struct DORITripCandidate: Codable, Equatable, Sendable {
    let fare: Double
    let pickupMinutes: Double
    let pickupKm: Double
    let tripMinutes: Double
    let tripKm: Double
    let origin: String
    let destination: String
    let timestamp: String
}

nonisolated struct DORIMarketContext: Codable, Equatable, Sendable {
    let now: String
    let hour: Int
    let weekday: Int
    let originZone: String
    let destinationZone: String
    let demand: DORIDemand
    let historicalDemand: DORIDemand?
    let forecastDemand: DORIDemand?
    let nextWaitMinutes: Double
    let destinationValue: Double
    let repositionKm: Double
    let repositionMinutes: Double
    let traffic: DORIJSONNull
    let events: DORIJSONNull
    let weather: DORIJSONNull

    private enum CodingKeys: String, CodingKey {
        case now, hour, weekday, originZone, destinationZone, demand
        case historicalDemand, forecastDemand, nextWaitMinutes, destinationValue
        case repositionKm, repositionMinutes, traffic, events, weather
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(now, forKey: .now)
        try values.encode(hour, forKey: .hour)
        try values.encode(weekday, forKey: .weekday)
        try values.encode(originZone, forKey: .originZone)
        try values.encode(destinationZone, forKey: .destinationZone)
        try values.encode(demand, forKey: .demand)
        if let historicalDemand { try values.encode(historicalDemand, forKey: .historicalDemand) }
        else { try values.encodeNil(forKey: .historicalDemand) }
        if let forecastDemand { try values.encode(forecastDemand, forKey: .forecastDemand) }
        else { try values.encodeNil(forKey: .forecastDemand) }
        try values.encode(nextWaitMinutes, forKey: .nextWaitMinutes)
        try values.encode(destinationValue, forKey: .destinationValue)
        try values.encode(repositionKm, forKey: .repositionKm)
        try values.encode(repositionMinutes, forKey: .repositionMinutes)
        try values.encode(traffic, forKey: .traffic)
        try values.encode(events, forKey: .events)
        try values.encode(weather, forKey: .weather)
    }
}

nonisolated struct DORIVehicleContext: Codable, Equatable, Sendable {
    let vehicleId: String
    let batteryPercent: Double
    let rangeKm: Double
    let consumptionKwhPerKm: Double
    let energyCostPerKm: Double
    let odometerKm: Double
    let distanceToStationKm: Double
    let destinationToStationKm: Double
    let requiredReturnAt: String
}

nonisolated struct DORIDriverContext: Codable, Equatable, Sendable {
    let driverId: String
    let shiftStart: String
    let shiftEnd: String
    let remainingMinutes: Double
    let connectedMinutes: Double
    let accumulatedIncome: Double
    let completedTrips: Int
}

nonisolated struct DORIDecisionInput: Codable, Equatable, Sendable {
    let trip: DORITripCandidate
    let market: DORIMarketContext
    let vehicle: DORIVehicleContext
    let driver: DORIDriverContext
    let source: DORIDataSource
}

nonisolated struct DORIScores: Codable, Equatable, Sendable {
    let time: Double
    let distance: Double
    let pickup: Double
    let destination: Double
    let operational: Double
}

nonisolated struct DORIDecisionResult: Codable, Equatable, Sendable {
    let recommendation: DORIRecommendation
    let reasons: [String]
    let scores: DORIScores
    let total: Double
    let threshold: Double
    let expectedAcceptValue: Double
    let expectedRejectValue: Double
    let opportunityCost: Double
    let demand: DORIDemand
    let operationalBlocks: [String]
    let nearBoundary: Bool
    let modelVersion: String
    let rulesVersion: String
    let parameterVersion: String
}

nonisolated struct DORIDecisionEvent: Codable, Equatable, Sendable {
    let schemaVersion: String
    let kind: String
    let id: UUID
    let createdAt: String
    let input: DORIDecisionInput
    let result: DORIDecisionResult
}

nonisolated enum DORICopilotInputFactory {
    static func make(
        fare: Double,
        pickupMinutes: Double,
        pickupKm: Double,
        tripMinutes: Double,
        tripKm: Double,
        hour: Int,
        demand: DORIDemand,
        batteryPercent: Double,
        rangeKm: Double,
        remainingMinutes: Double,
        destinationToStationKm: Double,
        destinationValue: Double,
        driverId: String,
        source: DORIDataSource = .manual,
        referenceDate: Date = Date()
    ) -> DORIDecisionInput {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: -6 * 3_600)!
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = hour
        components.minute = 0
        components.second = 0
        let now = calendar.date(from: components)!
        let start = calendar.date(byAdding: .minute, value: -120, to: now)!
        let end = calendar.date(byAdding: .second, value: Int(remainingMinutes * 60), to: now)!
        let calendarWeekday = calendar.component(.weekday, from: now)
        let isoWeekday = ((calendarWeekday + 5) % 7) + 1
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: now)

        return DORIDecisionInput(
            trip: .init(
                fare: fare, pickupMinutes: pickupMinutes, pickupKm: pickupKm,
                tripMinutes: tripMinutes, tripKm: tripKm, origin: "Centro",
                destination: "Zona de oficinas", timestamp: timestamp
            ),
            market: .init(
                now: timestamp, hour: hour, weekday: isoWeekday, originZone: "Centro",
                destinationZone: "Oficinas", demand: demand,
                historicalDemand: nil, forecastDemand: nil, nextWaitMinutes: 8,
                destinationValue: destinationValue, repositionKm: 1,
                repositionMinutes: 3, traffic: .init(), events: .init(), weather: .init()
            ),
            vehicle: .init(
                vehicleId: "laboratorio-ios", batteryPercent: batteryPercent,
                rangeKm: rangeKm, consumptionKwhPerKm: 0.16,
                energyCostPerKm: 0.6, odometerKm: 20_000,
                distanceToStationKm: 3, destinationToStationKm: destinationToStationKm,
                requiredReturnAt: formatter.string(from: end)
            ),
            driver: .init(
                driverId: driverId, shiftStart: formatter.string(from: start),
                shiftEnd: formatter.string(from: end), remainingMinutes: remainingMinutes,
                connectedMinutes: 120, accumulatedIncome: 300, completedTrips: 3
            ),
            source: source
        )
    }
}
