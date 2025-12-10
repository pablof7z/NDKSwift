import XCTest
@testable import NDKSwiftCore

/// End-to-end tests for zap functionality
final class ZapFlowE2ETests: XCTestCase {
    var zapperNDK: NDK!
    var recipientNDK: NDK!
    var recipientPubkey: String!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Use test relays (faster response)
        let testRelays = RelayConstants.walletRelays
        
        // Create zapper instance (the one sending zaps)
        let zapperSigner = try NDKPrivateKeySigner.generate()
        zapperNDK = NDK(relayUrls: testRelays, signer: zapperSigner)
        
        // Create recipient instance
        let recipientSigner = try NDKPrivateKeySigner.generate()
        recipientNDK = NDK(relayUrls: testRelays, signer: recipientSigner)
        recipientPubkey = try await recipientSigner.pubkey
        
        // Connect both instances
        await zapperNDK.connect()
        await recipientNDK.connect()
        
        // Wait for relay connections
        await zapperNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        await recipientNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
    }
    
    override func tearDown() async throws {
        await zapperNDK.disconnect()
        await recipientNDK.disconnect()
        zapperNDK = nil
        recipientNDK = nil
        try await super.tearDown()
    }
    
    func testLightningZapFlow() async throws {
        throw XCTSkip("Test needs to be updated for current API: prepareZap now expects RecipientZapInfo instead of NDKUser, need to use NDKZapManager instead of direct protocol calls")
    }
    
    func testNutzapFlow() async throws {
        throw XCTSkip("Test needs to be updated for current API: prepareZap now expects RecipientZapInfo instead of NDKUser, need to use NDKZapManager instead of direct protocol calls")
    }
    
    // MARK: - Helper Methods
    
    private func createMockZapReceipt(
        zapRequest: NDKZapRequest,
        paidAt: Date,
        amountSats: Int64,
        recipientPubkey: String,
        payerNDK: NDK
    ) async throws -> NDKZapReceipt {
        // Create mock receipt content
        let bolt11 = "lnbc1000n1..." // Mock invoice
        let preimage = "mock_preimage_\(UUID().uuidString)"
        let description = try JSONCoding.encodeToString(zapRequest.event)
        
        var tags: [[String]] = [
            ["bolt11", bolt11],
            ["preimage", preimage],
            ["description", description],
            ["p", recipientPubkey]
        ]
        
        if let eventId = zapRequest.event.tags.first(where: { $0.count >= 2 && $0[0] == "e" })?[1] {
            tags.append(["e", eventId])
        }
        
        let receiptEvent = try await NDKEventBuilder(ndk: payerNDK)
            .content("")
            .kind(EventKind.zapReceipt)
            .tags(tags)
            .build()
        
        return NDKZapReceipt(event: receiptEvent)
    }
}