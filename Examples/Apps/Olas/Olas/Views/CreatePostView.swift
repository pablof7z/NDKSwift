import SwiftUI
import PhotosUI
import NDKSwift
import CryptoKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CreatePostView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var blossomServerManager: BlossomServerManager
    @Environment(\.dismiss) var dismiss
    
    // Photo selection
    @State private var selectedItems: [PhotosPickerItem] = []
    #if canImport(UIKit)
    @State private var selectedImages: [UIImage] = []
    #elseif canImport(AppKit)
    @State private var selectedImages: [NSImage] = []
    #endif
    @State private var selectedImageData: [Data] = []
    
    // Caption
    @State private var caption = ""
    
    // UI States
    @State private var showCamera = false
    @State private var showImageEditor = false
    @State private var isPosting = false
    @State private var uploadProgress: Double = 0.0
    @State private var errorMessage: String?
    @State private var showError = false
    
    // Image editing
    @State private var editingImageIndex: Int = 0
    @State private var appliedFilters: [Int: String] = [:] // Image index to filter name
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if selectedImages.isEmpty {
                        emptyStateView
                    } else {
                        selectedImagesView
                    }
                }
            }
            .navigationTitle("Create Post")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !selectedImages.isEmpty {
                        Button("Clear") {
                            clearSelection()
                        }
                        .foregroundColor(OlasDesign.Colors.warning)
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                
                ToolbarItem(placement: .automatic) {
                    if !selectedImages.isEmpty {
                        Button("Clear") {
                            clearSelection()
                        }
                        .foregroundColor(OlasDesign.Colors.warning)
                    }
                }
            }
            #endif
            .onChange(of: selectedItems) { _, newItems in
                Task {
                    await loadImages(from: newItems)
                }
            }
            .sheet(isPresented: $showCamera) {
                #if canImport(UIKit)
                OlasCameraView { image in
                    selectedImages.append(image)
                    if let data = image.jpegData(compressionQuality: 0.9) {
                        selectedImageData.append(data)
                    }
                }
                #else
                Text("Camera not available on this platform")
                #endif
            }
            .sheet(isPresented: $showImageEditor) {
                if selectedImages.indices.contains(editingImageIndex) {
                    #if canImport(UIKit)
                    OlasImageEditor(
                        originalImage: selectedImages[editingImageIndex],
                        currentFilter: appliedFilters[editingImageIndex] ?? "No Filter"
                    ) { editedImage, filterName in
                        selectedImages[editingImageIndex] = editedImage
                        if let data = editedImage.jpegData(compressionQuality: 0.9) {
                            selectedImageData[editingImageIndex] = data
                        }
                        appliedFilters[editingImageIndex] = filterName
                    }
                    #else
                    Text("Image editor not available on this platform")
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                        .padding()
                    #endif
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .overlay {
                if isPosting {
                    postingOverlay
                }
            }
        }
    }
    
    // MARK: - Views
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: OlasDesign.Spacing.xl) {
            Spacer()
            
            // Photo picker
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 4,
                matching: .images
            ) {
                VStack(spacing: OlasDesign.Spacing.md) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [OlasDesign.Colors.primary, OlasDesign.Colors.secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Select Photos")
                        .font(OlasDesign.Typography.title)
                        .foregroundColor(OlasDesign.Colors.text)
                    
                    Text("Up to 4 photos")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .background(OlasDesign.Colors.surface)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(OlasDesign.Colors.border, lineWidth: 1)
                )
            }
            
            // Camera button
            OlasButton(
                title: "Take Photo",
                action: {
                    showCamera = true
                    #if os(iOS)
                    OlasDesign.Haptic.impact(.light)
                    #else
                    OlasDesign.Haptic.impact(0)
                    #endif
                },
                style: .secondary
            )
            
            Spacer()
        }
        .padding(OlasDesign.Spacing.lg)
    }
    
    @ViewBuilder
    private var selectedImagesView: some View {
        ScrollView {
            VStack(spacing: OlasDesign.Spacing.lg) {
                // Selected images
                imageCarousel
                
                // Caption input with built-in suggestions
                captionInput
                
                // Post button
                OlasButton(
                    title: isPosting ? "Posting..." : "Post",
                    action: createPost,
                    style: .primary,
                    isLoading: isPosting
                )
                .disabled(isPosting)
                .padding(.top, OlasDesign.Spacing.md)
            }
            .padding(OlasDesign.Spacing.lg)
        }
    }
    
    @ViewBuilder
    private var imageCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OlasDesign.Spacing.md) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        #if canImport(UIKit)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipped()
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(OlasDesign.Colors.border, lineWidth: 1)
                            )
                            .onTapGesture {
                                editingImageIndex = index
                                showImageEditor = true
                                OlasDesign.Haptic.selection()
                            }
                        #elseif canImport(AppKit)
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipped()
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(OlasDesign.Colors.border, lineWidth: 1)
                            )
                            .onTapGesture {
                                editingImageIndex = index
                                showImageEditor = true
                                OlasDesign.Haptic.selection()
                            }
                        #endif
                        
                        // Filter indicator
                        if let filterName = appliedFilters[index], filterName != "No Filter" {
                            Text(filterName)
                                .font(OlasDesign.Typography.caption)
                                .padding(.horizontal, OlasDesign.Spacing.xs)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                                .padding(OlasDesign.Spacing.xs)
                        }
                        
                        // Remove button
                        Button(action: {
                            removeImage(at: index)
                            #if os(iOS)
                        OlasDesign.Haptic.impact(.light)
                        #else
                        OlasDesign.Haptic.impact(0)
                        #endif
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white, Color.black.opacity(0.6))
                        }
                        .padding(OlasDesign.Spacing.xs)
                    }
                }
                
                // Add more photos button (if under limit)
                if selectedImages.count < 4 {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 4 - selectedImages.count,
                        matching: .images
                    ) {
                        VStack {
                            Image(systemName: "plus")
                                .font(.title)
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                        }
                        .frame(width: 200, height: 200)
                        .background(OlasDesign.Colors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(OlasDesign.Colors.border, style: StrokeStyle(lineWidth: 2, dash: [5]))
                        )
                    }
                }
            }
        }
        .frame(height: 220)
    }
    
    @ViewBuilder
    private var captionInput: some View {
        OlasCaptionComposer(caption: $caption)
            .environmentObject(appState)
    }
    
    
    @ViewBuilder
    private var postingOverlay: some View {
        ZStack {
            OlasDesign.Colors.background.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: OlasDesign.Spacing.lg) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: OlasDesign.Colors.primary))
                    .scaleEffect(1.5)
                
                Text("Uploading Images...")
                    .font(OlasDesign.Typography.body)
                    .foregroundColor(OlasDesign.Colors.text)
                
                ProgressView(value: uploadProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: OlasDesign.Colors.primary))
                    .frame(width: 200)
            }
            .padding(OlasDesign.Spacing.xl)
            .background(OlasDesign.Colors.surface)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Methods
    
    private func loadImages(from items: [PhotosPickerItem]) async {
        selectedImages = []
        selectedImageData = []
        
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                #if canImport(UIKit)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImages.append(image)
                        selectedImageData.append(data)
                    }
                }
                #elseif canImport(AppKit)
                if let image = NSImage(data: data) {
                    await MainActor.run {
                        selectedImages.append(image)
                        selectedImageData.append(data)
                    }
                }
                #endif
            }
        }
    }
    
    private func removeImage(at index: Int) {
        selectedImages.remove(at: index)
        selectedImageData.remove(at: index)
        appliedFilters.removeValue(forKey: index)
        
        // Reindex filters
        let oldFilters = appliedFilters
        appliedFilters = [:]
        for (oldIndex, filter) in oldFilters {
            if oldIndex > index {
                appliedFilters[oldIndex - 1] = filter
            } else if oldIndex < index {
                appliedFilters[oldIndex] = filter
            }
        }
    }
    
    private func clearSelection() {
        selectedItems = []
        selectedImages = []
        selectedImageData = []
        appliedFilters = [:]
        caption = ""
        #if os(iOS)
        OlasDesign.Haptic.impact(.light)
        #else
        OlasDesign.Haptic.impact(0)
        #endif
    }
    
    private func createPost() {
        Task {
            await performCreatePost()
        }
    }
    
    @MainActor
    private func performCreatePost() async {
        guard let ndk = nostrManager.ndk else { return }
        
        isPosting = true
        uploadProgress = 0.0
        
        do {
            // Get signer
            let authManager = NDKAuthManager.shared
            guard let signer = authManager.activeSigner else {
                throw OlasError.invalidKey
            }
            
            // 1. Upload images to Blossom
            var imetaTags: [[String]] = []
            let progressPerImage = 0.8 / Double(selectedImageData.count)
            
            // Default Blossom servers
            let blossomServers = [
                "https://blossom.primal.net",
                "https://blossom.nostr.wine", 
                "https://blossom.damus.io"
            ]
            
            // Create Blossom client
            let blossomClient = BlossomClient()
            
            for (index, imageData) in selectedImageData.enumerated() {
                // Calculate hash
                let sha256 = SHA256.hash(data: imageData).compactMap { String(format: "%02x", $0) }.joined()
                let size = Int64(imageData.count)
                let mimeType = "image/jpeg"
                
                // Try uploading to multiple servers
                var uploadSuccess = false
                var uploadedUrl: String?
                var uploadError: Error?
                
                for server in blossomServers {
                    do {
                        // Create auth event
                        let auth = try await BlossomAuth.createUploadAuth(
                            sha256: sha256,
                            size: size,
                            mimeType: mimeType,
                            signer: signer,
                            ndk: nostrManager.ndk!,
                            expiration: Date().addingTimeInterval(60) // 1 minute expiration
                        )
                        
                        // Upload
                        let blob = try await blossomClient.upload(
                            data: imageData,
                            mimeType: mimeType,
                            to: server,
                            auth: auth
                        )
                        
                        uploadedUrl = blob.url
                        uploadSuccess = true
                        
                        // Create imeta tag
                        var imetaTag = ["imeta"]
                        imetaTag.append("url \(blob.url)")
                        imetaTag.append("m \(mimeType)")
                        imetaTag.append("alt Image \(index + 1)")
                        imetaTag.append("x \(sha256)")
                        imetaTag.append("size \(size)")
                        
                        // Add dimensions if available
                        if let image = selectedImages[safe: index] {
                            if let dimensions = getImageDimensions(image) {
                                imetaTag.append("dim \(dimensions.width)x\(dimensions.height)")
                            }
                        }
                        
                        imetaTags.append(imetaTag)
                        
                        break // Success, no need to try other servers
                    } catch {
                        uploadError = error
                        print("Blossom upload to \(server) failed: \(error)")
                        // Continue to next server
                    }
                }
                
                if !uploadSuccess {
                    // Fall back to placeholder if all servers fail
                    uploadedUrl = "https://image.nostr.build/placeholder\(index).jpg"
                    print("All Blossom uploads failed: \(uploadError?.localizedDescription ?? "Unknown error")")
                    
                    // Create basic imeta tag for placeholder
                    let imetaTag = [
                        "imeta",
                        "url \(uploadedUrl!)",
                        "m image/jpeg",
                        "alt Image \(index + 1)"
                    ]
                    imetaTags.append(imetaTag)
                }
                
                uploadProgress += progressPerImage
            }
            
            // 2. Create and publish event
            // Use kind 20 for picture posts as per Olas spec
            let event = try await NDKEventBuilder(ndk: ndk)
                .content(caption) // Only caption in content for kind 20
                .kind(20) // kind 20 - picture post
                .tags(imetaTags) // Image metadata in tags
                .build(signer: signer)
            
            uploadProgress = 0.9
            
            _ = try await ndk.publish(event)
            
            uploadProgress = 1.0
            
            // Success!
            OlasDesign.Haptic.success()
            
            // Wait a moment to show completion
            try await Task.sleep(nanoseconds: 500_000_000)
            
            // Dismiss the view
            dismiss()
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            OlasDesign.Haptic.error()
        }
        
        isPosting = false
    }
    
    #if canImport(UIKit)
    private func getImageDimensions(_ image: UIImage) -> (width: Int, height: Int)? {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return (width: width, height: height)
    }
    #elseif canImport(AppKit)
    private func getImageDimensions(_ image: NSImage) -> (width: Int, height: Int)? {
        guard let representations = image.representations.first else { return nil }
        let width = representations.pixelsWide
        let height = representations.pixelsHigh
        return (width: width, height: height)
    }
    #endif
}

// MARK: - Preview

struct CreatePostView_Previews: PreviewProvider {
    static var previews: some View {
        CreatePostView()
            .environmentObject(AppState())
    }
}