import Foundation

public struct UberTestOffer: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let service: String
    public let fare: Decimal
    public let currency: String
    public let pickup: String
    public let pickupMinutes: Double?
    public let pickupDistanceKm: Double
    public let tripDurationMinutes: Double
    public let tripDistanceKm: Double
    public let riderRating: Double?
    public let expiresAfterSeconds: Int

    public init(id: String, service: String, fare: Decimal, currency: String = "MXN", pickup: String,
                pickupMinutes: Double? = nil, pickupDistanceKm: Double, tripDurationMinutes: Double, tripDistanceKm: Double,
                riderRating: Double? = nil, expiresAfterSeconds: Int = 15) {
        self.id = id; self.service = service; self.fare = fare; self.currency = currency
        self.pickup = pickup; self.pickupMinutes = pickupMinutes; self.pickupDistanceKm = pickupDistanceKm
        self.tripDurationMinutes = tripDurationMinutes; self.tripDistanceKm = tripDistanceKm
        self.riderRating = riderRating; self.expiresAfterSeconds = expiresAfterSeconds
    }
}

public struct UberTestOfferBatch: Codable, Equatable, Sendable {
    public let id: String
    public let environment: String
    public let createdAt: Date
    public let offers: [UberTestOffer]

    public init(id: String, environment: String = "TEST", createdAt: Date = .now, offers: [UberTestOffer]) throws {
        guard environment == "TEST" else { throw UberTestError.productionPayloadRejected }
        guard !offers.isEmpty, offers.count <= 10 else { throw UberTestError.invalidBatchSize }
        self.id = id; self.environment = environment; self.createdAt = createdAt; self.offers = offers
    }
}

public enum UberTestOutcome: String, Codable, Equatable, Sendable { case accepted, discarded, expired }
public struct UberTestResult: Codable, Equatable, Sendable {
    public let batchId: String; public let offerId: String; public let outcome: UberTestOutcome; public let occurredAt: Date
}
public enum UberTestError: Error, Equatable { case invalidBatchSize, productionPayloadRejected, duplicateBatch, duplicateOffer }

public struct UberTestQueue: Codable, Sendable {
    public private(set) var batch: UberTestOfferBatch?
    public private(set) var currentIndex = 0
    public private(set) var results: [UberTestResult] = []
    private var seenBatchIDs = [String]()
    private var seenOfferIDs = [String]()
    private let maxRememberedIDs = 1000

    public init() {}
    private enum CodingKeys: String, CodingKey { case batch, currentIndex, results, seenBatchIDs, seenOfferIDs }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        batch = try values.decodeIfPresent(UberTestOfferBatch.self, forKey: .batch)
        currentIndex = try values.decode(Int.self, forKey: .currentIndex)
        results = try values.decode([UberTestResult].self, forKey: .results)
        seenBatchIDs = try values.decode(Set<String>.self, forKey: .seenBatchIDs)
        seenOfferIDs = try values.decode(Set<String>.self, forKey: .seenOfferIDs)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(batch, forKey: .batch); try values.encode(currentIndex, forKey: .currentIndex)
        try values.encode(results, forKey: .results); try values.encode(seenBatchIDs, forKey: .seenBatchIDs); try values.encode(seenOfferIDs, forKey: .seenOfferIDs)
    }
    public init(snapshotData: Data) throws { self = try JSONDecoder().decode(Self.self, from: snapshotData) }
    public func snapshotData() throws -> Data { try JSONEncoder().encode(self) }
    public var current: UberTestOffer? { batch.flatMap { currentIndex < $0.offers.count ? $0.offers[currentIndex] : nil } }
    public var isWaiting: Bool { current == nil }

    public mutating func receive(_ incoming: UberTestOfferBatch) throws {
        if seenBatchIDs.contains(incoming.id) {
            guard batch?.id == incoming.id, batch?.offers == incoming.offers else { throw UberTestError.duplicateBatch }
            batch = incoming
            currentIndex = min(results.count, incoming.offers.count)
            return
        }
        guard incoming.offers.allSatisfy({ !seenOfferIDs.contains($0.id) }) else { throw UberTestError.duplicateOffer }
        seenBatchIDs.append(incoming.id); seenOfferIDs.append(contentsOf: incoming.offers.map(\.id))
        if seenBatchIDs.count > maxRememberedIDs { seenBatchIDs.removeFirst(seenBatchIDs.count - maxRememberedIDs) }
        if seenOfferIDs.count > maxRememberedIDs { seenOfferIDs.removeFirst(seenOfferIDs.count - maxRememberedIDs) }
        batch = incoming; currentIndex = 0; results = []
    }

    @discardableResult public mutating func finishCurrent(as outcome: UberTestOutcome, at date: Date = .now) -> UberTestResult? {
        guard let batch, let offer = current else { return nil }
        let result = UberTestResult(batchId: batch.id, offerId: offer.id, outcome: outcome, occurredAt: date)
        results.append(result); currentIndex += 1
        return result
    }
}
