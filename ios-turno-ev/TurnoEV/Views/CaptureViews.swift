import AVFoundation
import SwiftUI
import UIKit

/// Camera capture for shift evidence. Falls back to the photo library when no
/// capture device is present.
struct EvidencePicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = Self.isCameraAvailable ? .camera : .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (Data) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        nonisolated func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            Task { @MainActor in
                if let image, let data = Self.compress(image) {
                    self.onCapture(data)
                }
                self.onFinish()
            }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in self.onFinish() }
        }

        /// Evidence is stored compact so a full shift fits in local storage.
        @MainActor
        private static func compress(_ image: UIImage, maxSide: CGFloat = 720) -> Data? {
            let longest = max(image.size.width, image.size.height)
            let scale = min(1, maxSide / max(longest, 1))
            let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: target)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
            return resized.jpegData(compressionQuality: 0.7)
        }
    }
}

/// Tappable evidence slot: shows the captured thumbnail once taken.
struct PhotoSlotView: View {
    let title: String
    var hint: String?
    let data: Data?
    let onCapture: (Data) -> Void

    @State private var isPickerPresented: Bool = false

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            ZStack {
                if let data, let image = UIImage(data: data) {
                    Color.black
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .opacity(0.65)
                                .allowsHitTesting(false)
                        }
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(.headline, weight: .black))
                            .foregroundStyle(Palette.canvas)
                            .frame(width: 34, height: 34)
                            .background(Palette.volt, in: .circle)
                        Text(title)
                            .font(.system(.caption2, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: .capsule)
                    }
                } else {
                    Palette.surfaceRaised.opacity(0.55)
                    VStack(spacing: 5) {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                            .foregroundStyle(Palette.textMuted)
                        Text(title)
                            .font(.system(.caption, weight: .bold))
                            .multilineTextAlignment(.center)
                        if let hint {
                            Text(hint)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(6)
                }
            }
            .frame(height: 116)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        data == nil ? Palette.hairline : Palette.volt.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1, dash: data == nil ? [5, 4] : [])
                    )
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $isPickerPresented) {
            EvidencePicker(onCapture: onCapture)
                .ignoresSafeArea()
        }
    }
}

// MARK: - QR scanning

/// Live QR reader for the windshield sticker. Includes external capture devices so
/// the cloud simulator's injected camera is found.
struct QRScannerView: UIViewControllerRepresentable {
    let onDetected: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onDetected = onDetected
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {
        controller.onDetected = onDetected
    }
}

final class QRScannerController: UIViewController {
    var onDetected: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasDelivered: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            let capture = session
            Task.detached { capture.stopRunning() }
        }
    }

    private func configureSession() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        guard let device = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }

        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func startIfNeeded() {
        guard !session.isRunning, !session.inputs.isEmpty else { return }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else { return }
            let capture = self.session
            Task.detached { capture.startRunning() }
        }
    }
}

extension QRScannerController: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let codes = metadataObjects
            .compactMap { $0 as? AVMetadataMachineReadableCodeObject }
            .compactMap(\.stringValue)
        guard let code = codes.first(where: { !$0.isEmpty }) else { return }

        Task { @MainActor in
            guard !self.hasDelivered else { return }
            self.hasDelivered = true
            self.onDetected?(code)
        }
    }
}

/// Camera viewfinder with framing corners and an animated sweep line.
struct ScannerFrame: View {
    @State private var sweepDown: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.6
            ZStack {
                ForEach(Array(corners.enumerated()), id: \.offset) { item in
                    RoundedRectangle(cornerRadius: 6)
                        .trim(from: 0, to: 0.28)
                        .stroke(Palette.volt, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(item.element))
                        .frame(width: side, height: side)
                }
                Rectangle()
                    .fill(Palette.volt)
                    .frame(width: side - 12, height: 2)
                    .shadow(color: Palette.volt, radius: 8)
                    .offset(y: sweepDown ? side / 2 - 10 : -side / 2 + 10)
                    .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: sweepDown)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear { sweepDown = true }
        .allowsHitTesting(false)
    }

    private var corners: [Double] { [0, 90, 180, 270] }
}
