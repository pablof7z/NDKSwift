import SwiftUI
import Photos

struct PhotoLibraryView: View {
    @Binding var selectedImage: UIImage?
    let onNext: () -> Void
    let onCancel: () -> Void

    @State private var photos: [PHAsset] = []
    @State private var selectedAsset: PHAsset?
    @State private var showCamera = false
    @State private var isLoading = true

    private let imageManager = PHCachingImageManager()

    var body: some View {
        GeometryReader { geometry in
            let cellSize = (geometry.size.width - 6) / 4 // 4 columns with 2pt spacing between

            VStack(spacing: 0) {
                previewArea
                albumSelector
                photoGrid(cellSize: cellSize)
            }
        }
        .background(Color.black)
        .navigationTitle("New Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") {
                    onNext()
                }
                .fontWeight(.semibold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .disabled(selectedImage == nil)
            }
        }
        .task {
            await loadPhotos()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(image: $selectedImage)
        }
    }

    private var previewArea: some View {
        ZStack {
            Color(white: 0.1)

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(height: 360)
    }

    private var albumSelector: some View {
        HStack {
            Button {
                // Album picker
            } label: {
                HStack(spacing: 6) {
                    Text("Recents")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    // Multi-select mode
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(white: 0.15))
                        .clipShape(Circle())
                }

                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(white: 0.15))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.1))
        }
    }

    private func photoGrid(cellSize: CGFloat) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.fixed(cellSize), spacing: 2),
                    GridItem(.fixed(cellSize), spacing: 2),
                    GridItem(.fixed(cellSize), spacing: 2),
                    GridItem(.fixed(cellSize), spacing: 2)
                ],
                spacing: 2
            ) {
                ForEach(photos, id: \.localIdentifier) { asset in
                    PhotoGridItem(
                        asset: asset,
                        size: cellSize,
                        isSelected: selectedAsset?.localIdentifier == asset.localIdentifier,
                        imageManager: imageManager
                    ) {
                        selectPhoto(asset)
                    }
                }
            }
        }
        .background(Color.black)
    }

    private func loadPhotos() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            isLoading = false
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 100

        let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var assets: [PHAsset] = []
        results.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        await MainActor.run {
            photos = assets
            isLoading = false

            if let first = assets.first {
                selectPhoto(first)
            }
        }
    }

    private func selectPhoto(_ asset: PHAsset) {
        selectedAsset = asset

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let targetSize = CGSize(
            width: asset.pixelWidth,
            height: asset.pixelHeight
        )

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            if let image {
                selectedImage = image
            }
        }
    }
}

private struct PhotoGridItem: View {
    let asset: PHAsset
    let size: CGFloat
    let isSelected: Bool
    let imageManager: PHCachingImageManager
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Color(white: 0.1)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                }

                if isSelected {
                    Rectangle()
                        .stroke(OlasTheme.Colors.deepTeal, lineWidth: 3)

                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(
                                    LinearGradient(
                                        colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Circle())
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        let thumbSize = CGSize(width: size * 2, height: size * 2)

        imageManager.requestImage(
            for: asset,
            targetSize: thumbSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let image {
                thumbnail = image
            }
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
