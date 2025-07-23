import SwiftUI
import AVFoundation
import CoreImage

#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
struct OlasCameraView: View {
    @Environment(\.dismiss) var dismiss
    let onCapture: (UIImage) -> Void
    
    @StateObject private var camera = CameraModel()
    @State private var showFlash = false
    @State private var captureAnimation = false
    @State private var showGrid = false
    @State private var timerSeconds: Int? = nil
    @State private var timerCountdown: Int = 0
    @State private var isCountingDown = false
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(camera: camera)
                .ignoresSafeArea()
                .onAppear {
                    camera.checkPermissions()
                }
            
            // Grid overlay
            if showGrid {
                gridOverlay
            }
            
            // UI Controls
            VStack {
                // Top bar
                topBar
                
                Spacer()
                
                // Bottom controls
                bottomControls
            }
            
            // Flash animation
            if showFlash {
                Color.white
                    .ignoresSafeArea()
                    .opacity(0.8)
                    .allowsHitTesting(false)
            }
            
            // Timer countdown
            if isCountingDown {
                timerCountdownView
            }
        }
        .background(Color.black)
    }
    
    @ViewBuilder
    private var topBar: some View {
        HStack {
            // Close button
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            
            Spacer()
            
            // Flash toggle
            Button(action: {
                camera.toggleFlash()
                OlasDesign.Haptic.selection()
            }) {
                Image(systemName: camera.flashMode.icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            
            // Grid toggle
            Button(action: {
                showGrid.toggle()
                OlasDesign.Haptic.selection()
            }) {
                Image(systemName: showGrid ? "grid" : "grid.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            
            // Timer
            Menu {
                Button("Off") { timerSeconds = nil }
                Button("3s") { timerSeconds = 3 }
                Button("10s") { timerSeconds = 10 }
            } label: {
                Image(systemName: timerSeconds == nil ? "timer" : "timer.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
        }
        .padding(.horizontal)
        .padding(.top, 50)
    }
    
    @ViewBuilder
    private var bottomControls: some View {
        HStack(spacing: 60) {
            // Photo library
            Button(action: {
                // Placeholder for photo library
            }) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white)
                    )
            }
            
            // Capture button
            Button(action: capturePhoto) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                        .frame(width: 70, height: 70)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 60, height: 60)
                        .scaleEffect(captureAnimation ? 0.8 : 1.0)
                }
            }
            .disabled(isCountingDown)
            
            // Camera flip
            Button(action: {
                camera.flipCamera()
                OlasDesign.Haptic.selection()
            }) {
                Image(systemName: "camera.rotate")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
        }
        .padding(.bottom, 30)
    }
    
    @ViewBuilder
    private var gridOverlay: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                
                // Vertical lines
                path.move(to: CGPoint(x: width / 3, y: 0))
                path.addLine(to: CGPoint(x: width / 3, y: height))
                
                path.move(to: CGPoint(x: 2 * width / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * width / 3, y: height))
                
                // Horizontal lines
                path.move(to: CGPoint(x: 0, y: height / 3))
                path.addLine(to: CGPoint(x: width, y: height / 3))
                
                path.move(to: CGPoint(x: 0, y: 2 * height / 3))
                path.addLine(to: CGPoint(x: width, y: 2 * height / 3))
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var timerCountdownView: some View {
        Text("\(timerCountdown)")
            .font(.system(size: 120, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .shadow(radius: 10)
            .transition(.scale.combined(with: .opacity))
    }
    
    private func capturePhoto() {
        if let timer = timerSeconds {
            startTimer(seconds: timer)
        } else {
            performCapture()
        }
    }
    
    private func startTimer(seconds: Int) {
        isCountingDown = true
        timerCountdown = seconds
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if timerCountdown > 1 {
                timerCountdown -= 1
                OlasDesign.Haptic.impact(.light)
            } else {
                timer.invalidate()
                isCountingDown = false
                performCapture()
            }
        }
    }
    
    private func performCapture() {
        // Capture animation
        withAnimation(.easeInOut(duration: 0.1)) {
            captureAnimation = true
            showFlash = camera.flashMode != .off
        }
        
        OlasDesign.Haptic.impact(.medium)
        
        // Capture photo
        camera.capturePhoto { image in
            onCapture(image)
            dismiss()
        }
        
        // Reset animations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            captureAnimation = false
            showFlash = false
        }
    }
}

// MARK: - Camera Model

class CameraModel: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var flashMode: FlashMode = .auto
    @Published var isAuthorized = false
    @Published var isCameraReady = false
    
    private var photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var completionHandler: ((UIImage) -> Void)?
    
    enum FlashMode {
        case off, on, auto
        
        var icon: String {
            switch self {
            case .off: return "bolt.slash"
            case .on: return "bolt.fill"
            case .auto: return "bolt.badge.a"
            }
        }
        
        var avMode: AVCaptureDevice.FlashMode {
            switch self {
            case .off: return .off
            case .on: return .on
            case .auto: return .auto
            }
        }
    }
    
    override init() {
        super.init()
        setupSession()
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.startSession()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }
    
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        // Add video input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }
        } catch {
            print("Error setting up camera input: \(error)")
        }
        
        // Add photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            if #available(iOS 16.0, *) {
                // Use maxPhotoDimensions for iOS 16+
                if let format = camera.activeFormat.supportedMaxPhotoDimensions.first {
                    photoOutput.maxPhotoDimensions = format
                }
            } else {
                // Fallback for older iOS versions
                photoOutput.isHighResolutionCaptureEnabled = true
            }
        }
        
        session.commitConfiguration()
    }
    
    func startSession() {
        guard !session.isRunning else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.isCameraReady = true
            }
        }
    }
    
    func stopSession() {
        guard session.isRunning else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async {
                self?.isCameraReady = false
            }
        }
    }
    
    func toggleFlash() {
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        case .auto: flashMode = .off
        }
    }
    
    func flipCamera() {
        session.beginConfiguration()
        
        // Remove current input
        if let input = currentInput {
            session.removeInput(input)
        }
        
        // Get new camera
        let position: AVCaptureDevice.Position = currentInput?.device.position == .back ? .front : .back
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            session.commitConfiguration()
            return
        }
        
        // Add new input
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }
        } catch {
            print("Error flipping camera: \(error)")
        }
        
        session.commitConfiguration()
    }
    
    func capturePhoto(completion: @escaping (UIImage) -> Void) {
        completionHandler = completion
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode.avMode
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else {
            print("Error capturing photo: \(error!)")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else { return }
        
        // Apply orientation fix
        let fixedImage = image.fixedOrientation()
        
        DispatchQueue.main.async { [weak self] in
            self?.completionHandler?(fixedImage)
            self?.completionHandler = nil
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var camera: CameraModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

// MARK: - UIImage Extension

extension UIImage {
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? self
    }
}

// MARK: - Preview

struct OlasCameraView_Previews: PreviewProvider {
    static var previews: some View {
        OlasCameraView { _ in }
    }
}
#else
// Placeholder for non-iOS platforms
struct OlasCameraView: View {
    let onCapture: (Any) -> Void
    
    var body: some View {
        Text("Camera not available on this platform")
    }
}
#endif