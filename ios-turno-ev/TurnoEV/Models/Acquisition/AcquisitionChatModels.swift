import Foundation

nonisolated enum AcquisitionChatScope: String, Codable, Sendable {
    case general
    case unit

    var visibleLabel: String {
        switch self {
        case .general: "Chat general"
        case .unit: "Conversación de unidad"
        }
    }
}

nonisolated enum AcquisitionChatMessageKind: String, Codable, Sendable {
    case text
    case attachment
    case system
}

nonisolated struct AcquisitionChatThreadSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let supplierID: UUID
    let offerID: UUID?
    let scope: AcquisitionChatScope
    let title: String
    let supplierName: String
    let lastMessage: String?
    let lastMessageKind: AcquisitionChatMessageKind?
    let lastMessageAt: Date?
    let unreadCount: Int

    var previewText: String {
        if let lastMessage, !lastMessage.isEmpty { return lastMessage }
        if lastMessageKind == .attachment { return "Adjunto" }
        return "Sin mensajes todavía"
    }
}

nonisolated struct AcquisitionChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let sequence: Int64
    let threadID: UUID
    let senderProfileID: UUID?
    let senderRole: AcquisitionRole?
    let kind: AcquisitionChatMessageKind
    let body: String?
    let attachmentPath: String?
    let createdAt: Date
    var attachmentData: Data?

    var isSystem: Bool { kind == .system }

    func isOwn(profileID: UUID) -> Bool {
        senderProfileID == profileID
    }
}

nonisolated struct AcquisitionChatAttachment: Equatable, Sendable {
    let data: Data
    let fileExtension: String
    let contentType: String

    init(data: Data, fileExtension: String = "jpg", contentType: String = "image/jpeg") {
        self.data = data
        self.fileExtension = fileExtension
        self.contentType = contentType
    }
}

nonisolated enum AcquisitionChatAttachmentPath {
    static func make(
        environmentID: UUID,
        supplierID: UUID,
        threadID: UUID,
        fileExtension: String
    ) -> String {
        let safeExtension = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        return [
            environmentID.uuidString.lowercased(),
            supplierID.uuidString.lowercased(),
            threadID.uuidString.lowercased(),
            "\(UUID().uuidString.lowercased()).\(safeExtension.isEmpty ? "jpg" : safeExtension)",
        ].joined(separator: "/")
    }
}
