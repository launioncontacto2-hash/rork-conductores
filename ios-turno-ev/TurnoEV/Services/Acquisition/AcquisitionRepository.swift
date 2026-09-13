import Foundation
import Supabase

@MainActor
protocol AcquisitionRepository {
    func loadMembership(
        profileID: UUID,
        environmentID: UUID
    ) async throws -> AcquisitionMembership
    func loadRequests() async throws -> [AcquisitionRequest]
    func loadOffers() async throws -> [AcquisitionOfferSummary]
    func loadSuppliers() async throws -> [AcquisitionSupplierSummary]
    func loadContacts() async throws -> [AcquisitionInstitutionalContact]
    func loadOfferDetail(
        offerID: UUID,
        membership: AcquisitionMembership
    ) async throws -> AcquisitionOfferDetail
    func submitOffer(
        _ submission: AcquisitionOfferSubmission,
        membership: AcquisitionMembership
    ) async throws -> AcquisitionOfferSummary
    func respondToOffer(_ command: AcquisitionOfferCommand) async throws -> AcquisitionOfferCommandResult
    func completeDelivery(_ command: AcquisitionDeliveryCommand) async throws -> AcquisitionDeliveryCommandResult
    func loadChatThreads() async throws -> [AcquisitionChatThreadSummary]
    func ensureChatThread(supplierID: UUID?, offerID: UUID?) async throws -> AcquisitionChatThreadSummary
    func loadChatMessages(threadID: UUID) async throws -> [AcquisitionChatMessage]
    func sendChatMessage(
        thread: AcquisitionChatThreadSummary,
        body: String,
        attachment: AcquisitionChatAttachment?
    ) async throws -> AcquisitionChatMessage
    func markChatRead(threadID: UUID, sequence: Int64) async throws
}

extension AcquisitionRepository {
    func loadSuppliers() async throws -> [AcquisitionSupplierSummary] { [] }
    func loadContacts() async throws -> [AcquisitionInstitutionalContact] { [] }
    func loadChatThreads() async throws -> [AcquisitionChatThreadSummary] { [] }
    func ensureChatThread(supplierID: UUID?, offerID: UUID?) async throws -> AcquisitionChatThreadSummary {
        throw CancellationError()
    }
    func loadChatMessages(threadID: UUID) async throws -> [AcquisitionChatMessage] { [] }
    func sendChatMessage(
        thread: AcquisitionChatThreadSummary,
        body: String,
        attachment: AcquisitionChatAttachment?
    ) async throws -> AcquisitionChatMessage {
        throw CancellationError()
    }
    func markChatRead(threadID: UUID, sequence: Int64) async throws {}
}

nonisolated enum AcquisitionQueries {
    static let membershipColumns = "id, environment_id, profile_id, supplier_id, role, status, starts_at, ends_at"
    static let requestColumns = "id, code, title, target_quantity, model, versions, minimum_year, maximum_year, maximum_mileage, delivery_city, deadline_at, status"
    static let offerColumns = "id, request_id, status, model, version, year, mileage, price_mxn, transfer_included, vin, declared_soh, agreed_price_mxn, submitted_at"
    static let assessmentColumns = "maximum_recommended_mxn, recommendation, evidence_status, summary"
    static let negotiationColumns = "id, actor_role, action, amount_mxn, message, created_at, event_sequence"
    static let evidenceColumns = "id, kind, object_path, verified"
    static let orderColumns = "id, supplier_id, final_price_mxn, payment_status, status"
    static let deliveryColumns = "status"
    static let receptionColumns = "vin_correct, mileage_correct, chargers_complete, keys_complete, new_damage, result, issue_summary, hold_amount_mxn"
    static let holdColumns = "amount_mxn, reason, status, supplier_resolution_note"
    static let supplierColumns = "id, name, city"
    static let contactColumns = "id, supplier_id, organization_name, person_name, job_title, phone, email, business_hours, is_primary"
    static let chatMessageColumns = "id, event_sequence, thread_id, sender_profile_id, sender_role, message_kind, body, attachment_path, attachment_mime_type, attachment_filename, attachment_size_bytes, created_at"
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
        let event_sequence: Int
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

        private enum CodingKeys: String, CodingKey {
            case p_offer_id
            case p_request_id
            case p_vin
            case p_model
            case p_version
            case p_year
            case p_mileage
            case p_declared_soh
            case p_color
            case p_price_mxn
            case p_transfer_included
            case p_evidence
            case p_idempotency_key
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(p_offer_id, forKey: .p_offer_id)
            try container.encode(p_request_id, forKey: .p_request_id)
            try container.encode(p_vin, forKey: .p_vin)
            try container.encode(p_model, forKey: .p_model)
            try container.encodeIfPresent(p_version, forKey: .p_version)
            if p_version == nil { try container.encodeNil(forKey: .p_version) }
            try container.encode(p_year, forKey: .p_year)
            try container.encode(p_mileage, forKey: .p_mileage)
            try container.encodeIfPresent(p_declared_soh, forKey: .p_declared_soh)
            if p_declared_soh == nil { try container.encodeNil(forKey: .p_declared_soh) }
            try container.encode(p_color, forKey: .p_color)
            try container.encode(p_price_mxn, forKey: .p_price_mxn)
            try container.encode(p_transfer_included, forKey: .p_transfer_included)
            try container.encode(p_evidence, forKey: .p_evidence)
            try container.encode(p_idempotency_key, forKey: .p_idempotency_key)
        }
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

    nonisolated struct OrderRow: Decodable, Sendable {
        let id: UUID
        let supplier_id: UUID
        let final_price_mxn: Decimal
        let payment_status: String
        let status: String
    }

    nonisolated struct DeliveryRow: Decodable, Sendable {
        let status: String
    }

    nonisolated struct ReceptionRow: Decodable, Sendable {
        let vin_correct: Bool
        let mileage_correct: Bool
        let chargers_complete: Bool
        let keys_complete: Bool
        let new_damage: Bool
        let result: AcquisitionReceptionResult
        let issue_summary: String?
        let hold_amount_mxn: Decimal
    }

    nonisolated struct HoldRow: Decodable, Sendable {
        let amount_mxn: Decimal
        let reason: String
        let status: AcquisitionHoldStatus
        let supplier_resolution_note: String?
    }

    nonisolated struct SupplierRow: Decodable, Sendable {
        let id: UUID
        let name: String
        let city: String
    }

    nonisolated struct ContactRow: Decodable, Sendable {
        let id: UUID
        let supplier_id: UUID?
        let organization_name: String
        let person_name: String
        let job_title: String
        let phone: String
        let email: String
        let business_hours: String
        let is_primary: Bool
    }

    nonisolated struct CompleteDeliveryParameters: Encodable, Sendable {
        let p_order_id: UUID
        let p_action: String
        let p_checklist: AcquisitionReceptionChecklist?
        let p_result: String?
        let p_note: String?
        let p_hold_amount_mxn: Int?
        let p_idempotency_key: String
    }

    nonisolated struct CompleteDeliveryRow: Decodable, Sendable {
        let order_id: UUID
        let status: String
        let recommended_result: AcquisitionReceptionResult?
        let hold_amount_mxn: Decimal?
    }

    nonisolated struct ChatThreadRow: Decodable, Sendable {
        let thread_id: UUID
        let supplier_id: UUID
        let offer_id: UUID?
        let scope: AcquisitionChatScope
        let title: String
        let supplier_name: String
        let last_message: String?
        let last_message_kind: AcquisitionChatMessageKind?
        let last_message_at: Date?
        let unread_count: Int
    }

    nonisolated struct EnsuredChatThreadRow: Decodable, Sendable {
        let id: UUID
        let supplier_id: UUID
        let offer_id: UUID?
        let scope: AcquisitionChatScope
        let title: String
    }

    nonisolated struct ChatMessageRow: Decodable, Sendable {
        let id: UUID
        let event_sequence: Int64
        let thread_id: UUID
        let sender_profile_id: UUID?
        let sender_role: String
        let message_kind: AcquisitionChatMessageKind
        let body: String?
        let attachment_path: String?
        let attachment_mime_type: String?
        let attachment_filename: String?
        let attachment_size_bytes: Int?
        let created_at: Date
    }

    nonisolated struct EnsureChatThreadParameters: Encodable, Sendable {
        let p_supplier_id: UUID?
        let p_offer_id: UUID?

        enum CodingKeys: String, CodingKey {
            case p_supplier_id
            case p_offer_id
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let p_supplier_id {
                try container.encode(p_supplier_id, forKey: .p_supplier_id)
            } else {
                // The administrator intentionally has no supplier membership.
                // PostgREST still needs this required RPC argument as JSON null.
                try container.encodeNil(forKey: .p_supplier_id)
            }
            if let p_offer_id {
                try container.encode(p_offer_id, forKey: .p_offer_id)
            } else {
                try container.encodeNil(forKey: .p_offer_id)
            }
        }
    }

    nonisolated struct SendChatMessageParameters: Encodable, Sendable {
        let p_thread_id: UUID
        let p_body: String?
        let p_attachment_path: String?
        let p_attachment_mime_type: String?
        let p_attachment_filename: String?
        let p_attachment_size_bytes: Int?
        let p_idempotency_key: String

        enum CodingKeys: String, CodingKey {
            case p_thread_id
            case p_body
            case p_attachment_path
            case p_attachment_mime_type
            case p_attachment_filename
            case p_attachment_size_bytes
            case p_idempotency_key
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(p_thread_id, forKey: .p_thread_id)
            try container.encode(p_body, forKey: .p_body)
            try container.encode(p_attachment_path, forKey: .p_attachment_path)
            try container.encode(p_attachment_mime_type, forKey: .p_attachment_mime_type)
            try container.encode(p_attachment_filename, forKey: .p_attachment_filename)
            try container.encode(p_attachment_size_bytes, forKey: .p_attachment_size_bytes)
            try container.encode(p_idempotency_key, forKey: .p_idempotency_key)
        }
    }

    nonisolated struct MarkChatReadParameters: Encodable, Sendable {
        let p_thread_id: UUID
        let p_last_read_sequence: Int64
    }

    nonisolated struct ChatReadReceiptRow: Decodable, Sendable {
        let thread_id: UUID
        let last_read_sequence: Int64
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

    func loadMembership(
        profileID: UUID,
        environmentID: UUID
    ) async throws -> AcquisitionMembership {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }

        let rows: [MembershipRow] = try await client
            .from("acquisition_memberships")
            .select(AcquisitionQueries.membershipColumns)
            .eq("profile_id", value: profileID.uuidString)
            .eq("environment_id", value: environmentID.uuidString)
            .execute()
            .value

        return try Self.membership(
            from: rows,
            profileID: profileID,
            environmentID: environmentID,
            now: Date()
        )
    }

    nonisolated static func membership(
        from rows: [MembershipRow],
        profileID: UUID,
        environmentID: UUID,
        now: Date
    ) throws -> AcquisitionMembership {
        let eligible = rows.filter { row in
            row.profile_id == profileID
                && row.environment_id == environmentID
                && row.status == "active"
                && row.starts_at <= now
                && (row.ends_at.map { $0 > now } ?? true)
        }

        guard !eligible.isEmpty else { throw RepositoryError.noMembership }
        guard eligible.count == 1 else {
            throw RepositoryError.multipleMemberships(eligible.count)
        }

        let row = eligible[0]
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

    func loadSuppliers() async throws -> [AcquisitionSupplierSummary] {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }

        let rows: [SupplierRow] = try await client
            .from("acquisition_suppliers")
            .select(AcquisitionQueries.supplierColumns)
            .order("name", ascending: true)
            .execute()
            .value

        return rows.map {
            AcquisitionSupplierSummary(id: $0.id, name: $0.name, city: $0.city)
        }
    }

    func loadContacts() async throws -> [AcquisitionInstitutionalContact] {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }

        let rows: [ContactRow] = try await client
            .from("acquisition_contacts")
            .select(AcquisitionQueries.contactColumns)
            .order("is_primary", ascending: false)
            .order("organization_name", ascending: true)
            .execute()
            .value

        return rows.map {
            AcquisitionInstitutionalContact(
                id: $0.id,
                supplierID: $0.supplier_id,
                organizationName: $0.organization_name,
                personName: $0.person_name,
                jobTitle: $0.job_title,
                phone: $0.phone,
                email: $0.email,
                businessHours: $0.business_hours,
                isPrimary: $0.is_primary
            )
        }
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
            .order("event_sequence", ascending: true)
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

        let delivery = try await loadDeliveryJourney(
            offerID: offerID,
            membership: membership,
            client: client
        )

        return AcquisitionOfferDetail(
            offer: Self.offer(from: offerRow),
            assessment: assessment,
            negotiations: negotiationRows.map { Self.negotiation(from: $0) },
            evidence: evidence,
            delivery: delivery
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
            throw AcquisitionOfferSubmissionError(
                stage: .authorization,
                evidenceKind: nil,
                technicalDescription: "invalid_provider_scope"
            )
        }
        guard submission.evidence.count == AcquisitionEvidenceKind.allCases.count else {
            throw RepositoryError.evidenceRequired
        }

        // A response can be lost after the transactional RPC commits. Checking
        // the client-generated identifier first makes an explicit retry return
        // the existing offer instead of uploading again or creating a duplicate.
        do {
            let existing: [OfferRow] = try await client
                .from("acquisition_offers")
                .select(AcquisitionQueries.offerColumns)
                .eq("id", value: submission.offerID.uuidString)
                .limit(1)
                .execute()
                .value
            if let row = existing.first { return Self.offer(from: row) }
        } catch {
            throw AcquisitionOfferSubmissionError(
                stage: .authorization,
                evidenceKind: nil,
                technicalDescription: error.localizedDescription
            )
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
            do {
                // Force the SDK to recover/refresh the persisted Auth session before
                // Storage builds its authenticated request. The same client still
                // performs the upload; no parallel authentication path is introduced.
                _ = try await client.auth.session
                try await bucket.upload(
                    path,
                    data: item.data,
                    options: FileOptions(contentType: "image/jpeg", upsert: false)
                )
            } catch {
                let diagnostic = AcquisitionRemoteDiagnostic.describe(
                    error,
                    operation: "storage.upload acquisition-evidence",
                    context: [
                        "bucket": "acquisition-evidence",
                        "path": AcquisitionRemoteDiagnostic.redact(path: path),
                        "mime": "image/jpeg",
                        "bytes": String(item.data.count),
                        "environment_id": AcquisitionRemoteDiagnostic.redact(membership.environmentID),
                        "supplier_id": AcquisitionRemoteDiagnostic.redact(supplierID),
                        "offer_id": AcquisitionRemoteDiagnostic.redact(submission.offerID),
                        "evidence": item.kind.rawValue,
                        "upsert": "false",
                    ]
                )
                print("[Adquisiciones][TEST][Storage] \(diagnostic)")
                throw AcquisitionOfferSubmissionError(
                    stage: .evidenceUpload,
                    evidenceKind: item.kind,
                    technicalDescription: diagnostic
                )
            }
            references.append(EvidenceReference(kind: item.kind.rawValue, path: path))
        }

        do {
            let _: OfferRow = try await client
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
        } catch {
            throw AcquisitionOfferSubmissionError(
                stage: .rpc,
                evidenceKind: nil,
                technicalDescription: error.localizedDescription
            )
        }

        do {
            let persisted: [OfferRow] = try await client
                .from("acquisition_offers")
                .select(AcquisitionQueries.offerColumns)
                .eq("id", value: submission.offerID.uuidString)
                .limit(1)
                .execute()
                .value
            guard let row = persisted.first else {
                throw RepositoryError.offerNotFound
            }
            return Self.offer(from: row)
        } catch {
            throw AcquisitionOfferSubmissionError(
                stage: .persistenceCheck,
                evidenceKind: nil,
                technicalDescription: error.localizedDescription
            )
        }
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

    func completeDelivery(
        _ command: AcquisitionDeliveryCommand
    ) async throws -> AcquisitionDeliveryCommandResult {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }

        let row: CompleteDeliveryRow = try await client
            .rpc(
                "complete_acquisition_delivery",
                params: CompleteDeliveryParameters(
                    p_order_id: command.orderID,
                    p_action: command.action.rawValue,
                    p_checklist: command.checklist,
                    p_result: nil,
                    p_note: command.note,
                    p_hold_amount_mxn: nil,
                    p_idempotency_key: command.idempotencyKey
                )
            )
            .execute()
            .value

        return AcquisitionDeliveryCommandResult(
            orderID: row.order_id,
            status: row.status,
            receptionResult: row.recommended_result,
            holdAmountMxn: row.hold_amount_mxn.map { Self.integer(from: $0) } ?? 0
        )
    }

    func loadChatThreads() async throws -> [AcquisitionChatThreadSummary] {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }
        let rows: [ChatThreadRow] = try await client
            .rpc("list_acquisition_chat_threads")
            .execute()
            .value
        return rows.map(Self.chatThread(from:))
    }

    func ensureChatThread(
        supplierID: UUID?,
        offerID: UUID?
    ) async throws -> AcquisitionChatThreadSummary {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }
        let row: EnsuredChatThreadRow = try await client
            .rpc(
                "ensure_acquisition_chat_thread",
                params: EnsureChatThreadParameters(
                    p_supplier_id: supplierID,
                    p_offer_id: offerID
                )
            )
            .execute()
            .value
        let supplierRows: [SupplierRow] = try await client
            .from("acquisition_suppliers")
            .select(AcquisitionQueries.supplierColumns)
            .eq("id", value: row.supplier_id.uuidString)
            .execute()
            .value
        return AcquisitionChatThreadSummary(
            id: row.id,
            supplierID: row.supplier_id,
            offerID: row.offer_id,
            scope: row.scope,
            title: row.title,
            supplierName: supplierRows.first?.name ?? "Proveedor",
            lastMessage: nil,
            lastMessageKind: nil,
            lastMessageAt: nil,
            unreadCount: 0
        )
    }

    func loadChatMessages(threadID: UUID) async throws -> [AcquisitionChatMessage] {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }
        let rows: [ChatMessageRow] = try await client
            .from("acquisition_chat_messages")
            .select(AcquisitionQueries.chatMessageColumns)
            .eq("thread_id", value: threadID.uuidString)
            .order("event_sequence", ascending: true)
            .execute()
            .value
        let bucket = client.storage.from("acquisition-chat-attachments")
        var messages: [AcquisitionChatMessage] = []
        for row in rows {
            let attachmentData: Data?
            if let path = row.attachment_path {
                attachmentData = try? await bucket.download(path: path)
            } else {
                attachmentData = nil
            }
            messages.append(Self.chatMessage(from: row, attachmentData: attachmentData))
        }
        return messages
    }

    func sendChatMessage(
        thread: AcquisitionChatThreadSummary,
        body: String,
        attachment: AcquisitionChatAttachment?
    ) async throws -> AcquisitionChatMessage {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }
        let attachmentPath: String?
        if let attachment {
            guard attachment.data.count <= 10 * 1_024 * 1_024 else {
                throw RepositoryError.evidenceTooLarge
            }
            let path = AcquisitionChatAttachmentPath.make(
                environmentID: try await currentEnvironmentID(),
                supplierID: thread.supplierID,
                threadID: thread.id,
                fileExtension: attachment.fileExtension
            )
            try await client.storage.from("acquisition-chat-attachments").upload(
                path,
                data: attachment.data,
                options: FileOptions(
                    contentType: attachment.contentType,
                    upsert: false
                )
            )
            attachmentPath = path
        } else {
            attachmentPath = nil
        }

        let idempotencyKey = "ios-acquisition-chat-\(UUID().uuidString.lowercased())"
        do {
            let row: ChatMessageRow = try await client
                .rpc(
                    "send_acquisition_chat_message",
                    params: SendChatMessageParameters(
                        p_thread_id: thread.id,
                        p_body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                        p_attachment_path: attachmentPath,
                        p_attachment_mime_type: attachment?.contentType,
                        p_attachment_filename: attachment?.filename,
                        p_attachment_size_bytes: attachment?.size,
                        p_idempotency_key: idempotencyKey
                    )
                )
                .execute()
                .value
            return Self.chatMessage(from: row, attachmentData: attachment?.data)
        } catch {
            let diagnostic = AcquisitionRemoteDiagnostic.describe(
                error,
                operation: "rpc.send_acquisition_chat_message",
                context: [
                    "thread_id": AcquisitionRemoteDiagnostic.redact(thread.id),
                    "supplier_id": AcquisitionRemoteDiagnostic.redact(thread.supplierID),
                    "offer_id": thread.offerID.map(AcquisitionRemoteDiagnostic.redact) ?? "null",
                    "scope": thread.scope.rawValue,
                    "attachment": attachmentPath == nil ? "none" : "private",
                    "idempotency_key": AcquisitionRemoteDiagnostic.redact(idempotencyKey),
                ]
            )
            print("[Adquisiciones][TEST][Chat] \(diagnostic)")
            throw AcquisitionChatSendError(technicalDescription: diagnostic)
        }
    }

    func markChatRead(threadID: UUID, sequence: Int64) async throws {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }
        let _: ChatReadReceiptRow = try await client
            .rpc(
                "mark_acquisition_chat_read",
                params: MarkChatReadParameters(
                    p_thread_id: threadID,
                    p_last_read_sequence: sequence
                )
            )
            .execute()
            .value
    }

    private func currentEnvironmentID() async throws -> UUID {
        guard let client = SupabaseBridge.client else {
            throw RepositoryError.notConfigured
        }
        let session = try await client.auth.session
        let profile = try await SupabaseAuthProbe.loadProfile(authUserId: session.user.id)
        return profile.environment_id
    }

    private func loadDeliveryJourney(
        offerID: UUID,
        membership: AcquisitionMembership,
        client: SupabaseClient
    ) async throws -> AcquisitionDeliveryJourney? {
        let orderRows: [OrderRow] = try await client
            .from("acquisition_orders")
            .select(AcquisitionQueries.orderColumns)
            .eq("offer_id", value: offerID.uuidString)
            .execute()
            .value
        guard let order = orderRows.first else { return nil }

        let deliveryRows: [DeliveryRow] = try await client
            .from("acquisition_deliveries")
            .select(AcquisitionQueries.deliveryColumns)
            .eq("order_id", value: order.id.uuidString)
            .execute()
            .value
        guard let delivery = deliveryRows.first else { return nil }

        let receptionRows: [ReceptionRow] = try await client
            .from("acquisition_receptions")
            .select(AcquisitionQueries.receptionColumns)
            .eq("order_id", value: order.id.uuidString)
            .execute()
            .value
        let holdRows: [HoldRow] = try await client
            .from("acquisition_holds")
            .select(AcquisitionQueries.holdColumns)
            .eq("order_id", value: order.id.uuidString)
            .execute()
            .value

        let supplierName: String?
        if membership.role == .doriAdmin {
            let supplierRows: [SupplierRow] = try await client
                .from("acquisition_suppliers")
                .select(AcquisitionQueries.supplierColumns)
                .eq("id", value: order.supplier_id.uuidString)
                .execute()
                .value
            supplierName = supplierRows.first?.name
        } else {
            supplierName = nil
        }

        let reception = receptionRows.first.map {
            AcquisitionReception(
                checklist: AcquisitionReceptionChecklist(
                    vinCorrect: $0.vin_correct,
                    mileageCorrect: $0.mileage_correct,
                    chargersComplete: $0.chargers_complete,
                    keysComplete: $0.keys_complete,
                    newDamage: $0.new_damage
                ),
                result: $0.result,
                issueSummary: $0.issue_summary,
                holdAmountMxn: Self.integer(from: $0.hold_amount_mxn)
            )
        }
        let hold = holdRows.first.map {
            AcquisitionHold(
                amountMxn: Self.integer(from: $0.amount_mxn),
                reason: $0.reason,
                status: $0.status,
                supplierResolutionNote: $0.supplier_resolution_note
            )
        }

        return AcquisitionDeliveryJourney(
            orderID: order.id,
            supplierName: supplierName,
            finalPriceMxn: Self.integer(from: order.final_price_mxn),
            orderStatus: order.status,
            deliveryStatus: delivery.status,
            reception: reception,
            hold: hold
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
            deadlineAt: row.deadline_at,
            status: row.status
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

    nonisolated static func chatThread(from row: ChatThreadRow) -> AcquisitionChatThreadSummary {
        AcquisitionChatThreadSummary(
            id: row.thread_id,
            supplierID: row.supplier_id,
            offerID: row.offer_id,
            scope: row.scope,
            title: row.title,
            supplierName: row.supplier_name,
            lastMessage: row.last_message,
            lastMessageKind: row.last_message_kind,
            lastMessageAt: row.last_message_at,
            unreadCount: row.unread_count
        )
    }

    nonisolated static func chatMessage(
        from row: ChatMessageRow,
        attachmentData: Data?
    ) -> AcquisitionChatMessage {
        AcquisitionChatMessage(
            id: row.id,
            sequence: row.event_sequence,
            threadID: row.thread_id,
            senderProfileID: row.sender_profile_id,
            senderRole: AcquisitionRole(rawValue: row.sender_role),
            kind: row.message_kind,
            body: row.body,
            attachmentPath: row.attachment_path,
            attachmentContentType: row.attachment_mime_type,
            attachmentFilename: row.attachment_filename,
            attachmentSize: row.attachment_size_bytes,
            createdAt: row.created_at,
            attachmentData: attachmentData
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

nonisolated enum SessionMembershipRoute: Equatable {
    case staff
    case acquisition(AcquisitionRole)
}

/// One sign-in door for both existing station staff and acquisition-only accounts.
/// Existing staff resolution remains first, so adding this module cannot steal an
/// operational account's established route.
@MainActor
enum SupabaseSessionResolver {
    nonisolated static func preferredRoute(
        hasStaffMembership: Bool,
        acquisitionMembership: AcquisitionMembership?
    ) throws -> SessionMembershipRoute {
        if hasStaffMembership { return .staff }
        guard let acquisitionMembership else {
            throw SupabaseAcquisitionRepository.RepositoryError.noMembership
        }
        return .acquisition(acquisitionMembership.role)
    }

    static func run(email: String, password: String) async throws -> SupabaseSessionResolution {
        guard let client = SupabaseBridge.client else {
            throw SupabaseAuthProbe.ProbeError.notConfigured
        }

        let session = try await client.auth.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )

        let profile = try await SupabaseAuthProbe.loadProfile(authUserId: session.user.id)

        if let staff = try await SupabaseAuthProbe.resolveStaff(
            authUserId: session.user.id,
            profile: profile
        ) {
            _ = try Self.preferredRoute(
                hasStaffMembership: true,
                acquisitionMembership: nil
            )
            return .staff(staff)
        }

        let membership = try await SupabaseAcquisitionRepository().loadMembership(
            profileID: profile.id,
            environmentID: profile.environment_id
        )
        _ = try Self.preferredRoute(
            hasStaffMembership: false,
            acquisitionMembership: membership
        )
        return .acquisition(
            AcquisitionSessionIdentity(
                authUserID: session.user.id,
                profile: profile,
                membership: membership
            )
        )
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

    func loadMembership(
        profileID: UUID,
        environmentID: UUID
    ) async throws -> AcquisitionMembership {
        AcquisitionMembership(
            id: membership.id,
            environmentID: environmentID,
            profileID: profileID,
            supplierID: membership.supplierID,
            role: membership.role
        )
    }
    func loadRequests() async throws -> [AcquisitionRequest] { requests }
    func loadOffers() async throws -> [AcquisitionOfferSummary] { offers }
    func loadContacts() async throws -> [AcquisitionInstitutionalContact] {
        [
            AcquisitionInstitutionalContact(
                id: UUID(),
                supplierID: membership.role == .doriAdmin ? UUID() : nil,
                organizationName: membership.role == .doriAdmin ? "BYD Iztacalco" : "DORI Puebla",
                personName: membership.role == .doriAdmin ? "Laura Méndez" : "Jorge Ramos",
                jobTitle: membership.role == .doriAdmin ? "Gerente de seminuevos" : "Supervisor de adquisiciones",
                phone: "222 000 0000",
                email: membership.role == .doriAdmin ? "byd.iztacalco@dori.mx" : "adquisiciones.pue@dori.mx",
                businessHours: "09:00 a 18:00",
                isPrimary: true
            ),
        ]
    }
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
    func completeDelivery(
        _ command: AcquisitionDeliveryCommand
    ) async throws -> AcquisitionDeliveryCommandResult {
        AcquisitionDeliveryCommandResult(
            orderID: command.orderID,
            status: command.action == .ready ? "ready_for_delivery" : "closed",
            receptionResult: command.action == .receive ? .accepted : nil,
            holdAmountMxn: 0
        )
    }
}
