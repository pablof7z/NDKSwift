import SwiftUI
import PhotosUI
import NDKSwift

public struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    let ndk: NDK

    @State private var selectedImage: UIImage?
    @State private var editedImage: UIImage?
    @State private var caption = ""
    @State private var isPublishing = false
    @State private var error: Error?
    @State private var showError = false

    @State private var step: PostCreationStep = .selectPhoto
    @State private var showPhotoPicker = false
    @State private var showEditor = false

    enum PostCreationStep {
        case selectPhoto
        case editPhoto
        case addCaption
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .selectPhoto:
                    photoSelectionView

                case .editPhoto:
                    if let image = selectedImage {
                        ImageEditorView(
                            image: .constant(image),
                            isPresented: $showEditor
                        ) { finalImage in
                            editedImage = finalImage
                            step = .addCaption
                        }
                    }

                case .addCaption:
                    captionView
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(error?.localizedDescription ?? "Unknown error")
            }
        }
    }

    private var photoSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.badge.plus")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Create New Post")
                .font(.title2.bold())

            Text("Share a photo with your followers")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                PhotosPicker(selection: Binding(
                    get: { nil },
                    set: { item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                selectedImage = image
                                step = .editPhoto
                            }
                        }
                    }
                ), matching: .images) {
                    Text("Choose from Library")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Text("Take a Photo")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .navigationTitle("New Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .fullScreenCover(isPresented: $showPhotoPicker) {
            CameraView(image: Binding(
                get: { selectedImage },
                set: { image in
                    if let image {
                        selectedImage = image
                        step = .editPhoto
                    }
                }
            ))
        }
    }

    private var captionView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    if let image = editedImage ?? selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .cornerRadius(12)
                            .padding(.top)
                    }

                    TextField("Write a caption...", text: $caption, axis: .vertical)
                        .lineLimit(5...10)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
            }

            Spacer()

            Button {
                Task {
                    await publishPost()
                }
            } label: {
                if isPublishing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Share")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(
                LinearGradient(
                    colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .cornerRadius(14)
            .padding()
            .disabled(isPublishing)
        }
        .navigationTitle("New Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    step = .editPhoto
                }
                .disabled(isPublishing)
            }
        }
    }

    private func publishPost() async {
        guard let image = editedImage ?? selectedImage else { return }

        isPublishing = true
        defer { isPublishing = false }

        do {
            // Upload image to Blossom or similar service
            let imageUrl = try await uploadImage(image)

            // Get image dimensions
            let dimensions = "\(Int(image.size.width))x\(Int(image.size.height))"

            // Publish kind 20 event
            _ = try await ndk.publish { builder in
                builder
                    .kind(EventKind.image)
                    .content(caption)
                    .imetaTag(url: imageUrl) { imeta in
                        imeta.dim = dimensions
                        imeta.m = "image/jpeg"
                    }
            }

            await MainActor.run {
                dismiss()
            }
        } catch {
            self.error = error
            showError = true
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
