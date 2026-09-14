import AVFoundation
import AVKit
import Observation
import QuickLook
import SwiftUI
import UIKit

@MainActor
@Observable
final class AcquisitionAudioRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false
    private(set) var startedAt: Date?
    var errorMessage: String?

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, Date().timeIntervalSince(startedAt))
    }

    func start() {
        errorMessage = nil
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            startAuthorized()
        case .denied:
            errorMessage = "Permite usar el micrófono para grabar una nota de voz."
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startAuthorized()
                    } else {
                        self?.errorMessage = "Permite usar el micrófono para grabar una nota de voz."
                    }
                }
            }
        @unknown default:
            errorMessage = "No pudimos acceder al micrófono."
        }
    }

    func stop() -> AcquisitionChatAttachment? {
        guard let recorder else { return nil }
        recorder.stop()
        let url = recorder.url
        self.recorder = nil
        isRecording = false
        startedAt = nil
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            errorMessage = "No pudimos preparar la nota de voz."
            return nil
        }
        return AcquisitionChatAttachment(
            data: data,
            fileExtension: "m4a",
            contentType: "audio/mp4",
            filename: "Nota de voz.m4a"
        )
    }

    func cancel() {
        let url = recorder?.url
        recorder?.stop()
        recorder = nil
        isRecording = false
        startedAt = nil
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func startAuthorized() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("dori-chat-\(UUID().uuidString).m4a")
            recorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                ]
            )
            recorder?.record()
            startedAt = Date()
            isRecording = true
        } catch {
            recorder = nil
            errorMessage = "No pudimos iniciar la grabación."
        }
    }
}

struct AcquisitionChatAttachmentPreview: View {
    let attachment: AcquisitionChatAttachment
    let onRemove: (() -> Void)?
    var imageGallery: [AcquisitionChatAttachment] = []
    @State private var previewItem: AcquisitionFilePreviewItem?
    @State private var shareItem: AcquisitionFilePreviewItem?
    @State private var showsImageGallery = false
    @State private var videoItem: AcquisitionFilePreviewItem?

    var body: some View {
        HStack(spacing: 12) {
            preview
            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.filename)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text("\(attachment.kindLabel) · \(attachment.sizeText)")
                    .font(.caption2)
                    .foregroundStyle(AcquisitionTheme.textSecondary)
            }
            Spacer(minLength: 8)
            if let onRemove {
                Button("Quitar", action: onRemove)
                    .font(.caption.weight(.bold))
            } else {
                Button {
                    shareItem = AcquisitionFilePreviewItem.make(
                        data: attachment.data,
                        filename: attachment.filename
                    )
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Compartir o guardar \(attachment.filename)")
            }
        }
        .padding(10)
        .background(AcquisitionTheme.surfaceRaised, in: .rect(cornerRadius: 14))
        .sheet(item: $previewItem) { item in
            NavigationStack {
                Group {
                    AcquisitionQuickLookView(url: item.url)
                        .ignoresSafeArea()
                }
                .navigationTitle(attachment.filename)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: item.url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Compartir, guardar o abrir en otra app")
                    }
                }
            }
        }
        .sheet(item: $shareItem) { item in
            AcquisitionActivityShareView(items: [item.url])
        }
        .fullScreenCover(isPresented: $showsImageGallery) {
            AcquisitionImageGalleryView(
                attachments: imageGallery.isEmpty ? [attachment] : imageGallery,
                initialFilename: attachment.filename
            )
        }
        .fullScreenCover(item: $videoItem) { item in
            NavigationStack {
                VideoPlayer(player: AVPlayer(url: item.url))
                    .background(Color.black)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(attachment.filename)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: item.url) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if attachment.kind == .image,
           let image = UIImage(data: attachment.data) {
            Button {
                showsImageGallery = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(.rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir imagen en pantalla completa")
        } else if attachment.kind == .audio {
            AcquisitionAudioPlayback(data: attachment.data)
        } else if attachment.kind == .video {
            Button {
                videoItem = AcquisitionFilePreviewItem.make(
                    data: attachment.data,
                    filename: attachment.filename
                )
            } label: {
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .frame(width: 58, height: 58)
                    .background(AcquisitionTheme.info.opacity(0.15), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reproducir \(attachment.filename)")
        } else {
            Button {
                previewItem = AcquisitionFilePreviewItem.make(
                    data: attachment.data,
                    filename: attachment.filename
                )
            } label: {
                Image(systemName: attachment.kind.systemImage)
                    .font(.title2)
                    .frame(width: 58, height: 58)
                    .background(AcquisitionTheme.info.opacity(0.15), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir \(attachment.filename)")
        }
    }
}

struct AcquisitionImageGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let attachments: [AcquisitionChatAttachment]
    @State private var selection: Int

    init(attachments: [AcquisitionChatAttachment], initialFilename: String? = nil) {
        self.attachments = attachments.filter { $0.kind == .image }
        let index = self.attachments.firstIndex { $0.filename == initialFilename } ?? 0
        _selection = State(initialValue: index)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                TabView(selection: $selection) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                        if let image = UIImage(data: attachment.data) {
                            AcquisitionZoomableImage(image: image, reduceMotion: reduceMotion)
                                .tag(index)
                                .accessibilityLabel("Foto \(index + 1) de \(attachments.count)")
                        } else {
                            ContentUnavailableView(
                                "No pudimos mostrar esta fotografía",
                                systemImage: "photo.badge.exclamationmark",
                                description: Text("Las demás fotografías siguen disponibles.")
                            )
                            .foregroundStyle(.white)
                            .tag(index)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            .navigationTitle(attachments.isEmpty ? "Fotografía" : "\(selection + 1) de \(attachments.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Volver") { dismiss() }
                }
                if attachments.indices.contains(selection),
                   let item = AcquisitionFilePreviewItem.make(
                       data: attachments[selection].data,
                       filename: attachments[selection].filename
                   ) {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: item.url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
        }
    }
}

private struct AcquisitionZoomableImage: View {
    let image: UIImage
    let reduceMotion: Bool
    @State private var scale: CGFloat = 1

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = min(max($0.magnification, 1), 5) }
                    .onEnded { _ in if scale < 1.05 { scale = 1 } }
            )
            .onTapGesture(count: 2) {
                if reduceMotion {
                    scale = scale > 1 ? 1 : 2.5
                } else {
                    withAnimation(.timingCurve(0.22, 0.75, 0.30, 1, duration: 0.34)) {
                        scale = scale > 1 ? 1 : 2.5
                    }
                }
            }
    }
}

private extension AcquisitionChatAttachment {
    var kindLabel: String {
        switch kind {
        case .image: "Imagen"
        case .video: "Video"
        case .audio: "Audio"
        case .document: "Archivo"
        }
    }
}

private struct AcquisitionAudioPlayback: View {
    let data: Data
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            Button {
                toggle()
            } label: {
                VStack(spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: isPlaying && player?.isPlaying == true ? "pause.fill" : "play.fill")
                        Text("\(timeText(player?.currentTime ?? 0)) / \(timeText(player?.duration ?? 0))")
                            .font(.caption2.monospacedDigit())
                    }
                    ProgressView(value: progress)
                        .frame(width: 100)
                }
                .frame(width: 112, height: 58)
                .background(AcquisitionTheme.info.opacity(0.15), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pausar audio" : "Reproducir audio")
        }
    }

    private var progress: Double {
        guard let player, player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    private func toggle() {
        if player == nil { player = try? AVAudioPlayer(data: data) }
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio)
            try? session.setActive(true)
            if player.currentTime >= player.duration { player.currentTime = 0 }
            isPlaying = player.play()
        }
    }

    private func timeText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct AcquisitionFilePreviewItem: Identifiable {
    let id = UUID()
    let url: URL

    static func make(data: Data, filename: String) -> Self? {
        let safeName = filename.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dori-preview-\(UUID().uuidString)-\(safeName)")
        do {
            try data.write(to: url, options: .atomic)
            return Self(url: url)
        } catch {
            return nil
        }
    }
}

struct AcquisitionQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem { url as NSURL }
    }
}

struct AcquisitionActivityShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
