import Foundation
import AVFoundation
import SwiftUI
import NDKSwift
import CryptoKit
import Photos

@MainActor
class VideoManager: ObservableObject {
    @Published var isRecording = false
    @Published var recordedVideoURL: URL?
    @Published var videoDuration: TimeInterval = 0
    @Published var thumbnailImage: UIImage?
    
    private let maxVideoDuration: TimeInterval = 60.0 // 60 seconds max
    private var recordingTimer: Timer?
    
    func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
    
    func generateThumbnail(for videoURL: URL) async -> UIImage? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 0, preferredTimescale: 1)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Error generating thumbnail: \(error)")
            return nil
        }
    }
    
    func compressVideo(inputURL: URL) async throws -> Data {
        let asset = AVAsset(url: inputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw VideoError.compressionFailed
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw VideoError.compressionFailed
        }
        
        let compressedData = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)
        
        return compressedData
    }
    
    func saveVideoToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else {
            throw VideoError.photoLibraryAccessDenied
        }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

enum VideoError: LocalizedError {
    case compressionFailed
    case uploadFailed
    case photoLibraryAccessDenied
    case invalidVideo
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress video"
        case .uploadFailed:
            return "Failed to upload video"
        case .photoLibraryAccessDenied:
            return "Photo library access denied"
        case .invalidVideo:
            return "Invalid video file"
        }
    }
}

// MARK: - Video Player View

struct OlasVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            VideoPlayer(player: player)
                .onAppear {
                    player = AVPlayer(url: url)
                    player?.play()
                    isPlaying = true
                    
                    // Loop video
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: player?.currentItem,
                        queue: .main
                    ) { _ in
                        player?.seek(to: .zero)
                        player?.play()
                    }
                }
                .onDisappear {
                    player?.pause()
                    player = nil
                }
                .onTapGesture {
                    showControls.toggle()
                    if showControls {
                        scheduleHideControls()
                    }
                }
            
            if showControls {
                VStack {
                    Spacer()
                    
                    HStack {
                        Button(action: togglePlayPause) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding()
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            // Mute/unmute
                            if let player = player {
                                player.isMuted.toggle()
                            }
                        }) {
                            Image(systemName: player?.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding()
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                    }
                    .padding()
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            scheduleHideControls()
        }
    }
    
    private func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
        scheduleHideControls()
    }
    
    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            withAnimation {
                showControls = false
            }
        }
    }
}

// MARK: - Camera View for Video Recording

struct OlasVideoCameraView: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    @Binding var isRecording: Bool
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.videoMaximumDuration = 60.0
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .video
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: OlasVideoCameraView
        
        init(_ parent: OlasVideoCameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let videoURL = info[.mediaURL] as? URL {
                parent.videoURL = videoURL
            }
            parent.onDismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDismiss()
        }
    }
}

// MARK: - Video Thumbnail View

struct VideoThumbnailView: View {
    let videoURL: URL
    @State private var thumbnail: UIImage?
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    )
            }
            
            // Play button overlay
            Image(systemName: "play.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 5)
        }
        .task {
            thumbnail = await generateThumbnail()
        }
    }
    
    private func generateThumbnail() async -> UIImage? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 1, preferredTimescale: 1)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}

// MARK: - Video Extensions

extension AVPlayer {
    var isPlaying: Bool {
        return rate != 0 && error == nil
    }
}