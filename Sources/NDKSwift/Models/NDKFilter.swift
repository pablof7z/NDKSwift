import Foundation

/// Filter for subscribing to events
public struct NDKFilter: Codable, Equatable {
    /// Event IDs to filter
    public var ids: [EventID]?

    /// Pubkeys of event authors
    public var authors: [PublicKey]?

    /// Event kinds
    public var kinds: [Kind]?

    /// Referenced event IDs (in 'e' tags)
    public var events: [EventID]?

    /// Referenced pubkeys (in 'p' tags)
    public var pubkeys: [PublicKey]?

    /// Events created after this timestamp
    public var since: Timestamp?

    /// Events created before this timestamp
    public var until: Timestamp?

    /// Maximum number of events to return
    public var limit: Int?

    /// Generic tag filters
    private var tagFilters: [String: [String]] = [:]

    // MARK: - Initialization

    public init(
        ids: [EventID]? = nil,
        authors: [PublicKey]? = nil,
        kinds: [Kind]? = nil,
        events: [EventID]? = nil,
        pubkeys: [PublicKey]? = nil,
        since: Timestamp? = nil,
        until: Timestamp? = nil,
        limit: Int? = nil,
        tags: [String: Set<String>]? = nil
    ) {
        self.ids = ids
        self.authors = authors
        self.kinds = kinds
        self.events = events
        self.pubkeys = pubkeys
        self.since = since
        self.until = until
        self.limit = limit

        // Convert tags to tagFilters format
        if let tags = tags {
            for (tagName, values) in tags {
                self.tagFilters["#\(tagName)"] = Array(values)
            }
        }
    }

    // MARK: - Tag Filters

    /// Add a generic tag filter
    public mutating func addTagFilter(_ tagName: String, values: [String]) {
        tagFilters["#\(tagName)"] = values
    }

    /// Get tag filter values
    public func tagFilter(_ tagName: String) -> [String]? {
        return tagFilters["#\(tagName)"]
    }

    /// Get all tag filters as a dictionary
    public var tags: [String: Set<String>]? {
        guard !tagFilters.isEmpty else { return nil }
        var result: [String: Set<String>] = [:]
        for (key, values) in tagFilters {
            // Remove the # prefix
            let tagName = String(key.dropFirst())
            result[tagName] = Set(values)
        }
        return result
    }

    // MARK: - Codable

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        // Decode standard fields
        self.ids = try container.decodeIfPresent([String].self, forKey: DynamicCodingKey(stringValue: "ids")!)
        self.authors = try container.decodeIfPresent([String].self, forKey: DynamicCodingKey(stringValue: "authors")!)
        self.kinds = try container.decodeIfPresent([Int].self, forKey: DynamicCodingKey(stringValue: "kinds")!)
        self.since = try container.decodeIfPresent(Timestamp.self, forKey: DynamicCodingKey(stringValue: "since")!)
        self.until = try container.decodeIfPresent(Timestamp.self, forKey: DynamicCodingKey(stringValue: "until")!)
        self.limit = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKey(stringValue: "limit")!)

        // Handle special tag filters
        if let events = try container.decodeIfPresent([String].self, forKey: DynamicCodingKey(stringValue: "#e")!) {
            self.events = events
        }
        if let pubkeys = try container.decodeIfPresent([String].self, forKey: DynamicCodingKey(stringValue: "#p")!) {
            self.pubkeys = pubkeys
        }

        // Decode generic tag filters
        for key in container.allKeys {
            if key.stringValue.hasPrefix("#") && key.stringValue != "#e" && key.stringValue != "#p" {
                if let values = try container.decodeIfPresent([String].self, forKey: key) {
                    tagFilters[key.stringValue] = values
                }
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        // Encode standard fields
        try container.encodeIfPresent(ids, forKey: DynamicCodingKey(stringValue: "ids")!)
        try container.encodeIfPresent(authors, forKey: DynamicCodingKey(stringValue: "authors")!)
        try container.encodeIfPresent(kinds, forKey: DynamicCodingKey(stringValue: "kinds")!)
        try container.encodeIfPresent(since, forKey: DynamicCodingKey(stringValue: "since")!)
        try container.encodeIfPresent(until, forKey: DynamicCodingKey(stringValue: "until")!)
        try container.encodeIfPresent(limit, forKey: DynamicCodingKey(stringValue: "limit")!)

        // Encode special tag filters
        try container.encodeIfPresent(events, forKey: DynamicCodingKey(stringValue: "#e")!)
        try container.encodeIfPresent(pubkeys, forKey: DynamicCodingKey(stringValue: "#p")!)

        // Encode generic tag filters
        for (key, values) in tagFilters {
            try container.encode(values, forKey: DynamicCodingKey(stringValue: key)!)
        }
    }

    // MARK: - Matching

    /// Check if an event matches this filter
    public func matches(event: NDKEvent) -> Bool {
        // Check IDs
        if let ids = ids, !ids.contains(event.id ?? "") {
            return false
        }

        // Check authors
        if let authors = authors, !authors.contains(event.pubkey) {
            return false
        }

        // Check kinds
        if let kinds = kinds, !kinds.contains(event.kind) {
            return false
        }

        // Check timestamp
        if let since = since, event.createdAt < since {
            return false
        }
        if let until = until, event.createdAt > until {
            return false
        }

        // Check referenced events
        if let events = events {
            let eventRefs = event.tags(withName: "e").compactMap { $0.count > 1 ? $0[1] : nil }
            if !events.contains(where: { eventRefs.contains($0) }) {
                return false
            }
        }

        // Check referenced pubkeys
        if let pubkeys = pubkeys {
            let pubkeyRefs = event.tags(withName: "p").compactMap { $0.count > 1 ? $0[1] : nil }
            if !pubkeys.contains(where: { pubkeyRefs.contains($0) }) {
                return false
            }
        }

        // Check generic tag filters
        for (tagKey, filterValues) in tagFilters {
            let tagName = String(tagKey.dropFirst()) // Remove '#'
            let eventTagValues = event.tags(withName: tagName).compactMap { $0.count > 1 ? $0[1] : nil }

            if !filterValues.contains(where: { eventTagValues.contains($0) }) {
                return false
            }
        }

        return true
    }

    // MARK: - Utilities

    /// Check if this filter is more specific than another
    public func isMoreSpecific(than other: NDKFilter) -> Bool {
        var specificityScore = 0
        var otherScore = 0

        // Compare each field
        if ids != nil { specificityScore += 10 }
        if other.ids != nil { otherScore += 10 }

        if authors != nil { specificityScore += 5 }
        if other.authors != nil { otherScore += 5 }

        if kinds != nil { specificityScore += 3 }
        if other.kinds != nil { otherScore += 3 }

        if events != nil || pubkeys != nil { specificityScore += 4 }
        if other.events != nil || other.pubkeys != nil { otherScore += 4 }

        if since != nil || until != nil { specificityScore += 2 }
        if other.since != nil || other.until != nil { otherScore += 2 }

        if limit != nil { specificityScore += 1 }
        if other.limit != nil { otherScore += 1 }

        specificityScore += tagFilters.count * 2
        otherScore += other.tagFilters.count * 2

        return specificityScore > otherScore
    }

    /// Merge with another filter
    public func merged(with other: NDKFilter) -> NDKFilter? {
        var merged = NDKFilter()

        // For arrays, we need to find common elements
        if let selfIds = ids, let otherIds = other.ids {
            let common = Set(selfIds).intersection(Set(otherIds))
            if common.isEmpty { return nil }
            merged.ids = Array(common)
        } else {
            merged.ids = ids ?? other.ids
        }

        if let selfAuthors = authors, let otherAuthors = other.authors {
            let common = Set(selfAuthors).intersection(Set(otherAuthors))
            if common.isEmpty { return nil }
            merged.authors = Array(common)
        } else {
            merged.authors = authors ?? other.authors
        }

        if let selfKinds = kinds, let otherKinds = other.kinds {
            let common = Set(selfKinds).intersection(Set(otherKinds))
            if common.isEmpty { return nil }
            merged.kinds = Array(common)
        } else {
            merged.kinds = kinds ?? other.kinds
        }

        // For timestamps, use the most restrictive range
        let mergedSince = max(since ?? 0, other.since ?? 0)
        let mergedUntil = min(until ?? .max, other.until ?? .max)

        if mergedSince > mergedUntil {
            return nil
        }

        merged.since = mergedSince
        merged.until = mergedUntil

        // For limit, use the smaller one
        if let selfLimit = limit, let otherLimit = other.limit {
            merged.limit = min(selfLimit, otherLimit)
        } else {
            merged.limit = limit ?? other.limit
        }

        return merged
    }

    /// Returns a dictionary representation of the filter
    public var dictionary: [String: Any] {
        var dict: [String: Any] = [:]

        if let ids = ids { dict["ids"] = ids }
        if let authors = authors { dict["authors"] = authors }
        if let kinds = kinds { dict["kinds"] = kinds }
        if let events = events { dict["#e"] = events }
        if let pubkeys = pubkeys { dict["#p"] = pubkeys }
        if let since = since { dict["since"] = since }
        if let until = until { dict["until"] = until }
        if let limit = limit { dict["limit"] = limit }

        // Add generic tag filters
        for (key, values) in tagFilters {
            dict[key] = values
        }

        return dict
    }
}
