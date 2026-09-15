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
    var offerActivities: [UUID: AcquisitionOfferActivity] = [:]
    var unreadActivityOfferIDs: Set<UUID> = []
    var suppliers: [AcquisitionSupplierSummary] = []
    var contacts: [AcquisitionInstitutionalContact] = []
    var chatThreads: [AcquisitionChatThreadSummary] = []
    private var reloadRequested = false
    private var isObserving = false
    private var isLoading = false

    init(principal: SessionPrincipal, repository: any AcquisitionRepository) {
        self.principal = principal
        self.repository = repository
    }

    var activeRequest: AcquisitionRequest? {
        requests.first
    }

    var activeSummary: AcquisitionRequestSummary? {
        activeRequest.map { AcquisitionRequestSummary(request: $0, offers: uniqueOffers) }
    }

    var destination: AcquisitionDestination? {
        AcquisitionNavigation.destination(for: principal.role)
    }

    var organizationName: String {
        switch destination {
        case .administrator:
            let city = (activeRequest?.deliveryCity ?? principal.stationName)?
                .replacingOccurrences(of: "Estación ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
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

    var organizationLocation: String? {
        switch destination {
        case .administrator:
            return activeRequest.map { "Estación \($0.deliveryCity)" }
        case .provider:
            guard let supplierID = membership?.supplierID else { return nil }
            return suppliers.first(where: { $0.id == supplierID })?.city
        case nil:
            return nil
        }
    }

    var organizationContext: String {
        destination == .administrator
            ? "Compra segura. Más unidades en ruta."
            : "Proveedor autorizado para solicitudes de DORI."
    }

    var uniqueOffers: [AcquisitionOfferSummary] {
        AcquisitionHumanStatus.uniqueVehicles(offers)
    }

    var unreadChatCount: Int {
        chatThreads.reduce(0) { $0 + $1.unreadCount }
    }

    var counterpartContacts: [AcquisitionInstitutionalContact] {
        guard let membership else { return [] }
        return AcquisitionContactDirectory.counterpartContacts(contacts, membership: membership)
    }

    func supplierName(for offer: AcquisitionOfferSummary) -> String? {
        guard let role = membership?.role else { return nil }
        switch role {
        case .provider:
            return organizationName
        case .doriAdmin:
            guard let supplierID = offer.supplierID else { return nil }
            return suppliers.first(where: { $0.id == supplierID })?.name
        }
    }

    func activity(for offer: AcquisitionOfferSummary) -> AcquisitionOfferActivity? {
        offerActivities[offer.id] ?? offer.submittedAt.map {
            AcquisitionOfferActivity(
                offerID: offer.id,
                actorRole: .provider,
                action: "submitted",
                amountMxn: offer.priceMxn,
                previousAmountMxn: nil,
                createdAt: $0,
                sequence: 0
            )
        }
    }

    func hasNewActivity(for offer: AcquisitionOfferSummary) -> Bool {
        unreadActivityOfferIDs.contains(offer.id)
    }

    func load() async {
        if isLoading {
            reloadRequested = true
            return
        }
        repeat {
            let startedAt = ContinuousClock.now
            reloadRequested = false
            isLoading = true
            if membership == nil { state = .loading }
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

            async let requestsTask = repository.loadRequests()
            async let offersTask = repository.loadOffers()
            async let activitiesTask = repository.loadOfferActivities()
            async let unreadTask = repository.unreadNotificationOfferIDs()
            async let suppliersTask = repository.loadSuppliers()
            async let contactsTask = repository.loadContacts()
            async let chatTask = repository.loadChatThreads()

            let loadedRequests = try await requestsTask
            let loadedOffers = try await offersTask
            let loadedSuppliers = try await suppliersTask
            let loadedActivities = (try? await activitiesTask) ?? [:]
            let loadedUnreadActivityOfferIDs = (try? await unreadTask) ?? []
            let loadedContacts = (try? await contactsTask) ?? []
            let loadedChatThreads = (try? await chatTask) ?? []

            membership = loadedMembership
            requests = loadedRequests
            offers = loadedOffers
            offerActivities = loadedActivities
            unreadActivityOfferIDs = loadedUnreadActivityOfferIDs
            suppliers = loadedSuppliers
            contacts = loadedContacts
            chatThreads = loadedChatThreads
            state = loadedRequests.isEmpty && loadedOffers.isEmpty ? .empty : .content
            let duration = startedAt.duration(to: ContinuousClock.now)
            print("[Adquisiciones][Rendimiento] inicio=\(duration)")

        } catch {
            membership = nil
            requests = []
            offers = []
            offerActivities = [:]
            unreadActivityOfferIDs = []
            suppliers = []
            contacts = []
            chatThreads = []
            state = .failed
            print("[Adquisiciones] No se pudo cargar el módulo: \(error.localizedDescription)")
        }
        isLoading = false
        } while reloadRequested

        if let membership, !isObserving {
            isObserving = true
            realtime.start(environmentID: membership.environmentID) { [weak self] in
                Task {
                    await self?.load()
                    await AcquisitionPushCoordinator.shared.refreshBadge()
                }
            }
        }
    }

    func stopObserving() {
        isObserving = false
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
