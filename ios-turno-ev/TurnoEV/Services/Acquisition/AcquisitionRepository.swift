import Foundation
import Supabase

@MainActor
protocol AcquisitionRepository {
    func loadMembership(profileID: UUID) async throws -> AcquisitionMembership
    func loadRequests() async throws -> [AcquisitionRequest]
    func loadOffers() async throws -> [AcquisitionOfferSummary]
    func loadOfferDetail(
        offerID: UUID,
        membership: AcquisitionMembership
    ) async throws -> AcquisitionOfferDetail
    func submitOffer(
        _ submission: AcquisitionOfferSubmission,
        membership: AcquisitionMembership
    ) async throws -> AcquisitionOfferSummary
    func respondToOffer(_ command: AcquisitionOfferCommand) async throws -> AcquisitionOfferCommandResult
}

nonisolated enum AcquisitionQueries {
    static let membershipColumns = "id, environment_id, profile_id, supplier_id, role, status, starts_at, ends_at"
    static let requestColumns = "id, code, title, target_quantity, model, versions, minimum_year, maximum_year, maximum_mileage, delivery_city, deadline_at, status"
    static let offerColumns = "id, request_id, status, model, version, year, mileage, price_mxn, transfer_included, vin, declared_soh, agreed_price_mxn, submitted_at"
    static let assessmentColumns = "maximum_recommended_mxn, recommendation, evidence_status, summary"
    static let negotiationColumns = "id, actor_role, action, amount_mxn, message, created_at"
    static let evidenceColumns = "id, kind, object_path, verified"
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
        let price_mxn: Decimal
        let transfer_included: Bool
        let vin: String
        let declared_soh: Decimal?
        let agreed_price_mxn: Decimal?
        let submitted_at: Date?
    }

    nonisolated struct AssessmentRow: Decodable, Sendable {
        let maximum_recommended_mxn: Decimal?
        let recommendation: AcquisitionRecommendation
        let evidence_status: String
        let summary: String
    }

    nonisolated struct NegotiationRow: Decodable, Sendable {
        let id: UUID
        let actor_role: AcquisitionRole
        let action: String
        let amount_mxn: Decimal?
        let message: String?
        let created_at: Date
    }

    nonisolated struct EvidenceRow: Decodable, Sendable {
        let id: UUID
        let kind: AcquisitionEvidenceKind
        let object_path: String
        let verified: Bool
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

    nonisolated struct RespondOfferParameters: Encodable, Sendable {
        let p_offer_id: UUID
        let p_action: String
        let p_amount_mxn: Int?
        let p_message: String?
        let p_idempotency_key: String
    }

    nonisolated struct RespondOfferRow: Decodable, Sendable {
        let offer_id: UUID
        let status: String
        let agreed_price_mxn: Decimal?
        let order_id: UUID?
    }

    enum RepositoryError: LocalizedError {
        case notConfigured
        case noMembership
        case multipleMemberships(Int)
        case invalidRole(String)
        case invalidScope(AcquisitionRole)
        case offerNotFound
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
            case .offerNotFound:
                "La propuesta ya no está disponible."
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

    func loadOfferDetail(
        offerID: UUID,
        membership: AcquisitionMembership
    ) async throws -> AcquisitionOfferDetail {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }

        let offerRows: [OfferRow] = try await client
            .from("acquisition_offers")
            .select(AcquisitionQueries.offerColumns)
            .eq("id", value: offerID.uuidString)
            .execute()
            .value
        guard let offerRow = offerRows.first else { throw RepositoryError.offerNotFound }

        let negotiationRows: [NegotiationRow] = try await client
            .from("acquisition_negotiations")
            .select(AcquisitionQueries.negotiationColumns)
            .eq("offer_id", value: offerID.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value

        let evidenceRows: [EvidenceRow] = try await client
            .from("acquisition_evidence")
            .select(AcquisitionQueries.evidenceColumns)
            .eq("offer_id", value: offerID.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value

        var evidence: [AcquisitionEvidenceItem] = []
        let bucket = client.storage.from("acquisition-evidence")
        for row in evidenceRows {
            let data = try await bucket.download(path: row.object_path)
            evidence.append(
                AcquisitionEvidenceItem(
                    id: row.id,
                    kind: row.kind,
                    objectPath: row.object_path,
                    verified: row.verified,
                    imageData: data
                )
            )
        }

        let assessment: AcquisitionOfferAssessment?
        if membership.role == .doriAdmin {
            let rows: [AssessmentRow] = try await client
                .from("acquisition_offer_assessments")
                .select(AcquisitionQueries.assessmentColumns)
                .eq("offer_id", value: offerID.uuidString)
                .execute()
                .value
            assessment = rows.first.map { Self.assessment(from: $0) }
        } else {
            assessment = nil
        }

        return AcquisitionOfferDetail(
            offer: Self.offer(from: offerRow),
            assessment: assessment,
            negotiations: negotiationRows.map { Self.negotiation(from: $0) },
            evidence: evidence
        )
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

    func respondToOffer(_ command: AcquisitionOfferCommand) async throws -> AcquisitionOfferCommandResult {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }

        let row: RespondOfferRow = try await client
            .rpc(
                "respond_acquisition_offer",
                params: RespondOfferParameters(
                    p_offer_id: command.offerID,
                    p_action: command.action.rawValue,
                    p_amount_mxn: command.amountMxn,
                    p_message: command.message,
                    p_idempotency_key: command.idempotencyKey
                )
            )
            .execute()
            .value

        return AcquisitionOfferCommandResult(
            offerID: row.offer_id,
            status: row.status,
            agreedPriceMxn: row.agreed_price_mxn.map { Self.integer(from: $0) },
            orderID: row.order_id
        )
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
            priceMxn: Self.integer(from: row.price_mxn),
            transferIncluded: row.transfer_included,
            vin: row.vin,
            declaredSoh: row.declared_soh.map { Self.integer(from: $0) },
            agreedPriceMxn: row.agreed_price_mxn.map { Self.integer(from: $0) },
            submittedAt: row.submitted_at
        )
    }

    nonisolated static func assessment(from row: AssessmentRow) -> AcquisitionOfferAssessment {
        AcquisitionOfferAssessment(
            suggestedAmountMxn: row.maximum_recommended_mxn.map { Self.integer(from: $0) },
            recommendation: row.recommendation,
            evidenceStatus: row.evidence_status,
            summary: row.summary
        )
    }

    nonisolated static func negotiation(from row: NegotiationRow) -> AcquisitionNegotiation {
        AcquisitionNegotiation(
            id: row.id,
            actorRole: row.actor_role,
            action: row.action,
            amountMxn: row.amount_mxn.map { Self.integer(from: $0) },
            message: row.message,
            createdAt: row.created_at
        )
    }

    nonisolated static func integer(from value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).intValue
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
    func loadOfferDetail(
        offerID: UUID,
        membership: AcquisitionMembership
    ) async throws -> AcquisitionOfferDetail {
        let offer = offers.first(where: { $0.id == offerID })
            ?? AcquisitionOfferSummary(
                id: offerID,
                requestID: requests[0].id,
                status: "submitted",
                model: requests[0].model,
                version: requests[0].versions.first,
                year: 2025,
                mileage: 8_400,
                priceMxn: 274_000,
                transferIncluded: true,
                vin: "LGXCE6CB1S0000011",
                declaredSoh: 96
            )
        return AcquisitionOfferDetail(
            offer: offer,
            assessment: membership.role == .doriAdmin
                ? AcquisitionOfferAssessment(
                    suggestedAmountMxn: 268_000,
                    recommendation: .negotiate,
                    evidenceStatus: "complete",
                    summary: "La unidad cumple los parámetros principales."
                )
                : nil,
            negotiations: [],
            evidence: AcquisitionEvidenceKind.allCases.map {
                AcquisitionEvidenceItem(
                    id: UUID(),
                    kind: $0,
                    objectPath: "preview/\($0.rawValue).jpg",
                    verified: false,
                    imageData: nil
                )
            }
        )
    }
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
    func respondToOffer(_ command: AcquisitionOfferCommand) async throws -> AcquisitionOfferCommandResult {
        AcquisitionOfferCommandResult(
            offerID: command.offerID,
            status: command.action == .award ? "awarded" : command.action == .accept ? "price_agreed" : command.action == .reject ? "rejected" : "negotiating",
            agreedPriceMxn: command.amountMxn,
            orderID: command.action == .award ? UUID() : nil
        )
    }
}
