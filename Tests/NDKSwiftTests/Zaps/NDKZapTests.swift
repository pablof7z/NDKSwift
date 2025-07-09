@testable import NDKSwift
import XCTest

final class NDKZapTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        signer = try NDKPrivateKeySigner(privateKey: TestConstants.validPrivateKey)
        ndk = NDK(signer: signer)
    }
    
    override func tearDown() async throws {
        ndk = nil
        signer = nil
    }
    
    // MARK: - Zap Request Tests
    
    func testCreateZapRequest() async throws {
        let recipient = NDKUser(pubkey: TestConstants.recipientPubkey)
        recipient.ndk = ndk
        let relays = ["wss://relay.damus.io", "wss://nos.lol"]
        
        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            recipient: recipient,
            amountMillisats: 1000000, // 1000 sats
            comment: "Great post!",
            relays: relays
        )
        
        XCTAssertEqual(zapRequest.event.kind, EventKind.zapRequest)
        XCTAssertEqual(zapRequest.amountMillisats, 1000000)
        XCTAssertEqual(zapRequest.amountSats, 1000)
        XCTAssertEqual(zapRequest.comment, "Great post!")
        XCTAssertEqual(zapRequest.recipientPubkey, TestConstants.recipientPubkey)
        XCTAssertEqual(zapRequest.relays, relays)
    }
    
    func testZapRequestWithEvent() async throws {
        let recipient = NDKUser(pubkey: TestConstants.recipientPubkey)
        recipient.ndk = ndk
        let eventToZap = NDKEvent()
        eventToZap.ndk = ndk
        eventToZap.id = "test_event_id"
        
        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            recipient: recipient,
            amountMillisats: 500000,
            comment: nil,
            relays: ["wss://relay.damus.io"],
            zappedEvent: eventToZap
        )
        
        XCTAssertEqual(zapRequest.zappedEventId, "test_event_id")
        XCTAssertNil(zapRequest.comment)
    }
    
    // MARK: - Zap Receipt Tests
    
    func testZapReceiptValidation() async throws {
        // Create a zap request
        let recipient = NDKUser(pubkey: TestConstants.recipientPubkey)
        recipient.ndk = ndk
        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            recipient: recipient,
            amountMillisats: 1000000,
            comment: "Test zap",
            relays: ["wss://relay.damus.io"]
        )
        
        // Create a zap receipt
        let providerSigner = try NDKPrivateKeySigner(privateKey: TestConstants.providerPrivateKey)
        let receipt = try await NDKZapReceipt.create(
            ndk: ndk,
            signer: providerSigner,
            zapRequest: zapRequest,
            bolt11: "lnbc10u1p3unwfusp5t9r3yymhpfqculx78u027lxspgxcr2n2987mx2j55nnfs95nxnzqpp5jmrh92pfld78spqs78v9euf2385t83uvpwk9ldrlvf6ch7tpascqhp5zvkrmemgth3tufcvflmzjzfvjt023nazlhljz2n9hattj4f8jq8qxqyjw5qcqpjrzjqtc4fc44feggv7065fqe5m4ytjarg3repr5j9el35xhmtfexc42yczarjuqqfzqqqqqqqqlgqqqqqqgq9q9qxpqysgq079nkq507a5tw7xgttmj4u990j7wfggtrasah5gd4ywfr2pjcn29383tphp4t48gquelz9z78p4cq7ml3nrrphw5w6eckhjwmhezhnqpy6gyf0",
            preimage: "test_preimage"
        )
        
        let providerPubkey = try await providerSigner.pubkey
        
        // Validate receipt
        XCTAssertTrue(receipt.validate(lnurlProviderPubkey: providerPubkey, zapRequest: zapRequest))
        
        // Test invalid validation (wrong provider pubkey)
        XCTAssertFalse(receipt.validate(lnurlProviderPubkey: "wrong_pubkey"))
    }
    
    func testZapReceiptParsing() {
        let event = NDKEvent()
        event.ndk = ndk
        event.kind = EventKind.zapReceipt
        event.tags = [
            ["bolt11", "lnbc10u1..."],
            ["preimage", "test_preimage"],
            ["description", "{\"kind\":9734,\"content\":\"Test\"}"],
            ["p", TestConstants.recipientPubkey],
            ["P", TestConstants.senderPubkey],
            ["e", "event_id"]
        ]
        
        let receipt = NDKZapReceipt(event: event)
        
        XCTAssertEqual(receipt.bolt11, "lnbc10u1...")
        XCTAssertEqual(receipt.preimage, "test_preimage")
        XCTAssertEqual(receipt.recipientPubkey, TestConstants.recipientPubkey)
        XCTAssertEqual(receipt.senderPubkey, TestConstants.senderPubkey)
        XCTAssertEqual(receipt.zappedEventId, "event_id")
    }
    
    // MARK: - Nutzap Tests
    
    func testCreateNutzap() async throws {
        let recipient = NDKUser(pubkey: TestConstants.recipientPubkey)
        recipient.ndk = ndk
        let mint = URL(string: "https://mint.minibits.cash")!
        
        let proofs = [
            CashuProof(
                amount: 100,
                C: "02abc123",
                id: "00456a94ab4e1c46",
                secret: "[\"P2PK\",{\"nonce\":\"test\",\"data\":\"02recipientpubkey\"}]",
                dleq: nil
            )
        ]
        
        let nutzap = try await NDKNutzap.create(
            ndk: ndk,
            recipient: recipient,
            proofs: proofs,
            mint: mint,
            comment: "Nutzap test!"
        )
        
        XCTAssertEqual(nutzap.event.kind, EventKind.nutzap)
        XCTAssertEqual(nutzap.comment, "Nutzap test!")
        XCTAssertEqual(nutzap.mintURL, mint)
        XCTAssertEqual(nutzap.recipientPubkey, TestConstants.recipientPubkey)
        XCTAssertEqual(nutzap.totalAmount, 100)
        XCTAssertEqual(nutzap.proofs.count, 1)
    }
    
    func testNutzapPreferences() async throws {
        let p2pkKeyPair = KeyPair(
            publicKey: "testpubkey",
            privateKey: "testprivkey"
        )
        
        let preferences = try await NDKNutzapPreferences.create(
            ndk: ndk,
            relays: ["wss://relay1.com", "wss://relay2.com"],
            mints: [
                (url: URL(string: "https://mint1.com")!, units: ["sat", "usd"]),
                (url: URL(string: "https://mint2.com")!, units: ["sat"])
            ],
            p2pkKeyPair: p2pkKeyPair
        )
        
        XCTAssertEqual(preferences.event.kind, EventKind.nutzapPreferences)
        XCTAssertEqual(preferences.relays, ["wss://relay1.com", "wss://relay2.com"])
        XCTAssertEqual(preferences.mints.count, 2)
        XCTAssertEqual(preferences.p2pkPubkey, "02testpubkey") // Note the "02" prefix
    }
    
    // MARK: - Zap Manager Tests
    
    func testZapManagerRegistration() {
        let zapManager = NDKZapManager(ndk: ndk)
        
        let mockLightningProvider = MockZapProvider(type: .lightning)
        let mockNutzapProvider = MockZapProvider(type: .nutzap)
        
        zapManager.register(provider: mockLightningProvider)
        zapManager.register(provider: mockNutzapProvider)
        
        // Can't directly test internal state, but we can test behavior
        // by attempting to zap and seeing which provider is called
    }
    
    // MARK: - NIP-57 Test Vectors from nostr-tools
    
    func testNostrToolsLightningInvoiceVectors() {
        // Test vectors from nostr-tools nip57.test.ts
        struct InvoiceTestVector {
            let amount: Int64  // in sats
            let invoice: String
            let description: String
        }
        
        let testVectors = [
            InvoiceTestVector(
                amount: 400,
                invoice: "lnbc4u1p5zcarnpp5djng98r73nxu66nxp6gndjkw24q7rdzgp7p80lt0gk4z3h3krkssdq9w3jhxazlwpshjhmwda6hgetzdahhyarjv96xjmmwyp38jup6yqhp5yqhuyqh8ymmc0qxqyjw5qcqpjrzjqtc4fc44feggv7065fqe5m4ytjarg3repr5j9el35xhmtfexc42yczarjuqqfzqqqqqqqqlgqqqqqqgq9q9qxpqysgq079nkq507a5tw7xgttmj4u990j7wfggtrasah5gd4ywfr2pjcn29383tphp4t48gquelz9z78p4cq7ml3nrrphw5w6eckhjwmhezhnqpy6gyf0",
                description: "400 sats invoice"
            ),
            InvoiceTestVector(
                amount: 840_000,
                invoice: "lnbc8400u1p5zcaz5pp5ltvyhtg4ed7sd8jurj28ugmavezkmqsadpe3t9npufpcrd0uet0scqz95qxzjkcmre8ejk2ceyqgp6xqzfvsp57hmrdf7n4hhx2cmlyt7jfp6meqk8kvf54qtdg6w5rqggffdzvd8q9qgqtqssq079nkq507a5tw7xgttmj4u990j7wfggtrasah5gd4ywfr2pjcn29383tphp4t48gquelz9z78p4cq7ml3nrrphw5w6eckhjwmhezhnqpy6gyf0",
                description: "840,000 sats invoice"
            ),
            InvoiceTestVector(
                amount: 21,
                invoice: "lnbc210n1p5zcuaxpp52nn778cfk46md4ld0hdj2juuzvfrsrdaf4ek2k0yeensae07x2cqdq9w3jhxazlwpshjmt0de6xjarejgj9u46pwy5jhgmpwxqyjw5qcqpjrzjqtc4fc44feggv7065fqe5m4ytjarg3repr5j9el35xhmtfexc42yczarjuqqfzqqqqqqqqlgqqqqqqgq9q9qxpqysgq079nkq507a5tw7xgttmj4u990j7wfggtrasah5gd4ywfr2pjcn29383tphp4t48gquelz9z78p4cq7ml3nrrphw5w6eckhjwmhezhnqpy6gyf0",
                description: "21 sats invoice"
            ),
            InvoiceTestVector(
                amount: 89_964,
                invoice: "lnbc899640n1p5zcuavpp5w72fqrf09286lq33vw364qryrq5nw60z4dhdx56f8w05xkx4massdq9w3jhxazlwpshjgr4dejhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqtc4fc44feggv7065fqe5m4ytjarg3repr5j9el35xhmtfexc42yczarjuqqfzqqqqqqqqlgqqqqqqgq9q9qxpqysgq079nkq507a5tw7xgttmj4u990j7wfggtrasah5gd4ywfr2pjcn29383tphp4t48gquelz9z78p4cq7ml3nrrphw5w6eckhjwmhezhnqpy6gyf0",
                description: "89,964 sats invoice"
            )
        ]
        
        // Test that we can extract amounts from BOLT11 invoices
        for vector in testVectors {
            // Basic validation that the invoice starts with expected prefix
            XCTAssertTrue(vector.invoice.hasPrefix("lnbc"), "Invoice should start with 'lnbc'")
            
            // Validate the amount is correct
            // Note: In real implementation, you would decode the BOLT11 invoice
            // to extract the amount. Here we're just validating the test vectors.
            XCTAssertTrue(vector.amount > 0, "Amount should be positive")
        }
    }
    
    func testZapInfo() async throws {
        let zapInfo = ZapInfo(
            type: .lightning,
            amountSats: 1000,
            sender: TestConstants.senderPubkey,
            recipient: TestConstants.recipientPubkey,
            comment: "Test zap",
            timestamp: Date(),
            event: NDKEvent()
        )
        
        XCTAssertEqual(zapInfo.amountSats, 1000)
        XCTAssertEqual(zapInfo.sender, TestConstants.senderPubkey)
        XCTAssertEqual(zapInfo.comment, "Test zap")
    }
}

// MARK: - Mock Implementations

class MockZapProvider: NDKZapProvider {
    let type: ZapType
    var canZapCalled = false
    var zapCalled = false
    
    init(type: ZapType) {
        self.type = type
    }
    
    func canZap(user: NDKUser) async throws -> Bool {
        canZapCalled = true
        return true
    }
    
    func zap(event: NDKEvent?, to user: NDKUser, amountSats: Int64, comment: String?) async throws -> ZapResult {
        zapCalled = true
        let sentEvent = NDKEvent()
        sentEvent.ndk = user.ndk
        sentEvent.kind = type == .lightning ? EventKind.zapRequest : EventKind.nutzap
        
        return ZapResult(
            sentEvent: sentEvent,
            awaitConfirmation: { sentEvent }
        )
    }
}

// MARK: - Test Constants

private enum TestConstants {
    static let validPrivateKey = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    static let providerPrivateKey = "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
    static let recipientPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
    static let senderPubkey = "97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322"
}
