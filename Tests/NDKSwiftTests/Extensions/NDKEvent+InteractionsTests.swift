import XCTest
@testable import NDKSwift

final class NDKEventInteractionsTests: XCTestCase {
    
    var signer: NDKPrivateKeySigner!
    var signerPubkey: PublicKey!
    var ndk: NDK!
    var testEvent: NDKEvent!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a test signer
        signer = try NDKPrivateKeySigner.generate()
        signerPubkey = try await signer.pubkey
        
        // Create NDK instance
        ndk = NDK()
        ndk.signer = signer
        
        // Create a test event
        testEvent = try await NDKEventBuilder()
            .content("Test event for interactions")
            .kind(EventKind.textNote)
            .build(signer: signer)
    }
    
    // MARK: - NIP-18: Repost Tests
    
    func testRepostTextNote() async throws {
        // Create a text note
        let textNote = try await NDKEventBuilder()
            .content("This is a text note")
            .kind(EventKind.textNote)
            .build(signer: signer)
        
        // Create repost
        let repost = try await textNote.repost(signer: signer)
        
        // Verify repost properties
        XCTAssertEqual(repost.kind, EventKind.repost, "Text notes should use kind 6")
        XCTAssertEqual(repost.pubkey, signerPubkey)
        
        // Verify content includes serialized event
        let expectedContent = try textNote.serialize()
        XCTAssertEqual(repost.content, expectedContent)
        
        // Verify tags
        let eTags = repost.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(eTags.first?[1], textNote.id)
        
        let pTags = repost.tags(withName: "p")
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(pTags.first?[1], textNote.pubkey)
        
        // Should not have k tag for text notes
        let kTags = repost.tags(withName: "k")
        XCTAssertEqual(kTags.count, 0)
    }
    
    func testRepostNonTextNote() async throws {
        // Create a non-text note (e.g., reaction)
        let reaction = try await NDKEventBuilder()
            .content("+")
            .kind(EventKind.reaction)
            .build(signer: signer)
        
        // Create repost
        let repost = try await reaction.repost(signer: signer)
        
        // Verify repost properties
        XCTAssertEqual(repost.kind, EventKind.genericRepost, "Non-text notes should use kind 16")
        XCTAssertEqual(repost.pubkey, signerPubkey)
        
        // Verify content includes serialized event
        let expectedContent = try reaction.serialize()
        XCTAssertEqual(repost.content, expectedContent)
        
        // Verify tags
        let eTags = repost.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(eTags.first?[1], reaction.id)
        
        let pTags = repost.tags(withName: "p")
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(pTags.first?[1], reaction.pubkey)
        
        // Should have k tag for non-text notes
        let kTags = repost.tags(withName: "k")
        XCTAssertEqual(kTags.count, 1)
        XCTAssertEqual(kTags.first?[1], String(EventKind.reaction))
    }
    
    func testRepostProtectedEvent() async throws {
        // Create a protected event (NIP-70)
        let protectedEvent = try await NDKEventBuilder()
            .content("Protected content")
            .kind(EventKind.textNote)
            .tag(["-"])
            .build(signer: signer)
        
        // Create repost
        let repost = try await protectedEvent.repost(signer: signer)
        
        // Verify content is empty for protected events
        XCTAssertEqual(repost.content, "", "Protected events should have empty content in repost")
        
        // Verify other properties are correct
        XCTAssertEqual(repost.kind, EventKind.repost)
        XCTAssertTrue(repost.tags(withName: "e").contains { $0[1] == protectedEvent.id })
    }
    
    func testQuoteRepost() async throws {
        let comment = "Check out this great post!"
        
        // Create quote repost
        let quoteRepost = try await testEvent.quoteRepost(comment: comment, signer: signer)
        
        // Verify quote repost properties
        XCTAssertEqual(quoteRepost.kind, EventKind.textNote, "Quote reposts should be text notes")
        XCTAssertEqual(quoteRepost.pubkey, signerPubkey)
        
        // Verify content includes comment and reference
        let reference = try testEvent.encode()
        let expectedContent = "\(comment)\n\nnostr:\(reference)"
        XCTAssertEqual(quoteRepost.content, expectedContent)
        
        // Verify q tag
        let qTags = quoteRepost.tags(withName: "q")
        XCTAssertEqual(qTags.count, 1)
        XCTAssertEqual(qTags.first?[1], testEvent.id)
        XCTAssertEqual(qTags.first?[3], testEvent.pubkey)
    }
    
    // MARK: - NIP-25: Reaction Tests
    
    func testReaction() async throws {
        let reactionContent = "🚀"
        
        // Create reaction
        let reaction = try await testEvent.react(with: reactionContent, signer: signer)
        
        // Verify reaction properties
        XCTAssertEqual(reaction.kind, EventKind.reaction)
        XCTAssertEqual(reaction.content, reactionContent)
        XCTAssertEqual(reaction.pubkey, signerPubkey)
        
        // Verify tags
        let eTags = reaction.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(eTags.first?[1], testEvent.id)
        
        let pTags = reaction.tags(withName: "p")
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(pTags.first?[1], testEvent.pubkey)
        
        let kTags = reaction.tags(withName: "k")
        XCTAssertEqual(kTags.count, 1)
        XCTAssertEqual(kTags.first?[1], String(testEvent.kind))
    }
    
    func testLikeReaction() async throws {
        // Create like reaction
        let like = try await testEvent.like(signer: signer)
        
        // Verify like properties
        XCTAssertEqual(like.kind, EventKind.reaction)
        XCTAssertEqual(like.content, "+")
        XCTAssertEqual(like.pubkey, signerPubkey)
        
        // Verify it references the original event
        XCTAssertTrue(like.referencedEventIds.contains(testEvent.id))
        XCTAssertTrue(like.referencedPubkeys.contains(testEvent.pubkey))
    }
    
    func testDislikeReaction() async throws {
        // Create dislike reaction
        let dislike = try await testEvent.dislike(signer: signer)
        
        // Verify dislike properties
        XCTAssertEqual(dislike.kind, EventKind.reaction)
        XCTAssertEqual(dislike.content, "-")
        XCTAssertEqual(dislike.pubkey, signerPubkey)
        
        // Verify it references the original event
        XCTAssertTrue(dislike.referencedEventIds.contains(testEvent.id))
        XCTAssertTrue(dislike.referencedPubkeys.contains(testEvent.pubkey))
    }
    
    // MARK: - NIP-09: Deletion Tests
    
    func testCreateDeletionRequest() async throws {
        let reason = "Posted by mistake"
        
        // Create deletion request
        let deletion = try await testEvent.createDeletionRequest(reason: reason, signer: signer)
        
        // Verify deletion properties
        XCTAssertEqual(deletion.kind, EventKind.deletion)
        XCTAssertEqual(deletion.content, reason)
        XCTAssertEqual(deletion.pubkey, signerPubkey)
        
        // Verify tags
        let eTags = deletion.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(eTags.first?[1], testEvent.id)
        
        let kTags = deletion.tags(withName: "k")
        XCTAssertEqual(kTags.count, 1)
        XCTAssertEqual(kTags.first?[1], String(testEvent.kind))
    }
    
    func testCreateDeletionRequestWithoutReason() async throws {
        // Create deletion request without reason
        let deletion = try await testEvent.createDeletionRequest(signer: signer)
        
        // Verify deletion properties
        XCTAssertEqual(deletion.kind, EventKind.deletion)
        XCTAssertEqual(deletion.content, "")
        XCTAssertEqual(deletion.pubkey, signerPubkey)
        
        // Verify it references the original event
        XCTAssertTrue(deletion.referencedEventIds.contains(testEvent.id))
    }
    
    func testDeleteMultipleEvents() async throws {
        // Create multiple events
        let event1 = try await NDKEventBuilder()
            .content("Event 1")
            .kind(EventKind.textNote)
            .build(signer: signer)
        
        let event2 = try await NDKEventBuilder()
            .content("Event 2")
            .kind(EventKind.reaction)
            .build(signer: signer)
        
        let reason = "Bulk deletion"
        
        // Create deletion event using builder
        let deletion = try await NDKEventBuilder.deletion(
            events: [(event1.id, event1.kind), (event2.id, event2.kind)],
            reason: reason
        ).build(signer: signer)
        
        // Verify deletion properties
        XCTAssertEqual(deletion.kind, EventKind.deletion)
        XCTAssertEqual(deletion.content, reason)
        
        // Verify e tags
        let eTags = deletion.tags(withName: "e")
        XCTAssertEqual(eTags.count, 2)
        let eventIds = eTags.map { $0[1] }
        XCTAssertTrue(eventIds.contains(event1.id))
        XCTAssertTrue(eventIds.contains(event2.id))
        
        // Verify k tags
        let kTags = deletion.tags(withName: "k")
        XCTAssertEqual(kTags.count, 2)
        let kinds = kTags.map { $0[1] }
        XCTAssertTrue(kinds.contains(String(event1.kind)))
        XCTAssertTrue(kinds.contains(String(event2.kind)))
    }
    
    // MARK: - Builder Factory Method Tests
    
    func testReactionBuilderFactory() async throws {
        // Create reaction using factory method
        let reaction = try await NDKEventBuilder.reaction("+", to: testEvent)
            .build(signer: signer)
        
        // Verify reaction
        XCTAssertEqual(reaction.kind, EventKind.reaction)
        XCTAssertEqual(reaction.content, "+")
        XCTAssertTrue(reaction.referencedEventIds.contains(testEvent.id))
        XCTAssertTrue(reaction.referencedPubkeys.contains(testEvent.pubkey))
        XCTAssertEqual(reaction.tagValue("k"), String(testEvent.kind))
    }
    
    func testDeletionBuilderFactory() async throws {
        // Create deletion using factory method
        let deletion = try await NDKEventBuilder.deletion(event: testEvent, reason: "Test")
            .build(signer: signer)
        
        // Verify deletion
        XCTAssertEqual(deletion.kind, EventKind.deletion)
        XCTAssertEqual(deletion.content, "Test")
        XCTAssertTrue(deletion.referencedEventIds.contains(testEvent.id))
        XCTAssertEqual(deletion.tagValue("k"), String(testEvent.kind))
    }
    
    func testRepostBuilderFactory() async throws {
        // Create repost using factory method
        let repost = try await NDKEventBuilder.repost(testEvent)
            .build(signer: signer)
        
        // Verify repost
        XCTAssertEqual(repost.kind, EventKind.repost)
        XCTAssertTrue(repost.referencedEventIds.contains(testEvent.id))
        XCTAssertTrue(repost.referencedPubkeys.contains(testEvent.pubkey))
        XCTAssertEqual(repost.content, try testEvent.serialize())
    }
}