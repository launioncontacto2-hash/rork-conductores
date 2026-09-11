import SwiftUI
import UIKit

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
                ContentUnavailableView(
                    "No pudimos abrir la conversación",
                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                    description: Text("Intenta nuevamente.")
                )
            } else {
                ProgressView("Abriendo conversación…")
            }
        }
        .task {
            do {
                thread = try await repository.ensureChatThread(
                    supplierID: membership.supplierID,
                    offerID: offerID
                )
            } catch {
                failed = true
            }
        }
        .navigationTitle("Chat de la unidad")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AcquisitionChatView: View {
    @State private var model: AcquisitionChatViewModel
    @State private var showsPicker = false

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

            if let attachment = model.attachment,
               let image = UIImage(data: attachment.data) {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(.rect(cornerRadius: 10))
                    Text("Imagen lista para enviar")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Quitar") { model.removeAttachment() }
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

            if let feedback = model.feedbackMessage {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button { showsPicker = true } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                }
                .accessibilityLabel("Adjuntar imagen")

                TextField("Mensaje", text: $bindableModel.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Palette.surfaceRaised, in: .rect(cornerRadius: 16))

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(model.canSend ? Palette.volt : Palette.textMuted)
                }
                .disabled(!model.canSend || model.isSending)
                .accessibilityLabel("Enviar mensaje")
            }
            .padding(12)
            .background(Palette.surface.opacity(0.98))
        }
        .background(StationBackground())
        .navigationTitle(model.thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { model.stop() }
        .fullScreenCover(isPresented: $showsPicker) {
            EvidencePicker { data in model.capture(data) }
                .ignoresSafeArea()
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
                    if let data = message.attachmentData,
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(.rect(cornerRadius: 12))
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
