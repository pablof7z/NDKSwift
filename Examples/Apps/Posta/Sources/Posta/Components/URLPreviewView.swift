import SwiftUI
import LinkPresentation

/// View for displaying URL previews with image embedding support
struct URLPreviewView: View {
    let url: URL
    
    @State private var linkMetadata: LPLinkMetadata?
    @State private var isLoading = true
    @State private var isImage = false
    @State private var imageLoadFailed = false
    @State private var showFullScreenImage = false
    
    var body: some View {
        Group {
            if isImage && !imageLoadFailed {
                // Direct image display
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxHeight: 200)
                            .frame(maxWidth: .infinity)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 500)
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
                            )
                            .padding(.vertical, 4)
                            .onTapGesture {
                                showFullScreenImage = true
                            }
                    case .failure(_):
                        // Fall back to link preview
                        EmptyView()
                            .onAppear {
                                imageLoadFailed = true
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
            } else if let metadata = linkMetadata {
                // Rich link preview
                LinkPreviewCard(metadata: metadata, url: url)
            } else if isLoading {
                // Loading state
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading preview...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemFill))
                .cornerRadius(12)
            }
        }
        .onAppear {
            checkIfImage()
            if !isImage {
                fetchLinkMetadata()
            }
        }
        .fullScreenCover(isPresented: $showFullScreenImage) {
            FullScreenImageView(
                url: url,
                isPresented: $showFullScreenImage
            )
            .edgesIgnoringSafeArea(.all)
        }
    }
    
    private func checkIfImage() {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg"]
        let pathExtension = url.pathExtension.lowercased()
        isImage = imageExtensions.contains(pathExtension)
        
        // Also check content type from URL if possible
        if !isImage {
            // Check if URL ends with image extension after query params
            let urlString = url.absoluteString.lowercased()
            for ext in imageExtensions {
                if urlString.contains(".\(ext)?") || urlString.contains(".\(ext)&") {
                    isImage = true
                    break
                }
            }
        }
    }
    
    private func fetchLinkMetadata() {
        Task {
            let provider = LPMetadataProvider()
            provider.timeout = 5 // 5 second timeout
            
            do {
                let metadata = try await provider.startFetchingMetadata(for: url)
                await MainActor.run {
                    self.linkMetadata = metadata
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

/// Card view for displaying link metadata
struct LinkPreviewCard: View {
    let metadata: LPLinkMetadata
    let url: URL
    
    @State private var iconImage: UIImage?
    @State private var previewImage: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preview image if available
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxHeight: 180)
                    .clipped()
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    // Site icon
                    if let icon = iconImage {
                        Image(uiImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .cornerRadius(4)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        // Title
                        if let title = metadata.title {
                            Text(title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(2)
                                .foregroundColor(.primary)
                        }
                        
                        // URL host
                        Text(url.host ?? url.absoluteString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                
                // Description if no preview image
                if previewImage == nil, let description = metadata.value(forKey: "_summary") as? String {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemFill))
        .cornerRadius(12)
        .onTapGesture {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
        .task {
            await loadImages()
        }
    }
    
    private func loadImages() async {
        // Load icon
        if let iconProvider = metadata.iconProvider {
            iconProvider.loadDataRepresentation(for: .image) { data, error in
                if let data = data, let image = UIImage(data: data) {
                    Task { @MainActor in
                        self.iconImage = image
                    }
                }
            }
        }
        
        // Load preview image
        if let imageProvider = metadata.imageProvider {
            imageProvider.loadDataRepresentation(for: .image) { data, error in
                if let data = data, let image = UIImage(data: data) {
                    Task { @MainActor in
                        self.previewImage = image
                    }
                }
            }
        }
    }
}