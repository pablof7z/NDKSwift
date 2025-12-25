import SwiftUI
import UIKit
import AVFoundation

/// QR code scanner view
struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    @State private var isScanning = true
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined

    var body: some View {
        ZStack {
            if cameraPermission == .authorized {
                CameraPreview(onScan: handleScan)
                    .ignoresSafeArea()

                // Scan frame overlay
                scanOverlay
            } else if cameraPermission == .denied || cameraPermission == .restricted {
                permissionDeniedView
            } else {
                ProgressView("Requesting camera access...")
            }
        }
        .navigationTitle("Scan QR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            checkCameraPermission()
        }
    }

    @ViewBuilder
    private var scanOverlay: some View {
        VStack {
            Spacer()

            // Scan frame
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white, lineWidth: 3)
                .frame(width: 250, height: 250)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.black.opacity(0.3))
                )

            Spacer()

            // Instructions
            Text("Point camera at QR code")
                .font(.headline)
                .foregroundStyle(.white)
                .padding()
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 50)
        }
    }

    @ViewBuilder
    private var permissionDeniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Camera Access Required")
                .font(.title2.bold())

            Text("Please enable camera access in Settings to scan QR codes")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }

    private func checkCameraPermission() {
        cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)

        if cameraPermission == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermission = granted ? .authorized : .denied
                }
            }
        }
    }

    private func handleScan(_ value: String) {
        guard isScanning else { return }
        isScanning = false

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        onScan(value)
    }
}

/// Camera preview using AVCaptureSession
struct CameraPreview: UIViewRepresentable {
    let onScan: (String) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.onScan = onScan
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}
}

class CameraPreviewView: UIView, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        captureSession = session

        guard let device = AVCaptureDevice.default(for: .video) else { return }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            previewLayer = preview
            layer.addSublayer(preview)

            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } catch {
            print("Camera setup error: \(error)")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else {
            return
        }

        captureSession?.stopRunning()
        onScan?(stringValue)
    }
}

#Preview {
    NavigationStack {
        QRScannerView { value in
            print("Scanned: \(value)")
        }
    }
}
