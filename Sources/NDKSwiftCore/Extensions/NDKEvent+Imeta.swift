import Foundation

/// Extension for NDKEvent to handle NIP-92 imeta tag extraction
public extension NDKEvent {
    /// Extract all imeta tags from this event
    /// - Returns: Array of NDKImetaTag objects parsed from the event's tags
    var imetas: [NDKImetaTag] {
        return tags
            .filter { $0.first == "imeta" }
            .compactMap { ImetaUtils.mapImetaTag($0) }
    }

    /// Check if this event contains any imeta tags
    var hasImeta: Bool {
        return tags.contains { $0.first == "imeta" }
    }

    /// Get imeta tags for a specific URL
    /// - Parameter url: The URL to search for
    /// - Returns: Array of NDKImetaTag objects that match the URL
    func imetas(for url: String) -> [NDKImetaTag] {
        return imetas.filter { $0.url == url }
    }

    /// Get the first imeta tag (if any)
    var firstImeta: NDKImetaTag? {
        return imetas.first
    }

    /// Get all media URLs from imeta tags
    var imetaURLs: [String] {
        return imetas.compactMap { $0.url }
    }

    /// Get imeta tags grouped by MIME type
    var imetasByMimeType: [String: [NDKImetaTag]] {
        var grouped: [String: [NDKImetaTag]] = [:]

        for imeta in imetas {
            if let mimeType = imeta.m {
                if grouped[mimeType] == nil {
                    grouped[mimeType] = []
                }
                grouped[mimeType]?.append(imeta)
            }
        }

        return grouped
    }

    /// Get only image imeta tags
    var imageImetas: [NDKImetaTag] {
        return imetas.filter { imeta in
            guard let mimeType = imeta.m?.lowercased() else { return false }
            return mimeType.hasPrefix("image/")
        }
    }

    /// Get only video imeta tags
    var videoImetas: [NDKImetaTag] {
        return imetas.filter { imeta in
            guard let mimeType = imeta.m?.lowercased() else { return false }
            return mimeType.hasPrefix("video/")
        }
    }

    /// Get only audio imeta tags
    var audioImetas: [NDKImetaTag] {
        return imetas.filter { imeta in
            guard let mimeType = imeta.m?.lowercased() else { return false }
            return mimeType.hasPrefix("audio/")
        }
    }

    /// Get dimensions from the first image imeta tag
    var primaryImageDimensions: (width: Int, height: Int)? {
        guard let firstImage = imageImetas.first,
              let dimString = firstImage.dim else { return nil }

        let parts = dimString.split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]) else { return nil }

        return (width: width, height: height)
    }

    /// Get the blurhash from the first image imeta tag
    var primaryImageBlurhash: String? {
        return imageImetas.first?.blurhash
    }

    /// Get the primary image URL (first image imeta URL)
    var primaryImageURL: String? {
        return imageImetas.first?.url
    }

    /// Get all image URLs from imeta tags
    var imageURLs: [String] {
        return imageImetas.compactMap { $0.url }
    }
}
