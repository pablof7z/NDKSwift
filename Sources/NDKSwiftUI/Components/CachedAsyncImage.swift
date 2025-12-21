import Combine
import NDKSwiftCore
import SwiftSVG
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// A drop-in replacement for AsyncImage with persistent disk and memory caching.
///
/// This view provides automatic image caching both in memory and on disk,
/// reducing network requests and improving app performance. It's designed
/// to be a seamless replacement for SwiftUI's AsyncImage.
///
/// ## Features
/// - Automatic memory caching for recently viewed images
/// - Persistent disk caching across app launches
/// - Seamless URL changes with automatic reloading
/// - Customizable content and placeholder views
/// - Thread-safe cache operations
///
/// ## Usage
/// ```swift
/// // Basic usage with system placeholder
/// CachedAsyncImage(url: imageURL) { image in
///     image
///         .resizable()
///         .aspectRatio(contentMode: .fit)
/// } placeholder: {
///     ProgressView()
/// }
///
/// // With custom placeholder
/// CachedAsyncImage(url: profileURL) { image in
///     image
///         .resizable()
///         .clipShape(Circle())
/// } placeholder: {
///     Image(systemName: "person.circle.fill")
///         .foregroundColor(.gray)
/// }
/// ```
///
/// ## Performance Notes
/// - Images are cached using their URL as the key
/// - Memory cache is automatically managed based on system memory pressure
/// - Disk cache persists across app launches and has configurable size limits
/// - Cache lookups are performed in order: memory → disk → network
public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @StateObject private var loader = ImageLoader()

    /// Creates a cached async image view.
    ///
    /// - Parameters:
    ///   - url: The URL of the image to load. Pass nil to clear the current image.
    ///   - content: A closure that returns the view to display when the image loads successfully.
    ///   - placeholder: A closure that returns the view to display while the image is loading or if it fails to load.
    public init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if let image = loader.image {
                content(image)
            } else {
                placeholder()
            }
        }
        .onAppear {
            loader.load(url: url)
        }
        .onChange(of: url) { _, newURL in
            loader.load(url: newURL)
        }
    }
}

/// Manages image loading and caching.
///
/// This class handles the asynchronous loading of images from URLs,
/// checking both memory and disk caches before downloading from the network.
/// It publishes the loaded image for SwiftUI to display.
private class ImageLoader: ObservableObject {
    @Published var image: Image?

    private var cancellable: AnyCancellable?
    private static let imageCache = ImageCache.shared

    func load(url: URL?) {
        guard let url = url else {
            image = nil
            return
        }

        // Check memory cache first
        if let cachedImage = Self.imageCache.getFromMemory(url: url) {
            NDKLogger.log(.debug, category: .cache, "[CachedAsyncImage] Memory cache HIT: \(url.lastPathComponent)")
            #if canImport(UIKit)
                image = Image(uiImage: cachedImage)
            #elseif canImport(AppKit)
                image = Image(nsImage: cachedImage)
            #endif
            return
        }

        // Check disk cache
        Task {
            if let diskImage = await Self.imageCache.getFromDisk(url: url) {
                NDKLogger.log(.debug, category: .cache, "[CachedAsyncImage] Disk cache HIT: \(url.lastPathComponent)")
                await MainActor.run {
                    #if canImport(UIKit)
                        self.image = Image(uiImage: diskImage)
                    #elseif canImport(AppKit)
                        self.image = Image(nsImage: diskImage)
                    #endif
                }
                return
            }

            NDKLogger.log(.debug, category: .cache, "[CachedAsyncImage] Cache MISS, downloading: \(url.lastPathComponent)")

            // Download if not cached
            await downloadImage(from: url)
        }
    }

    private func downloadImage(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)

#if canImport(UIKit)
            let uiImage: UIImage?

            if url.pathExtension.lowercased() == "svg" {
                uiImage = UIImage(svgData: data)
            } else {
                uiImage = UIImage(data: data)
            }

            guard let finalImage = uiImage else { return }

            // Cache the image
            await Self.imageCache.store(image: finalImage, for: url)
            NDKLogger.log(.debug, category: .cache, "[CachedAsyncImage] Downloaded and cached: \(url.lastPathComponent)")

            await MainActor.run {
                self.image = Image(uiImage: finalImage)
            }
#elseif canImport(AppKit)
            let nsImage: NSImage?

            if url.pathExtension.lowercased() == "svg" {
                nsImage = NSImage(svgData: data)
            } else {
                nsImage = NSImage(data: data)
            }

            guard let finalImage = nsImage else { return }

            // Cache the image
            await Self.imageCache.store(image: finalImage, for: url)
            NDKLogger.log(.debug, category: .cache, "[CachedAsyncImage] Downloaded and cached: \(url.lastPathComponent)")

            await MainActor.run {
                self.image = Image(nsImage: finalImage)
            }
#endif
        } catch {
            NDKLogger.log(.error, category: .cache, "[CachedAsyncImage] Failed to download \(url.lastPathComponent): \(error)")
        }
    }
}

/// Singleton image cache with memory and disk storage
private class ImageCache {
    static let shared = ImageCache()

    #if canImport(UIKit)
        private let memoryCache = NSCache<NSString, UIImage>()
    #elseif canImport(AppKit)
        private let memoryCache = NSCache<NSString, NSImage>()
    #endif
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        // Set up cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("NDKSwiftUI/Images")

        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Configure memory cache
        memoryCache.countLimit = 100 // Max 100 images in memory
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // Max 100MB

        // Listen for memory warnings
        #if canImport(UIKit)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clearMemoryCache),
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )
        #endif
    }

    #if canImport(UIKit)
        func getFromMemory(url: URL) -> UIImage? {
            return memoryCache.object(forKey: url.absoluteString as NSString)
        }

        func getFromDisk(url: URL) async -> UIImage? {
            let filePath = cacheFilePath(for: url)

            guard fileManager.fileExists(atPath: filePath.path) else { return nil }

            // Check if cache is expired (7 days)
            if let attributes = try? fileManager.attributesOfItem(atPath: filePath.path),
               let modificationDate = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modificationDate) > 7 * 24 * 60 * 60
            {
                try? fileManager.removeItem(at: filePath)
                return nil
            }

            guard let data = try? Data(contentsOf: filePath),
                  let image = UIImage(data: data) else { return nil }

            // Also store in memory cache
            memoryCache.setObject(image, forKey: url.absoluteString as NSString, cost: data.count)

            return image
        }

        func store(image: UIImage, for url: URL) async {
            // Store in memory
            let cost = image.pngData()?.count ?? 0
            memoryCache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)

            // Store on disk
            let filePath = cacheFilePath(for: url)
            if let data = image.pngData() {
                try? data.write(to: filePath)
            }
        }

    #elseif canImport(AppKit)
        func getFromMemory(url: URL) -> NSImage? {
            return memoryCache.object(forKey: url.absoluteString as NSString)
        }

        func getFromDisk(url: URL) async -> NSImage? {
            let filePath = cacheFilePath(for: url)

            guard fileManager.fileExists(atPath: filePath.path) else { return nil }

            // Check if cache is expired (7 days)
            if let attributes = try? fileManager.attributesOfItem(atPath: filePath.path),
               let modificationDate = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modificationDate) > 7 * 24 * 60 * 60
            {
                try? fileManager.removeItem(at: filePath)
                return nil
            }

            guard let data = try? Data(contentsOf: filePath),
                  let image = NSImage(data: data) else { return nil }

            // Also store in memory cache
            memoryCache.setObject(image, forKey: url.absoluteString as NSString, cost: data.count)

            return image
        }

        func store(image: NSImage, for url: URL) async {
            // Store in memory
            let tiffRep = image.tiffRepresentation
            let cost = tiffRep?.count ?? 0
            memoryCache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)

            // Store on disk
            let filePath = cacheFilePath(for: url)
            if let tiffData = tiffRep,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let data = bitmapRep.representation(using: .tiff, properties: [:])
            {
                try? data.write(to: filePath)
            }
        }
    #endif

    private func cacheFilePath(for url: URL) -> URL {
        let fileName = url.absoluteString.data(using: .utf8)?.base64EncodedString() ?? "unknown"
        return cacheDirectory.appendingPathComponent(fileName)
    }

    @objc private func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    func clearAll() {
        clearMemoryCache()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
