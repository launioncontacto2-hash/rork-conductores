import Foundation
import Observation

nonisolated enum AcquisitionLoadState: Equatable, Sendable {
    case idle
    case loading
    case content
    case empty
    case failed
}

@MainActor
@Observable
final class AcquisitionViewModel {
    let principal: SessionPrincipal
    private let repository: any AcquisitionRepository
    private let realtime = AcquisitionRealtimeObserver()

    var state: AcquisitionLoadState = .idle
    var membership: AcquisitionMembership?
    var requests: [AcquisitionRequest] = []
    var offers: [AcquisitionOfferSummary] = []
    var suppliers: [AcquisitionSupplierSummary] = []

    init(principal: SessionPrincipal, repository: any AcquisitionRepository) {
        self.principal = principal
        self.repository = repository
    }

    var activeRequest: AcquisitionRequest? {
        requests.first
    }

    var activeSummary: AcquisitionRequestSummary? {
        activeRequest.map { AcquisitionRequestSummary(request: $0, offers: offers) }
    }

    var destination: AcquisitionDestination? {
        AcquisitionNavigation.destination(for: principal.role)
    }

    var organizationName: String {
        switch destination {
        case .administrator:
            let city = activeRequest?.deliveryCity.trimmingCharacters(in: .whitespacesAndNewlines)
            return city.map { $0.isEmpty ? "DORI" : "DORI \($0)" } ?? "DORI"
        case .provider:
            guard let supplierID = membership?.supplierID else { return principal.name }
            return suppliers.first(where: { $0.id == supplierID })?.name ?? principal.name
        case nil:
            return principal.name
        }
    }

    var organizationSubtitle: String {
        destination == .administrator ? "Adquisiciones activas" : "Portal de proveedor"
    }

    var uniqueOffers: [AcquisitionOfferSummary] {
        AcquisitionHumanStatus.uniqueVehicles(offers)
    }

    func supplierName(for offer: AcquisitionOfferSummary) -> String? {
        membership?.role == .provider ? organizationName : nil
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading

        do {
            guard let profileID = UUID(uuidString: principal.profileId),
                  let environmentID = principal.environmentId.flatMap(UUID.init(uuidString:)) else {
                throw ViewModelError.invalidProfile
            }

            let loadedMembership = try await repository.loadMembership(
                profileID: profileID,
                environmentID: environmentID
            )
            guard loadedMembership.profileID == profileID,
                  loadedMembership.environmentID == environmentID,
                  loadedMembership.role.sessionRole == principal.role else {
                throw ViewModelError.roleMismatch
            }

            let loadedRequests = try await repository.loadRequests()
            let loadedOffers = try await repository.loadOffers()
            let loadedSuppliers = try await repository.loadSuppliers()

            membership = loadedMembership
            requests = loadedRequests
            offers = loadedOffers
            suppliers = loadedSuppliers
            state = loadedRequests.isEmpty ? .empty : .content

            realtime.start(environmentID: loadedMembership.environmentID) { [weak self] in
                Task { await self?.load() }
            }
        } catch {
            membership = nil
            requests = []
            offers = []
            suppliers = []
            state = .failed
            print("[Adquisiciones] No se pudo cargar el módulo: \(error.localizedDescription)")
        }
    }

    func stopObserving() {
        realtime.stop()
    }

    nonisolated enum ViewModelError: LocalizedError {
        case invalidProfile
        case roleMismatch

        var errorDescription: String? {
            switch self {
            case .invalidProfile:
                "La sesión no contiene un perfil válido."
            case .roleMismatch:
                "La membresía no corresponde al rol de la sesión."
            }
        }
    }
}
