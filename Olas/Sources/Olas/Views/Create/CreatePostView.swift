import SwiftUI
import PhotosUI
import NDKSwift
import UnifiedBlurHash

public struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    let ndk: NDK

    @State private var selectedImage: UIImage?
    @State private var editedImage: UIImage?
    @State private var caption = ""
    @State private var isPublishing = false
    @State private var publishingProgress: Double = 0
    @State private var publishingStatus: String = ""
    @State private var showSuccess = false
    @State private var error: Error?
    @State private var showError = false

    @State private var step: PostCreationStep = .selectPhoto

    enum PostCreationStep {
        case selectPhoto
        case editPhoto
        case addCaption
        case publishing
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    switch step {
                    case .selectPhoto:
                        PhotoLibraryView(
                            selectedImage: $selectedImage,
                            onNext: {
                                if selectedImage != nil {
                                    step = .editPhoto
                                }
                            },
                            onCancel: {
                                dismiss()
                            }
                        )

                    case .editPhoto:
                        if let image = Binding($selectedImage) {
                            ImageEditorView(
                                image: image,
                                onComplete: { finalImage in
                                    editedImage = finalImage
                                    step = .addCaption
                                },
                                onBack: {
                                    step = .selectPhoto
                                }
                            )
                        }

                    case .addCaption:
                        if let image = editedImage ?? selectedImage {
                            CaptionView(
                                image: image,
                                caption: $caption,
                                onShare: {
                                    step = .publishing
                                    Task {
                                        await publishPost()
                                    }
                                },
                                onBack: {
                                    step = .editPhoto
                                }
                            )
                        }

                    case .publishing:
                        publishingView
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    step = .addCaption
                }
            } message: {
                Text(error?.localizedDescription ?? "Unknown error")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var publishingView: some View {
        VStack(spacing: 24) {
            Spacer()

            if showSuccess {
                // Success state
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .transition(.scale.combined(with: .opacity))

                Text("Posted!")
                    .font(.system(size: 20, weight: .semibold))

                Text("Your post is now live")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            } else {
                // Progress state
                ZStack {
                    Circle()
                        .stroke(Color(white: 0.2), lineWidth: 4)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: publishingProgress)
                        .stroke(
                            LinearGradient(
                                colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: publishingProgress)
                }

                Text(publishingStatus.isEmpty ? "Uploading..." : publishingStatus)
                    .font(.system(size: 17, weight: .semibold))

                Text("Preparing your image")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private func publishPost() async {
        guard let image = editedImage ?? selectedImage else { return }

        isPublishing = true
        publishingProgress = 0.1
        publishingStatus = "Uploading..."

        do {
            // Upload image
            publishingProgress = 0.3
            let imageUrl = try await uploadImage(image)

            publishingProgress = 0.6
            publishingStatus = "Publishing..."

            // Get image dimensions
            let dimensions = "\(Int(image.size.width))x\(Int(image.size.height))"

            // Generate blurhash (NIP-68)
            publishingProgress = 0.8
            let blurhash = await UnifiedBlurHash.getBlurHashString(from: image)

            // Publish kind 20 event
            _ = try await ndk.publish { builder in
                builder
                    .kind(EventKind.image)
                    .content(caption)
                    .imetaTag(url: imageUrl) { imeta in
                        imeta.dim = dimensions
                        imeta.m = "image/jpeg"
                        imeta.blurhash = blurhash
                    }
            }

            publishingProgress = 1.0
            publishingStatus = "Done!"

            // Show success
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showSuccess = true
            }

            // Dismiss after delay
            try? await Task.sleep(for: .seconds(1.5))

            await MainActor.run {
                dismiss()
            }
        } catch {
            self.error = error
            showError = true
            isPublishing = false
        }
    }

    private func uploadImage(_ image: UIImage) async throws -> String {
        // Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw PostError.imageCompressionFailed
        }

        // Upload to Blossom server (using nostr.build as fallback)
        let uploadUrl = URL(string: "https://nostr.build/api/v2/upload/files")!
        var request = URLRequest(url: uploadUrl)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PostError.uploadFailed
        }

        // Parse response to get URL
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let status = json?["status"] as? String, status == "success",
              let dataArray = json?["data"] as? [[String: Any]],
              let firstItem = dataArray.first,
              let url = firstItem["url"] as? String else {
            throw PostError.invalidUploadResponse
        }

        return url
    }
}

enum PostError: LocalizedError {
    case imageCompressionFailed
    case uploadFailed
    case invalidUploadResponse

    var errorDescription: String? {
        switch self {
        case .imageCompressionFailed:
            return "Failed to compress image"
        case .uploadFailed:
            return "Failed to upload image"
        case .invalidUploadResponse:
            return "Invalid response from upload server"
        }
    }
}

// Helper extension for optional binding
extension Binding {
    init?(_ source: Binding<Value?>) {
        guard source.wrappedValue != nil else { return nil }
        self.init(
            get: { source.wrappedValue! },
            set: { source.wrappedValue = $0 }
        )
    }
}
