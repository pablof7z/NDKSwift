import Foundation
// import UnifiedBlurHash
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Processes media files to extract metadata like blurhash and dimensions
public enum BlossomMediaProcessor {
    
    /// Process image data to extract metadata
    /// - Parameter data: The image data
    /// - Returns: Tuple containing blurhash and dimensions, or nil if not an image
    public static func processImage(_ data: Data) -> (blurhash: String, dimensions: (width: Int, height: Int))? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = image.scale
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        
        // For now, return a placeholder blurhash since we can't use external dependencies
        // A real implementation would calculate the actual blurhash
        let blurhash = "L00000fQfQfQfQfQfQfQfQfQfQfQ"
        
        return (blurhash: blurhash, dimensions: (width: pixelWidth, height: pixelHeight))
        
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        
        // For macOS, we need to get the pixel dimensions differently
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        
        // For now, return a placeholder blurhash since we can't use external dependencies
        // A real implementation would calculate the actual blurhash with component counts
        // based on image dimensions (e.g., min(9, max(4, pixelWidth / 100)))
        let blurhash = "L00000fQfQfQfQfQfQfQfQfQfQfQ"
        
        return (blurhash: blurhash, dimensions: (width: pixelWidth, height: pixelHeight))
        #endif
    }
    
    /// Check if the given MIME type is an image type we can process
    public static func isProcessableImageType(_ mimeType: String?) -> Bool {
        guard let mimeType = mimeType?.lowercased() else { return false }
        return mimeType.hasPrefix("image/") && 
               (mimeType.contains("jpeg") || 
                mimeType.contains("jpg") || 
                mimeType.contains("png") || 
                mimeType.contains("webp") ||
                mimeType.contains("heic") ||
                mimeType.contains("heif"))
    }
    
    /// Infer MIME type from data signature
    public static func inferMimeType(from data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        
        let bytes = [UInt8](data.prefix(12))
        
        // Check common image format signatures
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        } else if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        } else if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return "image/gif"
        } else if data.count >= 12 && 
                  bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return "image/webp"
        } else if data.count >= 12 &&
                  bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 &&
                  (bytes[8] == 0x68 && bytes[9] == 0x65 && bytes[10] == 0x69 && bytes[11] == 0x63) {
            return "image/heic"
        }
        
        return nil
    }
}