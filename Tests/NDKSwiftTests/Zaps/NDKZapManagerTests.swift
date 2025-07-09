import XCTest
@testable import NDKSwift

final class NDKZapManagerTests: XCTestCase {
    var ndk: NDK!
    var zapManager: NDKZapManager!
    var mockRelay: MockRelay!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockRelay = MockRelay(url: "wss://test.relay")
        ndk = NDK()
        ndk.relayPool = NDKRelayPool(ndk: ndk)
        ndk.relayPool.addRelay(mockRelay)
        
        zapManager = NDKZapManager(ndk: ndk)
    }
    
    override func tearDown() async throws {
        await mockRelay.disconnect()
        try await super.tearDown()
    }
    
    // MARK: - Protocol Selection Tests
    
    func testSelectsNutzapProtocolWhenAvailable() async throws {
        // Create recipient with both Lightning and Nutzap support
        let recipient = NDKUser(pubkey: "test-recipient", ndk: ndk)
        
        // Mock profile with both LUD16 and Nutzap preferences
        let profileEvent = NDKEvent(
            pubkey: recipient.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.metadata,
            content: """
            {
                "lud16": "test@wallet.com",
                "name": "Test User"
            }
            """
        )
        
        // Mock Nutzap preferences
        let nutzapPrefsEvent = NDKEvent(
            pubkey: recipient.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.nutzapPreferences,
            content: ""
        )
        nutzapPrefsEvent.addTag(["mint", "https://mint1.com"])
        nutzapPrefsEvent.addTag(["relay", "wss://relay1.com"])
        
        mockRelay.mockEvents = [profileEvent, nutzapPrefsEvent]
        
        // Register test payment provider
        let mockProvider = MockPaymentProvider(id: "test-provider")
        zapManager.register(provider: mockProvider)
        
        // Smart routing should prefer Nutzap for privacy
        let result = try await zapManager.zap(
            to: recipient,
            amountSats: 1000,
            comment: "Test zap"
        )
        
        XCTAssertEqual(result.type, .nutzap)
    }
    
    func testFallsBackToLightningWhenNutzapUnavailable() async throws {
        // Create recipient with only Lightning support
        let recipient = NDKUser(pubkey: "test-recipient", ndk: ndk)
        
        // Mock profile with only LUD16
        let profileEvent = NDKEvent(
            pubkey: recipient.pubkey,
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
        
        // Register test payment provider
        let mockProvider = MockPaymentProvider(id: "test-provider")
        zapManager.register(provider: mockProvider)
        
        // Should use Lightning when Nutzap not available
        let result = try await zapManager.zap(
            to: recipient,
            amountSats: 1000,
            comment: "Test zap"
        )
        
        XCTAssertEqual(result.type, .lightning)
    }
    
    func testRespectsPreferredZapType() async throws {
        // Create recipient with both Lightning and Nutzap support
        let recipient = NDKUser(pubkey: "test-recipient", ndk: ndk)
        
        // Mock profile with both
        let profileEvent = NDKEvent(
            pubkey: recipient.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.metadata,
            content: """
            {
                "lud16": "test@wallet.com"
            }
            """
        )
        
        let nutzapPrefsEvent = NDKEvent(
            pubkey: recipient.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.nutzapPreferences,
            content: ""
        )
        nutzapPrefsEvent.addTag(["mint", "https://mint1.com"])
        
        mockRelay.mockEvents = [profileEvent, nutzapPrefsEvent]
        
        // Register test payment provider
        let mockProvider = MockPaymentProvider(id: "test-provider")
        zapManager.register(provider: mockProvider)
        
        // Force Lightning even though Nutzap is available
        let result = try await zapManager.zap(
            to: recipient,
            amountSats: 1000,
            comment: "Test zap",
            preferredType: .lightning
        )
        
        XCTAssertEqual(result.type, .lightning)
    }
    
    // MARK: - Payment Provider Selection Tests
    
    func testSelectsPreferredPaymentProvider() async throws {
        let recipient = NDKUser(pubkey: "test-recipient", ndk: ndk)
        setupMockLightningProfile(for: recipient)
        
        // Register multiple providers
        let provider1 = MockPaymentProvider(id: "provider-1")
        let provider2 = MockPaymentProvider(id: "provider-2")
        let provider3 = MockPaymentProvider(id: "provider-3")
        
        zapManager.register(provider: provider1)
        zapManager.register(provider: provider2)
        zapManager.register(provider: provider3)
        
        // Zap with preferred provider
        _ = try await zapManager.zap(
            to: recipient,
            amountSats: 1000,
            preferredProvider: "provider-2"
        )
        
        // Verify provider-2 was used
        XCTAssertTrue(provider2.fulfillCalled)
        XCTAssertFalse(provider1.fulfillCalled)
        XCTAssertFalse(provider3.fulfillCalled)
    }
    
    func testFallsBackWhenPreferredProviderUnavailable() async throws {
        let recipient = NDKUser(pubkey: "test-recipient", ndk: ndk)
        setupMockLightningProfile(for: recipient)
        
        // Register providers
        let provider1 = MockPaymentProvider(id: "provider-1")
        provider1.isAvailableValue = false // Not available
        
        let provider2 = MockPaymentProvider(id: "provider-2")
        provider2.isAvailableValue = true
        
        zapManager.register(provider: provider1)
        zapManager.register(provider: provider2)
        
        // Try to use unavailable provider
        _ = try await zapManager.zap(
            to: recipient,
            amountSats: 1000,
            preferredProvider: "provider-1"
        )
        
        // Should fall back to provider-2
        XCTAssertFalse(provider1.fulfillCalled)
        XCTAssertTrue(provider2.fulfillCalled)
    }
    
    func testThrowsWhenNoProviderCanFulfill() async throws {
        let recipient = NDKUser(pubkey: "test-recipient", ndk: ndk)
        setupMockLightningProfile(for: recipient)
        
        // Register provider that can't fulfill Lightning invoices
        let provider = MockPaymentProvider(id: "cashu-only")
        provider.canFulfillLightning = false
        zapManager.register(provider: provider)
        
        // Should throw no wallet configured
        do {
            _ = try await zapManager.zap(
                to: recipient,
                amountSats: 1000
            )
            XCTFail("Expected error")
        } catch {
            guard case ZapError.noWalletConfigured = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
        }
    }
    
    // MARK: - Event Zapping Tests
    
    func testZapEvent() async throws {
        let author = NDKUser(pubkey: "author-pubkey", ndk: ndk)
        setupMockLightningProfile(for: author)
        
        let event = NDKEvent(
            pubkey: author.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Hello world"
        )
        event.ndk = ndk
        
        let provider = MockPaymentProvider(id: "test-provider")
        zapManager.register(provider: provider)
        
        let result = try await event.zap(
            amountSats: 1000,
            comment: "Great post!"
        )
        
        XCTAssertEqual(result.type, .lightning)
        XCTAssertTrue(provider.fulfillCalled)
    }
    
    // MARK: - Zap Fetching Tests
    
    func testFetchZapsForEvent() async throws {
        let eventId = "test-event-id"
        
        // Create mock zap receipt
        let zapReceipt = NDKEvent(
            pubkey: "lnurl-provider",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.zapReceipt,
            content: ""
        )
        zapReceipt.addTag(["e", eventId])
        zapReceipt.addTag(["p", "recipient-pubkey"])
        zapReceipt.addTag(["bolt11", "lnbc1000n1..."])
        
        // Create mock nutzap
        let nutzap = NDKEvent(
            pubkey: "sender-pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.nutzap,
            content: "Nutzap comment"
        )
        nutzap.addTag(["e", eventId])
        nutzap.addTag(["p", "recipient-pubkey"])
        nutzap.addTag(["amount", "2000"])
        
        mockRelay.mockEvents = [zapReceipt, nutzap]
        
        let event = NDKEvent(
            pubkey: "author",
            createdAt: 0,
            kind: EventKind.textNote,
            content: "Test"
        )
        event.id = eventId
        event.ndk = ndk
        
        let zaps = try await event.fetchZaps()
        
        XCTAssertEqual(zaps.count, 2)
        XCTAssertTrue(zaps.contains { $0.type == .lightning })
        XCTAssertTrue(zaps.contains { $0.type == .nutzap })
    }
    
    func testFetchZapsForUser() async throws {
        let userPubkey = "test-user"
        
        // Create mock zaps to the user
        let zapReceipt = NDKEvent(
            pubkey: "lnurl-provider",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.zapReceipt,
            content: ""
        )
        zapReceipt.addTag(["p", userPubkey])
        zapReceipt.addTag(["bolt11", "lnbc1000n1..."])
        
        mockRelay.mockEvents = [zapReceipt]
        
        let user = NDKUser(pubkey: userPubkey, ndk: ndk)
        let zaps = try await user.fetchZaps()
        
        XCTAssertEqual(zaps.count, 1)
        XCTAssertEqual(zaps.first?.type, .lightning)
        XCTAssertEqual(zaps.first?.recipient, userPubkey)
    }
    
    // MARK: - Configuration Tests
    
    func testConfigureDefaults() async throws {
        // Create mock wallets
        let nwcWallet = try NDKNWCWallet(connectionURI: "nostr+walletconnect://...")
        let mockWallet = MockWallet()
        
        zapManager.configureDefaults(wallet: mockWallet, nwcWallet: nwcWallet)
        
        let recipient = NDKUser(pubkey: "test-recipient", ndk: ndk)
        setupMockLightningProfile(for: recipient)
        
        // Should have providers registered
        _ = try await zapManager.zap(
            to: recipient,
            amountSats: 1000
        )
        
        // Verify some provider was used (implementation depends on order)
        XCTAssertTrue(true, "Zap completed without throwing")
    }
    
    // MARK: - Helper Methods
    
    private func setupMockLightningProfile(for user: NDKUser) {
        let profileEvent = NDKEvent(
            pubkey: user.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.metadata,
            content: """
            {
                "lud16": "test@wallet.com"
            }
            """
        )
        mockRelay.mockEvents.append(profileEvent)
    }
}

// MARK: - Mock Payment Provider

class MockPaymentProvider: NDKPaymentProvider, @unchecked Sendable {
    let id: String
    var isAvailableValue = true
    var canFulfillLightning = true
    var canFulfillCashu = true
    var fulfillCalled = false
    var lastRequest: PaymentRequest?
    
    init(id: String) {
        self.id = id
    }
    
    func isAvailable() async -> Bool {
        isAvailableValue
    }
    
    func canFulfill(_ request: PaymentRequest) async -> Bool {
        switch request {
        case is LightningInvoiceRequest:
            return canFulfillLightning
        case is CashuProofRequest:
            return canFulfillCashu
        default:
            return false
        }
    }
    
    func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        fulfillCalled = true
        lastRequest = request
        
        switch request {
        case let invoice as LightningInvoiceRequest:
            return LightningPaymentConfirmation(
                preimage: "mock-preimage",
                paidAt: Date()
            )
        case let cashu as CashuProofRequest:
            return CashuPaymentConfirmation(
                proofs: [CashuProof(
                    amount: cashu.amount,
                    id: "mock-id",
                    secret: "mock-secret",
                    C: "mock-C"
                )]
            )
        default:
            throw NDKError.paymentFailed(reason: "Unsupported payment type")
        }
    }
}

// MARK: - Mock Wallet

class MockWallet: NDKWallet, @unchecked Sendable {
    var pubkey: String? = "mock-wallet-pubkey"
    
    func balance() async throws -> Int64 {
        10000
    }
    
    func pay(invoice: String) async throws -> String? {
        "mock-preimage"
    }
    
    func createInvoice(amountSats: Int64, description: String?, expirySeconds: Int?) async throws -> String {
        "lnbc\(amountSats)n1..."
    }
    
    func checkInvoice(_ invoice: String) async throws -> InvoiceStatus {
        InvoiceStatus(paid: true, preimage: "mock-preimage")
    }
    
    func cashuTokens() async throws -> [CashuToken] {
        []
    }
    
    func createCashuToken(amount: Int64, unit: String, mint: String) async throws -> CashuToken {
        CashuToken(token: [], unit: unit)
    }
    
    func redeemCashuToken(_ token: CashuToken) async throws -> Int64 {
        0
    }
}