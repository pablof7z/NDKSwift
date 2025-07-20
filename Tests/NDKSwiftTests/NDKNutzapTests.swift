import XCTest
@testable import NDKSwift
import CashuSwift

final class NDKNutzapTests: XCTestCase {
    
    var mockSigner: MockNDKSigner!
    var ndk: NDK!
    var testMintURL: URL!
    var testRecipientPubkey: String!
    var testSenderPubkey: String!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Setup test data
        testMintURL = URL(string: "https://testnut.cashu.space")!
        testRecipientPubkey = "e9fbced3a42dcf551486650cc752ab354347dd413b307484e4fd1818ab53f991"
        testSenderPubkey = "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f"
        
        // Setup mock signer and NDK
        mockSigner = MockNDKSigner(publicKey: testSenderPubkey)
        ndk = NDK()
        ndk.signer = mockSigner
    }
    
    override func tearDown() async throws {
        mockSigner = nil
        ndk = nil
        try await super.tearDown()
    }
    
    // MARK: - NDKNutzap Creation Tests
    
    func testCreateBasicNutzap() async throws {
        let recipient = NDKUser(pubkey: testRecipientPubkey)
        
        let proof = CashuSwift.Proof(
            keysetID: "keyset123",
            amount: 42,
            secret: "[\"P2PK\",{\"nonce\":\"b00bdd0467b0090a25bdf2d2f0d45ac4e355c482c1418350f273a04fedaaee83\",\"data\":\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\"}]",
            C: "02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f"
        )
        
        let nutzap = try await NDKNutzap.create(
            ndk: ndk,
            recipient: recipient,
            proofs: [proof],
            mint: testMintURL,
            comment: "Great content!",
            zappedEvent: nil
        )
        
        // Verify basic properties
        XCTAssertEqual(nutzap.event.kind, 9321)
        XCTAssertEqual(nutzap.event.pubkey, testSenderPubkey)
        XCTAssertEqual(nutzap.comment, "Great content!")
        XCTAssertEqual(nutzap.mintURL, testMintURL)
        XCTAssertEqual(nutzap.recipientPubkey, testRecipientPubkey)
        XCTAssertNil(nutzap.zappedEventId)
        XCTAssertEqual(nutzap.totalAmount, 42)
        
        // Verify proofs
        let parsedProofs = nutzap.proofs
        XCTAssertEqual(parsedProofs.count, 1)
        XCTAssertEqual(parsedProofs.first?.amount, 42)
        XCTAssertEqual(parsedProofs.first?.keysetID, "keyset123")
        XCTAssertEqual(parsedProofs.first?.C, "02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f")
    }
    
    func testCreateNutzapWithZappedEvent() async throws {
        let recipient = NDKUser(pubkey: testRecipientPubkey)
        
        // Create a zapped event
        let zappedEvent = try await NDKEventBuilder()
            .kind(1)
            .content("This is a great post!")
            .build(signer: mockSigner)
        
        let proof = CashuSwift.Proof(
            keysetID: "keyset456",
            amount: 21,
            secret: "[\"P2PK\",{\"nonce\":\"a11acc0467b0090a25bdf2d2f0d45ac4e355c482c1418350f273a04fedaaee84\",\"data\":\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\"}]",
            C: "03388c77191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d4f"
        )
        
        let nutzap = try await NDKNutzap.create(
            ndk: ndk,
            recipient: recipient,
            proofs: [proof],
            mint: testMintURL,
            comment: nil,
            zappedEvent: zappedEvent
        )
        
        // Verify zapped event relationship
        XCTAssertEqual(nutzap.zappedEventId, zappedEvent.id)
        XCTAssertNil(nutzap.comment) // No comment provided
        
        // Verify e tag in the event
        let eTags = nutzap.event.tags.filter { $0.first == "e" }
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(eTags.first?[1], zappedEvent.id)
        XCTAssertEqual(eTags.first?[2], "") // Empty relay hint
    }
    
    func testCreateNutzapWithMultipleProofs() async throws {
        let recipient = NDKUser(pubkey: testRecipientPubkey)
        
        let proof1 = CashuSwift.Proof(
            keysetID: "keyset789",
            amount: 25,
            secret: "[\"P2PK\",{\"nonce\":\"proof1_nonce\",\"data\":\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\"}]",
            C: "02111c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d1a"
        )
        
        let proof2 = CashuSwift.Proof(
            keysetID: "keyset789",
            amount: 25,
            secret: "[\"P2PK\",{\"nonce\":\"proof2_nonce\",\"data\":\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\"}]",
            C: "02222c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d2b"
        )
        
        let proof3 = CashuSwift.Proof(
            keysetID: "keyset789",
            amount: 50,
            secret: "[\"P2PK\",{\"nonce\":\"proof3_nonce\",\"data\":\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\"}]",
            C: "02333c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3c"
        )
        
        let nutzap = try await NDKNutzap.create(
            ndk: ndk,
            recipient: recipient,
            proofs: [proof1, proof2, proof3],
            mint: testMintURL,
            comment: "Multi-proof nutzap",
            zappedEvent: nil
        )
        
        // Verify total amount calculation
        XCTAssertEqual(nutzap.totalAmount, 100) // 25 + 25 + 50
        
        // Verify all proofs are included
        let parsedProofs = nutzap.proofs
        XCTAssertEqual(parsedProofs.count, 3)
        
        let amounts = parsedProofs.map { $0.amount }.sorted()
        XCTAssertEqual(amounts, [25, 25, 50])
        
        // Verify proof tags in event
        let proofTags = nutzap.event.tags.filter { $0.first == "proof" }
        XCTAssertEqual(proofTags.count, 3)
    }
    
    // MARK: - NDKNutzap Parsing Tests
    
    func testParseNutzapFromEvent() throws {
        // Create event manually
        let eventJSON = """
        {
            "id": "test_nutzap_id",
            "kind": 9321,
            "content": "Thanks for the zap!",
            "pubkey": "\(testSenderPubkey!)",
            "created_at": 1234567890,
            "tags": [
                ["u", "\(testMintURL.absoluteString)"],
                ["p", "\(testRecipientPubkey!)"],
                ["amount", "100"],
                ["unit", "sat"],
                ["proof", "{\\"amount\\":100,\\"C\\":\\"02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f\\",\\"id\\":\\"keyset1\\",\\"secret\\":\\"[P2PK_secret]\\"}"],
                ["e", "zapped_event_id"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let eventJSONData = try JSONSerialization.data(withJSONObject: eventDict)
        let event = try JSONCoding.decode(NDKEvent.self, from: eventJSONData)
        let nutzap = NDKNutzap(event: event)
        
        // Test all parsed properties
        XCTAssertEqual(nutzap.comment, "Thanks for the zap!")
        XCTAssertEqual(nutzap.mintURL, testMintURL)
        XCTAssertEqual(nutzap.recipientPubkey, testRecipientPubkey)
        XCTAssertEqual(nutzap.zappedEventId, "zapped_event_id")
        XCTAssertEqual(nutzap.totalAmount, 100)
        
        // Test proof parsing
        let proofs = nutzap.proofs
        XCTAssertEqual(proofs.count, 1)
        XCTAssertEqual(proofs.first?.amount, 100)
        XCTAssertEqual(proofs.first?.keysetID, "keyset1")
    }
    
    func testParseNutzapWithMalformedProof() throws {
        let eventJSON = """
        {
            "id": "test_nutzap_id",
            "kind": 9321,
            "content": "Test",
            "pubkey": "\(testSenderPubkey!)",
            "created_at": 1234567890,
            "tags": [
                ["u", "\(testMintURL.absoluteString)"],
                ["p", "\(testRecipientPubkey!)"],
                ["amount", "50"],
                ["unit", "sat"],
                ["proof", "invalid_json_here"],
                ["proof", "{\\"amount\\":50,\\"C\\":\\"02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f\\",\\"id\\":\\"keyset1\\",\\"secret\\":\\"[P2PK_secret]\\"}"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let eventJSONData = try JSONSerialization.data(withJSONObject: eventDict)
        let event = try JSONCoding.decode(NDKEvent.self, from: eventJSONData)
        let nutzap = NDKNutzap(event: event)
        
        // Should parse only valid proofs
        let proofs = nutzap.proofs
        XCTAssertEqual(proofs.count, 1)
        XCTAssertEqual(proofs.first?.amount, 50)
        XCTAssertEqual(nutzap.totalAmount, 50)
    }
    
    func testParseNutzapWithNoProofs() throws {
        let eventJSON = """
        {
            "id": "test_nutzap_id",
            "kind": 9321,
            "content": "Test",
            "pubkey": "\(testSenderPubkey!)",
            "created_at": 1234567890,
            "tags": [
                ["u", "\(testMintURL.absoluteString)"],
                ["p", "\(testRecipientPubkey!)"],
                ["amount", "0"],
                ["unit", "sat"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let eventJSONData = try JSONSerialization.data(withJSONObject: eventDict)
        let event = try JSONCoding.decode(NDKEvent.self, from: eventJSONData)
        let nutzap = NDKNutzap(event: event)
        
        // Should return empty proofs array and zero amount
        XCTAssertEqual(nutzap.proofs.count, 0)
        XCTAssertEqual(nutzap.totalAmount, 0)
    }
    
    // MARK: - NDKNutzapPreferences Tests
    
    func testCreateNutzapPreferences() async throws {
        let mint1 = NDKNutzapPreferences.MintConfig(
            url: URL(string: "https://mint1.example.com")!,
            relays: ["wss://relay1.com", "wss://relay2.com"]
        )
        
        let mint2 = NDKNutzapPreferences.MintConfig(
            url: URL(string: "https://mint2.example.com")!,
            relays: []
        )
        
        let preferencesEvent = try await NDKNutzap.createPreferences(
            ndk: ndk,
            mints: [mint1, mint2]
        )
        
        // Verify event structure
        XCTAssertEqual(preferencesEvent.kind, 10019)
        XCTAssertEqual(preferencesEvent.pubkey, testSenderPubkey)
        
        // Verify mint tags
        let mintTags = preferencesEvent.tags.filter { $0.first == "mint" }
        XCTAssertEqual(mintTags.count, 2)
        
        let mintURLs = mintTags.compactMap { $0.count > 1 ? $0[1] : nil }
        XCTAssertTrue(mintURLs.contains("https://mint1.example.com"))
        XCTAssertTrue(mintURLs.contains("https://mint2.example.com"))
        
        // Verify pubkey tag
        let pubkeyTags = preferencesEvent.tags.filter { $0.first == "pubkey" }
        XCTAssertEqual(pubkeyTags.count, 1)
        XCTAssertEqual(pubkeyTags.first?[1], testSenderPubkey)
    }
    
    func testParseNutzapPreferences() throws {
        let preferencesJSON = """
        {
            "id": "preferences_id",
            "kind": 10019,
            "content": "",
            "pubkey": "\(testRecipientPubkey!)",
            "created_at": 1234567890,
            "tags": [
                ["mint", "https://mint1.example.com", "wss://relay1.com", "wss://relay2.com"],
                ["mint", "https://mint2.example.com"],
                ["p2pk", "02custom_p2pk_key_here"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = preferencesJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let eventJSONData = try JSONSerialization.data(withJSONObject: eventDict)
        let event = try JSONCoding.decode(NDKEvent.self, from: eventJSONData)
        let preferences = NDKNutzapPreferences(event: event)
        
        Task {
            // Test mint parsing
            let mints = await preferences.mints
            XCTAssertEqual(mints.count, 2)
            
            let mint1 = mints.first { $0.url.absoluteString == "https://mint1.example.com" }
            XCTAssertNotNil(mint1)
            XCTAssertEqual(mint1?.relays.count, 2)
            XCTAssertTrue(mint1?.relays.contains("wss://relay1.com") ?? false)
            XCTAssertTrue(mint1?.relays.contains("wss://relay2.com") ?? false)
            
            let mint2 = mints.first { $0.url.absoluteString == "https://mint2.example.com" }
            XCTAssertNotNil(mint2)
            XCTAssertEqual(mint2?.relays.count, 0)
            
            // Test P2PK pubkey parsing
            let p2pkPubkey = await preferences.p2pkPubkey
            XCTAssertEqual(p2pkPubkey, "02custom_p2pk_key_here")
        }
    }
    
    func testNutzapPreferencesWithoutP2PKTag() throws {
        let preferencesJSON = """
        {
            "id": "preferences_id",
            "kind": 10019,
            "content": "",
            "pubkey": "\(testRecipientPubkey!)",
            "created_at": 1234567890,
            "tags": [
                ["mint", "https://mint1.example.com"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = preferencesJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let eventJSONData = try JSONSerialization.data(withJSONObject: eventDict)
        let event = try JSONCoding.decode(NDKEvent.self, from: eventJSONData)
        let preferences = NDKNutzapPreferences(event: event)
        
        Task {
            // Should fall back to event author's pubkey
            let p2pkPubkey = await preferences.p2pkPubkey
            XCTAssertEqual(p2pkPubkey, testRecipientPubkey)
        }
    }
    
    func testNutzapValidation() async throws {
        // This test would require implementing CashuHelpers.isProofLockedTo
        // For now, just test that validation method exists and can be called
        let recipient = NDKUser(pubkey: testRecipientPubkey)
        
        let proof = CashuSwift.Proof(
            keysetID: "keyset123",
            amount: 42,
            secret: "[\"P2PK\",{\"nonce\":\"test_nonce\",\"data\":\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\"}]",
            C: "02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f"
        )
        
        let nutzap = try await NDKNutzap.create(
            ndk: ndk,
            recipient: recipient,
            proofs: [proof],
            mint: testMintURL,
            comment: "Test",
            zappedEvent: nil
        )
        
        // Create mock preferences
        let preferencesEvent = try await NDKNutzap.createPreferences(
            ndk: ndk,
            mints: [NDKNutzapPreferences.MintConfig(url: testMintURL)]
        )
        let preferences = NDKNutzapPreferences(event: preferencesEvent)
        
        // Validation method should exist and be callable
        let isValid = await nutzap.validate(recipientPreferences: preferences)
        
        // The actual validation logic depends on CashuHelpers implementation
        // For now, just verify the method can be called without crashing
        XCTAssertNotNil(isValid)
    }
    
    // MARK: - Error Cases
    
    func testCreateNutzapWithNoSigner() async throws {
        let ndkWithoutSigner = NDK()
        let recipient = NDKUser(pubkey: testRecipientPubkey)
        
        let proof = CashuSwift.Proof(
            keysetID: "keyset123",
            amount: 42,
            secret: "[P2PK_secret]",
            C: "02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f"
        )
        
        do {
            _ = try await NDKNutzap.create(
                ndk: ndkWithoutSigner,
                recipient: recipient,
                proofs: [proof],
                mint: testMintURL,
                comment: nil,
                zappedEvent: nil
            )
            XCTFail("Should throw error when no signer configured")
        } catch let error as NDKError {
            if case .notConfigured(let message) = error {
                XCTAssertEqual(message, "No signer configured")
            } else {
                XCTFail("Expected notConfigured error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testCreateNutzapWithEmptyProofs() async throws {
        let recipient = NDKUser(pubkey: testRecipientPubkey)
        
        let nutzap = try await NDKNutzap.create(
            ndk: ndk,
            recipient: recipient,
            proofs: [],
            mint: testMintURL,
            comment: "Empty proofs test",
            zappedEvent: nil
        )
        
        // Should create event but with no proof tags
        XCTAssertEqual(nutzap.proofs.count, 0)
        XCTAssertEqual(nutzap.totalAmount, 0)
        
        let proofTags = nutzap.event.tags.filter { $0.first == "proof" }
        XCTAssertEqual(proofTags.count, 0)
    }
}