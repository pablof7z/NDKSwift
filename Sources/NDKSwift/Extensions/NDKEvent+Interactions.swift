/// Extensions for NDKEvent to handle user interactions (NIP-09, NIP-18, NIP-25)
public extension NDKEvent {
    
    // MARK: - NIP-18: Reposts
    
    /// Create a repost of this event
    /// 
    /// - Parameters:
    ///   - signer: The signer to use for creating the repost
    ///   - ndk: The NDK instance for context
    /// 
    /// - Returns: The created repost event
    /// 
    /// This method follows NIP-18 specifications:
    /// - Uses kind 6 for text notes (kind 1)
    /// - Uses kind 16 for all other event kinds
    /// - Includes the full event JSON in content (unless protected by NIP-70)
    /// - Adds appropriate tags (e, p, and k for non-text events)
    func repost(signer: NDKSigner, ndk: NDK) async throws -> NDKEvent {
        // Determine repost kind based on original event kind
        let repostKind = self.kind == EventKind.textNote ? EventKind.repost : EventKind.genericRepost
        
        // Set content to JSON stringified event (unless it's protected)
        let content: String
        if !self.isProtected {
            content = (try? self.serialize()) ?? ""
        } else {
            content = ""
        }
        
        var builder = await NDKEventBuilder(ndk: ndk)
            .content(content)
            .kind(repostKind)
            .tagUser(self.pubkey)
            .tagEvent(self)
        
        // For non-text events, add k tag with original kind
        if self.kind != EventKind.textNote {
            builder = builder.tag(["k", String(self.kind)])
        }
        
        return try await builder.build(signer: signer)
    }
    
    /// Create a quote repost of this event (kind 1 with q tag)
    /// 
    /// - Parameters:
    ///   - comment: The comment to add to the quote
    ///   - signer: The signer to use
    ///   - ndk: The NDK instance for context
    /// 
    /// - Returns: The created quote repost event
    func quoteRepost(comment: String, signer: NDKSigner, ndk: NDK) async throws -> NDKEvent {
        // Create nevent/note reference
        let reference = try self.encode()
        let fullContent = "\(comment)\n\n\(NostrConstants.nostrPrefix)\(reference)"
        
        // Create quote repost as a text note with q tag
        let builder = await NDKEventBuilder(ndk: ndk)
            .content(fullContent)
            .kind(EventKind.textNote)
            .quoteEvent(self)
        
        return try await builder.build(signer: signer)
    }
    
    // MARK: - NIP-25: Reactions
    
    /// Create a reaction to this event
    /// 
    /// - Parameters:
    ///   - content: The reaction content (e.g., "+", "-", "❤️", "🚀")
    ///   - signer: The signer to use
    ///   - ndk: The NDK instance for context
    /// 
    /// - Returns: The created reaction event
    func react(with content: String, signer: NDKSigner, ndk: NDK) async throws -> NDKEvent {
        // Create reaction event
        let builder = await NDKEventBuilder(ndk: ndk)
            .content(content)
            .kind(EventKind.reaction)
            .tagUser(self.pubkey)
            .tag(["k", String(self.kind)])
            .tagEvent(self)
        
        return try await builder.build(signer: signer)
    }
    
    /// Create a like reaction (+)
    func like(signer: NDKSigner, ndk: NDK) async throws -> NDKEvent {
        return try await react(with: "+", signer: signer, ndk: ndk)
    }
    
    /// Create a dislike reaction (-)
    func dislike(signer: NDKSigner, ndk: NDK) async throws -> NDKEvent {
        return try await react(with: "-", signer: signer, ndk: ndk)
    }
    
    // MARK: - NIP-09: Event Deletion
    
    /// Delete this event by creating and publishing a deletion request
    /// 
    /// - Parameters:
    ///   - reason: The reason for deletion (optional)
    ///   - signer: The signer to use
    ///   - ndk: NDK instance to publish the deletion (required)
    /// 
    /// - Returns: The published deletion event
    @discardableResult
    func delete(reason: String = "", signer: NDKSigner, ndk: NDK) async throws -> NDKEvent {
        
        // Create deletion event
        let builder = await NDKEventBuilder(ndk: ndk)
            .content(reason)
            .kind(EventKind.deletion)
            .tag(["k", String(self.kind)])
            .tagEvent(self)
        
        let deletionEvent = try await builder.build(signer: signer)
        
        // Publish the deletion event
        _ = try await ndk.publish(deletionEvent)
        
        return deletionEvent
    }
    
    /// Create a deletion request for this event without publishing
    /// 
    /// - Parameters:
    ///   - reason: The reason for deletion (optional)
    ///   - signer: The signer to use
    ///   - ndk: The NDK instance for context
    /// 
    /// - Returns: The created deletion event
    func createDeletionRequest(reason: String = "", signer: NDKSigner, ndk: NDK) async throws -> NDKEvent {
        // Create deletion event
        let builder = await NDKEventBuilder(ndk: ndk)
            .content(reason)
            .kind(EventKind.deletion)
            .tag(["k", String(self.kind)])
            .tagEvent(self)
        
        return try await builder.build(signer: signer)
    }
}