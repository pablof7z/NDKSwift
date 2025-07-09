import XCTest
@testable import NDKSwift

final class ZapIntegrationTests: XCTestCase {
    var ndk: NDK!
    var zapManager: NDKZapManager!
    var mockRelay: MockRelay!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Set up NDK with mock relay
        mockRelay = MockRelay(url: "wss://test.relay")
        ndk = NDK()
        ndk.relayPool = NDKRelayPool(ndk: ndk)
        ndk.relayPool.addRelay(mockRelay)
        
        // Set up signer
        signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        // Set up zap manager
        zapManager = ndk.zapManager
    }
    
    override func tearDown() async throws {
        await mockRelay.disconnect()
        try await super.tearDown()
    }
    
    // MARK: - End-to-End Lightning Zap Test
    
    func testFullLightningZapFlow() async throws {
        // 1. Set up recipient with Lightning support
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        let profileEvent = createProfileEvent(
            pubkey: recipient.pubkey,
            lud16: "alice@wallet.com"
        )
        mockRelay.mockEvents = [profileEvent]
        
        // 2. Set up payment provider
        let mockWallet = MockLightningWallet()
        let paymentProvider = WalletAdapterPaymentProvider(wallet: mockWallet)
        zapManager.register(provider: paymentProvider)
        
        // 3. Execute zap
        let zapTask = Task<ZapResult, Error> {
            try await recipient.zap(
                amountSats: 1000,
                comment: "Great work!"
            )
        }
        
        // 4. Wait for zap request to be created
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // 5. Simulate zap receipt from LNURL provider
        let receipt = createZapReceipt(
            recipient: recipient.pubkey,
            amountSats: 1000,
            preimage: mockWallet.lastPreimage ?? "test-preimage"
        )
        mockRelay.simulateEventReceived(receipt)
        
        // 6. Get result
        let result = try await zapTask.value
        
        // 7. Verify result
        XCTAssertEqual(result.type, .lightning)
        XCTAssertEqual(result.amountSats, 1000)
        XCTAssertNotNil(result.receiptEvent)
        
        // 8. Verify we can fetch the zap
        let zaps = try await recipient.fetchZaps()
        XCTAssertEqual(zaps.count, 1)
        XCTAssertEqual(zaps.first?.amountSats, 1000)
        XCTAssertEqual(zaps.first?.type, .lightning)
    }
    
    // MARK: - End-to-End Nutzap Test
    
    func testFullNutzapFlow() async throws {
        // 1. Set up recipient with Nutzap support
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        let nutzapPrefs = createNutzapPreferences(
            pubkey: recipient.pubkey,
            mint: "https://mint.example.com"
        )
        mockRelay.mockEvents = [nutzapPrefs]
        
        // 2. Set up Cashu payment provider
        let mockWallet = MockCashuWallet()
        let paymentProvider = WalletAdapterPaymentProvider(wallet: mockWallet)
        zapManager.register(provider: paymentProvider)
        
        // 3. Execute nutzap
        let result = try await recipient.zap(
            amountSats: 2000,
            comment: "Nutzap test!",
            preferredType: .nutzap
        )
        
        // 4. Verify result
        XCTAssertEqual(result.type, .nutzap)
        XCTAssertEqual(result.amountSats, 2000)
        XCTAssertNotNil(result.nutzapEvent)
        
        // 5. Verify nutzap was published
        let publishedEvents = await mockRelay.publishedEvents
        let nutzapEvent = publishedEvents.first { event in
            Task { await event.kind == EventKind.nutzap }.result ?? false
        }
        XCTAssertNotNil(nutzapEvent)
        
        // 6. Verify we can fetch the nutzap
        let zaps = try await recipient.fetchZaps(includeNutzaps: true)
        XCTAssertEqual(zaps.count, 1)
        XCTAssertEqual(zaps.first?.amountSats, 2000)
        XCTAssertEqual(zaps.first?.type, .nutzap)
    }
    
    // MARK: - Multiple Provider Test
    
    func testZapWithMultipleProviders() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey", ndk: ndk)
        setupLightningProfile(for: recipient)
        
        // Register multiple providers
        let failingProvider = FailingPaymentProvider(id: "failing")
        let workingProvider = MockLightningWallet()
        let workingAdapter = WalletAdapterPaymentProvider(wallet: workingProvider)
        
        zapManager.register(provider: failingProvider)
        zapManager.register(provider: workingAdapter)
        
        // Should skip failing provider and use working one
        let zapTask = Task<ZapResult, Error> {
            try await recipient.zap(amountSats: 500)
        }
        
        // Simulate receipt
        try await Task.sleep(nanoseconds: 100_000_000)
        let receipt = createZapReceipt(
            recipient: recipient.pubkey,
            amountSats: 500,
            preimage: workingProvider.lastPreimage ?? "test"
        )
        mockRelay.simulateEventReceived(receipt)
        
        let result = try await zapTask.value
        XCTAssertEqual(result.amountSats, 500)
        XCTAssertTrue(failingProvider.attemptedFulfill)
    }
    
    // MARK: - Event Zapping Test
    
    func testZapEvent() async throws {
        // Create an event to zap
        let author = NDKUser(pubkey: "author-pubkey", ndk: ndk)
        setupLightningProfile(for: author)
        
        let event = NDKEvent(
            pubkey: author.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Hello Nostr!"
        )
        event.id = "event-123"
        event.ndk = ndk
        
        // Set up payment
        let wallet = MockLightningWallet()
        zapManager.register(provider: WalletAdapterPaymentProvider(wallet: wallet))
        
        // Zap the event
        let zapTask = Task<ZapResult, Error> {
            try await event.zap(
                amountSats: 100,
                comment: "Love this post!"
            )
        }
        
        // Simulate receipt with event tag
        try await Task.sleep(nanoseconds: 100_000_000)
        let receipt = createZapReceipt(
            recipient: author.pubkey,
            amountSats: 100,
            preimage: wallet.lastPreimage ?? "test",
            zappedEventId: "event-123"
        )
        mockRelay.simulateEventReceived(receipt)
        
        let result = try await zapTask.value
        XCTAssertEqual(result.amountSats, 100)
        
        // Fetch zaps for the event
        let eventZaps = try await event.fetchZaps()
        XCTAssertEqual(eventZaps.count, 1)
        XCTAssertEqual(eventZaps.first?.comment, "Love this post!")
    }
    
    // MARK: - Helper Methods
    
    private func setupLightningProfile(for user: NDKUser) {
        let profileEvent = createProfileEvent(
            pubkey: user.pubkey,
            lud16: "test@wallet.com"
        )
        mockRelay.mockEvents.append(profileEvent)
    }
    
    private func createProfileEvent(pubkey: String, lud16: String) -> NDKEvent {
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.metadata,
            content: """
            {
                "lud16": "\(lud16)",
                "name": "Test User"
            }
            """
        )
        return event
    }
    
    private func createNutzapPreferences(pubkey: String, mint: String) -> NDKEvent {
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.nutzapPreferences,
            content: ""
        )
        event.addTag(["mint", mint, "sat"])
        event.addTag(["relay", "wss://relay1.com"])
        event.addTag(["p2pk", pubkey])
        return event
    }
    
    private func createZapReceipt(
        recipient: String,
        amountSats: Int64,
        preimage: String,
        zappedEventId: String? = nil
    ) -> NDKEvent {
        let receipt = NDKEvent(
            pubkey: "lnurl-provider",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.zapReceipt,
            content: ""
        )
        
        receipt.addTag(["p", recipient])
        receipt.addTag(["bolt11", "lnbc\(amountSats)000n1..."])
        receipt.addTag(["preimage", preimage])
        
        if let eventId = zappedEventId {
            receipt.addTag(["e", eventId])
        }
        
        // Add description tag with mock zap request
        let zapRequest = NDKEvent(
            pubkey: signer.pubkey ?? "",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.zapRequest,
            content: ""
        )
        zapRequest.addTag(["p", recipient])
        zapRequest.addTag(["amount", String(amountSats * 1000)])
        
        if let requestJSON = try? JSONEncoder().encode(zapRequest),
           let requestString = String(data: requestJSON, encoding: .utf8) {
            receipt.addTag(["description", requestString])
        }
        
        return receipt
    }
}

// MARK: - Mock Lightning Wallet

class MockLightningWallet: NDKWallet, @unchecked Sendable {
    var pubkey: String? = "mock-lightning-wallet"
    var lastPreimage: String?
    
    func balance() async throws -> Int64 {
        100_000
    }
    
    func pay(invoice: String) async throws -> String? {
        lastPreimage = "preimage-\(UUID().uuidString)"
        return lastPreimage
    }
    
    func createInvoice(amountSats: Int64, description: String?, expirySeconds: Int?) async throws -> String {
        "lnbc\(amountSats)n1..."
    }
    
    func checkInvoice(_ invoice: String) async throws -> InvoiceStatus {
        InvoiceStatus(paid: true, preimage: lastPreimage)
    }
    
    func cashuTokens() async throws -> [CashuToken] {
        []
    }
    
    func createCashuToken(amount: Int64, unit: String, mint: String) async throws -> CashuToken {
        throw NDKError.notImplemented
    }
    
    func redeemCashuToken(_ token: CashuToken) async throws -> Int64 {
        throw NDKError.notImplemented
    }
}

// MARK: - Failing Payment Provider

class FailingPaymentProvider: NDKPaymentProvider, @unchecked Sendable {
    let id: String
    var attemptedFulfill = false
    
    init(id: String) {
        self.id = id
    }
    
    func isAvailable() async -> Bool {
        true
    }
    
    func canFulfill(_ request: PaymentRequest) async -> Bool {
        false // Always fails
    }
    
    func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        attemptedFulfill = true
        throw NDKError.paymentFailed(reason: "Test failure")
    }
}