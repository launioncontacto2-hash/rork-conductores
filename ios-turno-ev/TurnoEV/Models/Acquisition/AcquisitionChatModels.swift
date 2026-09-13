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

nonisolated enum AcquisitionChatAttachmentKind: String, Codable, Sendable {
    case image
    case video
    case audio
    case document

    static func resolve(contentType: String) -> Self {
        if contentType.hasPrefix("image/") { return .image }
        if contentType.hasPrefix("video/") { return .video }
        if contentType.hasPrefix("audio/") { return .audio }
        return .document
    }

    var systemImage: String {
        switch self {
        case .image: "photo.fill"
        case .video: "video.fill"
        case .audio: "waveform"
        case .document: "doc.fill"
        }
    }
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
    let attachmentContentType: String?
    let attachmentFilename: String?
    let attachmentSize: Int?
    let createdAt: Date
    var attachmentData: Data?

    init(
        id: UUID,
        sequence: Int64,
        threadID: UUID,
        senderProfileID: UUID?,
        senderRole: AcquisitionRole?,
        kind: AcquisitionChatMessageKind,
        body: String?,
        attachmentPath: String?,
        attachmentContentType: String? = nil,
        attachmentFilename: String? = nil,
        attachmentSize: Int? = nil,
        createdAt: Date,
        attachmentData: Data? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.threadID = threadID
        self.senderProfileID = senderProfileID
        self.senderRole = senderRole
        self.kind = kind
        self.body = body
        self.attachmentPath = attachmentPath
        self.attachmentContentType = attachmentContentType
        self.attachmentFilename = attachmentFilename
        self.attachmentSize = attachmentSize
        self.createdAt = createdAt
        self.attachmentData = attachmentData
    }

    var isSystem: Bool { kind == .system }

    var attachmentKind: AcquisitionChatAttachmentKind? {
        attachmentContentType.map(AcquisitionChatAttachmentKind.resolve(contentType:))
    }

    var downloadedAttachment: AcquisitionChatAttachment? {
        guard let attachmentData else { return nil }
        let pathExtension = attachmentPath.map { URL(fileURLWithPath: $0).pathExtension }
        let fileExtension = pathExtension.flatMap { $0.isEmpty ? nil : $0 } ?? "bin"
        let contentType = attachmentContentType
            ?? (fileExtension.lowercased() == "jpg" ? "image/jpeg" : "application/octet-stream")
        return AcquisitionChatAttachment(
            data: attachmentData,
            fileExtension: fileExtension,
            contentType: contentType,
            filename: attachmentFilename ?? "Adjunto.\(fileExtension)"
        )
    }

    func isOwn(profileID: UUID) -> Bool {
        senderProfileID == profileID
    }
}

nonisolated struct AcquisitionChatAttachment: Equatable, Sendable {
    let data: Data
    let fileExtension: String
    let contentType: String
    let filename: String

    var kind: AcquisitionChatAttachmentKind {
        AcquisitionChatAttachmentKind.resolve(contentType: contentType)
    }

    var size: Int { data.count }

    init(
        data: Data,
        fileExtension: String = "jpg",
        contentType: String = "image/jpeg",
        filename: String = "Imagen.jpg"
    ) {
        self.data = data
        self.fileExtension = fileExtension
        self.contentType = contentType
        self.filename = filename
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
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
