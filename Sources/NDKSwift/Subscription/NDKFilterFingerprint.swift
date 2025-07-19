import Foundation

/// Filter fingerprint for grouping compatibility
/// Follows ndk-core's approach: uses filter keys (not values) to determine groupability
public struct NDKFilterFingerprint: Hashable {
    public let value: String
    
    /// Create fingerprint from filters following ndk-core pattern:
    /// Format: [+][filter-keys-sorted|filter-keys-sorted|...]
    /// - Prefix '+' indicates closeOnEose
    /// - Filter keys are sorted alphabetically
    /// - Multiple filters separated by '|'
    /// - Time constraints (since/until) include actual values
    public init(filters: [NDKFilter], closeOnEose: Bool) {
        var parts: [String] = []
        
        for filter in filters {
            var keys: [String] = []
            
            // Add keys for non-nil properties (not values, except for time)
            if filter.ids != nil { keys.append("ids") }
            if filter.authors != nil { keys.append("authors") }
            if filter.kinds != nil { keys.append("kinds") }
            if filter.events != nil { keys.append("#e") }
            if filter.pubkeys != nil { keys.append("#p") }
            
            // Time constraints include values to prevent mixing different windows
            if let since = filter.since { keys.append("since:\(since)") }
            if let until = filter.until { keys.append("until:\(until)") }
            
            // Limit affects groupability
            if filter.limit != nil { keys.append("limit") }
            
            // Add generic tag filters
            if let tags = filter.tags {
                for tagName in tags.keys.sorted() {
                    keys.append("#\(tagName)")
                }
            }
            
            // Sort keys and join
            let filterPart = keys.sorted().joined(separator: "-")
            parts.append(filterPart)
        }
        
        // Build final fingerprint
        let prefix = closeOnEose ? "+" : ""
        self.value = prefix + parts.joined(separator: "|")
    }
}