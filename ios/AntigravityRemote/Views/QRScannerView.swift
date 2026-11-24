import SwiftUI
import UIKit
import AVFoundation

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onFound: (String) -> Void

    @State private var torchOn = false
    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            if permissionDenied {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.amber)
                    Text("Chưa cấp quyền Camera")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Vào Cài đặt → Antigravity → bật Camera để quét mã QR từ máy tính.")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Button("Đóng") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.bg)
            } else {
                QRCameraRepresentable(torchOn: $torchOn) { code in
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onFound(code)
                }
                .ignoresSafeArea()

                // Scanning overlay
                VStack {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        Spacer()
                        Button {
                            torchOn.toggle()
                        } label: {
                            Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.headline)
                                .foregroundColor(torchOn ? AppTheme.amber : .white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    Spacer()

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppTheme.cyan, lineWidth: 3)
                        .frame(width: 240, height: 240)
                        .background(Color.clear)

                    Spacer()

                    Text("Đưa camera vào mã QR trên cửa sổ Bridge máy tính")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .padding(.bottom, 36)
                }
            }
        }
        .onAppear {
            checkCameraPermission()
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            permissionDenied = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    permissionDenied = !granted
                }
            }
        case .authorized:
            permissionDenied = false
        @unknown default:
            break
        }
    }
}

private struct QRCameraRepresentable: UIViewControllerRepresentable {
    @Binding var torchOn: Bool
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> QRCameraController {
        let vc = QRCameraController()
        vc.onFound = onFound
        return vc
    }

    func updateUIViewController(_ uiViewController: QRCameraController, context: Context) {
        uiViewController.setTorch(torchOn)
    }
}

private final class QRCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didEmit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(false)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didEmit,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue, !value.isEmpty else {
            return
        }
        didEmit = true
        session.stopRunning()
        onFound?(value)
    }
}
