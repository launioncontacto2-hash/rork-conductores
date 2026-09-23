import AVFoundation

@MainActor
public final class UberTestAlertSound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?

    public init() {
        let output = engine.outputNode.outputFormat(forBus: 0)
        format = AVAudioFormat(standardFormatWithSampleRate: output.sampleRate, channels: 1)
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    public func playOfferAlert() {
        guard let format else { return }
        let sampleRate = format.sampleRate
        let toneDuration = 0.18
        let gap = 0.08
        let tones = [880.0, 1174.66, 880.0]
        let totalFrames = AVAudioFrameCount((toneDuration * Double(tones.count) + gap * 2) * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames), let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = totalFrames
        for frame in 0..<Int(totalFrames) {
            let time = Double(frame) / sampleRate
            let toneIndex = Int(time / (toneDuration + gap))
            let within = time - Double(toneIndex) * (toneDuration + gap)
            if toneIndex < tones.count && within < toneDuration {
                let envelope = min(1, within * 35) * min(1, (toneDuration - within) * 18)
                channel[frame] = Float(sin(2 * .pi * tones[toneIndex] * within) * 0.22 * envelope)
            } else { channel[frame] = 0 }
        }
        player.stop(); player.scheduleBuffer(buffer); if !player.isPlaying { player.play() }
    }
}
