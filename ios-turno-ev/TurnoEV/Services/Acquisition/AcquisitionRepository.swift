import Foundation
import Supabase

@MainActor
protocol AcquisitionRepository {
    func loadMembership(profileID: UUID) async throws -> AcquisitionMembership
    func loadRequests() async throws -> [AcquisitionRequest]
    func loadOffers() async throws -> [AcquisitionOfferSummary]
    func submitOffer(
        _ submission: AcquisitionOfferSubmission,
        membership: AcquisitionMembership
    ) async throws -> AcquisitionOfferSummary
}

nonisolated enum AcquisitionQueries {
    static let membershipColumns = "id, environment_id, profile_id, supplier_id, role, status, starts_at, ends_at"
    static let requestColumns = "id, code, title, target_quantity, model, versions, minimum_year, maximum_year, maximum_mileage, delivery_city, deadline_at, status"
    static let offerColumns = "id, request_id, status, model, version, year, mileage, price_mxn, transfer_included, submitted_at"
}

@MainActor
final class SupabaseAcquisitionRepository: AcquisitionRepository {
    /// The repository has no actor-owned state, so constructing it is safe from
    /// SwiftUI's synchronous default-argument context. Database access remains
    /// isolated to the main actor through the protocol methods below.
    nonisolated init() {}

    nonisolated struct MembershipRow: Decodable, Sendable {
        let id: UUID
        let environment_id: UUID
        let profile_id: UUID
        let supplier_id: UUID?
        let role: String
        let status: String
        let starts_at: Date
        let ends_at: Date?
    }

    nonisolated struct RequestRow: Decodable, Sendable {
        let id: UUID
        let code: String
        let title: String
        let target_quantity: Int
        let model: String
        let versions: [String]
        let minimum_year: Int
        let maximum_year: Int
        let maximum_mileage: Int
        let delivery_city: String
        let deadline_at: Date?
        let status: String
    }

    nonisolated struct OfferRow: Decodable, Sendable {
        let id: UUID
        let request_id: UUID
        let status: String
        let model: String
        let version: String?
        let year: Int
        let mileage: Int
        let price_mxn: Int
        let transfer_included: Bool
        let submitted_at: Date?
    }

    nonisolated struct EvidenceReference: Encodable, Sendable {
        let kind: String
        let path: String
    }

    nonisolated struct SubmitOfferParameters: Encodable, Sendable {
        let p_offer_id: UUID
        let p_request_id: UUID
        let p_vin: String
        let p_model: String
        let p_version: String?
        let p_year: Int
        let p_mileage: Int
        let p_declared_soh: Int?
        let p_color: String
        let p_price_mxn: Int
        let p_transfer_included: Bool
        let p_evidence: [EvidenceReference]
        let p_idempotency_key: String
    }

    enum RepositoryError: LocalizedError {
        case notConfigured
        case noMembership
        case multipleMemberships(Int)
        case invalidRole(String)
        case invalidScope(AcquisitionRole)
        case evidenceRequired
        case evidenceTooLarge

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "Supabase no está configurado."
            case .noMembership:
                "El perfil no tiene una membresía de adquisición activa."
            case .multipleMemberships(let count):
                "El perfil tiene \(count) membresías de adquisición activas; debía tener una."
            case .invalidRole(let role):
                "La membresía de adquisición devolvió un rol no reconocido: \(role)."
            case .invalidScope(let role):
                "La membresía de \(role.rawValue) tiene un alcance de proveedor inválido."
            case .evidenceRequired:
                "La propuesta requiere las tres fotografías."
            case .evidenceTooLarge:
                "Una fotografía supera el límite permitido de 10 MB."
            }
        }
    }

    func loadMembership(profileID: UUID) async throws -> AcquisitionMembership {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }

        let rows: [MembershipRow] = try await client
            .from("acquisition_memberships")
            .select(AcquisitionQueries.membershipColumns)
            .eq("profile_id", value: profileID.uuidString)
            .eq("status", value: "active")
            .is("ends_at", value: nil)
            .execute()
            .value

        guard !rows.isEmpty else { throw RepositoryError.noMembership }
        guard rows.count == 1 else { throw RepositoryError.multipleMemberships(rows.count) }

        let row = rows[0]
        guard let role = AcquisitionRole(rawValue: row.role) else {
            throw RepositoryError.invalidRole(row.role)
        }
        guard (role == .doriAdmin && row.supplier_id == nil)
                || (role == .provider && row.supplier_id != nil) else {
            throw RepositoryError.invalidScope(role)
        }

        return AcquisitionMembership(
            id: row.id,
            environmentID: row.environment_id,
            profileID: row.profile_id,
            supplierID: row.supplier_id,
            role: role
        )
    }

    func loadRequests() async throws -> [AcquisitionRequest] {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }

        let rows: [RequestRow] = try await client
            .from("acquisition_requests")
            .select(AcquisitionQueries.requestColumns)
            .order("created_at", ascending: false)
            .execute()
            .value

        let visibleStatuses: Set<String> = [
            "published", "evaluating", "partially_awarded", "awarded",
        ]
        return rows
            .filter { visibleStatuses.contains($0.status) }
            .map { Self.request(from: $0) }
    }

    func loadOffers() async throws -> [AcquisitionOfferSummary] {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }

        let rows: [OfferRow] = try await client
            .from("acquisition_offers")
            .select(AcquisitionQueries.offerColumns)
            .order("submitted_at", ascending: false)
            .execute()
            .value

        return rows.map { Self.offer(from: $0) }
    }

    func submitOffer(
        _ submission: AcquisitionOfferSubmission,
        membership: AcquisitionMembership
    ) async throws -> AcquisitionOfferSummary {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }
        guard membership.role == .provider, let supplierID = membership.supplierID else {
            throw RepositoryError.invalidScope(membership.role)
        }
        guard submission.evidence.count == AcquisitionEvidenceKind.allCases.count else {
            throw RepositoryError.evidenceRequired
        }

        let bucket = client.storage.from("acquisition-evidence")
        var references: [EvidenceReference] = []
        for item in submission.evidence {
            guard !item.data.isEmpty else { throw RepositoryError.evidenceRequired }
            guard item.data.count <= 10 * 1_024 * 1_024 else {
                throw RepositoryError.evidenceTooLarge
            }

            let path = AcquisitionEvidencePath.make(
                environmentID: membership.environmentID,
                supplierID: supplierID,
                offerID: submission.offerID,
                kind: item.kind
            )
            try await bucket.upload(
                path,
                data: item.data,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
            references.append(EvidenceReference(kind: item.kind.rawValue, path: path))
        }

        let row: OfferRow = try await client
            .rpc(
                "submit_acquisition_offer",
                params: SubmitOfferParameters(
                    p_offer_id: submission.offerID,
                    p_request_id: submission.requestID,
                    p_vin: submission.vin,
                    p_model: submission.model,
                    p_version: submission.version,
                    p_year: submission.year,
                    p_mileage: submission.mileage,
                    p_declared_soh: submission.declaredSoh,
                    p_color: submission.color,
                    p_price_mxn: submission.priceMxn,
                    p_transfer_included: submission.transferIncluded,
                    p_evidence: references,
                    p_idempotency_key: submission.idempotencyKey
                )
            )
            .execute()
            .value

        return Self.offer(from: row)
    }

    nonisolated static func request(from row: RequestRow) -> AcquisitionRequest {
        AcquisitionRequest(
            id: row.id,
            code: row.code,
            title: row.title,
            targetQuantity: row.target_quantity,
            model: row.model,
            versions: row.versions,
            minimumYear: row.minimum_year,
            maximumYear: row.maximum_year,
            maximumMileage: row.maximum_mileage,
            deliveryCity: row.delivery_city,
            deadlineAt: row.deadline_at
        )
    }

    nonisolated static func offer(from row: OfferRow) -> AcquisitionOfferSummary {
        AcquisitionOfferSummary(
            id: row.id,
            requestID: row.request_id,
            status: row.status,
            model: row.model,
            version: row.version,
            year: row.year,
            mileage: row.mileage,
            priceMxn: row.price_mxn,
            transferIncluded: row.transfer_included,
            submittedAt: row.submitted_at
        )
    }
}

struct AcquisitionSessionIdentity {
    let authUserID: UUID
    let profile: SupabaseAuthProbe.ProfileRow
    let membership: AcquisitionMembership
}

enum SupabaseSessionResolution {
    case staff(SupabaseAuthProbe.Result)
    case acquisition(AcquisitionSessionIdentity)
}

/// One sign-in door for both existing station staff and acquisition-only accounts.
/// Existing staff resolution remains first, so adding this module cannot steal an
/// operational account's established route.
@MainActor
enum SupabaseSessionResolver {
    static func run(email: String, password: String) async throws -> SupabaseSessionResolution {
        guard let client = SupabaseBridge.client else {
            throw SupabaseAuthProbe.ProbeError.notConfigured
        }

        let session = try await client.auth.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )

        do {
            return .staff(try await SupabaseAuthProbe.resolve(authUserId: session.user.id))
        } catch SupabaseAuthProbe.ProbeError.noMembership {
            let profile = try await SupabaseAuthProbe.loadProfile(authUserId: session.user.id)
            let membership = try await SupabaseAcquisitionRepository()
                .loadMembership(profileID: profile.id)
            return .acquisition(
                AcquisitionSessionIdentity(
                    authUserID: session.user.id,
                    profile: profile,
                    membership: membership
                )
            )
        }
    }
}

@MainActor
final class PreviewAcquisitionRepository: AcquisitionRepository {
    let requests: [AcquisitionRequest]
    let offers: [AcquisitionOfferSummary]
    let membership: AcquisitionMembership

    init(role: AcquisitionRole) {
        let requestID = UUID(uuidString: "AD400000-0000-4000-8000-000000000001")!
        let profileID = UUID(uuidString: "AD400000-0000-4000-8000-000000000002")!
        membership = AcquisitionMembership(
            id: UUID(uuidString: "AD400000-0000-4000-8000-000000000003")!,
            environmentID: UUID(uuidString: "AD400000-0000-4000-8000-000000000004")!,
            profileID: profileID,
            supplierID: role == .provider
                ? UUID(uuidString: "AD400000-0000-4000-8000-000000000005")!
                : nil,
            role: role
        )
        requests = [
            AcquisitionRequest(
                id: requestID,
                code: "ADQ-TEST-001",
                title: "15 autos requeridos",
                targetQuantity: 15,
                model: "Dolphin Mini",
                versions: ["Plus"],
                minimumYear: 2024,
                maximumYear: 2026,
                maximumMileage: 30_000,
                deliveryCity: "Puebla",
                deadlineAt: nil
            ),
        ]
        offers = []
    }

    func loadMembership(profileID: UUID) async throws -> AcquisitionMembership {
        AcquisitionMembership(
            id: membership.id,
            environmentID: membership.environmentID,
            profileID: profileID,
            supplierID: membership.supplierID,
            role: membership.role
        )
    }
    func loadRequests() async throws -> [AcquisitionRequest] { requests }
    func loadOffers() async throws -> [AcquisitionOfferSummary] { offers }
    func submitOffer(
        _ submission: AcquisitionOfferSubmission,
        membership: AcquisitionMembership
    ) async throws -> AcquisitionOfferSummary {
        AcquisitionOfferSummary(
            id: submission.offerID,
            requestID: submission.requestID,
            status: "submitted",
            model: submission.model,
            version: submission.version,
            year: submission.year,
            mileage: submission.mileage,
            priceMxn: submission.priceMxn,
            transferIncluded: submission.transferIncluded,
            submittedAt: Date()
        )
    }
}
