import Foundation

/// Utilities for filter fingerprinting and merging based on ndk-core implementation
enum NDKFilterGrouping {
    /// Creates a fingerprint for filters to determine if they can be grouped together
    ///
    /// This creates a deterministic association of the filters. When the combination of filters
    /// makes it possible to group them, the fingerprint is used to group them.
    ///
    /// The different filters in the array are differentiated so that filters can only be
    /// grouped with other filters that have the same signature.
    ///
    /// - Parameters:
    ///   - filters: The filters to fingerprint
    ///   - closeOnEose: Whether the subscription closes on EOSE
    /// - Returns: The fingerprint string
    static func filterFingerprint(_ filters: [NDKFilter], closeOnEose: Bool) -> String {
        var elements: [String] = []

        for filter in filters {
            var keys: [String] = []

            // Add array-based keys (just the key name, not values)
            if filter.ids != nil { keys.append("ids") }
            if filter.authors != nil { keys.append("authors") }
            if filter.kinds != nil { keys.append("kinds") }
            if filter.events != nil { keys.append("#e") }
            if filter.pubkeys != nil { keys.append("#p") }
            if filter.since != nil { keys.append("since:\(filter.since!)") }
            if filter.until != nil { keys.append("until:\(filter.until!)") }
            if filter.limit != nil { keys.append("limit") }
            // Note: search property doesn't exist in NDKSwift

            // Add tag filters
            if let tags = filter.tags {
                for (tagName, _) in tags.sorted(by: { $0.key < $1.key }) {
                    keys.append("#\(tagName)")
                }
            }

            // Sort keys for deterministic output
            keys.sort()

            elements.append(keys.joined(separator: "-"))
        }

        // Prefix with + for closeOnEose to separate subscription types
        let prefix = closeOnEose ? "+" : ""
        return prefix + elements.joined(separator: "|")
    }

    /// Merges filters with the same structure
    ///
    /// Filters with limits are concatenated (not merged) as merging would change their meaning.
    /// Filters without limits have their array values merged and deduplicated.
    ///
    /// - Parameter filters: Filters to merge (should have same structure)
    /// - Returns: Merged filters
    static func mergeFilters(_ filters: [NDKFilter]) -> [NDKFilter] {
        guard !filters.isEmpty else { return [] }

        var result: [NDKFilter] = []
        var lastResult = NDKFilter()

        // Concatenate filters that have a limit
        let filtersWithLimit = filters.filter { $0.limit != nil }
        result.append(contentsOf: filtersWithLimit)

        // Only merge filters without limits
        let filtersWithoutLimit = filters.filter { $0.limit == nil }

        if filtersWithoutLimit.isEmpty {
            return result
        }

        // Merge array values
        var mergedIds = Set<String>()
        var mergedAuthors = Set<String>()
        var mergedKinds = Set<Int>()
        var mergedEventIds = Set<String>()
        var mergedPubkeys = Set<String>()
        var mergedTags = [String: Set<String>]()

        // Collect all values
        for filter in filtersWithoutLimit {
            if let ids = filter.ids {
                mergedIds.formUnion(ids)
            }
            if let authors = filter.authors {
                mergedAuthors.formUnion(authors)
            }
            if let kinds = filter.kinds {
                mergedKinds.formUnion(kinds)
            }
            if let events = filter.events {
                mergedEventIds.formUnion(events)
            }
            if let pubkeys = filter.pubkeys {
                mergedPubkeys.formUnion(pubkeys)
            }
            if let tags = filter.tags {
                for (tagName, tagValues) in tags {
                    mergedTags[tagName, default: Set()].formUnion(tagValues)
                }
            }
        }

        // Build merged filter
        if !mergedIds.isEmpty {
            lastResult.ids = Array(mergedIds)
        }
        if !mergedAuthors.isEmpty {
            lastResult.authors = Array(mergedAuthors)
        }
        if !mergedKinds.isEmpty {
            lastResult.kinds = Array(mergedKinds)
        }
        if !mergedEventIds.isEmpty {
            lastResult.events = Array(mergedEventIds)
        }
        if !mergedPubkeys.isEmpty {
            lastResult.pubkeys = Array(mergedPubkeys)
        }
        if !mergedTags.isEmpty {
            for (tagName, values) in mergedTags {
                lastResult.addTagFilter(tagName, values: Array(values))
            }
        }

        // Use time constraints from first filter (they should all be the same in a group)
        if let firstFilter = filtersWithoutLimit.first {
            lastResult.since = firstFilter.since
            lastResult.until = firstFilter.until
            // Note: search property doesn't exist in NDKSwift
        }

        result.append(lastResult)

        return result
    }
}
