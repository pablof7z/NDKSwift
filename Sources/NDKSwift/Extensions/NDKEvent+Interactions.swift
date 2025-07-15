import Foundation

/// Extensions for NDKEvent to handle user interactions (NIP-09, NIP-18, NIP-25)
public extension NDKEvent {
    
    // MARK: - NIP-18: Reposts
    
    /// Create a repost of this event
    /// 
    /// - Parameters:
    ///   - signer: The signer to use for creating the repost
    /// 
    /// - Returns: The created repost event
    /// 
    /// This method follows NIP-18 specifications:
    /// - Uses kind 6 for text notes (kind 1)
    /// - Uses kind 16 for all other event kinds
    /// - Includes the full event JSON in content (unless protected by NIP-70)
    /// - Adds appropriate tags (e, p, and k for non-text events)
    func repost(signer: NDKSigner) async throws -> NDKEvent {
        // Create repost event using builder
        return try await NDKEventBuilder.repost(self, includeContent: true)
            .build(signer: signer)
    }
    
    /// Create a quote repost of this event (kind 1 with q tag)
    /// 
    /// - Parameters:
    ///   - comment: The comment to add to the quote
    ///   - signer: The signer to use
    /// 
    /// - Returns: The created quote repost event
    func quoteRepost(comment: String, signer: NDKSigner) async throws -> NDKEvent {
        // Create nevent/note reference
        let reference = try self.encode()
        let fullContent = "\(comment)\n\nnostr:\(reference)"
        
        // Create quote repost as a text note with q tag
        return try await NDKEventBuilder()
            .content(fullContent)
            .kind(EventKind.textNote)
            .tag(["q", self.id, "", self.pubkey])
            .build(signer: signer)
    }
    
    // MARK: - NIP-25: Reactions
    
    /// Create a reaction to this event
    /// 
    /// - Parameters:
    ///   - content: The reaction content (e.g., "+", "-", "❤️", "🚀")
    ///   - signer: The signer to use
    /// 
    /// - Returns: The created reaction event
    func react(with content: String, signer: NDKSigner) async throws -> NDKEvent {
        // Create reaction event
        return try await NDKEventBuilder()
            .content(content)
            .kind(EventKind.reaction)
            .tagEvent(self.id)
            .tagUser(self.pubkey)
            .tag(["k", String(self.kind)])
            .build(signer: signer)
    }
    
    /// Create a like reaction (+)
    func like(signer: NDKSigner) async throws -> NDKEvent {
        return try await react(with: "+", signer: signer)
    }
    
    /// Create a dislike reaction (-)
    func dislike(signer: NDKSigner) async throws -> NDKEvent {
        return try await react(with: "-", signer: signer)
    }
    
    // MARK: - NIP-09: Event Deletion
    
    /// Delete this event by creating and publishing a deletion request
    /// 
    /// - Parameters:
    ///   - ndk: NDK instance to publish the deletion
    ///   - reason: The reason for deletion (optional)
    ///   - signer: The signer to use
    /// 
    /// - Returns: The published deletion event
    @discardableResult
    func delete(ndk: NDK, reason: String = "", signer: NDKSigner) async throws -> NDKEvent {
        // Create deletion event
        let deletionEvent = try await NDKEventBuilder()
            .content(reason)
            .kind(EventKind.deletion)
            .tagEvent(self.id)
            .tag(["k", String(self.kind)])
            .build(signer: signer)
        
        // Publish the deletion event
        try await ndk.publish(deletionEvent)
        
        return deletionEvent
    }
    
    /// Create a deletion request for this event without publishing
    /// 
    /// - Parameters:
    ///   - reason: The reason for deletion (optional)
    ///   - signer: The signer to use
    /// 
    /// - Returns: The created deletion event
    func createDeletionRequest(reason: String = "", signer: NDKSigner) async throws -> NDKEvent {
        // Create deletion event
        return try await NDKEventBuilder()
            .content(reason)
            .kind(EventKind.deletion)
            .tagEvent(self.id)
            .tag(["k", String(self.kind)])
            .build(signer: signer)
    }
}