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

    // Image format file signatures
    private enum ImageSignatures {
        // JPEG signature: FF D8 FF
        static let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF]
        // PNG signature: 89 50 4E 47 (‰PNG)
        static let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        // GIF signature: 47 49 46 (GIF)
        static let gif: [UInt8] = [0x47, 0x49, 0x46]
        // WebP signature at offset 8: 57 45 42 50 (WEBP)
        static let webp: [UInt8] = [0x57, 0x45, 0x42, 0x50]
        static let webpOffset = 8
        // HEIC file type box at offset 4: 66 74 79 70 (ftyp) followed by 68 65 69 63 (heic)
        static let ftypBox: [UInt8] = [0x66, 0x74, 0x79, 0x70]
        static let heicType: [UInt8] = [0x68, 0x65, 0x69, 0x63]
        static let ftypOffset = 4

        static let minimumHeaderSize = 12
    }

    /// Infer MIME type from data signature
    public static func inferMimeType(from data: Data) -> String? {
        guard data.count >= ImageSignatures.minimumHeaderSize else { return nil }

        let bytes = [UInt8](data.prefix(ImageSignatures.minimumHeaderSize))

        // Check common image format signatures
        if bytes.starts(with: ImageSignatures.jpeg) {
            return "image/jpeg"
        } else if bytes.starts(with: ImageSignatures.png) {
            return "image/png"
        } else if bytes.starts(with: ImageSignatures.gif) {
            return "image/gif"
        } else if Array(bytes[ImageSignatures.webpOffset...]).starts(with: ImageSignatures.webp) {
            return "image/webp"
        } else if Array(bytes[ImageSignatures.ftypOffset...]).starts(with: ImageSignatures.ftypBox) &&
                  Array(bytes[(ImageSignatures.ftypOffset + ImageSignatures.ftypBox.count)...]).starts(with: ImageSignatures.heicType) {
            return "image/heic"
        }

        return nil
    }
}