import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

struct AdvancedCameraView: View {
    @Binding var capturedImage: UIImage?
    @Binding var capturedVideo: URL?
    @State private var cameraMode: CameraMode = .photo
    @State private var currentFilter: FilterType = .none
    @State private var isFlashOn = false
    @State private var isGridVisible = false
    @State private var zoomLevel: CGFloat = 1.0
    @State private var exposureLevel: Float = 0.0
    @State private var beautifyLevel: Float = 0.0
    @State private var showFilters = false
    @State private var detectedFaces: [VNFaceObservation] = []
    @Environment(\.dismiss) private var dismiss
    
    enum CameraMode {
        case photo, video, portrait, night, pro
    }
    
    enum FilterType: String, CaseIterable {
        case none = "Normal"
        case vivid = "Vivid"
        case noir = "Noir"
        case chrome = "Chrome"
        case fade = "Fade"
        case instant = "Instant"
        case tonal = "Tonal"
        case process = "Process"
        case transfer = "Transfer"
        case sepia = "Sepia"
        case comic = "Comic"
        case crystallize = "Crystal"
        case thermal = "Thermal"
        case vortex = "Vortex"
        
        var ciFilterName: String? {
            switch self {
            case .none: return nil
            case .vivid: return "CIPhotoEffectChrome"
            case .noir: return "CIPhotoEffectNoir"
            case .chrome: return "CIPhotoEffectChrome"
            case .fade: return "CIPhotoEffectFade"
            case .instant: return "CIPhotoEffectInstant"
            case .tonal: return "CIPhotoEffectTonal"
            case .process: return "CIPhotoEffectProcess"
            case .transfer: return "CIPhotoEffectTransfer"
            case .sepia: return "CISepiaTone"
            case .comic: return "CIComicEffect"
            case .crystallize: return "CICrystallize"
            case .thermal: return "CIThermal"
            case .vortex: return "CIVortexDistortion"
            }
        }
        
        var icon: String {
            switch self {
            case .none: return "camera.filters"
            case .vivid: return "sun.max.fill"
            case .noir: return "moon.fill"
            case .chrome: return "sparkles"
            case .fade: return "cloud.fill"
            case .instant: return "camera.fill"
            case .tonal: return "circle.lefthalf.filled"
            case .process: return "square.stack.3d.up.fill"
            case .transfer: return "arrow.triangle.2.circlepath"
            case .sepia: return "drop.fill"
            case .comic: return "book.fill"
            case .crystallize: return "square.grid.3x3.fill"
            case .thermal: return "thermometer.sun.fill"
            case .vortex: return "tornado"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(
                currentFilter: currentFilter,
                zoomLevel: $zoomLevel,
                exposureLevel: $exposureLevel,
                beautifyLevel: $beautifyLevel,
                detectedFaces: $detectedFaces,
                onCapture: { image in
                    capturedImage = image
                    dismiss()
                }
            )
            .ignoresSafeArea()
            
            // Grid overlay
            if isGridVisible {
                GridOverlay()
                    .ignoresSafeArea()
            }
            
            // Face detection overlay
            FaceDetectionOverlay(faces: detectedFaces)
                .ignoresSafeArea()
            
            // Controls overlay
            VStack {
                // Top controls
                topControls
                
                Spacer()
                
                // Filter carousel
                if showFilters {
                    filterCarousel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Camera modes
                cameraModeSelector
                
                // Bottom controls
                bottomControls
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
    
    private var topControls: some View {
        HStack {
            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            
            Spacer()
            
            // Pro controls
            VStack(spacing: 20) {
                // Flash
                Button(action: { isFlashOn.toggle() }) {
                    Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.title2)
                        .foregroundStyle(isFlashOn ? .yellow : .white)
                        .padding()
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                
                // Grid
                Button(action: { isGridVisible.toggle() }) {
                    Image(systemName: "grid")
                        .font(.title2)
                        .foregroundStyle(isGridVisible ? OlasDesign.Colors.primary : .white)
                        .padding()
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                
                // Settings
                Menu {
                    // Exposure slider
                    VStack {
                        Text("Exposure")
                        Slider(value: $exposureLevel, in: -2...2)
                    }
                    
                    // Beauty slider
                    VStack {
                        Text("Beauty")
                        Slider(value: $beautifyLevel, in: 0...1)
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding()
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
            }
        }
        .padding()
    }
    
    private var filterCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(FilterType.allCases, id: \.self) { filter in
                    FilterThumbnail(
                        filter: filter,
                        isSelected: currentFilter == filter,
                        action: {
                            withAnimation(.spring()) {
                                currentFilter = filter
                            }
                            OlasDesign.Haptic.selection()
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black.opacity(0.5)],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }
    
    private var cameraModeSelector: some View {
        HStack(spacing: 30) {
            CameraModeButton(title: "PHOTO", isSelected: cameraMode == .photo) {
                cameraMode = .photo
            }
            
            CameraModeButton(title: "VIDEO", isSelected: cameraMode == .video) {
                cameraMode = .video
            }
            
            CameraModeButton(title: "PORTRAIT", isSelected: cameraMode == .portrait) {
                cameraMode = .portrait
            }
            
            CameraModeButton(title: "NIGHT", isSelected: cameraMode == .night) {
                cameraMode = .night
            }
            
            CameraModeButton(title: "PRO", isSelected: cameraMode == .pro) {
                cameraMode = .pro
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
    
    private var bottomControls: some View {
        HStack {
            // Gallery
            Button(action: {}) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.white)
                    )
            }
            
            Spacer()
            
            // Capture button
            CaptureButton(mode: cameraMode) {
                // Capture action handled by CameraPreviewView
            }
            
            Spacer()
            
            // Filter toggle
            Button(action: {
                withAnimation(.spring()) {
                    showFilters.toggle()
                }
            }) {
                Image(systemName: currentFilter == .none ? "camera.filters" : "camera.filters.fill")
                    .font(.title2)
                    .foregroundStyle(currentFilter == .none ? .white : OlasDesign.Colors.primary)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 30)
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let currentFilter: AdvancedCameraView.FilterType
    @Binding var zoomLevel: CGFloat
    @Binding var exposureLevel: Float
    @Binding var beautifyLevel: Float
    @Binding var detectedFaces: [VNFaceObservation]
    let onCapture: (UIImage) -> Void
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.currentFilter = currentFilter
        uiView.zoomLevel = zoomLevel
        uiView.exposureLevel = exposureLevel
        uiView.beautifyLevel = beautifyLevel
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CameraPreviewDelegate {
        let parent: CameraPreviewView
        
        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }
        
        func didCapturePhoto(_ image: UIImage) {
            parent.onCapture(image)
        }
        
        func didDetectFaces(_ faces: [VNFaceObservation]) {
            parent.detectedFaces = faces
        }
    }
}

protocol CameraPreviewDelegate: AnyObject {
    func didCapturePhoto(_ image: UIImage)
    func didDetectFaces(_ faces: [VNFaceObservation])
}

class CameraPreviewUIView: UIView {
    weak var delegate: CameraPreviewDelegate?
    var currentFilter: AdvancedCameraView.FilterType = .none
    var zoomLevel: CGFloat = 1.0
    var exposureLevel: Float = 0.0
    var beautifyLevel: Float = 0.0
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let context = CIContext()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCamera() {
        // Camera setup implementation
        // This is a simplified version - full implementation would include:
        // - AVCaptureSession setup
        // - Camera device configuration
        // - Preview layer setup
        // - Face detection setup
        // - Filter application
    }
}

// MARK: - Supporting Views

struct FilterThumbnail: View {
    let filter: AdvancedCameraView.FilterType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected ?
                            LinearGradient(
                                colors: OlasDesign.Colors.primaryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.gray.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: filter.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                
                Text(filter.rawValue)
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
    }
}

struct CameraModeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation(.spring()) {
                action()
            }
            OlasDesign.Haptic.selection()
        }) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .yellow : .white.opacity(0.7))
                .scaleEffect(isSelected ? 1.1 : 1.0)
        }
    }
}

struct CaptureButton: View {
    let mode: AdvancedCameraView.CameraMode
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            isPressed = true
            OlasDesign.Haptic.selection()
            action()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
        }) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 70, height: 70)
                
                Circle()
                    .fill(mode == .video ? .red : .white)
                    .frame(width: isPressed ? 55 : 60, height: isPressed ? 55 : 60)
                    .animation(.spring(response: 0.3), value: isPressed)
            }
        }
    }
}

struct GridOverlay: View {
    var body: some View {
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
            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        }
    }
}

struct FaceDetectionOverlay: View {
    let faces: [VNFaceObservation]
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(faces.indices, id: \.self) { index in
                let face = faces[index]
                Rectangle()
                    .stroke(
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(
                        width: face.boundingBox.width * geometry.size.width,
                        height: face.boundingBox.height * geometry.size.height
                    )
                    .position(
                        x: face.boundingBox.midX * geometry.size.width,
                        y: (1 - face.boundingBox.midY) * geometry.size.height
                    )
            }
        }
    }
}

// MARK: - AR Effects

struct AREffectsView: View {
    @State private var selectedEffect: AREffect = .none
    
    enum AREffect: String, CaseIterable {
        case none = "None"
        case glasses = "Glasses"
        case hat = "Hat"
        case mustache = "Mustache"
        case animalEars = "Animal Ears"
        case sparkles = "Sparkles"
        case hearts = "Hearts"
        case rainbow = "Rainbow"
        case fire = "Fire"
        
        var icon: String {
            switch self {
            case .none: return "xmark.circle"
            case .glasses: return "eyeglasses"
            case .hat: return "graduationcap.fill"
            case .mustache: return "mustache.fill"
            case .animalEars: return "hare.fill"
            case .sparkles: return "sparkles"
            case .hearts: return "heart.fill"
            case .rainbow: return "rainbow"
            case .fire: return "flame.fill"
            }
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(AREffect.allCases, id: \.self) { effect in
                    AREffectButton(
                        effect: effect,
                        isSelected: selectedEffect == effect,
                        action: {
                            selectedEffect = effect
                            OlasDesign.Haptic.selection()
                        }
                    )
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.7))
    }
}

struct AREffectButton: View {
    let effect: AREffectsView.AREffect
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected ?
                            LinearGradient(
                                colors: OlasDesign.Colors.primaryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: effect.icon)
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                
                Text(effect.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
        }
    }
}