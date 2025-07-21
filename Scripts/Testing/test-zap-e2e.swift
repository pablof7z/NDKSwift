#!/usr/bin/env swift

import Foundation
@testable import NDKSwift

// Run Zap E2E tests as a standalone script
@main
struct ZapE2ERunner {
    static func main() async throws {
        NDKLogger.log(.info, category: .general, "Starting Zap Flow E2E Tests")
        NDKLogger.logLevel = .debug
        
        do {
            // Test Lightning zaps
            NDKLogger.log(.info, category: .general, "\n=== Running Lightning Zap E2E Test ===")
            try await testLightningZapFlow()
            NDKLogger.log(.info, category: .general, "✅ Lightning Zap E2E test passed")
            
            // Test Nutzaps
            NDKLogger.log(.info, category: .general, "\n=== Running Nutzap E2E Test ===")
            try await testNutzapFlow()
            NDKLogger.log(.info, category: .general, "✅ Nutzap E2E test passed")
            
            NDKLogger.log(.info, category: .general, "\n✅ All Zap E2E tests passed!")
            
        } catch {
            NDKLogger.log(.error, category: .general, "❌ Test failed with error: \(error)")
            exit(1)
        }
    }
    
    static func testLightningZapFlow() async throws {
        let startTime = Date()
        NDKLogger.log(.info, category: .wallet, "🧪 Starting Lightning Zap E2E test")
        
        // Test configuration
        let testRelays = ["wss://relay.damus.io", "wss://relay.nostr.band", "wss://nos.lol"]
        
        // Create NDK instances
        let zapperNDK = NDK(cache: MemoryCache())
        let recipientNDK = NDK(cache: MemoryCache())
        
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
        
        await NDKLogger.logTiming(.debug, category: .connection, operation: "Connecting to relays") {
            await zapperNDK.connect()
            await recipientNDK.connect()
        }
        
        let zapperConnected = await zapperNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        let recipientConnected = await recipientNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        guard zapperConnected > 0 && recipientConnected > 0 else {
            throw TestError.connectionFailed
        }
        
        NDKLogger.log(.info, category: .connection, "✅ Connected to \(zapperConnected) and \(recipientConnected) relays")
        
        // Publish recipient profile with LNURL
        let lnurl = "LNURL1DP68GURN8GHJ7AMPD3KX2AR0VEEKZAR0WD5XJTNRDAKJ7TNHV4KXCTTTDEHHWM30D3H82UNVWQHKGATJDEJHY6T5WYHXXMMD9AKXUATJDSHHVVRGW3SHYETNWSS8G6RPVDKX2TFKVENX7APWVDHK6TMHD96XJER9D4SKX7E3VD9N8JTNRDAKJ7MR0VA5KUZP0V4JZUCM0D5HSXCT89E3K7MF0WCCSZ3J9W35HXAR4VF4XXCTVDFSHGTNFDUHSZYTHWDEN5TE0DEHHXARJ9EMKJMN99UHK6MR99E3KJMN99UHK6MR9VEJK2MN99UH8WETVDSKKKMN0WAHXJMMWDAEHGUN4V5HXXMR0DAHXUETW9E3K7MF0WCCSZ3MR9S4HQCTZD3HKVDNHXVMK2DPN8YMRSTNHXA3KXCT5D93KKEFSXGCKXDPNXVMXXVEJV3JHXDNRX9JXXER9V9JKZCE3V3NXVVFE8YUXZDMPX5ERGVFKVYMNQWF4VFSKGDF4V4JRZTF4XAJRGTPSXQCRQVPSXQCRQVPSXQCRQVPSXQCRQVPSXQCRQVPS"
        
        let profileContent = """
        {
            "name": "Test Recipient",
            "about": "E2E test recipient for zaps",
            "lud16": "test@getalby.com",
            "lud06": "\(lnurl)"
        }
        """
        
        let profileEvent = try await recipientNDK.event()
            .content(profileContent)
            .kind(EventKind.metadata)
            .build()
        
        let profileRelays = try await NDKLogger.logTiming(.debug, category: .event, operation: "Publishing profile") {
            try await recipientNDK.publish(profileEvent)
        }
        NDKLogger.log(.info, category: .event, "Published recipient profile to \(profileRelays.count) relays")
        
        // Wait for profile to propagate
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Create a text note to zap
        let noteContent = "Test note for zapping - \(UUID().uuidString)"
        let noteEvent = try await recipientNDK.event()
            .content(noteContent)
            .kind(EventKind.textNote)
            .build()
        
        let noteRelays = try await recipientNDK.publish(noteEvent)
        NDKLogger.log(.info, category: .event, "Published note to zap: \(noteEvent.id) to \(noteRelays.count) relays")
        
        // Subscribe to zap receipts
        let zapReceiptFilter = NDKFilter(
            kinds: [EventKind.zapReceipt],
            limit: 50
        )
        
        var receivedZapReceipt: NDKEvent?
        let subscription = zapperNDK.subscribe(filter: zapReceiptFilter)
        
        Task {
            NDKLogger.log(.debug, category: .subscription, "Listening for zap receipts...")
            for await event in subscription {
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
        
        // Create zap request
        NDKLogger.log(.info, category: .wallet, "Creating zap request...")
        
        let zapProtocol = NDKLightningZapProtocol()
        
        // Create zap request event
        let zapRequest = try await NDKLogger.logTiming(.debug, category: .wallet, operation: "Creating zap request") {
            try await zapProtocol.prepareZap(
                ndk: zapperNDK,
                target: .note(noteEvent),
                amount: 1000, // 1 sat
                comment: "Test zap from E2E",
                relays: testRelays
            )
        }
        
        NDKLogger.log(.debug, category: .wallet, "Created zap request: \(zapRequest.id)")
        
        // Since we can't actually pay with Lightning in E2E test,
        // we'll simulate the flow by creating a mock zap receipt
        let mockReceipt = try await createMockZapReceipt(
            for: zapRequest,
            targetEvent: noteEvent,
            amount: 1000,
            signer: zapperSigner
        )
        
        // Publish the mock receipt
        let receiptRelays = try await zapperNDK.publish(mockReceipt)
        NDKLogger.log(.info, category: .event, "Published mock zap receipt to \(receiptRelays.count) relays")
        
        // Wait for the receipt to be received via subscription
        let timeout = Date().addingTimeInterval(15.0)
        while receivedZapReceipt == nil && Date() < timeout {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let receipt = receivedZapReceipt else {
            throw TestError.zapReceiptNotReceived
        }
        
        // Verify receipt
        guard receipt.id == mockReceipt.id else {
            throw TestError.wrongZapReceipt
        }
        
        NDKLogger.log(.info, category: .wallet, "✅ Lightning Zap E2E test completed successfully in \(Date().timeIntervalSince(startTime))s")
        
        // Cleanup
        subscription.close()
        await zapperNDK.disconnect()
        await recipientNDK.disconnect()
    }
    
    static func testNutzapFlow() async throws {
        let startTime = Date()
        NDKLogger.log(.info, category: .wallet, "🧪 Starting Nutzap E2E test")
        
        let testRelays = ["wss://relay.damus.io", "wss://relay.nostr.band", "wss://nos.lol"]
        
        let zapperNDK = NDK(cache: MemoryCache())
        let recipientNDK = NDK(cache: MemoryCache())
        
        // Create signers
        let zapperSigner = try NDKPrivateKeySigner.generate()
        let recipientSigner = try NDKPrivateKeySigner.generate()
        zapperNDK.signer = zapperSigner
        recipientNDK.signer = recipientSigner
        
        let zapperPubkey = try await zapperSigner.pubkey
        let recipientPubkey = try await recipientSigner.pubkey
        
        NDKLogger.log(.debug, category: .wallet, "Created test users for nutzap")
        
        // Add relays and connect
        for relay in testRelays {
            await zapperNDK.addRelay(relay)
            await recipientNDK.addRelay(relay)
        }
        
        await zapperNDK.connect()
        await recipientNDK.connect()
        
        let zapperConnected = await zapperNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        let recipientConnected = await recipientNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        guard zapperConnected > 0 && recipientConnected > 0 else {
            throw TestError.connectionFailed
        }
        
        // Publish nutzap preferences for recipient
        let mintUrls = ["https://mint.minibits.cash/Bitcoin", "https://8333.space:3338"]
        let preferences = NDKNutzapPreferences(
            mintUrls: mintUrls,
            relays: testRelays,
            p2pkPubkey: recipientPubkey
        )
        
        let preferencesData = try JSONEncoder().encode(preferences)
        let preferencesContent = String(data: preferencesData, encoding: .utf8)!
        
        let preferencesEvent = try await recipientNDK.event()
            .content(preferencesContent)
            .kind(EventKind.nutzapPreferences)
            .build()
        
        let prefRelays = try await recipientNDK.publish(preferencesEvent)
        NDKLogger.log(.info, category: .event, "Published nutzap preferences to \(prefRelays.count) relays")
        
        // Create a note to nutzap
        let noteEvent = try await recipientNDK.event()
            .content("Test note for nutzapping - \(UUID().uuidString)")
            .kind(EventKind.textNote)
            .build()
        
        let noteRelays = try await recipientNDK.publish(noteEvent)
        NDKLogger.log(.info, category: .event, "Published note to nutzap: \(noteEvent.id)")
        
        // Subscribe to nutzap events
        let nutzapFilter = NDKFilter(
            kinds: [EventKind.nutzap],
            limit: 50
        )
        
        var receivedNutzap: NDKEvent?
        let subscription = recipientNDK.subscribe(filter: nutzapFilter)
        
        Task {
            NDKLogger.log(.debug, category: .subscription, "Listening for nutzaps...")
            for await event in subscription {
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
        
        // Create nutzap event
        let mockProofs = """
        [{"amount":1,"secret":"test_secret_\(UUID().uuidString)","C":"02abc123def456","id":"00ad"}]
        """
        
        let nutzapEvent = try await NDKLogger.logTiming(.debug, category: .wallet, operation: "Creating nutzap") {
            try await zapperNDK.event()
                .content(mockProofs)
                .kind(EventKind.nutzap)
                .tag(["p", recipientPubkey])
                .tag(["e", noteEvent.id])
                .tag(["amount", "1000"])  // 1 sat in millisats
                .tag(["u", mintUrls[0]])
                .tag(["comment", "Test nutzap from E2E"])
                .build()
        }
        
        let nutzapRelays = try await zapperNDK.publish(nutzapEvent)
        NDKLogger.log(.info, category: .event, "Published nutzap to \(nutzapRelays.count) relays")
        
        // Wait for nutzap to be received
        let timeout = Date().addingTimeInterval(15.0)
        while receivedNutzap == nil && Date() < timeout {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        guard let nutzap = receivedNutzap else {
            throw TestError.nutzapNotReceived
        }
        
        guard nutzap.id == nutzapEvent.id else {
            throw TestError.wrongNutzap
        }
        
        NDKLogger.log(.info, category: .wallet, "✅ Nutzap E2E test completed successfully in \(Date().timeIntervalSince(startTime))s")
        
        // Cleanup
        subscription.close()
        await zapperNDK.disconnect()
        await recipientNDK.disconnect()
    }
    
    // Helper function to create mock zap receipt
    static func createMockZapReceipt(
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
        
        let receipt = try NDKEvent(
            content: receiptContent,
            created_at: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.zapReceipt,
            tags: [
                ["p", targetEvent.pubkey],
                ["e", targetEvent.id],
                ["bolt11", "lnbc1pjk9d9xpp5..."], // Mock invoice
                ["description", zapRequest.asJson],
                ["amount", "\(amount)"]
            ]
        )
        
        try await receipt.sign(signer: signer)
        return receipt
    }
}

// Test errors
enum TestError: Error {
    case connectionFailed
    case zapReceiptNotReceived
    case wrongZapReceipt
    case nutzapNotReceived
    case wrongNutzap
}

// Nutzap preferences structure
struct NDKNutzapPreferences: Codable {
    let mintUrls: [String]
    let relays: [String]
    let p2pkPubkey: String
    
    enum CodingKeys: String, CodingKey {
        case mintUrls = "mints"
        case relays
        case p2pkPubkey = "pubkey"
    }
}