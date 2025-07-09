import XCTest
@testable import NDKSwift

final class NDKNutzapProtocolTests: XCTestCase {
    var ndk: NDK!
    var zapProtocol: NDKNutzapProtocol!
    var mockRelay: MockRelay!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockRelay = MockRelay(url: "wss://test.relay")
        ndk = NDK()
        ndk.relayPool = NDKRelayPool(ndk: ndk)
        ndk.relayPool.addRelay(mockRelay)
        
        zapProtocol = NDKNutzapProtocol(ndk: ndk)
    }
    
    override func tearDown() async throws {
        await mockRelay.disconnect()
        try await super.tearDown()
    }
    
    // MARK: - Can Zap Tests
    
    func testCanZapUserWithNutzapPreferences() async throws {
        let user = NDKUser(pubkey: "test-user", ndk: ndk)
        
        // Mock nutzap preferences
        let prefsEvent = NDKEvent(
            pubkey: user.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.nutzapPreferences,
            content: ""
        )
        prefsEvent.addTag(["mint", "https://mint.example.com", "sat", "usd"])
        prefsEvent.addTag(["relay", "wss://relay1.com"])
        prefsEvent.addTag(["relay", "wss://relay2.com"])
        prefsEvent.addTag(["p2pk", user.pubkey])
        
        mockRelay.mockEvents = [prefsEvent]
        
        let canZap = try await zapProtocol.canZap(user: user)
        XCTAssertTrue(canZap)
    }
    
    func testCannotZapUserWithoutNutzapPreferences() async throws {
        let user = NDKUser(pubkey: "test-user", ndk: ndk)
        
        // No nutzap preferences event
        mockRelay.mockEvents = []
        
        let canZap = try await zapProtocol.canZap(user: user)
        XCTAssertFalse(canZap)
    }
    
    func testCannotZapUserWithEmptyMints() async throws {
        let user = NDKUser(pubkey: "test-user", ndk: ndk)
        
        // Nutzap preferences without mints
        let prefsEvent = NDKEvent(
            pubkey: user.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.nutzapPreferences,
            content: ""
        )
        prefsEvent.addTag(["relay", "wss://relay1.com"])
        
        mockRelay.mockEvents = [prefsEvent]
        
        let canZap = try await zapProtocol.canZap(user: user)
        XCTAssertFalse(canZap)
    }
    
    // MARK: - Prepare Zap Tests
    
    func testPrepareNutzap() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        setupMockNutzapPreferences(for: recipient)
        
        let prepared = try await zapProtocol.prepareZap(
            to: recipient,
            amountSats: 1000,
            comment: "Nice work!"
        )
        
        XCTAssertEqual(prepared.type, .nutzap)
        XCTAssertEqual(prepared.amountSats, 1000)
        
        // Verify payment request
        guard let proofRequest = prepared.paymentRequest as? CashuProofRequest else {
            XCTFail("Expected CashuProofRequest")
            return
        }
        
        XCTAssertEqual(proofRequest.amount, 1000)
        XCTAssertEqual(proofRequest.mint, "https://mint.example.com")
        XCTAssertEqual(proofRequest.unit, "sat")
        XCTAssertEqual(proofRequest.p2pkPubkey, recipient.pubkey)
    }
    
    func testPrepareNutzapForEvent() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        setupMockNutzapPreferences(for: recipient)
        
        let event = NDKEvent(
            pubkey: recipient.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Hello Nostr!"
        )
        event.id = "event-id"
        
        let prepared = try await zapProtocol.prepareZap(
            event: event,
            to: recipient,
            amountSats: 500,
            comment: "Great post"
        )
        
        // Verify context contains event info
        XCTAssertEqual(prepared.context["eventId"] as? String, "event-id")
        XCTAssertEqual(prepared.context["comment"] as? String, "Great post")
    }
    
    // MARK: - Complete Zap Tests
    
    func testCompleteNutzap() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        let signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        setupMockNutzapPreferences(for: recipient)
        
        // Prepare nutzap
        let prepared = try await zapProtocol.prepareZap(
            to: recipient,
            amountSats: 1000,
            comment: "Test nutzap"
        )
        
        // Mock Cashu payment confirmation
        let proofs = [
            CashuProof(amount: 500, id: "id1", secret: "secret1", C: "C1"),
            CashuProof(amount: 500, id: "id2", secret: "secret2", C: "C2")
        ]
        let confirmation = CashuPaymentConfirmation(proofs: proofs)
        
        // Complete nutzap
        let result = try await zapProtocol.completeZap(
            prepared: prepared,
            confirmation: confirmation
        )
        
        XCTAssertEqual(result.type, .nutzap)
        XCTAssertEqual(result.amountSats, 1000)
        XCTAssertNotNil(result.nutzapEvent)
        
        // Verify nutzap event was published
        let publishedEvents = await mockRelay.publishedEvents
        XCTAssertEqual(publishedEvents.count, 1)
        
        let nutzapEvent = publishedEvents.first
        XCTAssertEqual(await nutzapEvent?.kind, EventKind.nutzap)
        
        // Verify event tags
        let tags = await nutzapEvent?.tags ?? []
        XCTAssertTrue(tags.contains { $0.first == "p" && $0[safe: 1] == recipient.pubkey })
        XCTAssertTrue(tags.contains { $0.first == "amount" && $0[safe: 1] == "1000" })
        XCTAssertTrue(tags.contains { $0.first == "u" && $0[safe: 1] == "sat" })
        XCTAssertTrue(tags.contains { $0.first == "proof" })
    }
    
    func testCompleteNutzapWithInvalidConfirmation() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        setupMockNutzapPreferences(for: recipient)
        
        let prepared = try await zapProtocol.prepareZap(
            to: recipient,
            amountSats: 1000,
            comment: "Test"
        )
        
        // Wrong type of confirmation
        let confirmation = LightningPaymentConfirmation(
            preimage: "wrong-type",
            paidAt: Date()
        )
        
        do {
            _ = try await zapProtocol.completeZap(
                prepared: prepared,
                confirmation: confirmation
            )
            XCTFail("Expected error")
        } catch {
            guard case ZapError.invalidPaymentConfirmation = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupMockNutzapPreferences(for user: NDKUser) {
        let prefsEvent = NDKEvent(
            pubkey: user.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.nutzapPreferences,
            content: ""
        )
        prefsEvent.addTag(["mint", "https://mint.example.com", "sat", "usd"])
        prefsEvent.addTag(["relay", "wss://relay1.com"])
        prefsEvent.addTag(["relay", "wss://relay2.com"])
        prefsEvent.addTag(["p2pk", user.pubkey])
        
        mockRelay.mockEvents = [prefsEvent]
    }
}