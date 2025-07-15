import XCTest
import CashuSwift
@testable import NDKSwift

/// Tests specifically for del tag creation in WalletEventManager
final class WalletEventManagerDelTagTests: XCTestCase {
    var ndk: NDK!
    var cache: MockCache!
    var signer: NDKPrivateKeySigner!
    var eventManager: WalletEventManager!
    var proofStateManager: ProofStateManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        cache = MockCache()
        signer = try NDKPrivateKeySigner.generate()
        ndk = NDK(signer: signer, cache: cache)
        eventManager = WalletEventManager(ndk: ndk)
        proofStateManager = ProofStateManager()
    }
    
    override func tearDown() async throws {
        eventManager = nil
        proofStateManager = nil
        ndk = nil
        cache = nil
        signer = nil
        try await super.tearDown()
    }
    
    func testUpdateTokenEventsCreatesDelTags() async throws {
        // Setup initial state
        let mint = "https://mint.example.com"
        let proof1 = CashuSwift.Proof(
            keysetID: "keyset1",
            amount: 10,
            secret: "secret1",
            C: "C1"
        )
        let proof2 = CashuSwift.Proof(
            keysetID: "keyset1",
            amount: 20,
            secret: "secret2",
            C: "C2"
        )
        
        // Simulate initial token event with both proofs
        let initialEventId = "initial-token-event"
        await proofStateManager.addProof(proof1, mint: mint, eventId: initialEventId, timestamp: 1000)
        await proofStateManager.addProof(proof2, mint: mint, eventId: initialEventId, timestamp: 1000)
        await eventManager.setCurrentTokenEventIds([initialEventId])
        
        // Mark proof1 as spent (deleted)
        await proofStateManager.markProofsAsDeleted([proof1])
        
        // Update token events - should create new event with only proof2
        // and include del tag for the initial event
        let availableByMint = await proofStateManager.getAvailableProofsByMint()
        let newEventIds = try await eventManager.updateTokenEvents(
            availableProofsByMint: availableByMint,
            proofStateManager: proofStateManager,
            signer: signer
        )
        
        // Verify new event was created
        XCTAssertEqual(newEventIds.count, 1)
        
        // Get the saved events from cache
        let filter = NDKFilter(kinds: [EventKind.cashuToken])
        let savedEvents = try await cache.queryEvents(filter)
        
        // Find the new token event
        let newTokenEvent = savedEvents.first { newEventIds.contains($0.id) }
        XCTAssertNotNil(newTokenEvent)
        
        // Decrypt and verify the content
        if let event = newTokenEvent {
            let decryptedContent = try await signer.decrypt(
                sender: NDKUser(pubkey: event.pubkey),
                value: event.content,
                scheme: .nip44
            )
            
            let tokenData = decryptedContent.data(using: .utf8)!
            let nip60Token = try JSONDecoder().decode(NIP60TokenEvent.self, from: tokenData)
            
            // Verify the new token has only proof2
            XCTAssertEqual(nip60Token.proofs.count, 1)
            XCTAssertEqual(nip60Token.proofs[0].C, "C2")
            
            // VERIFY DEL TAG IS PRESENT
            XCTAssertNotNil(nip60Token.del, "del tag should be present")
            XCTAssertEqual(nip60Token.del?.count, 1, "should have one del tag")
            XCTAssertEqual(nip60Token.del?[0], initialEventId, "del tag should reference initial event")
        }
    }
    
    func testNoDelTagWhenNoSupersededEvents() async throws {
        // Setup: Create new proofs without any previous owner
        let mint = "https://mint.example.com"
        let proof1 = CashuSwift.Proof(
            keysetID: "keyset1",
            amount: 10,
            secret: "secret1",
            C: "C1"
        )
        
        // Add proof without eventId (no previous owner)
        await proofStateManager.addProof(proof1, mint: mint)
        
        // Update token events
        let availableByMint = await proofStateManager.getAvailableProofsByMint()
        let newEventIds = try await eventManager.updateTokenEvents(
            availableProofsByMint: availableByMint,
            proofStateManager: proofStateManager,
            signer: signer
        )
        
        // Get the created event
        let filter = NDKFilter(kinds: [EventKind.cashuToken])
        let savedEvents = try await cache.queryEvents(filter)
        let newTokenEvent = savedEvents.first { newEventIds.contains($0.id) }
        
        XCTAssertNotNil(newTokenEvent)
        
        // Decrypt and verify NO del tag
        if let event = newTokenEvent {
            let decryptedContent = try await signer.decrypt(
                sender: NDKUser(pubkey: event.pubkey),
                value: event.content,
                scheme: .nip44
            )
            
            let tokenData = decryptedContent.data(using: .utf8)!
            let nip60Token = try JSONDecoder().decode(NIP60TokenEvent.self, from: tokenData)
            
            // Should have NO del tag
            XCTAssertNil(nip60Token.del, "del tag should not be present for new proofs")
        }
    }
    
    func testMultipleMintsDifferentDelTags() async throws {
        // Setup two mints with different proofs
        let mint1 = "https://mint1.example.com"
        let mint2 = "https://mint2.example.com"
        
        let mint1Proof1 = CashuSwift.Proof(keysetID: "ks1", amount: 10, secret: "s1", C: "M1P1")
        let mint1Proof2 = CashuSwift.Proof(keysetID: "ks1", amount: 20, secret: "s2", C: "M1P2")
        let mint2Proof1 = CashuSwift.Proof(keysetID: "ks2", amount: 30, secret: "s3", C: "M2P1")
        
        // Set up initial token events
        await proofStateManager.addProof(mint1Proof1, mint: mint1, eventId: "mint1-token", timestamp: 1000)
        await proofStateManager.addProof(mint1Proof2, mint: mint1, eventId: "mint1-token", timestamp: 1000)
        await proofStateManager.addProof(mint2Proof1, mint: mint2, eventId: "mint2-token", timestamp: 1000)
        
        await eventManager.setCurrentTokenEventIds(["mint1-token", "mint2-token"])
        
        // Spend one proof from mint1
        await proofStateManager.markProofsAsDeleted([mint1Proof1])
        
        // Update token events
        let availableByMint = await proofStateManager.getAvailableProofsByMint()
        let newEventIds = try await eventManager.updateTokenEvents(
            availableProofsByMint: availableByMint,
            proofStateManager: proofStateManager,
            signer: signer
        )
        
        // Should create 2 events (one new for mint1, same for mint2)
        XCTAssertEqual(newEventIds.count, 2)
        
        // Check the events
        let filter = NDKFilter(kinds: [EventKind.cashuToken])
        let savedEvents = try await cache.queryEvents(filter)
        
        for eventId in newEventIds {
            if let event = savedEvents.first(where: { $0.id == eventId }) {
                let decryptedContent = try await signer.decrypt(
                    sender: NDKUser(pubkey: event.pubkey),
                    value: event.content,
                    scheme: .nip44
                )
                
                let tokenData = decryptedContent.data(using: .utf8)!
                let nip60Token = try JSONDecoder().decode(NIP60TokenEvent.self, from: tokenData)
                
                if nip60Token.mint == mint1 {
                    // This should be the new mint1 token with del tag
                    XCTAssertEqual(nip60Token.proofs.count, 1)
                    XCTAssertEqual(nip60Token.proofs[0].C, "M1P2")
                    XCTAssertNotNil(nip60Token.del)
                    XCTAssertEqual(nip60Token.del?[0], "mint1-token")
                } else if nip60Token.mint == mint2 {
                    // This should be mint2 token without changes
                    XCTAssertEqual(nip60Token.proofs.count, 1)
                    XCTAssertEqual(nip60Token.proofs[0].C, "M2P1")
                    // Mint2 token might or might not have del tag depending on if it's the same event
                }
            }
        }
    }
}