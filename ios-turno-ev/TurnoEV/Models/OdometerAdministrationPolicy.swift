import Foundation

/// Administrative-only comparison against the station's registered odometer.
///
/// This policy is deliberately separate from the driver's exact manual-versus-photo
/// check. The driver never receives this value in the start flow. An administration
/// surface can inject a different value later without changing the driver contract.
nonisolated struct OdometerAdministrationPolicy: Equatable, Sendable {
    static let `default` = Self(masterToleranceKm: 5)

    let masterToleranceKm: Int

    init(masterToleranceKm: Int = 5) {
        self.masterToleranceKm = max(0, masterToleranceKm)
    }
}
