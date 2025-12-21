import Foundation

public extension NDKEventBuilder {

    /// Add media attachment (NIP-92/NIP-94) from a BlossomBlob
    /// - Parameters:
    ///   - blob: The BlossomBlob containing media metadata
    ///   - alt: Optional alt text for accessibility
    /// - Returns: Self for chaining
    @discardableResult
    func addMedia(from blob: BlossomBlob, alt: String? = nil) -> NDKEventBuilder {
        // Add imeta tag
        self.imetaTag(from: blob, alt: alt)

        // Add text content if empty
        if self.content.isEmpty {
            _ = self.content(blob.url, extractImeta: false)
        } else {
            _ = self.content(self.content + "\n\(blob.url)", extractImeta: false)
        }

        // Add alt text if provided
        if let alt = alt {
            self.tag(["alt", alt])
        }

        return self
    }

    /// Add media attachment from a URL
    /// - Parameters:
    ///   - url: The media URL
    ///   - type: MIME type (optional)
    ///   - sha256: SHA-256 hash (optional)
    ///   - size: File size in bytes (optional)
    ///   - dimensions: Dimensions as WxH string (optional)
    ///   - alt: Optional alt text
    /// - Returns: Self for chaining
    @discardableResult
    func addMedia(
        url: String,
        type: String? = nil,
        sha256: String? = nil,
        size: Int64? = nil,
        dimensions: String? = nil,
        alt: String? = nil
    ) -> NDKEventBuilder {

        var imeta = NDKImetaTag(url: url)
        if let type = type { imeta.m = type }
        if let sha256 = sha256 { imeta.x = sha256 }
        if let size = size { imeta.size = "\(size)" }
        if let dimensions = dimensions { imeta.dim = dimensions }
        if let alt = alt { imeta.alt = alt }

        self.imetaTag(imeta)

        // Add text content if empty
        if self.content.isEmpty {
            _ = self.content(url, extractImeta: false)
        } else {
            _ = self.content(self.content + "\n\(url)", extractImeta: false)
        }

        if let alt = alt {
            self.tag(["alt", alt])
        }

        return self
    }
}
