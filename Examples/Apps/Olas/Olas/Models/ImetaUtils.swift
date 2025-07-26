import Foundation
import NDKSwift

// MARK: - Image Metadata Utilities

struct SimpleImageMetadata {
    var url: String
    var mimeType: String?
    var blurhash: String?
    var width: Int?
    var height: Int?
    var sha256: String?
    var size: Int?
}

enum ImetaUtils {
    
    // Extract image metadata from NIP-92 imeta tags
    static func extractImageMetadata(from tags: [[String]]) -> [SimpleImageMetadata] {
        var imageMetadataList: [SimpleImageMetadata] = []
        
        for tag in tags {
            guard tag.count >= 2, tag[0] == "imeta" else { continue }
            
            var metadata = SimpleImageMetadata(url: "")
            
            // Parse imeta tag format: ["imeta", "url <url>", "m <mime>", "blurhash <hash>", ...]
            for i in 1..<tag.count {
                let parts = tag[i].split(separator: " ", maxSplits: 1)
                guard parts.count == 2 else { continue }
                
                let key = String(parts[0])
                let value = String(parts[1])
                
                switch key {
                case "url":
                    metadata.url = value
                case "m":
                    metadata.mimeType = value
                case "blurhash":
                    metadata.blurhash = value
                case "dim":
                    let dimensions = value.split(separator: "x")
                    if dimensions.count == 2,
                       let width = Int(dimensions[0]),
                       let height = Int(dimensions[1]) {
                        metadata.width = width
                        metadata.height = height
                    }
                case "x":
                    metadata.sha256 = value
                case "size":
                    if let size = Int(value) {
                        metadata.size = size
                    }
                default:
                    break
                }
            }
            
            // Only add if we have a valid URL
            if !metadata.url.isEmpty {
                imageMetadataList.append(metadata)
            }
        }
        
        return imageMetadataList
    }
    
    // Extract first image URL from tags (for quick access)
    static func extractFirstImageURL(from tags: [[String]]) -> String? {
        let metadata = extractImageMetadata(from: tags)
        return metadata.first?.url
    }
    
    // Extract all image URLs from tags
    static func extractImageURLs(from tags: [[String]]) -> [String] {
        let metadata = extractImageMetadata(from: tags)
        return metadata.map { $0.url }
    }
    
    // Build imeta tag for NIP-92
    static func buildImetaTag(for metadata: SimpleImageMetadata) -> [String] {
        var tag = ["imeta"]
        
        tag.append("url \(metadata.url)")
        
        if let mimeType = metadata.mimeType {
            tag.append("m \(mimeType)")
        }
        
        if let blurhash = metadata.blurhash {
            tag.append("blurhash \(blurhash)")
        }
        
        if let width = metadata.width, let height = metadata.height {
            tag.append("dim \(width)x\(height)")
        }
        
        if let sha256 = metadata.sha256 {
            tag.append("x \(sha256)")
        }
        
        if let size = metadata.size {
            tag.append("size \(size)")
        }
        
        return tag
    }
}