import SwiftUI

// MARK: - Blurhash View
struct BlurhashView: View {
    let hash: String
    @State private var image: UIImage?
    @State private var opacity: Double = 1.0
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(opacity)
                    .transition(.opacity)
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
}

// MARK: - Progressive Image View
struct OlasProgressiveImage: View {
    let imageURL: String
    let blurhash: String?
    @State private var phase: ImagePhase = .empty
    @State private var lowQualityImage: UIImage?
    @State private var highQualityImage: UIImage?
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
                    Image(uiImage: lowQualityImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(phase == .lowQuality && !showHighQuality ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: phase)
                        .animation(.easeOut(duration: 0.3), value: showHighQuality)
                }
                
                // Layer 3: High quality image
                if let highQualityImage = highQualityImage {
                    Image(uiImage: highQualityImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(showHighQuality ? 1 : 0)
                        .animation(.easeOut(duration: 0.5), value: showHighQuality)
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
            
            if let image = UIImage(data: data) {
                let resized = await resizeImage(image, to: targetSize)
                
                await MainActor.run {
                    self.lowQualityImage = resized
                    self.phase = .lowQuality
                }
            }
        } catch {
            print("Failed to load low quality image: \(error)")
        }
    }
    
    private func loadHighQuality(from url: URL, targetSize: CGSize) async {
        do {
            // Create a data task to monitor progress
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                guard let data = data, error == nil else { return }
                
                Task {
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
                }
            }
            
            // Monitor progress
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                Task { @MainActor in
                    self.progress = progress.fractionCompleted
                }
            }
            
            task.resume()
            
            // Clean up observation when done
            _ = await withCheckedContinuation { continuation in
                Task {
                    while task.state != .completed {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    }
                    observation.invalidate()
                    continuation.resume()
                }
            }
        }
    }
    
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
}


// MARK: - Image Cache Manager
class ImageCacheManager {
    static let shared = ImageCacheManager()
    
    private let memoryCache = NSCache<NSString, UIImage>()
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

// MARK: - String Extension for SHA256
extension String {
    var sha256Hash: String {
        // Simple hash for demo - in production use CryptoKit
        let hash = self.hashValue
        return String(format: "%016llx", Int64(bitPattern: UInt64(bitPattern: Int64(hash))))
    }
}

#Preview {
    VStack {
        OlasProgressiveImage(
            imageURL: "https://example.com/image.jpg",
            blurhash: "L6PZfSi_.AyE_3t7t7R**0o#DgR4"
        )
        .frame(width: 300, height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    .padding()
    .background(Color.black)
}