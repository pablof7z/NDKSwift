import SwiftUI
import UIKit
import UnifiedBlurHash

/// Thread-safe image cache using NSCache
actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private var runningTasks: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func setImage(_ image: UIImage, for url: URL) {
        let cost = image.jpegData(compressionQuality: 1.0)?.count ?? 0
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }

    func loadImage(from url: URL) async -> UIImage? {
        // Check cache first
        if let cached = cache.object(forKey: url.absoluteString as NSString) {
            return cached
        }

        // Check if already loading
        if let existingTask = runningTasks[url.absoluteString] {
            return await existingTask.value
        }

        // Start new download
        let task = Task<UIImage?, Never> {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await self.setImage(image, for: url)
                    return image
                }
            } catch {
                // Silent fail, return nil
            }
            return nil
        }

        runningTasks[url.absoluteString] = task
        let result = await task.value
        runningTasks[url.absoluteString] = nil

        return result
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}

// MARK: - Blurhash Decoder

/// Decodes blurhash strings into UIImage placeholders
enum BlurhashDecoder {
    /// Decode a blurhash string into a UIImage
    /// - Parameters:
    ///   - blurhash: The blurhash string from NIP-68 imeta tag
    ///   - size: Target size for the decoded image (small is fine, it will be scaled)
    /// - Returns: A UIImage representing the blurred placeholder, or nil if decoding fails
    static func decode(_ blurhash: String, size: CGSize = CGSize(width: 32, height: 32)) -> UIImage? {
        return UIImage(blurHash: blurhash, size: size)
    }
}

// MARK: - CachedAsyncImage

/// Cached async image view with blurhash placeholder support (NIP-68)
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let blurhash: String?
    let aspectRatio: CGFloat?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var blurhashImage: UIImage?

    init(
        url: URL?,
        blurhash: String? = nil,
        aspectRatio: CGFloat? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.blurhash = blurhash
        self.aspectRatio = aspectRatio
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else if let blurhashImage {
                // Show decoded blurhash as placeholder while loading
                Image(uiImage: blurhashImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
        .onAppear {
            decodeBlurhash()
        }
    }

    private func decodeBlurhash() {
        guard blurhashImage == nil, let blurhash, !blurhash.isEmpty else { return }

        // Decode at a small size - it will be scaled up with blur effect
        let size: CGSize
        if let aspectRatio, aspectRatio > 0 {
            // Use aspect ratio to get correct proportions
            if aspectRatio > 1 {
                size = CGSize(width: 32, height: 32 / aspectRatio)
            } else {
                size = CGSize(width: 32 * aspectRatio, height: 32)
            }
        } else {
            size = CGSize(width: 32, height: 32)
        }

        blurhashImage = BlurhashDecoder.decode(blurhash, size: size)
    }

    private func loadImage() async {
        guard let url else { return }

        if let loadedImage = await ImageCache.shared.loadImage(from: url) {
            self.image = loadedImage
        }
    }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(
        url: URL?,
        blurhash: String? = nil,
        aspectRatio: CGFloat? = nil,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            url: url,
            blurhash: blurhash,
            aspectRatio: aspectRatio,
            content: content,
            placeholder: { ProgressView() }
        )
    }
}

extension CachedAsyncImage where Placeholder == EmptyView {
    init(
        url: URL?,
        blurhash: String? = nil,
        aspectRatio: CGFloat? = nil,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            url: url,
            blurhash: blurhash,
            aspectRatio: aspectRatio,
            content: content,
            placeholder: { EmptyView() }
        )
    }
}
