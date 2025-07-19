import XCTest
@testable import NDKSwift
import CashuSwift

final class NDKNutzapEventTests: XCTestCase {
    
    var mockSigner: MockNDKSigner!
    var ndk: NDK!
    var testMintURL: String!
    var testRecipientPubkey: String!
    var testSenderPubkey: String!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Setup test data
        testMintURL = "https://testnut.cashu.space"
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
    
    // MARK: - Creation Tests
    
    func testCreateBasicNutzapEvent() async throws {
        // Create sample proofs
        let proof1 = CashuSwift.Proof(
            amount: 50,
            id: "keyset1",
            secret: "[\"P2PK\",{\"nonce\":\"b00bdd0467b0090a25bdf2d2f0d45ac4e355c482c1418350f273a04fedaaee83\",\"data\":\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\"}]",
            C: "02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f"
        )
        
        let proof2 = CashuSwift.Proof(
            amount: 10,
            id: "keyset1", 
            secret: "[\"P2PK\",{\"nonce\":\"a11acc0467b0090a25bdf2d2f0d45ac4e355c482c1418350f273a04fedaaee84\",\"data\":\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\"}]",
            C: "03388c77191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d4f"
        )
        
        let proofs = [proof1, proof2]
        let token = CashuSwift.Token(proofs: [testMintURL: proofs], unit: "sat")
        
        // Create nutzap event
        let nutzapEvent = try await NDKNutzapEvent.create(
            ndk: ndk,
            token: token,
            mintURL: testMintURL,
            recipient: testRecipientPubkey,
            comment: "Thanks for this great idea.",
            eventId: nil,
            signer: mockSigner
        )
        
        // Verify event structure
        XCTAssertEqual(nutzapEvent.event.kind, EventKind.nutzap)
        XCTAssertEqual(nutzapEvent.event.pubkey, testSenderPubkey)
        XCTAssertEqual(nutzapEvent.event.content, "Thanks for this great idea.")
        
        // Verify tags
        let tags = nutzapEvent.event.tags
        
        // Check p tag (recipient)
        let pTags = tags.filter { $0.first == "p" }
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(pTags.first?[1], testRecipientPubkey)
        
        // Check proof tags
        let proofTags = tags.filter { $0.first == "proof" }
        XCTAssertEqual(proofTags.count, 2)
        
        // Verify proof content
        for (index, proofTag) in proofTags.enumerated() {
            XCTAssertEqual(proofTag.count, 2)
            
            guard let proofData = proofTag[1].data(using: .utf8),
                  let decodedProof = try? JSONDecoder().decode(CashuSwift.Proof.self, from: proofData) else {
                XCTFail("Failed to decode proof at index \(index)")
                continue
            }
            
            let originalProof = proofs[index]
            XCTAssertEqual(decodedProof.amount, originalProof.amount)
            XCTAssertEqual(decodedProof.id, originalProof.id)
            XCTAssertEqual(decodedProof.secret, originalProof.secret)
            XCTAssertEqual(decodedProof.C, originalProof.C)
        }
        
        // Check mint tag  
        let mintTags = tags.filter { $0.first == "mint" }
        XCTAssertEqual(mintTags.count, 1)
        XCTAssertEqual(mintTags.first?[1], testMintURL)
        
        // Check unit tag
        let unitTags = tags.filter { $0.first == "u" }
        XCTAssertEqual(unitTags.count, 1)
        XCTAssertEqual(unitTags.first?[1], "sat")
        
        // Should not have e tag since no eventId provided
        let eTags = tags.filter { $0.first == "e" }
        XCTAssertEqual(eTags.count, 0)
    }
    
    func testCreateNutzapEventWithZappedEvent() async throws {
        let proof = CashuSwift.Proof(
            amount: 100,
            id: "keyset1",
            secret: "[\"P2PK\",{\"nonce\":\"b00bdd0467b0090a25bdf2d2f0d45ac4e355c482c1418350f273a04fedaaee83\",\"data\":\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\"}]",
            C: "02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f"
        )
        
        let token = CashuSwift.Token(proofs: [testMintURL: [proof]], unit: "sat")
        let zappedEventId = "abc123def456"
        
        let nutzapEvent = try await NDKNutzapEvent.create(
            ndk: ndk,
            token: token,
            mintURL: testMintURL,
            recipient: testRecipientPubkey,
            comment: nil,
            eventId: zappedEventId,
            signer: mockSigner
        )
        
        // Check e tag for zapped event
        let eTags = nutzapEvent.event.tags.filter { $0.first == "e" }
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(eTags.first?[1], zappedEventId)
        
        // Content should be empty when no comment
        XCTAssertEqual(nutzapEvent.event.content, "")
    }
    
    func testCreateNutzapEventWithNoProofs() async throws {
        let token = CashuSwift.Token(proofs: [:], unit: "sat")
        
        do {
            _ = try await NDKNutzapEvent.create(
                ndk: ndk,
                token: token,
                mintURL: testMintURL,
                recipient: testRecipientPubkey,
                comment: nil,
                eventId: nil,
                signer: mockSigner
            )
            XCTFail("Should throw error for empty proofs")
        } catch {
            XCTAssertTrue(error is NDKError)
        }
    }
    
    // MARK: - Parsing Tests
    
    func testParseValidNutzapEvent() throws {
        // Create a properly formatted nutzap event
        let eventJSON = """
        {
            "id": "000a93d6f8a1d2c4",
            "kind": 9321,
            "content": "Thanks for this great idea.",
            "pubkey": "\(testSenderPubkey)",
            "created_at": 1234567890,
            "tags": [
                ["proof", "{\\"amount\\":1,\\"C\\":\\"02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f\\",\\"id\\":\\"000a93d6f8a1d2c4\\",\\"secret\\":\\"[\\\\\\"P2PK\\\\\\",{\\\\\\"nonce\\\\\\":\\\\\\"b00bdd0467b0090a25bdf2d2f0d45ac4e355c482c1418350f273a04fedaaee83\\\\\\",\\\\\\"data\\\\\\":\\\\\\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\\\\\\"}]\\"}"],
                ["mint", "\(testMintURL!)"],
                ["u", "sat"],
                ["e", "abc123def456"],
                ["p", "\(testRecipientPubkey!)"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let event = try NDKEvent(from: eventDict)
        let nutzapEvent = NDKNutzapEvent(event: event)
        
        // Test parsing properties
        XCTAssertEqual(nutzapEvent.comment, "Thanks for this great idea.")
        XCTAssertEqual(nutzapEvent.mintURL, testMintURL)
        XCTAssertEqual(nutzapEvent.unit, "sat")
        XCTAssertEqual(nutzapEvent.recipient, testRecipientPubkey)
        XCTAssertEqual(nutzapEvent.nutzappedEventId, "abc123def456")
        
        // Test token extraction
        XCTAssertNotNil(nutzapEvent.token)
        let token = nutzapEvent.token!
        XCTAssertEqual(token.unit, "sat")
        XCTAssertEqual(token.proofsByMint.count, 1)
        XCTAssertTrue(token.proofsByMint.keys.contains(testMintURL))
        
        let proofs = token.proofsByMint[testMintURL]!
        XCTAssertEqual(proofs.count, 1)
        XCTAssertEqual(proofs.first?.amount, 1)
    }
    
    func testParseNutzapEventWithMultipleProofs() throws {
        let eventJSON = """
        {
            "id": "000a93d6f8a1d2c4",
            "kind": 9321,
            "content": "",
            "pubkey": "\(testSenderPubkey)",
            "created_at": 1234567890,
            "tags": [
                ["proof", "{\\"amount\\":50,\\"C\\":\\"02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f\\",\\"id\\":\\"keyset1\\",\\"secret\\":\\"[P2PK_secret_1]\\"}"],
                ["proof", "{\\"amount\\":25,\\"C\\":\\"03388c77191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d4f\\",\\"id\\":\\"keyset1\\",\\"secret\\":\\"[P2PK_secret_2]\\"}"],
                ["proof", "{\\"amount\\":25,\\"C\\":\\"04499d88201846fc72fce9d975d08e3191f8f96afb73ab1eec37e4465683066e5f\\",\\"id\\":\\"keyset1\\",\\"secret\\":\\"[P2PK_secret_3]\\"}"],
                ["mint", "\(testMintURL!)"],
                ["u", "sat"],
                ["p", "\(testRecipientPubkey!)"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let event = try NDKEvent(from: eventDict)
        let nutzapEvent = NDKNutzapEvent(event: event)
        
        // Test token with multiple proofs
        XCTAssertNotNil(nutzapEvent.token)
        let token = nutzapEvent.token!
        
        let proofs = token.proofsByMint[testMintURL]!
        XCTAssertEqual(proofs.count, 3)
        
        let totalAmount = proofs.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(totalAmount, 100) // 50 + 25 + 25
        
        // Verify individual proof amounts
        let amounts = proofs.map { $0.amount }.sorted()
        XCTAssertEqual(amounts, [25, 25, 50])
    }
    
    func testParseNutzapEventWithEmptyComment() throws {
        let eventJSON = """
        {
            "id": "000a93d6f8a1d2c4", 
            "kind": 9321,
            "content": "",
            "pubkey": "\(testSenderPubkey)",
            "created_at": 1234567890,
            "tags": [
                ["proof", "{\\"amount\\":1,\\"C\\":\\"02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f\\",\\"id\\":\\"000a93d6f8a1d2c4\\",\\"secret\\":\\"[P2PK_secret]\\"}"],
                ["mint", "\(testMintURL!)"],
                ["u", "sat"],
                ["p", "\(testRecipientPubkey!)"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let event = try NDKEvent(from: eventDict)
        let nutzapEvent = NDKNutzapEvent(event: event)
        
        // Empty content should return nil comment
        XCTAssertNil(nutzapEvent.comment)
    }
    
    func testParseNutzapEventMissingRequiredTags() throws {
        // Test event without proof tags
        let eventWithoutProofs = """
        {
            "id": "000a93d6f8a1d2c4",
            "kind": 9321,
            "content": "Test",
            "pubkey": "\(testSenderPubkey)",
            "created_at": 1234567890,
            "tags": [
                ["mint", "\(testMintURL!)"],
                ["u", "sat"],
                ["p", "\(testRecipientPubkey!)"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventWithoutProofs.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let event = try NDKEvent(from: eventDict)
        let nutzapEvent = NDKNutzapEvent(event: event)
        
        // Should return nil token when no valid proofs
        XCTAssertNil(nutzapEvent.token)
    }
    
    func testParseNutzapEventMissingMintTag() throws {
        let eventJSON = """
        {
            "id": "000a93d6f8a1d2c4",
            "kind": 9321,
            "content": "Test",
            "pubkey": "\(testSenderPubkey)",
            "created_at": 1234567890,
            "tags": [
                ["proof", "{\\"amount\\":1,\\"C\\":\\"02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f\\",\\"id\\":\\"000a93d6f8a1d2c4\\",\\"secret\\":\\"[P2PK_secret]\\"}"],
                ["u", "sat"],
                ["p", "\(testRecipientPubkey!)"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let event = try NDKEvent(from: eventDict)
        let nutzapEvent = NDKNutzapEvent(event: event)
        
        XCTAssertNil(nutzapEvent.mintURL)
        XCTAssertNil(nutzapEvent.token) // Should be nil when no mint URL
    }
    
    func testParseInvalidProofJSON() throws {
        let eventJSON = """
        {
            "id": "000a93d6f8a1d2c4",
            "kind": 9321,
            "content": "Test",
            "pubkey": "\(testSenderPubkey)",
            "created_at": 1234567890,
            "tags": [
                ["proof", "invalid_json"],
                ["proof", "{\\"amount\\":50,\\"C\\":\\"02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f\\",\\"id\\":\\"keyset1\\",\\"secret\\":\\"[P2PK_secret]\\"}"],
                ["mint", "\(testMintURL!)"],
                ["u", "sat"],
                ["p", "\(testRecipientPubkey!)"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let event = try NDKEvent(from: eventDict)
        let nutzapEvent = NDKNutzapEvent(event: event)
        
        // Should only parse valid proofs, ignoring invalid ones
        XCTAssertNotNil(nutzapEvent.token)
        let proofs = nutzapEvent.token!.proofsByMint[testMintURL]!
        XCTAssertEqual(proofs.count, 1)
        XCTAssertEqual(proofs.first?.amount, 50)
    }
    
    // MARK: - NIP-61 Compliance Tests
    
    func testNIP61ComplianceEventStructure() async throws {
        // Create nutzap that matches NIP-61 example exactly
        let proof = CashuSwift.Proof(
            amount: 1,
            id: "000a93d6f8a1d2c4",
            secret: "[\"P2PK\",{\"nonce\":\"b00bdd0467b0090a25bdf2d2f0d45ac4e355c482c1418350f273a04fedaaee83\",\"data\":\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\"}]",
            C: "02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f"
        )
        
        let token = CashuSwift.Token(proofs: [testMintURL: [proof]], unit: "sat")
        let eventId = "nutzapped-event-id"
        
        let nutzapEvent = try await NDKNutzapEvent.create(
            ndk: ndk,
            token: token,
            mintURL: testMintURL,
            recipient: testRecipientPubkey,
            comment: "Thanks for this great idea.",
            eventId: eventId,
            signer: mockSigner
        )
        
        // Verify NIP-61 required structure
        let tags = nutzapEvent.event.tags
        
        // Must have proof tag(s)
        let proofTags = tags.filter { $0.first == "proof" }
        XCTAssertFalse(proofTags.isEmpty, "Must have at least one proof tag")
        
        // Must have mint tag (u tag in NIP-61 example, but mint tag in our implementation)
        let mintTags = tags.filter { $0.first == "mint" }
        XCTAssertEqual(mintTags.count, 1, "Must have exactly one mint tag")
        
        // Must have p tag for recipient
        let pTags = tags.filter { $0.first == "p" }
        XCTAssertEqual(pTags.count, 1, "Must have exactly one p tag")
        XCTAssertEqual(pTags.first?[1], testRecipientPubkey)
        
        // Should have e tag when eventId provided
        let eTags = tags.filter { $0.first == "e" }
        XCTAssertEqual(eTags.count, 1, "Must have e tag when eventId provided")
        XCTAssertEqual(eTags.first?[1], eventId)
        
        // Should have unit tag
        let unitTags = tags.filter { $0.first == "u" }
        XCTAssertEqual(unitTags.count, 1, "Must have unit tag")
        XCTAssertEqual(unitTags.first?[1], "sat")
        
        // Content should contain the comment
        XCTAssertEqual(nutzapEvent.event.content, "Thanks for this great idea.")
        
        // Event kind must be 9321
        XCTAssertEqual(nutzapEvent.event.kind, 9321)
    }
    
    func testNIP61ProofFormat() throws {
        // Test that proof format matches NIP-61 specification
        let eventJSON = """
        {
            "id": "test_event_id",
            "kind": 9321,
            "content": "Thanks for this great idea.",
            "pubkey": "\(testSenderPubkey)",
            "created_at": 1234567890,
            "tags": [
                ["proof", "{\\"amount\\":1,\\"C\\":\\"02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f\\",\\"id\\":\\"000a93d6f8a1d2c4\\",\\"secret\\":\\"[\\\\\\"P2PK\\\\\\",{\\\\\\"nonce\\\\\\":\\\\\\"b00bdd0467b0090a25bdf2d2f0d45ac4e355c482c1418350f273a04fedaaee83\\\\\\",\\\\\\"data\\\\\\":\\\\\\"02eaee8939e3565e48cc62967e2fde9d8e2a4b3ec0081f29eceff5c64ef10ac1ed\\\\\\"}]\\"}"],
                ["mint", "\(testMintURL!)"],
                ["e", "nutzapped-event-id"],
                ["p", "\(testRecipientPubkey!)"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let event = try NDKEvent(from: eventDict)
        let nutzapEvent = NDKNutzapEvent(event: event)
        
        // Extract and verify proof structure
        let token = nutzapEvent.token!
        let proofs = token.proofsByMint[testMintURL]!
        let proof = proofs.first!
        
        // Verify proof contains P2PK lock structure
        XCTAssertTrue(proof.secret.contains("P2PK"))
        XCTAssertTrue(proof.secret.contains("nonce"))
        XCTAssertTrue(proof.secret.contains("data"))
        
        // Verify proof has required fields
        XCTAssertEqual(proof.amount, 1)
        XCTAssertEqual(proof.id, "000a93d6f8a1d2c4")
        XCTAssertEqual(proof.C, "02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f")
    }
    
    // MARK: - Edge Cases
    
    func testParseEventWithNoRecipient() throws {
        let eventJSON = """
        {
            "id": "000a93d6f8a1d2c4",
            "kind": 9321,
            "content": "Test",
            "pubkey": "\(testSenderPubkey)",
            "created_at": 1234567890,
            "tags": [
                ["proof", "{\\"amount\\":1,\\"C\\":\\"02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f\\",\\"id\\":\\"000a93d6f8a1d2c4\\",\\"secret\\":\\"[P2PK_secret]\\"}"],
                ["mint", "\(testMintURL!)"],
                ["u", "sat"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let event = try NDKEvent(from: eventDict)
        let nutzapEvent = NDKNutzapEvent(event: event)
        
        XCTAssertNil(nutzapEvent.recipient)
    }
    
    func testParseEventWithNoUnit() throws {
        let eventJSON = """
        {
            "id": "000a93d6f8a1d2c4",
            "kind": 9321,
            "content": "Test",
            "pubkey": "\(testSenderPubkey)",
            "created_at": 1234567890,
            "tags": [
                ["proof", "{\\"amount\\":1,\\"C\\":\\"02277c66191736eb72fce9d975d08e3191f8f96afb73ab1eec37e4465683066d3f\\",\\"id\\":\\"000a93d6f8a1d2c4\\",\\"secret\\":\\"[P2PK_secret]\\"}"],
                ["mint", "\(testMintURL!)"],
                ["p", "\(testRecipientPubkey!)"]
            ],
            "sig": "signature_here"
        }
        """
        
        guard let eventData = eventJSON.data(using: .utf8),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            XCTFail("Failed to create test event data")
            return
        }
        
        let event = try NDKEvent(from: eventDict)
        let nutzapEvent = NDKNutzapEvent(event: event)
        
        XCTAssertNil(nutzapEvent.unit)
        
        // Token should still be created with default "sat" unit  
        XCTAssertNotNil(nutzapEvent.token)
        XCTAssertEqual(nutzapEvent.token?.unit, "sat")
    }
}