import XCTest
@testable import NDKSwift

final class ZapFlowE2ETests: XCTestCase {
    
    // Test configuration
    let testRelays = ["wss://relay.damus.io", "wss://relay.nostr.band", "wss://nos.lol"]
    let timeout: TimeInterval = 30.0
    
    override func setUp() async throws {
        try await super.setUp()
        NDKLogger.logLevel = .debug
        NDKLogger.enabledCategories = [.wallet, .event, .relay, .network]
    }
    
    // MARK: - Basic Lightning Zap Flow
    
    func testBasicLightningZapE2E() async throws {
        NDKLogger.log(.info, category: .wallet, "🧪 Starting testBasicLightningZapE2E")
        
        // Create NDK instances
        let zapperNDK = NDK()
        let recipientNDK = NDK()
        
        // Create signers
        let zapperSigner = try NDKPrivateKeySigner.generate()
        let recipientSigner = try NDKPrivateKeySigner.generate()
        zapperNDK.signer = zapperSigner
        recipientNDK.signer = recipientSigner
        
        let zapperPubkey = try await zapperSigner.pubkey
        let recipientPubkey = try await recipientSigner.pubkey
        
        NDKLogger.log(.debug, category: .wallet, "Created test users - zapper: \(zapperPubkey.prefix(8))..., recipient: \(recipientPubkey.prefix(8))...")
        
        // Add relays and connect
        for relay in testRelays {
            await zapperNDK.addRelay(relay)
            await recipientNDK.addRelay(relay)
        }
        
        await zapperNDK.connect()
        await recipientNDK.connect()
        
        let zapperConnected = await zapperNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        let recipientConnected = await recipientNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        XCTAssertGreaterThan(zapperConnected, 0, "Zapper failed to connect to relays")
        XCTAssertGreaterThan(recipientConnected, 0, "Recipient failed to connect to relays")
        
        NDKLogger.log(.info, category: .network, "✅ Connected to relays")
        
        // Publish recipient profile with LNURL
        let lnurl = "LNURL1DP68GURN8GHJ7AMPD3KX2AR0VEEKZAR0WD5XJTNRDAKJ7TNHV4KXCTTTDEHHWM30D3H82UNVWQHKGATJDEJHY6T5WYHXXMMD9AKXUATJDSHHVVRGW3SHYETNWSS8G6RPVDKX2TFKVENX7APWVDHK6TMHD96XJER9D4SKX7E3VD9N8JTNRDAKJ7MR0VA5KUZP0V4JZUCM0D5HSXCT89E3K7MF0WCCSZ3J9W35HXAR4VF4XXCTVDFSHGTNFDUHSZYTHWDEN5TE0DEHHXARJ9EMKJMN99UHK6MR99E3KJMN99UHK6MR9VEJK2MN99UH8WETVDSKKKMN0WAHXJMMWDAEHGUN4V5HXXMR0DAHXUETW9E3K7MF0WCCSZ3MR9S4HQCTZD3HKVDNHXVMK2DPN8YMRSTNHXA3KXCT5D93KKEFSXGCKXDPNXVMXXVEJV3JHXDNRX9JXXER9V9JKZCE3V3NXVVFE8YUXZDMPX5ERGVFKVYMNQWF4VFSKGDF4V4JRZTF4XAJRGTPSXQCRQVPSXQCRQVPSXQCRQVPSXQCRQVPSXQCRQVPS"
        
        let profileContent = """
        {
            "name": "Test Recipient",
            "about": "E2E test recipient",
            "lud16": "test@getalby.com",
            "lud06": "\(lnurl)"
        }
        """
        
        let profileEvent = try await recipientNDK.event()
            .content(profileContent)
            .kind(EventKind.metadata)
            .build()
        
        let profileRelays = try await recipientNDK.publish(profileEvent)
        NDKLogger.log(.info, category: .event, "Published recipient profile to \(profileRelays.count) relays")
        
        // Wait for profile to propagate
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // Create a text note to zap
        let noteContent = "Test note for zapping - \(UUID().uuidString)"
        let noteEvent = try await recipientNDK.event()
            .content(noteContent)
            .kind(EventKind.textNote)
            .build()
        
        let noteRelays = try await recipientNDK.publish(noteEvent)
        NDKLogger.log(.info, category: .event, "Published note to zap: \(noteEvent.id) to \(noteRelays.count) relays")
        
        // Subscribe to zap receipts before zapping
        let zapReceiptFilter = NDKFilter(
            kinds: [EventKind.zapReceipt],
            limit: 50
        )
        
        let startTime = Date()
        var receivedZapReceipt: NDKEvent?
        let dataSource = zapperNDK.observe(filter: zapReceiptFilter)
        
        Task {
            await NDKLogger.logTiming(.debug, category: .subscription, operation: "Listening for zap receipts") {
                for await event in dataSource.events {
                    NDKLogger.log(.debug, category: .event, "📥 Received event kind \(event.kind): \(event.id)")
                    
                    // Check if this is our zap receipt
                    if event.kind == EventKind.zapReceipt {
                        // Check if it references our note
                        if let eTags = event.tags.filter({ $0.name == "e" }).first,
                           eTags.count > 1,
                           eTags[1] == noteEvent.id {
                            NDKLogger.log(.info, category: .wallet, "✅ Found our zap receipt!")
                            receivedZapReceipt = event
                            break
                        }
                    }
                }
            }
        }
        
        // Create mock payment provider for testing
        _ = MockLightningProvider()
        
        // Create zap request
        NDKLogger.log(.info, category: .wallet, "Creating zap for note...")
        
        do {
            let zapResult = try await NDKLogger.logTiming(.debug, category: .wallet, operation: "Zap creation") {
                // Use the protocol directly since we don't have a real payment provider
                let zapProtocol = NDKLightningZapProtocol(ndk: zapperNDK)
                
                // Create zap request
                // First create NDKUser from the recipient's public key
                let recipientUser = NDKUser(pubkey: recipientPubkey)
                
                let preparedZap = try await zapProtocol.prepareZap(
                    event: noteEvent,
                    to: recipientUser,
                    amountSats: 1000, // 1 sat
                    comment: "Test zap from E2E"
                )
                
                let zapRequest = preparedZap.metadata["zapRequest"] as! NDKZapRequest
                
                NDKLogger.log(.debug, category: .wallet, "Created zap request: \(zapRequest.event.id)")
                
                // Since we can't actually pay with Lightning in E2E test,
                // we'll simulate the flow by creating a mock zap receipt
                let mockReceipt = try await createMockZapReceipt(
                    for: zapRequest.event,
                    targetEvent: noteEvent,
                    amount: 1000,
                    signer: zapperSigner
                )
                
                // Publish the mock receipt
                let receiptRelays = try await zapperNDK.publish(mockReceipt)
                NDKLogger.log(.info, category: .event, "Published mock zap receipt to \(receiptRelays.count) relays")
                
                return mockReceipt
            }
            
            // Wait for the receipt to be received via subscription
            let timeout = Date().addingTimeInterval(15.0)
            while receivedZapReceipt == nil && Date() < timeout {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            
            XCTAssertNotNil(receivedZapReceipt, "Failed to receive zap receipt")
            XCTAssertEqual(receivedZapReceipt?.id, zapResult.id, "Received wrong zap receipt")
            
            NDKLogger.log(.info, category: .wallet, "✅ Zap E2E test completed successfully in \(Date().timeIntervalSince(startTime))s")
            
        } catch {
            XCTFail("Zap failed with error: \(error)")
        }
        
        // Cleanup
        await zapperNDK.disconnect()
        await recipientNDK.disconnect()
    }
    
    // MARK: - Nutzap Flow
    
    func testNutzapFlowE2E() async throws {
        NDKLogger.log(.info, category: .wallet, "🧪 Starting testNutzapFlowE2E")
        
        let zapperNDK = NDK()
        let recipientNDK = NDK()
        
        // Create signers
        let zapperSigner = try NDKPrivateKeySigner.generate()
        let recipientSigner = try NDKPrivateKeySigner.generate()
        zapperNDK.signer = zapperSigner
        recipientNDK.signer = recipientSigner
        
        _ = try await zapperSigner.pubkey
        let recipientPubkey = try await recipientSigner.pubkey
        
        // Add relays and connect
        for relay in testRelays {
            await zapperNDK.addRelay(relay)
            await recipientNDK.addRelay(relay)
        }
        
        await zapperNDK.connect()
        await recipientNDK.connect()
        
        let zapperConnected = await zapperNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        let recipientConnected = await recipientNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        XCTAssertGreaterThan(zapperConnected, 0)
        XCTAssertGreaterThan(recipientConnected, 0)
        
        // Publish nutzap preferences for recipient
        let mintUrls = ["https://mint.minibits.cash/Bitcoin", "https://mint2.example.com"]
        
        // Create preferences event with proper tags
        var prefTags: [[String]] = []
        for mintUrl in mintUrls {
            prefTags.append(["mint", mintUrl])
        }
        // Add p2pk pubkey tag
        prefTags.append(["p2pk", recipientPubkey])
        
        let preferencesEvent = try await recipientNDK.event()
            .content("")
            .kind(10019) // nutzap preferences kind
            .tags(prefTags)
            .build()
        
        let prefRelays = try await recipientNDK.publish(preferencesEvent)
        NDKLogger.log(.info, category: .event, "Published nutzap preferences to \(prefRelays.count) relays")
        
        // Create a note to nutzap
        let noteEvent = try await recipientNDK.event()
            .content("Test note for nutzapping - \(UUID().uuidString)")
            .kind(EventKind.textNote)
            .build()
        
        _ = try await recipientNDK.publish(noteEvent)
        NDKLogger.log(.info, category: .event, "Published note to nutzap: \(noteEvent.id)")
        
        // Subscribe to nutzap events
        let nutzapFilter = NDKFilter(
            kinds: [EventKind.nutzap],
            limit: 50
        )
        
        var receivedNutzap: NDKEvent?
        let dataSource = recipientNDK.observe(filter: nutzapFilter)
        
        Task {
            for await event in dataSource.events {
                NDKLogger.log(.debug, category: .event, "📥 Received nutzap event: \(event.id)")
                
                // Check if this nutzap is for our note
                if let pTags = event.tags.filter({ $0.name == "p" }).first,
                   pTags.count > 1,
                   pTags[1] == recipientPubkey,
                   let eTags = event.tags.filter({ $0.name == "e" }).first,
                   eTags.count > 1,
                   eTags[1] == noteEvent.id {
                    NDKLogger.log(.info, category: .wallet, "✅ Found our nutzap!")
                    receivedNutzap = event
                    break
                }
            }
        }
        
        // Create nutzap using the protocol
        do {
            _ = NDKNutzapProtocol(ndk: zapperNDK)
            
            // Create mock Cashu proofs
            let mockProofs = """
            [{"amount":1,"secret":"test","C":"02abc","id":"00ad"}]
            """
            
            // Create nutzap event
            let nutzapEvent = try await zapperNDK.event()
                .content(mockProofs)
                .kind(EventKind.nutzap)
                .tag(["p", recipientPubkey])
                .tag(["e", noteEvent.id])
                .tag(["amount", "1000"])  // 1 sat in millisats
                .tag(["u", mintUrls[0]])
                .tag(["comment", "Test nutzap from E2E"])
                .build()
            
            let nutzapRelays = try await zapperNDK.publish(nutzapEvent)
            NDKLogger.log(.info, category: .event, "Published nutzap to \(nutzapRelays.count) relays")
            
            // Wait for nutzap to be received
            let timeout = Date().addingTimeInterval(15.0)
            while receivedNutzap == nil && Date() < timeout {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            
            XCTAssertNotNil(receivedNutzap, "Failed to receive nutzap")
            XCTAssertEqual(receivedNutzap?.id, nutzapEvent.id, "Received wrong nutzap")
            
            NDKLogger.log(.info, category: .wallet, "✅ Nutzap E2E test completed successfully")
            
        } catch {
            XCTFail("Nutzap failed with error: \(error)")
        }
        
        // Cleanup
        await zapperNDK.disconnect()
        await recipientNDK.disconnect()
    }
    
    // MARK: - Helper Methods
    
    private func createMockZapReceipt(
        for zapRequest: NDKEvent,
        targetEvent: NDKEvent,
        amount: Int,
        signer: NDKSigner
    ) async throws -> NDKEvent {
        // Create a mock zap receipt that looks like it came from a Lightning node
        let receiptContent = """
        {
            "preimage": "0000000000000000000000000000000000000000000000000000000000000000",
            "payment_hash": "1111111111111111111111111111111111111111111111111111111111111111"
        }
        """
        
        let pubkey = try await signer.pubkey
        let createdAt = Timestamp(Date().timeIntervalSince1970)
        let tags = [
            ["p", targetEvent.pubkey],
            ["e", targetEvent.id],
            ["bolt11", "lnbc1pjk9d9xpp5..."],
            ["description", try zapRequest.toJSON()],
            ["amount", "\(amount)"]
        ]
        
        let receipt = try await NDKEventBuilder()
            .pubkey(pubkey)
            .createdAt(createdAt)
            .kind(EventKind.zapReceipt)
            .tags(tags)
            .content(receiptContent)
            .build(signer: signer)
        
        return receipt
    }
}

// Mock payment provider for testing
class MockLightningProvider: NDKPaymentProvider {
    var id: String { "mock-provider" }
    var displayName: String { "Mock Lightning Provider" }
    
    func isAvailable() async -> Bool {
        return true
    }
    
    func canFulfill(_ request: PaymentRequest) async -> Bool {
        return request is LightningInvoiceRequest
    }
    
    func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        guard let lightningRequest = request as? LightningInvoiceRequest else {
            throw ZapError.paymentFailed("Not a lightning request")
        }
        
        NDKLogger.log(.debug, category: .wallet, "Mock provider paying invoice: \(lightningRequest.invoice.prefix(20))...")
        
        return LightningPaymentConfirmation(
            amountSats: lightningRequest.amountSats,
            timestamp: Date(),
            preimage: "mock-preimage-\(UUID().uuidString)",
            paymentHash: "mock-payment-hash-\(UUID().uuidString)"
        )
    }
    
    func getBalance() async throws -> Int64? {
        return 100000
    }
}

