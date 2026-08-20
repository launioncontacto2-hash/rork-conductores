import AVFoundation
import SwiftUI
import UIKit

/// Explainer for the credit program: looping fleet clip, narration and synced captions.
struct CreditHowItWorksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var narration = CreditNarrationPlayer()

    private var caption: String {
        let current = CreditProgram.captions.last { narration.elapsed >= $0.start }
        return current?.text ?? CreditProgram.captions.first?.text ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.canvas
                LoopingVideoView(resourceName: CreditProgram.videoResourceName)
                    .allowsHitTesting(false)
                LinearGradient(
                    colors: [Palette.canvas.opacity(0.35), Palette.canvas.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 40)

                    VStack(alignment: .leading, spacing: 10) {
                        CapsLabel(text: "Cómo funciona")
                        Text("Bajamos el costo del riesgo, no lo cargamos al precio")
                            .font(.system(.title3, weight: .black))
                            .foregroundStyle(.white)
                    }

                    Text(caption)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22)
                        .animation(.smooth(duration: 0.35), value: caption)

                    Spacer(minLength: 24)

                    ProgressTrack(
                        value: narration.elapsed,
                        goal: max(narration.duration, 1),
                        tone: Palette.volt
                    )

                    HStack {
                        Text(Fmt.stopwatch(Int(narration.elapsed)))
                        Spacer()
                        Text(Fmt.stopwatch(Int(narration.duration)))
                    }
                    .font(.system(.caption2, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textMuted)
                    .padding(.top, 6)

                    BigButton(
                        title: narration.isPlaying ? "Pausar explicación" : (narration.elapsed > 0 ? "Continuar" : "Reproducir explicación"),
                        symbol: narration.isPlaying ? "pause.fill" : "play.fill"
                    ) {
                        narration.toggle()
                    }
                    .padding(.top, 18)

                    if !narration.isAvailable {
                        Text(CreditProgram.howItWorksScript)
                            .font(.footnote)
                            .foregroundStyle(Palette.textMuted)
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 26)
            }
            .navigationTitle("Programa de crédito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        narration.stop()
                        dismiss()
                    }
                }
            }
        }
        .task {
            narration.prepare()
            narration.play()
        }
        .task(id: narration.isPlaying) {
            while narration.isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                narration.tick()
            }
        }
        .onDisappear { narration.stop() }
    }
}

/// Narration playback for the explainer, driven by the view's async tick loop.
@Observable
final class CreditNarrationPlayer {
    private var player: AVAudioPlayer?

    var isPlaying: Bool = false
    var elapsed: Double = 0
    var duration: Double = 0

    var isAvailable: Bool { player != nil }

    func prepare() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: CreditProgram.narrationResourceName, withExtension: "mp3") else {
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.prepareToPlay()
            player = audio
            duration = audio.duration
        } catch {
            print("No se pudo preparar la narración del crédito: \(error.localizedDescription)")
        }
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if elapsed >= duration { player.currentTime = 0 }
            player.play()
            isPlaying = true
        }
    }

    func tick() {
        guard let player else { return }
        elapsed = player.currentTime
        if !player.isPlaying {
            isPlaying = false
            if elapsed >= duration - 0.2 { elapsed = duration }
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        elapsed = 0
    }
}

/// Muted, seamlessly looping background clip.
struct LoopingVideoView: UIViewRepresentable {
    let resourceName: String

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") {
            view.start(url: url)
        }
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: LoopingPlayerView, coordinator: ()) {
        uiView.stop()
    }
}

final class LoopingPlayerView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    func start(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        queuePlayer = player
        player.play()
    }

    func stop() {
        queuePlayer?.pause()
        playerLayer.player = nil
        looper = nil
        queuePlayer = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

#Preview {
    CreditHowItWorksView()
        .preferredColorScheme(.dark)
}
