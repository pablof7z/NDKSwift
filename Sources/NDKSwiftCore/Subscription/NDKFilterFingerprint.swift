import Foundation

/// A deterministic identifier for filter grouping, following ndk-core's approach
public typealias NDKFilterFingerprint = String

public extension NDKFilter {
    /// Creates a fingerprint for a single filter (matching ndk-core logic)
    /// Only includes property keys, except for since/until which include values
    func toFingerprint() -> String {
        var keys: [String] = []
        
        // Add keys for each non-nil property
        if ids != nil { keys.append(NostrConstants.JSONField.ids) }
        if authors != nil { keys.append(NostrConstants.JSONField.authors) }
        if kinds != nil { keys.append(NostrConstants.JSONField.kinds) }
        if let since = since { 
            keys.append("\(NostrConstants.JSONField.since):\(since)")  // Include value for time constraints
        }
        if let until = until { 
            keys.append("\(NostrConstants.JSONField.until):\(until)")  // Include value for time constraints
        }
        if tags != nil { keys.append(NostrConstants.JSONField.tags) }
        if limit != nil { keys.append(NostrConstants.JSONField.limit) }
        
        // Sort alphabetically and join with "-"
        return keys.sorted().joined(separator: "-")
    }
}

public extension Array where Element == NDKFilter {
    /// Creates a fingerprint for this array of filters
    /// - Parameter closeOnEose: Whether the subscription will close after EOSE
    /// - Returns: A fingerprint string prefixed with "+" if closeOnEose is true
    func toFingerprint(closeOnEose: Bool) -> NDKFilterFingerprint {
        let filterPrints = self.map { $0.toFingerprint() }
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