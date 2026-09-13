import AVFoundation
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
    @State private var previewItem: AcquisitionFilePreviewItem?

    var body: some View {
        HStack(spacing: 12) {
            preview
            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.filename)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text("\(attachment.kindLabel) · \(attachment.sizeText)")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer(minLength: 8)
            if let onRemove {
                Button("Quitar", action: onRemove)
                    .font(.caption.weight(.bold))
            }
        }
        .padding(10)
        .background(Palette.surfaceRaised, in: .rect(cornerRadius: 14))
        .sheet(item: $previewItem) { item in
            AcquisitionQuickLookView(url: item.url)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var preview: some View {
        if attachment.kind == .image,
           let image = UIImage(data: attachment.data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: 10))
        } else if attachment.kind == .audio {
            AcquisitionAudioPlayback(data: attachment.data)
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
                    .background(Palette.info.opacity(0.15), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir \(attachment.filename)")
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
                    Image(systemName: isPlaying && player?.isPlaying == true ? "pause.fill" : "play.fill")
                    ProgressView(value: progress)
                        .frame(width: 46)
                }
                .frame(width: 58, height: 58)
                .background(Palette.info.opacity(0.15), in: .rect(cornerRadius: 10))
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
            if player.currentTime >= player.duration { player.currentTime = 0 }
            player.play()
            isPlaying = true
        }
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
