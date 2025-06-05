import Foundation

/// Utility functions for handling imeta tags
public enum ImetaUtils {
    /// Maps a tag array to an NDKImetaTag structure
    /// Supports both single-value format: ["imeta", "url https://... alt text"]
    /// And multi-value format: ["imeta", "url https://...", "alt text", ...]
    public static func mapImetaTag(_ tag: Tag) -> NDKImetaTag? {
        guard tag.count >= 2, tag[0] == "imeta" else { return nil }

        var imeta = NDKImetaTag()

        if tag.count == 2 {
            // Single value format: ["imeta", "url https://... alt text"]
            let parts = tag[1].split(separator: " ", maxSplits: 1)
            guard parts.count >= 2 else { return nil }

            let field = String(parts[0])
            let value = String(parts[1])

            applyFieldValue(to: &imeta, field: field, value: value)
        } else {
            // Multi-value format: ["imeta", "url https://...", "alt text", ...]
            for i in 1 ..< tag.count {
                let parts = tag[i].split(separator: " ", maxSplits: 1)
                guard parts.count >= 2 else { continue }

                let field = String(parts[0])
                let value = String(parts[1])

                applyFieldValue(to: &imeta, field: field, value: value)
            }
        }

        return imeta
    }

    /// Converts an NDKImetaTag to a tag array format
    public static func imetaTagToTag(_ imeta: NDKImetaTag) -> Tag {
        var components = ["imeta"]

        if let url = imeta.url {
            components.append("url \(url)")
        }

        if let blurhash = imeta.blurhash {
            components.append("blurhash \(blurhash)")
        }

        if let dim = imeta.dim {
            components.append("dim \(dim)")
        }

        if let alt = imeta.alt {
            components.append("alt \(alt)")
        }

        if let m = imeta.m {
            components.append("m \(m)")
        }

        if let x = imeta.x {
            components.append("x \(x)")
        }

        if let size = imeta.size {
            components.append("size \(size)")
        }

        // Handle fallback array
        if let fallback = imeta.fallback {
            for fallbackUrl in fallback {
                components.append("fallback \(fallbackUrl)")
            }
        }

        // Handle additional fields
        for (key, value) in imeta.additionalFields {
            components.append("\(key) \(value)")
        }

        return components
    }

    // MARK: - Private Helpers

    private static func applyFieldValue(to imeta: inout NDKImetaTag, field: String, value: String) {
        switch field {
        case "url":
            imeta.url = value
        case "blurhash":
            imeta.blurhash = value
        case "dim":
            imeta.dim = value
        case "alt":
            imeta.alt = value
        case "m":
            imeta.m = value
        case "x":
            imeta.x = value
        case "size":
            imeta.size = value
        case "fallback":
            if imeta.fallback == nil {
                imeta.fallback = []
            }
            imeta.fallback?.append(value)
        default:
            imeta.additionalFields[field] = value
        }
    }
}
