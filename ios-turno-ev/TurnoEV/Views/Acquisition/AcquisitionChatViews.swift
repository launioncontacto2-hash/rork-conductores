import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AcquisitionChatListView: View {
    @State private var model: AcquisitionChatListViewModel
    let profileID: UUID
    let repository: any AcquisitionRepository

    init(
        membership: AcquisitionMembership,
        profileID: UUID,
        repository: any AcquisitionRepository
    ) {
        self.profileID = profileID
        self.repository = repository
        _model = State(
            initialValue: AcquisitionChatListViewModel(
                membership: membership,
                repository: repository
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AcquisitionSectionHeader(
                title: "Conversaciones",
                count: model.threads.count
            )

            if model.unreadCount > 0 {
                Label(
                    "\(model.unreadCount) \(model.unreadCount == 1 ? "mensaje nuevo" : "mensajes nuevos")",
                    systemImage: "bell.badge.fill"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.amber)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelFlat()
            }

            if model.isLoading && model.threads.isEmpty {
                ProgressView("Cargando conversaciones…")
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else if model.threads.isEmpty {
                Text("No hay conversaciones todavía.")
                    .foregroundStyle(Palette.textMuted)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelFlat()
            } else {
                ForEach(model.threads) { thread in
                    NavigationLink {
                        AcquisitionChatView(
                            thread: thread,
                            membership: model.membership,
                            profileID: profileID,
                            repository: repository
                        )
                    } label: {
                        AcquisitionChatThreadCard(thread: thread)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let message = model.feedbackMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.danger)
            }
        }
        .task { await model.load() }
        .onDisappear { model.stop() }
        .refreshable { await model.load() }
    }
}

private struct AcquisitionChatThreadCard: View {
    let thread: AcquisitionChatThreadSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: thread.scope == .general ? "bubble.left.and.bubble.right.fill" : "car.fill")
                .font(.title3)
                .foregroundStyle(thread.unreadCount > 0 ? Palette.volt : Palette.info)
                .frame(width: 42, height: 42)
                .background(Palette.surfaceRaised, in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.scope == .general ? thread.supplierName : thread.title)
                    .font(.headline)
                Text(thread.scope.visibleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textMuted)
                Text(thread.previewText)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            if thread.unreadCount > 0 {
                Text("\(thread.unreadCount)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Palette.canvas)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Palette.volt, in: .circle)
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panelFlat()
    }
}

struct AcquisitionUnitChatLauncherView: View {
    let offerID: UUID
    let membership: AcquisitionMembership
    let profileID: UUID
    let repository: any AcquisitionRepository
    @State private var thread: AcquisitionChatThreadSummary?
    @State private var failed = false

    var body: some View {
        ZStack {
            StationBackground()
            if let thread {
                AcquisitionChatView(
                    thread: thread,
                    membership: membership,
                    profileID: profileID,
                    repository: repository
                )
            } else if failed {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        "No pudimos abrir la conversación",
                        systemImage: "bubble.left.and.exclamationmark.bubble.right",
                        description: Text("Revisa tu conexión e intenta nuevamente.")
                    )
                    Button("Reintentar") {
                        Task { await openConversation() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.volt)
                }
            } else {
                ProgressView("Abriendo conversación…")
            }
        }
        .task { await openConversation() }
        .navigationTitle("Chat de la unidad")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func openConversation() async {
        failed = false
        do {
            thread = try await AcquisitionUnitChatResolver.resolve(
                offerID: offerID,
                membership: membership,
                repository: repository
            )
        } catch {
            failed = true
            print("[Adquisiciones] No se pudo resolver el chat de unidad: \(String(describing: type(of: error)))")
        }
    }
}

struct AcquisitionChatView: View {
    @State private var model: AcquisitionChatViewModel
    @State private var showsAttachmentMenu = false
    @State private var showsCamera = false
    @State private var showsLibrary = false
    @State private var showsFiles = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var audioRecorder = AcquisitionAudioRecorder()

    init(
        thread: AcquisitionChatThreadSummary,
        membership: AcquisitionMembership,
        profileID: UUID,
        repository: any AcquisitionRepository
    ) {
        _model = State(
            initialValue: AcquisitionChatViewModel(
                thread: thread,
                membership: membership,
                profileID: profileID,
                repository: repository
            )
        )
    }

    var body: some View {
        @Bindable var bindableModel = model
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.messages) { message in
                            AcquisitionChatMessageBubble(
                                message: message,
                                isOwn: message.isOwn(profileID: model.profileID)
                            )
                            .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let id = model.messages.last?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }

            if let attachment = model.attachment {
                AcquisitionChatAttachmentPreview(
                    attachment: attachment,
                    onRemove: { model.removeAttachment() }
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

            if audioRecorder.isRecording {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    HStack(spacing: 12) {
                        Button("Cancelar") { audioRecorder.cancel() }
                            .font(.caption.weight(.bold))
                        Image(systemName: "waveform")
                            .foregroundStyle(Palette.danger)
                        Text(durationText(audioRecorder.elapsed))
                            .font(.subheadline.monospacedDigit().weight(.bold))
                        Spacer()
                        Button {
                            if let attachment = audioRecorder.stop() {
                                model.capture(attachment)
                            }
                        } label: {
                            Label("Terminar", systemImage: "stop.circle.fill")
                        }
                        .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
            }

            if let feedback = model.feedbackMessage {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button { showsAttachmentMenu = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Adjuntar archivo")
                .disabled(audioRecorder.isRecording || model.isSending)

                TextField("Mensaje", text: $bindableModel.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Palette.surfaceRaised, in: .rect(cornerRadius: 16))

                if model.canSend {
                    Button {
                        Task { await model.send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(Palette.volt)
                    }
                    .disabled(model.isSending)
                    .accessibilityLabel("Enviar mensaje")
                } else {
                    Button { audioRecorder.start() } label: {
                        Image(systemName: "mic.circle.fill")
                            .font(.title)
                            .foregroundStyle(audioRecorder.isRecording ? Palette.danger : Palette.volt)
                    }
                    .disabled(audioRecorder.isRecording || model.isSending)
                    .accessibilityLabel("Grabar nota de voz")
                }
            }
            .padding(12)
            .background(Palette.surface.opacity(0.98))
        }
        .background(StationBackground())
        .navigationTitle(model.thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { model.stop() }
        .onDisappear { audioRecorder.cancel() }
        .confirmationDialog("Adjuntar", isPresented: $showsAttachmentMenu) {
            Button("Tomar foto") { showsCamera = true }
            Button("Elegir foto o video") { showsLibrary = true }
            Button("Archivo o documento") { showsFiles = true }
            Button("Cancelar", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showsCamera) {
            EvidencePicker { data in
                model.capture(
                    AcquisitionChatAttachment(
                        data: data,
                        fileExtension: "jpg",
                        contentType: "image/jpeg",
                        filename: "Foto.jpg"
                    )
                )
            }
                .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showsLibrary,
            selection: $libraryItem,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task { await loadLibraryItem(item) }
        }
        .fileImporter(
            isPresented: $showsFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            loadFile(result)
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @MainActor
    private func loadLibraryItem(_ item: PhotosPickerItem) async {
        defer { libraryItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            model.feedbackMessage = "No pudimos leer la foto o el video."
            return
        }
        let type = item.supportedContentTypes.first(where: {
            $0.conforms(to: .image) || $0.conforms(to: .movie)
        }) ?? .data
        let ext = type.preferredFilenameExtension ?? (type.conforms(to: .movie) ? "mov" : "jpg")
        model.capture(
            AcquisitionChatAttachment(
                data: data,
                fileExtension: ext,
                contentType: type.preferredMIMEType ?? "application/octet-stream",
                filename: type.conforms(to: .movie) ? "Video.\(ext)" : "Imagen.\(ext)"
            )
        )
    }

    @MainActor
    private func loadFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            model.feedbackMessage = "No pudimos abrir el archivo seleccionado."
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType ?? .data
            model.capture(
                AcquisitionChatAttachment(
                    data: data,
                    fileExtension: url.pathExtension.isEmpty ? "bin" : url.pathExtension,
                    contentType: type.preferredMIMEType ?? "application/octet-stream",
                    filename: url.lastPathComponent
                )
            )
        } catch {
            model.feedbackMessage = "No pudimos leer el archivo seleccionado."
        }
    }
}

private struct AcquisitionChatMessageBubble: View {
    let message: AcquisitionChatMessage
    let isOwn: Bool

    var body: some View {
        if message.isSystem {
            Text(message.body ?? "Operación actualizada.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        } else {
            HStack {
                if isOwn { Spacer(minLength: 46) }
                VStack(alignment: .leading, spacing: 6) {
                    if let attachment = message.downloadedAttachment {
                        AcquisitionChatAttachmentPreview(
                            attachment: attachment,
                            onRemove: nil
                        )
                    }
                    if let body = message.body, !body.isEmpty {
                        Text(body)
                    }
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(isOwn ? Palette.canvas.opacity(0.65) : Palette.textMuted)
                }
                .padding(12)
                .background(isOwn ? Palette.volt : Palette.surfaceRaised, in: .rect(cornerRadius: 16))
                .foregroundStyle(isOwn ? Palette.canvas : Palette.text)
                if !isOwn { Spacer(minLength: 46) }
            }
        }
    }
}
