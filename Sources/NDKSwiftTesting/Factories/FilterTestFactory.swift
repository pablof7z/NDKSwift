//
// FilterTestFactory.swift
// NDKSwift
//
// Factory methods for creating test filters.
//

import Foundation
import NDKSwiftCore

/// Factory for creating test filters
///
/// Example:
/// ```swift
/// // Create a filter for text notes
/// let filter = FilterTestFactory.textNotes()
///
/// // Create a filter for a specific author
/// let filter = FilterTestFactory.byAuthor(TestKeyPairs.alice.publicKey)
/// ```
public enum FilterTestFactory {
    /// Create a basic filter
    public static func create(
        ids: [String]? = nil,
        authors: [String]? = nil,
        kinds: [Kind]? = nil,
        tags: [String: [String]]? = nil,
        since: Timestamp? = nil,
        until: Timestamp? = nil,
        limit: Int? = nil
    ) -> NDKFilter {
        var tagsDict: [String: Set<String>]?
        if let tags {
            tagsDict = tags.mapValues { Set($0) }
        }

        return NDKFilter(
            ids: ids,
            authors: authors,
            kinds: kinds,
            since: since,
            until: until,
            limit: limit,
            tags: tagsDict
        )
    }

    /// Create a filter for text notes (kind: 1)
    public static func textNotes(
        authors: [String]? = nil,
        since: Timestamp? = nil,
        limit: Int = 20
    ) -> NDKFilter {
        create(
            authors: authors,
            kinds: [1],
            since: since,
            limit: limit
        )
    }

    /// Create a filter for events by a specific author
    public static func byAuthor(
        _ pubkey: String,
        kinds: [Kind]? = nil,
        since: Timestamp? = nil,
        limit: Int = 20
    ) -> NDKFilter {
        create(
            authors: [pubkey],
            kinds: kinds,
            since: since,
            limit: limit
        )
    }

    /// Create a filter for metadata events (kind: 0)
    public static func metadata(
        pubkeys: [String],
        since: Timestamp? = nil
    ) -> NDKFilter {
        create(
            authors: pubkeys,
            kinds: [0],
            since: since,
            limit: pubkeys.count
        )
    }

    /// Create a filter for replies to an event
    public static func replies(
        to eventId: String,
        kinds: [Kind] = [1],
        since: Timestamp? = nil,
        limit: Int = 50
    ) -> NDKFilter {
        create(
            kinds: kinds,
            tags: ["e": [eventId]],
            since: since,
            limit: limit
        )
    }

    /// Create a filter for events with specific p-tags (mentions)
    public static func mentioning(
        pubkeys: [String],
        kinds: [Kind]? = nil,
        since: Timestamp? = nil,
        limit: Int = 50
    ) -> NDKFilter {
        create(
            kinds: kinds,
            tags: ["p": pubkeys],
            since: since,
            limit: limit
        )
    }
}
