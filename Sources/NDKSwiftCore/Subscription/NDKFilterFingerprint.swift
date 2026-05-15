import CryptoKit
import Foundation

/// A deterministic identifier for filter grouping, following ndk-core's approach
public typealias NDKFilterFingerprint = String

public extension NDKFilter {
    /// Creates a fingerprint for a single filter.
    ///
    /// The fingerprint must be stable across:
    /// - process restarts (so persisted fetch-times keyed by fingerprint stay valid)
    /// - multiple NDK instances in the same process (extensions, tests)
    /// - rebuilds with different toolchains
    ///
    /// Swift's `Hasher` is seeded randomly per process, so `[String].hashValue`
    /// returns a different value on each launch. Using it here previously made
    /// every persisted fingerprint look stale on relaunch and split routing
    /// keys between NDK instances. We now SHA-256 a canonical string form.
    func toFingerprint() -> String {
        var parts: [String] = []

        if let ids = ids {
            parts.append("\(NostrConstants.JSONField.ids):\(ids.sorted().joined(separator: ","))")
        }
        if let authors = authors {
            parts.append("\(NostrConstants.JSONField.authors):\(authors.sorted().joined(separator: ","))")
        }
        if let kinds = kinds {
            let kindStr = kinds.sorted().map(String.init).joined(separator: ",")
            parts.append("\(NostrConstants.JSONField.kinds):\(kindStr)")
        }
        if let since = since {
            parts.append("\(NostrConstants.JSONField.since):\(since)")
        }
        if let until = until {
            parts.append("\(NostrConstants.JSONField.until):\(until)")
        }
        if let tags = tags {
            let tagStr = tags.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.sorted().joined(separator: ","))" }
                .joined(separator: ";")
            parts.append("\(NostrConstants.JSONField.tags):\(tagStr)")
        }
        if let limit = limit {
            parts.append("\(NostrConstants.JSONField.limit):\(limit)")
        }

        let canonical = parts.sorted().joined(separator: "-")
        if canonical.isEmpty {
            return "empty-filter"
        }
        let digest = SHA256.hash(data: Data(canonical.utf8))
        // 16 hex chars (64 bits) is plenty to dedupe filters across a process.
        return String(Data(digest).hexString.prefix(16))
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
