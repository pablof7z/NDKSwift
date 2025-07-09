import XCTest
@testable import NDKSwift

final class NDKLightningZapProtocolTests: XCTestCase {
    var ndk: NDK!
    var zapProtocol: NDKLightningZapProtocol!
    var mockRelay: MockRelay!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockRelay = MockRelay(url: "wss://test.relay")
        ndk = NDK()
        ndk.relayPool = NDKRelayPool(ndk: ndk)
        ndk.relayPool.addRelay(mockRelay)
        
        zapProtocol = NDKLightningZapProtocol(ndk: ndk)
    }
    
    override func tearDown() async throws {
        await mockRelay.disconnect()
        try await super.tearDown()
    }
    
    // MARK: - Can Zap Tests
    
    func testCanZapUserWithLUD16() async throws {
        let user = NDKUser(pubkey: "test-user", ndk: ndk)
        
        // Mock profile with lud16
        let profileEvent = NDKEvent(
            pubkey: user.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.metadata,
            content: """
            {
                "lud16": "alice@wallet.com",
                "name": "Alice"
            }
            """
        )
        mockRelay.mockEvents = [profileEvent]
        
        let canZap = try await zapProtocol.canZap(user: user)
        XCTAssertTrue(canZap)
    }
    
    func testCanZapUserWithLUD06() async throws {
        let user = NDKUser(pubkey: "test-user", ndk: ndk)
        
        // Mock profile with lud06
        let profileEvent = NDKEvent(
            pubkey: user.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.metadata,
            content: """
            {
                "lud06": "LNURL1DP68GURN8GHJ7...",
                "name": "Bob"
            }
            """
        )
        mockRelay.mockEvents = [profileEvent]
        
        let canZap = try await zapProtocol.canZap(user: user)
        XCTAssertTrue(canZap)
    }
    
    func testCannotZapUserWithoutLNURL() async throws {
        let user = NDKUser(pubkey: "test-user", ndk: ndk)
        
        // Mock profile without lightning
        let profileEvent = NDKEvent(
            pubkey: user.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.metadata,
            content: """
            {
                "name": "Charlie"
            }
            """
        )
        mockRelay.mockEvents = [profileEvent]
        
        let canZap = try await zapProtocol.canZap(user: user)
        XCTAssertFalse(canZap)
    }
    
    // MARK: - Prepare Zap Tests
    
    func testPrepareZapCreatesValidRequest() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        let signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        setupMockProfile(for: recipient)
        
        let prepared = try await zapProtocol.prepareZap(
            to: recipient,
            amountSats: 1000,
            comment: "Great post!"
        )
        
        XCTAssertEqual(prepared.type, .lightning)
        XCTAssertEqual(prepared.amountSats, 1000)
        
        // Verify payment request
        guard let invoiceRequest = prepared.paymentRequest as? LightningInvoiceRequest else {
            XCTFail("Expected LightningInvoiceRequest")
            return
        }
        
        XCTAssertEqual(invoiceRequest.amountSats, 1000)
        XCTAssertTrue(invoiceRequest.callbackURL.contains("wallet.com"))
    }
    
    func testPrepareZapForEvent() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        let signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        setupMockProfile(for: recipient)
        
        let event = NDKEvent(
            pubkey: recipient.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Hello world"
        )
        event.id = "event-id"
        
        let prepared = try await zapProtocol.prepareZap(
            event: event,
            to: recipient,
            amountSats: 500,
            comment: nil
        )
        
        // Verify zap request has event tag
        let zapRequest = prepared.context["zapRequest"] as? NDKZapRequest
        XCTAssertNotNil(zapRequest)
        
        let zappedEventId = await zapRequest?.zappedEventId
        XCTAssertEqual(zappedEventId, "event-id")
    }
    
    // MARK: - Complete Zap Tests
    
    func testCompleteZapWaitsForReceipt() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        let signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        setupMockProfile(for: recipient)
        
        // Prepare zap
        let prepared = try await zapProtocol.prepareZap(
            to: recipient,
            amountSats: 1000,
            comment: "Test"
        )
        
        // Mock payment confirmation
        let confirmation = LightningPaymentConfirmation(
            preimage: "test-preimage",
            paidAt: Date()
        )
        
        // Set up expectation for zap receipt
        let receiptExpectation = expectation(description: "Zap receipt received")
        
        Task {
            // Wait a bit then publish mock receipt
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            
            let receipt = NDKEvent(
                pubkey: "lnurl-provider",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.zapReceipt,
                content: ""
            )
            receipt.addTag(["p", recipient.pubkey])
            receipt.addTag(["bolt11", "lnbc1000n1..."])
            receipt.addTag(["preimage", "test-preimage"])
            
            // Simulate receipt from relay
            mockRelay.simulateEventReceived(receipt)
            receiptExpectation.fulfill()
        }
        
        // Complete zap (should wait for receipt)
        let result = try await zapProtocol.completeZap(
            prepared: prepared,
            confirmation: confirmation
        )
        
        await fulfillment(of: [receiptExpectation], timeout: 2.0)
        
        XCTAssertEqual(result.type, .lightning)
        XCTAssertEqual(result.amountSats, 1000)
        XCTAssertNotNil(result.receiptEvent)
    }
    
    func testCompleteZapThrowsOnTimeout() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        let signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        setupMockProfile(for: recipient)
        
        // Prepare zap
        let prepared = try await zapProtocol.prepareZap(
            to: recipient,
            amountSats: 1000,
            comment: "Test"
        )
        
        // Mock payment confirmation
        let confirmation = LightningPaymentConfirmation(
            preimage: "test-preimage",
            paidAt: Date()
        )
        
        // Don't publish any receipt - should timeout
        do {
            _ = try await zapProtocol.completeZap(
                prepared: prepared,
                confirmation: confirmation
            )
            XCTFail("Expected timeout error")
        } catch {
            guard case ZapError.timeoutWaitingForReceipt = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupMockProfile(for user: NDKUser) {
        let profileEvent = NDKEvent(
            pubkey: user.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.metadata,
            content: """
            {
                "lud16": "test@wallet.com",
                "name": "Test User"
            }
            """
        )
        mockRelay.mockEvents = [profileEvent]
    }
}