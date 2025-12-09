import SwiftUI
import UIKit

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

/// Cached async image view with loading and error states
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else {
            isLoading = false
            loadFailed = true
            return
        }

        isLoading = true
        loadFailed = false

        if let loadedImage = await ImageCache.shared.loadImage(from: url) {
            self.image = loadedImage
            isLoading = false
        } else {
            isLoading = false
            loadFailed = true
        }
    }
}

// Convenience initializer for simple use case
extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(url: url, content: content, placeholder: { ProgressView() })
    }
}
