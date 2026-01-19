import Foundation

/// A deterministic identifier for filter grouping, following ndk-core's approach
public typealias NDKFilterFingerprint = String

public extension NDKFilter {
    /// Creates a fingerprint for a single filter
    ///
    /// The fingerprint includes hashed values of filter fields to ensure that
    /// filters with different values are correctly identified as distinct.
    /// For example, `authors: ["alice"]` and `authors: ["bob"]` will have
    /// different fingerprints.
    ///
    /// This is critical for subscription grouping - filters must only be grouped
    /// when they have the exact same values, not just the same field presence.
    func toFingerprint() -> String {
        var parts: [String] = []

        // Include hashed values for each non-nil property to ensure
        // filters with different values get different fingerprints
        if let ids = ids {
            let hash = ids.sorted().hashValue
            parts.append("\(NostrConstants.JSONField.ids):\(hash)")
        }
        if let authors = authors {
            let hash = authors.sorted().hashValue
            parts.append("\(NostrConstants.JSONField.authors):\(hash)")
        }
        if let kinds = kinds {
            let hash = kinds.sorted().hashValue
            parts.append("\(NostrConstants.JSONField.kinds):\(hash)")
        }
        if let since = since {
            parts.append("\(NostrConstants.JSONField.since):\(since)")
        }
        if let until = until {
            parts.append("\(NostrConstants.JSONField.until):\(until)")
        }
        if let tags = tags {
            // Create deterministic hash from sorted tag entries
            let tagHash = tags.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value.sorted().hashValue)" }
                .joined(separator: ",")
                .hashValue
            parts.append("\(NostrConstants.JSONField.tags):\(tagHash)")
        }
        if let limit = limit {
            parts.append("\(NostrConstants.JSONField.limit):\(limit)")
        }

        // Sort alphabetically and join with "-"
        return parts.sorted().joined(separator: "-")
    }
}

public extension Array where Element == NDKFilter {
    /// Creates a fingerprint for this array of filters
    /// - Parameter closeOnEose: Whether the subscription will close after EOSE
    /// - Returns: A fingerprint string prefixed with "+" if closeOnEose is true
    func toFingerprint(closeOnEose: Bool) -> NDKFilterFingerprint {
        let filterPrints = map { $0.toFingerprint() }
        let prefix = closeOnEose ? "+" : ""
        return prefix + filterPrints.joined(separator: "|")
    }
}

/// Utilities for managing subscription IDs with relay limits
public enum NDKSubscriptionIDGenerator {
    /// Maximum length for subscription IDs (some relays limit to 32 bytes)
    public static let maxSubscriptionIDLength = 32

    /// Generate a relay-safe subscription ID from a fingerprint
    /// - Parameters:
    ///   - fingerprint: The full fingerprint
    ///   - suffix: Optional suffix to add
    /// - Returns: A subscription ID that respects relay limits
    public static func generateRelayID(from fingerprint: String, suffix: String? = nil) -> String {
        var id = fingerprint

        // If there's a suffix, we need to ensure total length stays under limit
        if let suffix = suffix {
            let maxPrefixLength = maxSubscriptionIDLength - suffix.count - 1 // -1 for separator
            if fingerprint.count > maxPrefixLength {
                id = String(fingerprint.prefix(maxPrefixLength))
            }
            id = "\(id)_\(suffix)"
        }

        // Final truncation to ensure we never exceed the limit
        if id.count > maxSubscriptionIDLength {
            return String(id.prefix(maxSubscriptionIDLength))
        }

        return id
    }
}
