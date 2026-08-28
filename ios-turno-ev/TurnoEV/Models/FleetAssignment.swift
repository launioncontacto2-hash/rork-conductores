import Foundation

/// The fixed unit a driver works with. Recruitment hands the person to the station and
/// the supervisor is the only role that ties a unit to them: a titular unit, or a
/// temporary substitute while the titular one is in the workshop.

nonisolated enum AssignedUnitKind: String, Codable, Sendable {
    case titular
    case substitute

    var label: String {
        switch self {
        case .titular: "Unidad fija"
        case .substitute: "Unidad sustituta"
        }
    }

    var shortLabel: String {
        switch self {
        case .titular: "Fija"
        case .substitute: "Sustituta"
        }
    }

    var symbol: String {
        switch self {
        case .titular: "car.side.fill"
        case .substitute: "arrow.triangle.2.circlepath"
        }
    }
}

/// One driver ↔ one unit. Written by the supervisor, read by the driver app.
nonisolated struct VehicleAssignment: Codable, Identifiable, Sendable {
    let id: String
    let stationId: String
    let driverId: String
    var driverName: String
    var vehicleId: String
    var vehicleNumber: String
    var kind: AssignedUnitKind
    /// Unit the driver returns to once the substitute ends.
    var titularVehicleId: String?
    var titularVehicleNumber: String?
    var note: String
    var assignedBy: String
    var assignedAt: Date
    /// Who tied this unit to this driver. Never defaulted at the writing end: every
    /// caller has to say where the assignment came from.
    let origin: AssignmentOrigin

    var isSubstitute: Bool { kind == .substitute }

    /// Whether this record can be presented as the station's own act.
    var isAuthoritative: Bool { origin == .backend }
}

extension VehicleAssignment {
    /// Conservative reading of a record written before provenance existed.
    ///
    /// Everything already on a device was written by a demonstration session — the only
    /// kind that could write one — so a missing stamp reads `.simulated`. It is never
    /// promoted: an old row keeps working for the demonstration world and stays invisible
    /// to a proved identity, which is the whole point of reading it conservatively.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        stationId = try container.decode(String.self, forKey: .stationId)
        driverId = try container.decode(String.self, forKey: .driverId)
        driverName = try container.decode(String.self, forKey: .driverName)
        vehicleId = try container.decode(String.self, forKey: .vehicleId)
        vehicleNumber = try container.decode(String.self, forKey: .vehicleNumber)
        kind = try container.decode(AssignedUnitKind.self, forKey: .kind)
        titularVehicleId = try container.decodeIfPresent(String.self, forKey: .titularVehicleId)
        titularVehicleNumber = try container.decodeIfPresent(String.self, forKey: .titularVehicleNumber)
        note = try container.decode(String.self, forKey: .note)
        assignedBy = try container.decode(String.self, forKey: .assignedBy)
        assignedAt = try container.decode(Date.self, forKey: .assignedAt)
        origin = try container.decodeIfPresent(AssignmentOrigin.self, forKey: .origin) ?? .simulated
    }
}

/// Shared assignment registry. Same bridge pattern as the recruitment handoff: what the
/// supervisor writes, the driver app reads on its next refresh.
nonisolated enum AssignmentBook {
    private static let storageKey = "turnoev.assignments.v1"

    private static func load() -> [VehicleAssignment] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([VehicleAssignment].self, from: data)) ?? []
    }

    private static func save(_ assignments: [VehicleAssignment]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(assignments) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func all() -> [VehicleAssignment] {
        load().sorted { $0.assignedAt > $1.assignedAt }
    }

    static func assignments(stationId: String) -> [VehicleAssignment] {
        all().filter { $0.stationId == stationId }
    }

    static func assignment(driverId: String?) -> VehicleAssignment? {
        guard let driverId else { return nil }
        return load().first { $0.driverId == driverId }
    }

    /// The driver currently holding a unit, if any. Keeps one unit tied to one person.
    static func holder(vehicleId: String) -> VehicleAssignment? {
        load().first { $0.vehicleId == vehicleId }
    }

    static func upsert(_ assignment: VehicleAssignment) {
        var current = load()
        current.removeAll { $0.driverId == assignment.driverId }
        // A unit cannot be tied to two people at the same time.
        current.removeAll { $0.vehicleId == assignment.vehicleId }
        current.append(assignment)
        save(current)
    }

    static func remove(driverId: String) {
        var current = load()
        current.removeAll { $0.driverId == driverId }
        save(current)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Builds the record the supervisor writes when tying a unit to a driver.
    static func make(
        stationId: String,
        driverId: String,
        driverName: String,
        vehicleId: String,
        vehicleNumber: String,
        kind: AssignedUnitKind,
        note: String,
        assignedBy: String,
        origin: AssignmentOrigin,
        now: Date,
        previous: VehicleAssignment?
    ) -> VehicleAssignment {
        let titularId: String?
        let titularNumber: String?
        switch kind {
        case .titular:
            titularId = nil
            titularNumber = nil
        case .substitute:
            // The unit being replaced is the titular one the driver already had.
            titularId = previous?.kind == .titular ? previous?.vehicleId : previous?.titularVehicleId
            titularNumber = previous?.kind == .titular ? previous?.vehicleNumber : previous?.titularVehicleNumber
        }

        return VehicleAssignment(
            id: "asg-\(UUID().uuidString.prefix(8))",
            stationId: stationId,
            driverId: driverId,
            driverName: driverName,
            vehicleId: vehicleId,
            vehicleNumber: vehicleNumber,
            kind: kind,
            titularVehicleId: titularId,
            titularVehicleNumber: titularNumber,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            assignedBy: assignedBy,
            assignedAt: now,
            origin: origin
        )
    }
}
