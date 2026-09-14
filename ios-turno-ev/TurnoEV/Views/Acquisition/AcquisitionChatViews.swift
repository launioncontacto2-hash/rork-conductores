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
            threadVisual

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.scope == .general
                     ? thread.supplierName
                     : thread.vehicle?.title ?? thread.title)
                    .font(.headline)
                Text(thread.scope == .unit
                     ? "VIN \(thread.vehicle?.abbreviatedVin ?? "no disponible")"
                     : thread.scope.visibleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textMuted)
                Text(thread.previewText)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if let lastMessageAt = thread.lastMessageAt {
                    Text(lastMessageAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                if thread.unreadCount > 0 {
                    Text("\(thread.unreadCount)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Palette.canvas)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(Palette.volt, in: .circle)
                }
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panelFlat()
    }

    @ViewBuilder
    private var threadVisual: some View {
        if let data = thread.vehicle?.thumbnailData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 62, height: 54)
                .clipShape(.rect(cornerRadius: 10))
        } else {
            Image(systemName: thread.scope == .general ? "bubble.left.and.bubble.right.fill" : "car.fill")
                .font(.title3)
                .foregroundStyle(thread.unreadCount > 0 ? Palette.volt : Palette.info)
                .frame(width: 54, height: 54)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 10))
        }
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

struct AcquisitionPushChatLauncherView: View {
    let threadID: UUID
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
                ContentUnavailableView(
                    "No pudimos abrir la conversación",
                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                    description: Text("La conversación puede haber dejado de estar disponible.")
                )
            } else {
                ProgressView("Abriendo conversación…")
            }
        }
        .task {
            do {
                let threads = try await repository.loadChatThreads()
                thread = threads.first(where: { $0.id == threadID })
                failed = thread == nil
            } catch {
                failed = true
            }
        }
        .navigationTitle("Conversación")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AcquisitionChatView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: AcquisitionChatViewModel
    private let membership: AcquisitionMembership
    private let repository: any AcquisitionRepository
    @State private var showsAttachmentMenu = false
    @State private var showsCamera = false
    @State private var showsLibrary = false
    @State private var showsFiles = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var audioRecorder = AcquisitionAudioRecorder()
    @State private var showsVehicleSheet = false

    init(
        thread: AcquisitionChatThreadSummary,
        membership: AcquisitionMembership,
        profileID: UUID,
        repository: any AcquisitionRepository
    ) {
        self.membership = membership
        self.repository = repository
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
            if let vehicle = model.thread.vehicle {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showsVehicleSheet = true
                } label: {
                    AcquisitionChatVehicleHeader(vehicle: vehicle)
                }
                .buttonStyle(AcquisitionPremiumPressStyle(reduceMotion: reduceMotion))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.messages) { message in
                            AcquisitionChatMessageBubble(
                                message: message,
                                isOwn: message.isOwn(profileID: model.profileID),
                                imageGallery: model.messages.compactMap { item in
                                    guard let attachment = item.downloadedAttachment,
                                          attachment.kind == .image else { return nil }
                                    return attachment
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let id = model.messages.last?.id {
                        if reduceMotion {
                            proxy.scrollTo(id, anchor: .bottom)
                        } else {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    }

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
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
        }
        .background(StationBackground())
        .navigationTitle(model.thread.scope == .unit ? "Chat" : model.thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { model.stop() }
        .onDisappear { audioRecorder.cancel() }
        .sheet(isPresented: $showsVehicleSheet) {
            if let vehicle = model.thread.vehicle, let offerID = model.thread.offerID {
                NavigationStack {
                    AcquisitionChatVehicleSheet(
                        vehicle: vehicle,
                        offerID: offerID,
                        membership: membership,
                        repository: repository
                    )
                        .navigationTitle("Ficha rápida")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Cerrar") { showsVehicleSheet = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
            }
        }
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

private struct AcquisitionChatVehicleHeader: View {
    let vehicle: AcquisitionChatVehicleContext

    var body: some View {
        HStack(spacing: 12) {
            vehicleImage
                .frame(width: 38, height: 38)
                .clipShape(.rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(vehicle.model) · \(String(vehicle.year))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text("\(vehicle.mileageText) · VIN \(vehicle.abbreviatedVin) · \(vehicle.status)")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            Text(vehicle.priceText)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.text)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.textMuted.opacity(0.7))
        }
        .padding(12)
        .acquisitionGlassPanel(cornerRadius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vehicle.model), \(String(vehicle.year)), \(vehicle.mileageText), \(vehicle.priceText), VIN \(vehicle.abbreviatedVin), \(vehicle.status), activar para ver ficha completa")
    }

    @ViewBuilder private var vehicleImage: some View {
        if let data = vehicle.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack { Palette.surface; Image(systemName: "car.side.fill").foregroundStyle(Palette.volt) }
        }
    }
}

private struct AcquisitionChatVehicleSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let vehicle: AcquisitionChatVehicleContext
    let offerID: UUID
    let membership: AcquisitionMembership
    let repository: any AcquisitionRepository
    @State private var detail: AcquisitionOfferDetail?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let detail {
                    if let primary = Self.primaryEvidence(in: detail.evidence),
                       let data = primary.imageData,
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipped()
                            .clipShape(.rect(cornerRadius: 19))
                    } else {
                        ZStack {
                            Palette.surfaceRaised
                            VStack(spacing: 10) {
                                Image(systemName: "car.side.fill")
                                    .font(.largeTitle)
                                Text("Fotografía no disponible")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(Palette.textMuted)
                        }
                        .frame(height: 220)
                        .clipShape(.rect(cornerRadius: 19))
                    }
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(detail.offer.modelAndVersion)
                                .font(.title2.weight(.bold))
                            Text("VIN \(detail.offer.abbreviatedVin)")
                                .font(.caption.monospaced())
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer()
                        AcquisitionHumanStatusIndicator(
                            title: AcquisitionHumanStatus.title(for: detail.offer.status, role: membership.role),
                            group: AcquisitionHumanStatus.group(for: detail.offer.status, role: membership.role)
                        )
                    }
                    VStack(spacing: 0) {
                        AcquisitionSheetFactRow(icon: "calendar", label: "Año", value: detail.offer.yearText)
                        AcquisitionSheetFactRow(icon: "gauge.with.dots.needle.50percent", label: "Kilometraje", value: "\(detail.offer.mileageText) km")
                        AcquisitionSheetFactRow(icon: "paintpalette", label: "Color", value: detail.offer.color.flatMap { $0.isEmpty ? nil : $0 } ?? "Por confirmar")
                        AcquisitionSheetFactRow(icon: "dollarsign.circle", label: "Precio", value: detail.offer.agreedPriceText ?? detail.offer.priceText)
                        AcquisitionSheetFactRow(icon: "battery.75percent", label: "Batería", value: detail.offer.declaredSoh.map { "\($0) %" } ?? "Por verificar")
                        AcquisitionSheetFactRow(icon: "building.2", label: "Proveedor", value: detail.supplierName ?? "Información pendiente", drawsDivider: false)
                    }
                    .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.38), value: detail.offer.status)
                } else if failed {
                    ContentUnavailableView(
                        "No pudimos cargar la ficha",
                        systemImage: "wifi.exclamationmark",
                        description: Text("El chat permanece disponible. Intenta nuevamente.")
                    )
                } else {
                    ProgressView("Cargando ficha…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(18)
        }
        .background(StationBackground())
        .task {
            do {
                detail = try await repository.loadOfferDetail(
                    offerID: offerID,
                    membership: membership
                )
            } catch {
                failed = true
            }
        }
    }

    private static func primaryEvidence(
        in evidence: [AcquisitionEvidenceItem]
    ) -> AcquisitionEvidenceItem? {
        evidence.first { $0.kind == .exteriorDriverSide }
            ?? evidence.first { $0.kind == .front }
            ?? evidence.first
    }
}

private struct AcquisitionChatMessageBubble: View {
    let message: AcquisitionChatMessage
    let isOwn: Bool
    let imageGallery: [AcquisitionChatAttachment]

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
                            onRemove: nil,
                            imageGallery: imageGallery
                        )
                    }
                    if let body = message.body, !body.isEmpty {
                        Text(body)
                    }
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                .padding(12)
                .background(
                    isOwn ? Palette.volt.opacity(0.18) : Color.white.opacity(0.055),
                    in: .rect(cornerRadius: 17)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(
                            isOwn ? Palette.volt.opacity(0.22) : Color.white.opacity(0.09),
                            lineWidth: 1
                        )
                }
                .foregroundStyle(Palette.text)
                if !isOwn { Spacer(minLength: 46) }
            }
        }
    }
}
