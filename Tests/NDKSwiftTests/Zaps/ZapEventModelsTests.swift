import XCTest
@testable import NDKSwift

final class ZapEventModelsTests: XCTestCase {
    
    // MARK: - NDKZapRequest Tests
    
    func testCreateZapRequest() async throws {
        let ndk = NDK()
        let signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        
        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            recipient: recipient,
            amountMillisats: 1000000, // 1000 sats
            comment: "Great post!",
            relays: ["wss://relay1.com", "wss://relay2.com"]
        )
        
        // Verify event properties
        XCTAssertEqual(await zapRequest.event.kind, EventKind.zapRequest)
        XCTAssertEqual(await zapRequest.event.content, "Great post!")
        
        // Verify required tags
        XCTAssertEqual(await zapRequest.recipientPubkey, recipient.pubkey)
        XCTAssertEqual(await zapRequest.amountMillisats, 1000000)
        XCTAssertEqual(await zapRequest.amountSats, 1000)
        XCTAssertEqual(await zapRequest.relays, ["wss://relay1.com", "wss://relay2.com"])
        XCTAssertEqual(await zapRequest.comment, "Great post!")
    }
    
    func testCreateZapRequestForEvent() async throws {
        let ndk = NDK()
        let signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        let event = NDKEvent(
            pubkey: recipient.pubkey,
            createdAt: 0,
            kind: EventKind.textNote,
            content: "Hello"
        )
        event.id = "event-id-123"
        
        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            recipient: recipient,
            amountMillisats: 500000,
            comment: nil,
            relays: ["wss://relay.com"],
            zappedEvent: event
        )
        
        XCTAssertEqual(await zapRequest.zappedEventId, "event-id-123")
        XCTAssertNil(await zapRequest.comment)
    }
    
    func testZapRequestEncoding() async throws {
        let ndk = NDK()
        let signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let recipient = NDKUser(pubkey: "test", ndk: ndk)
        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            recipient: recipient,
            amountMillisats: 1000,
            comment: "Test",
            relays: ["wss://relay.com"]
        )
        
        let encoded = try zapRequest.encodeForCallback()
        XCTAssertFalse(encoded.isEmpty)
        
        // Should be valid JSON
        let data = Data(encoded.utf8)
        let decoded = try JSONDecoder().decode(NDKEvent.self, from: data)
        XCTAssertEqual(await decoded.kind, EventKind.zapRequest)
    }
    
    // MARK: - NDKZapReceipt Tests
    
    func testZapReceiptParsing() async throws {
        let receipt = NDKEvent(
            pubkey: "lnurl-provider",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.zapReceipt,
            content: ""
        )
        
        receipt.addTag(["p", "recipient-pubkey"])
        receipt.addTag(["P", "sender-pubkey"]) // Optional sender
        receipt.addTag(["bolt11", "lnbc1000n1..."]) 
        receipt.addTag(["preimage", "test-preimage"])
        receipt.addTag(["e", "zapped-event-id"])
        
        let zapReceipt = NDKZapReceipt(event: receipt)
        
        XCTAssertEqual(await zapReceipt.recipientPubkey, "recipient-pubkey")
        XCTAssertEqual(await zapReceipt.senderPubkey, "sender-pubkey")
        XCTAssertEqual(await zapReceipt.bolt11, "lnbc1000n1...")
        XCTAssertEqual(await zapReceipt.preimage, "test-preimage")
        XCTAssertEqual(await zapReceipt.zappedEventId, "zapped-event-id")
    }
    
    func testZapReceiptValidation() async throws {
        let receipt = NDKEvent(
            pubkey: "lnurl-provider",
            createdAt: 0,
            kind: EventKind.zapReceipt,
            content: ""
        )
        
        receipt.addTag(["p", "recipient"])
        receipt.addTag(["bolt11", "lnbc1000n1..."])
        receipt.addTag(["description", "{}"])
        
        let zapReceipt = NDKZapReceipt(event: receipt)
        
        // Should validate with correct provider pubkey
        let isValid = await zapReceipt.validate(lnurlProviderPubkey: "lnurl-provider")
        XCTAssertTrue(isValid)
        
        // Should fail with wrong provider pubkey
        let isInvalid = await zapReceipt.validate(lnurlProviderPubkey: "wrong-provider")
        XCTAssertFalse(isInvalid)
    }
    
    func testBolt11AmountParsing() async throws {
        // Test various bolt11 formats
        let testCases: [(bolt11: String, expectedMillisats: Int64?)] = [
            ("lnbc1000n1...", 1000000), // 1000 sats in nanosats
            ("lnbc100u1...", 100000), // 100 sats in microsats
            ("lnbc10m1...", 10), // 10 millisats
            ("lnbc1500p1...", 1500000000000), // 1500 sats in picosats
            ("lnbc11...", 1100000000000), // 1 BTC
            ("invalid", nil)
        ]
        
        for (bolt11, expected) in testCases {
            let receipt = NDKEvent(
                pubkey: "provider",
                createdAt: 0,
                kind: EventKind.zapReceipt,
                content: ""
            )
            receipt.addTag(["bolt11", bolt11])
            
            let zapReceipt = NDKZapReceipt(event: receipt)
            let amount = await zapReceipt.amountMillisats
            
            XCTAssertEqual(amount, expected, "Failed for bolt11: \(bolt11)")
        }
    }
    
    // MARK: - NDKNutzap Tests
    
    func testCreateNutzap() async throws {
        let ndk = NDK()
        let signer = NDKPrivateKeySigner.generate()
        
        let proofs = [
            CashuProof(amount: 512, id: "id1", secret: "secret1", C: "C1"),
            CashuProof(amount: 256, id: "id2", secret: "secret2", C: "C2"),
            CashuProof(amount: 128, id: "id3", secret: "secret3", C: "C3"),
            CashuProof(amount: 64, id: "id4", secret: "secret4", C: "C4"),
            CashuProof(amount: 32, id: "id5", secret: "secret5", C: "C5"),
            CashuProof(amount: 8, id: "id6", secret: "secret6", C: "C6")
        ]
        
        let nutzap = try await NDKNutzap.create(
            ndk: ndk,
            signer: signer,
            proofs: proofs,
            mint: "https://mint.example.com",
            unit: "sat",
            recipient: "recipient-pubkey",
            comment: "Nutzap!",
            zappedEvent: nil
        )
        
        // Verify basic properties
        XCTAssertEqual(await nutzap.event.kind, EventKind.nutzap)
        XCTAssertEqual(await nutzap.event.content, "Nutzap!")
        
        // Verify amount calculation
        XCTAssertEqual(await nutzap.totalAmount, 1000)
        
        // Verify tags
        XCTAssertEqual(await nutzap.recipientPubkey, "recipient-pubkey")
        XCTAssertEqual(await nutzap.mint, "https://mint.example.com")
        XCTAssertEqual(await nutzap.unit, "sat")
        XCTAssertEqual(await nutzap.comment, "Nutzap!")
        
        // Verify proofs
        let parsedProofs = await nutzap.proofs
        XCTAssertEqual(parsedProofs.count, 6)
        XCTAssertEqual(parsedProofs.first?.amount, 512)
    }
    
    func testNutzapForEvent() async throws {
        let ndk = NDK()
        let signer = NDKPrivateKeySigner.generate()
        
        let event = NDKEvent(
            pubkey: "author",
            createdAt: 0,
            kind: EventKind.textNote,
            content: "Test"
        )
        event.id = "event-456"
        
        let proofs = [CashuProof(amount: 1000, id: "id", secret: "secret", C: "C")]
        
        let nutzap = try await NDKNutzap.create(
            ndk: ndk,
            signer: signer,
            proofs: proofs,
            mint: "https://mint.com",
            unit: "sat",
            recipient: "author",
            comment: nil,
            zappedEvent: event
        )
        
        XCTAssertEqual(await nutzap.zappedEventId, "event-456")
        XCTAssertNil(await nutzap.comment)
    }
    
    // MARK: - NDKNutzapPreferences Tests
    
    func testNutzapPreferencesParsing() async throws {
        let prefsEvent = NDKEvent(
            pubkey: "user-pubkey",
            createdAt: 0,
            kind: EventKind.nutzapPreferences,
            content: ""
        )
        
        prefsEvent.addTag(["mint", "https://mint1.com", "sat", "usd"])
        prefsEvent.addTag(["mint", "https://mint2.com", "btc"])
        prefsEvent.addTag(["relay", "wss://relay1.com"])
        prefsEvent.addTag(["relay", "wss://relay2.com"])
        prefsEvent.addTag(["p2pk", "custom-pubkey"])
        
        let prefs = NDKNutzapPreferences(event: prefsEvent)
        
        // Verify mints
        let mints = await prefs.mints
        XCTAssertEqual(mints.count, 2)
        XCTAssertEqual(mints[0].url, "https://mint1.com")
        XCTAssertEqual(mints[0].units, ["sat", "usd"])
        XCTAssertEqual(mints[1].url, "https://mint2.com")
        XCTAssertEqual(mints[1].units, ["btc"])
        
        // Verify relays
        let relays = await prefs.relays
        XCTAssertEqual(relays, ["wss://relay1.com", "wss://relay2.com"])
        
        // Verify P2PK pubkey
        let p2pkPubkey = await prefs.p2pkPubkey
        XCTAssertEqual(p2pkPubkey, "custom-pubkey")
    }
    
    func testNutzapPreferencesWithDefaultP2PK() async throws {
        let prefsEvent = NDKEvent(
            pubkey: "user-pubkey",
            createdAt: 0,
            kind: EventKind.nutzapPreferences,
            content: ""
        )
        
        prefsEvent.addTag(["mint", "https://mint.com"])
        // No p2pk tag specified
        
        let prefs = NDKNutzapPreferences(event: prefsEvent)
        
        // Should default to event pubkey
        let p2pkPubkey = await prefs.p2pkPubkey
        XCTAssertEqual(p2pkPubkey, "user-pubkey")
    }
    
    func testCreateNutzapPreferences() async throws {
        let ndk = NDK()
        let signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let mints = [
            NDKNutzapPreferences.Mint(url: "https://mint1.com", units: ["sat"]),
            NDKNutzapPreferences.Mint(url: "https://mint2.com", units: ["sat", "usd"])
        ]
        
        let prefs = try await NDKNutzapPreferences.create(
            ndk: ndk,
            mints: mints,
            relays: ["wss://relay1.com"],
            p2pkPubkey: nil // Use default
        )
        
        // Verify creation
        XCTAssertEqual(await prefs.event.kind, EventKind.nutzapPreferences)
        XCTAssertEqual(await prefs.mints.count, 2)
        XCTAssertEqual(await prefs.relays.count, 1)
        XCTAssertEqual(await prefs.p2pkPubkey, signer.pubkey)
    }
}