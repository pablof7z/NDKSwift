import Foundation

// MARK: - Convenience Initializers

public extension NDKFilter {
    /// Creates a filter for user profile metadata (kind:0)
    /// - Parameters:
    ///   - pubkey: The public key of the user
    ///   - limit: Optional limit for results (default: 1)
    static func profile(for pubkey: String, limit: Int? = 1) -> NDKFilter {
        NDKFilter(authors: [pubkey], kinds: [EventKind.metadata], limit: limit)
    }
    
    /// Creates a filter for user's text notes (kind:1)
    /// - Parameters:
    ///   - pubkey: The public key of the user
    ///   - limit: Optional limit for results
    ///   - since: Optional timestamp to fetch events since
    ///   - until: Optional timestamp to fetch events until
    static func textNotes(
        by pubkey: String,
        limit: Int? = nil,
        since: Timestamp? = nil,
        until: Timestamp? = nil
    ) -> NDKFilter {
        NDKFilter(authors: [pubkey], kinds: [EventKind.textNote], since: since, until: until, limit: limit)
    }
    
    /// Creates a filter for user's contact list (kind:3)
    /// - Parameters:
    ///   - pubkey: The public key of the user
    ///   - limit: Optional limit for results (default: 1)
    static func contactList(for pubkey: String, limit: Int? = 1) -> NDKFilter {
        NDKFilter(authors: [pubkey], kinds: [EventKind.contacts], limit: limit)
    }
    
    /// Creates a filter for reactions to a specific event
    /// - Parameters:
    ///   - eventId: The event ID to find reactions for
    ///   - limit: Optional limit for results
    static func reactions(to eventId: String, limit: Int? = nil) -> NDKFilter {
        NDKFilter(kinds: [EventKind.reaction], events: [eventId], limit: limit)
    }
    
    /// Creates a filter for deletion events (kind:5)
    /// - Parameters:
    ///   - pubkey: The public key of the user who created deletions
    ///   - limit: Optional limit for results
    static func deletions(by pubkey: String, limit: Int? = nil) -> NDKFilter {
        NDKFilter(authors: [pubkey], kinds: [EventKind.deletion], limit: limit)
    }
    
    /// Creates a filter for relay list metadata (kind:10002)
    /// - Parameters:
    ///   - pubkey: The public key of the user
    ///   - limit: Optional limit for results (default: 1)
    static func relayList(for pubkey: String, limit: Int? = 1) -> NDKFilter {
        NDKFilter(authors: [pubkey], kinds: [EventKind.relayList], limit: limit)
    }
    
    /// Creates a filter for multiple event kinds by a user
    /// - Parameters:
    ///   - kinds: Array of event kinds to filter
    ///   - pubkey: The public key of the user
    ///   - limit: Optional limit for results
    static func multipleKinds(_ kinds: [Kind], by pubkey: String, limit: Int? = nil) -> NDKFilter {
        NDKFilter(authors: [pubkey], kinds: kinds, limit: limit)
    }
}