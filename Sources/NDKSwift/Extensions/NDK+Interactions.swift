import Foundation

/// Extensions for NDK to handle user interactions (NIP-09, NIP-18, NIP-25)
public extension NDK {
    
    // MARK: - NIP-18: Reposts
    
    /// Repost an event
    /// 
    /// - Parameter event: The event to repost
    /// 
    /// - Returns: The published repost event
    /// 
    /// This method follows NIP-18 specifications:
    /// - Uses kind 6 for text notes (kind 1)
    /// - Uses kind 16 for all other event kinds
    /// - Includes the full event JSON in content (unless protected by NIP-70)
    /// - Adds appropriate tags (e, p, and k for non-text events)
    func repost(_ event: NDKEvent) async throws -> NDKEvent {
        guard let signer = signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        let repostEvent = try await event.repost(signer: signer)
        _ = try await publish(repostEvent)
        return repostEvent
    }
    
    /// Quote repost an event with a comment
    /// 
    /// - Parameters:
    ///   - event: The event to quote
    ///   - comment: The comment to add
    /// 
    /// - Returns: The published quote repost event
    func quoteRepost(_ event: NDKEvent, comment: String) async throws -> NDKEvent {
        guard let signer = signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        let quoteEvent = try await event.quoteRepost(comment: comment, signer: signer)
        _ = try await publish(quoteEvent)
        return quoteEvent
    }
    
    // MARK: - NIP-25: Reactions
    
    /// React to an event
    /// 
    /// - Parameters:
    ///   - event: The event to react to
    ///   - content: The reaction content (e.g., "+", "-", "❤️", "🚀")
    /// 
    /// - Returns: The published reaction event
    func react(to event: NDKEvent, with content: String) async throws -> NDKEvent {
        guard let signer = signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        let reaction = try await event.react(with: content, signer: signer)
        _ = try await publish(reaction)
        return reaction
    }
    
    /// Like an event (+ reaction)
    /// 
    /// - Parameter event: The event to like
    /// - Returns: The published reaction event
    func like(_ event: NDKEvent) async throws -> NDKEvent {
        return try await react(to: event, with: "+")
    }
    
    /// Dislike an event (- reaction)
    /// 
    /// - Parameter event: The event to dislike
    /// - Returns: The published reaction event
    func dislike(_ event: NDKEvent) async throws -> NDKEvent {
        return try await react(to: event, with: "-")
    }
    
    // MARK: - NIP-09: Event Deletion
    
    /// Delete one or more events
    /// 
    /// - Parameters:
    ///   - events: The events to delete
    ///   - reason: The reason for deletion (optional)
    /// 
    /// - Returns: The published deletion event
    func deleteEvents(_ events: [NDKEvent], reason: String = "") async throws -> NDKEvent {
        guard let signer = signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        var builder = NDKEventBuilder()
            .content(reason)
            .kind(EventKind.deletion)
        
        for event in events {
            builder = builder
                .tagEvent(event.id)
                .tag(["k", String(event.kind)])
        }
        
        let deletionEvent = try await builder.build(signer: signer)
        _ = try await publish(deletionEvent)
        return deletionEvent
    }
    
    /// Delete a single event
    /// 
    /// - Parameters:
    ///   - event: The event to delete
    ///   - reason: The reason for deletion (optional)
    /// 
    /// - Returns: The published deletion event
    func deleteEvent(_ event: NDKEvent, reason: String = "") async throws -> NDKEvent {
        return try await deleteEvents([event], reason: reason)
    }
}