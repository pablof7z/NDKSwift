import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - String Extension for SHA256
extension String {
    var sha256Hash: String {
        // Simple hash for demo - in production use CryptoKit
        let hash = self.hashValue
        return String(format: "%016llx", Int64(bitPattern: UInt64(bitPattern: Int64(hash))))
    }
}

// MARK: - Blurhash View
struct BlurhashView: View {
    let hash: String
    #if os(iOS)
    @State private var image: UIImage?
    #else
    @State private var image: NSImage?
    #endif
    @State private var opacity: Double = 1.0
    
    var body: some View {
        ZStack {
            if let image = image {
                #if os(iOS)
                SwiftUI.Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(opacity)
                    .transition(.opacity)
                #else
                SwiftUI.Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(opacity)
                    .transition(.opacity)
                #endif
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.systemGray5),
                                Color(.systemGray6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .onAppear {
            decodeHash()
        }
    }
    
    private func decodeHash() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Decode blurhash (placeholder implementation)
            // In production, use a proper blurhash library
            let placeholderImage = createPlaceholderImage(from: hash)
            
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.image = placeholderImage
                }
            }
        }
    }
    
    #if os(iOS)
    private func createPlaceholderImage(from hash: String) -> UIImage? {
        // Create a gradient placeholder based on hash
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Extract colors from hash (simplified)
            let hashValue = hash.hashValue
            let hue1 = CGFloat(abs(hashValue % 360)) / 360.0
            let hue2 = CGFloat(abs((hashValue >> 8) % 360)) / 360.0
            
            let color1 = UIColor(hue: hue1, saturation: 0.5, brightness: 0.8, alpha: 1.0)
            let color2 = UIColor(hue: hue2, saturation: 0.5, brightness: 0.6, alpha: 1.0)
            
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [color1.cgColor, color2.cgColor] as CFArray,
                locations: [0, 1]
            )!
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }
    }
    #else
    private func createPlaceholderImage(from hash: String) -> NSImage? {
        // macOS implementation
        let size = CGSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()
        
        let hashValue = hash.hashValue
        let hue1 = CGFloat(abs(hashValue % 360)) / 360.0
        let hue2 = CGFloat(abs((hashValue >> 8) % 360)) / 360.0
        
        let color1 = NSColor(hue: hue1, saturation: 0.5, brightness: 0.8, alpha: 1.0)
        let color2 = NSColor(hue: hue2, saturation: 0.5, brightness: 0.6, alpha: 1.0)
        
        let gradient = NSGradient(colors: [color1, color2])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        
        image.unlockFocus()
        return image
    }
    #endif
}

// MARK: - Progressive Image View
struct OlasProgressiveImage: View {
    let imageURL: String
    let blurhash: String?
    @State private var phase: ImagePhase = .empty
    #if os(iOS)
    @State private var lowQualityImage: UIImage?
    @State private var highQualityImage: UIImage?
    #else
    @State private var lowQualityImage: NSImage?
    @State private var highQualityImage: NSImage?
    #endif
    @State private var progress: Double = 0
    @State private var showHighQuality = false
    
    enum ImagePhase {
        case empty
        case blurhash
        case lowQuality
        case highQuality
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 1: Blurhash or placeholder
                if let blurhash = blurhash {
                    BlurhashView(hash: blurhash)
                        .opacity(phase == .empty || phase == .blurhash ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: phase)
                } else {
                    OlasShimmer()
                        .opacity(phase == .empty ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: phase)
                }
                
                // Layer 2: Low quality image
                if let lowQualityImage = lowQualityImage {
                    #if os(iOS)
                    SwiftUI.Image(uiImage: lowQualityImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(phase == .lowQuality && !showHighQuality ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: phase)
                        .animation(.easeOut(duration: 0.3), value: showHighQuality)
                    #else
                    SwiftUI.Image(nsImage: lowQualityImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(phase == .lowQuality && !showHighQuality ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: phase)
                        .animation(.easeOut(duration: 0.3), value: showHighQuality)
                    #endif
                }
                
                // Layer 3: High quality image
                if let highQualityImage = highQualityImage {
                    #if os(iOS)
                    SwiftUI.Image(uiImage: highQualityImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(showHighQuality ? 1 : 0)
                        .animation(.easeOut(duration: 0.5), value: showHighQuality)
                    #else
                    SwiftUI.Image(nsImage: highQualityImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(showHighQuality ? 1 : 0)
                        .animation(.easeOut(duration: 0.5), value: showHighQuality)
                    #endif
                }
                
                // Loading progress indicator
                if phase == .lowQuality && progress < 1.0 {
                    VStack {
                        Spacer()
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            .scaleEffect(x: 1, y: 0.5)
                            .padding(.horizontal, OlasDesign.Spacing.md)
                            .padding(.bottom, OlasDesign.Spacing.sm)
                            .opacity(0.8)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .onAppear {
                loadImage(size: geometry.size)
            }
        }
    }
    
    private func loadImage(size: CGSize) {
        // Start with blurhash
        if blurhash != nil {
            phase = .blurhash
        }
        
        guard let url = URL(string: imageURL) else { return }
        
        // Load low quality version first
        Task {
            await loadLowQuality(from: url, targetSize: CGSize(width: size.width * 0.25, height: size.height * 0.25))
        }
        
        // Then load high quality
        Task {
            await loadHighQuality(from: url, targetSize: size)
        }
    }
    
    private func loadLowQuality(from url: URL, targetSize: CGSize) async {
        // Simulate progressive loading with URLSession
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            #if os(iOS)
            if let image = UIImage(data: data) {
                let resized = await resizeImage(image, to: targetSize)
                
                await MainActor.run {
                    self.lowQualityImage = resized
                    self.phase = .lowQuality
                }
            }
            #else
            if let image = NSImage(data: data) {
                let resized = await resizeImage(image, to: targetSize)
                
                await MainActor.run {
                    self.lowQualityImage = resized
                    self.phase = .lowQuality
                }
            }
            #endif
        } catch {
            print("Failed to load low quality image: \(error)")
        }
    }
    
    private func loadHighQuality(from url: URL, targetSize: CGSize) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            #if os(iOS)
            if let image = UIImage(data: data) {
                let resized = await resizeImage(image, to: targetSize)
                
                await MainActor.run {
                    self.highQualityImage = resized
                    self.phase = .highQuality
                    
                    // Smooth transition
                    withAnimation(.easeOut(duration: 0.5)) {
                        self.showHighQuality = true
                    }
                }
            }
            #else
            if let image = NSImage(data: data) {
                let resized = await resizeImage(image, to: targetSize)
                
                await MainActor.run {
                    self.highQualityImage = resized
                    self.phase = .highQuality
                    
                    // Smooth transition
                    withAnimation(.easeOut(duration: 0.5)) {
                        self.showHighQuality = true
                    }
                }
            }
            #endif
        } catch {
            print("Failed to load high quality image: \(error)")
        }
    }
    
    #if os(iOS)
    private func resizeImage(_ image: UIImage, to size: CGSize) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let renderer = UIGraphicsImageRenderer(size: size)
                let resized = renderer.image { context in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                continuation.resume(returning: resized)
            }
        }
    }
    #else
    private func resizeImage(_ image: NSImage, to size: CGSize) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let resized = NSImage(size: size)
                resized.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: size))
                resized.unlockFocus()
                continuation.resume(returning: resized)
            }
        }
    }
    #endif
}


// MARK: - Image Cache Manager
class ImageCacheManager {
    static let shared = ImageCacheManager()
    
    #if os(iOS)
    private let memoryCache = NSCache<NSString, UIImage>()
    #else
    private let memoryCache = NSCache<NSString, NSImage>()
    #endif
    private let diskCacheURL: URL
    private let maxMemoryCacheSize = 50 * 1024 * 1024 // 50MB
    private let maxDiskCacheSize = 100 * 1024 * 1024 // 100MB
    
    private init() {
        // Setup disk cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = cacheDir.appendingPathComponent("OlasImageCache")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        
        // Configure memory cache
        memoryCache.totalCostLimit = maxMemoryCacheSize
        
        // Clean old cache on init
        cleanOldCache()
    }
    
    #if os(iOS)
    func getCachedImage(for url: String) -> UIImage? {
        let key = NSString(string: url)
        
        // Check memory cache first
        if let image = memoryCache.object(forKey: key) {
            return image
        }
        
        // Check disk cache
        let fileURL = diskCacheURL.appendingPathComponent(url.sha256Hash)
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            // Add to memory cache
            memoryCache.setObject(image, forKey: key, cost: data.count)
            return image
        }
        
        return nil
    }
    #else
    func getCachedImage(for url: String) -> NSImage? {
        let key = NSString(string: url)
        
        // Check memory cache first
        if let image = memoryCache.object(forKey: key) {
            return image
        }
        
        // Check disk cache
        let fileURL = diskCacheURL.appendingPathComponent(url.sha256Hash)
        if let data = try? Data(contentsOf: fileURL),
           let image = NSImage(data: data) {
            // Add to memory cache
            memoryCache.setObject(image, forKey: key, cost: data.count)
            return image
        }
        
        return nil
    }
    #endif
    
    #if os(iOS)
    func cacheImage(_ image: UIImage, for url: String) {
        let key = NSString(string: url)
        
        // Add to memory cache
        if let data = image.jpegData(compressionQuality: 0.8) {
            memoryCache.setObject(image, forKey: key, cost: data.count)
            
            // Save to disk
            let fileURL = diskCacheURL.appendingPathComponent(url.sha256Hash)
            try? data.write(to: fileURL)
        }
    }
    #else
    func cacheImage(_ image: NSImage, for url: String) {
        let key = NSString(string: url)
        
        // Add to memory cache
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            memoryCache.setObject(image, forKey: key, cost: data.count)
            
            // Save to disk
            let fileURL = diskCacheURL.appendingPathComponent(url.sha256Hash)
            try? data.write(to: fileURL)
        }
    }
    #endif
    
    private func cleanOldCache() {
        // Remove files older than 7 days
        let fileManager = FileManager.default
        let expirationDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        if let files = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.creationDateKey]) {
            for file in files {
                if let attributes = try? file.resourceValues(forKeys: [.creationDateKey]),
                   let creationDate = attributes.creationDate,
                   creationDate < expirationDate {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
}

// End of BlurhashView.swift
