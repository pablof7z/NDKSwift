import XCTest
@testable import NDKSwift
import CashuSwift

final class NIP60WalletE2ETests: XCTestCase {
    var ndk: NDK!
    var wallet: NIP60Wallet!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create NDK instance with in-memory cache for testing
        let cache = MemoryCache()
        ndk = NDK(cache: cache)
        
        // Add test relays
        let relay1 = await ndk.pool.addRelay("wss://relay.damus.io")
        let relay2 = await ndk.pool.addRelay("wss://relay.primal.net")
        let relay3 = await ndk.pool.addRelay("wss://relay.nostr.band")
        
        // Connect to relays explicitly
        print("🔌 Connecting to relays...")
        do {
            try await relay1.connect()
            print("   ✅ Connected to \(relay1.url)")
        } catch {
            print("   ❌ Failed to connect to \(relay1.url): \(error)")
        }
        
        do {
            try await relay2.connect()
            print("   ✅ Connected to \(relay2.url)")
        } catch {
            print("   ❌ Failed to connect to \(relay2.url): \(error)")
        }
        
        do {
            try await relay3.connect()
            print("   ✅ Connected to \(relay3.url)")
        } catch {
            print("   ❌ Failed to connect to \(relay3.url): \(error)")
        }
        
        // Wait for connections to establish
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Check connection status
        print("\n📡 Final relay connection status:")
        let allRelays = await ndk.pool.relays
        var connectedCount = 0
        for relay in allRelays {
            if await relay.isConnected {
                connectedCount += 1
                print("   ✅ Connected: \(relay.url)")
            } else {
                print("   ❌ Not connected: \(relay.url)")
            }
        }
        print("   Total connected: \(connectedCount) relay(s)")
    }
    
    override func tearDown() async throws {
        // NDKPool doesn't have a disconnect method
        try await super.tearDown()
    }
    
    func testCreateWalletDepositAndVerify7375Event() async throws {
        // Skip test in CI environment
        #if os(macOS) || os(iOS)
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping e2e test in CI environment")
        }
        #endif
        
        // 1. Create a new pubkey
        let privateKey = Crypto.generatePrivateKey()
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        let pubkey = try await signer.pubkey
        
        print("\n✅ Created new pubkey: \(pubkey)")
        
        // Set signer on NDK
        ndk.signer = signer
        
        // 2. Create a nutsack wallet
        wallet = NIP60Wallet(ndk: ndk)
        
        // Setup wallet with testnut mint
        let testMint = "https://testnut.cashu.space"
        let relays = ["wss://relay.damus.io", "wss://relay.primal.net"]
        
        // Track wallet setup publishing
        print("\n📤 Setting up wallet...")
        try await wallet.setup(
            mints: [testMint],
            relays: relays,
            publishMintList: false
        )
        
        print("✅ Created nutsack wallet with testnut mint")
        
        // Wait for wallet setup to propagate
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // 3. Create a deposit on testnut.cashu.space for a random amount
        let randomAmount = Int64.random(in: 21...100) // Random sats between 21-100
        print("\n🎲 Creating deposit for \(randomAmount) sats")
        
        let quote = try await wallet.requestMint(
            amount: randomAmount,
            mintURL: testMint,
            persistQuote: true
        )
        
        print("⚡ Lightning invoice created")
        print("📋 Quote ID: \(quote.quoteId)")
        
        // Create expectation for 7375 event
        let eventExpectation = expectation(description: "7375 event published")
        var received7375Event: NDKEvent?
        var publishedRelays: Set<String> = []
        
        // Subscribe to monitor for 7375 events
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.cashuToken]
        )
        
        // Create subscription to all connected relays
        let subscription = await ndk.subscribe(filters: [filter], closeOnEose: false)
        
        // Track which relays send us the event
        Task {
            do {
                for try await event in subscription {
                    if event.kind == EventKind.cashuToken {
                        print("\n📨 Received 7375 event: \(event.id)")
                        received7375Event = event
                        
                        // Give time for event to propagate to other relays
                        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                        eventExpectation.fulfill()
                    }
                }
            } catch {
                print("❌ Subscription error: \(error)")
            }
        }
        
        // 4. Monitor deposit status
        print("\n⏳ Monitoring deposit (testnut auto-settles)...")
        
        let depositStream = await wallet.monitorDeposit(
            quote: quote,
            pollingInterval: 3.0,
            timeout: 60.0 // 1 minute timeout
        )
        
        var depositCompleted = false
        
        do {
            for try await status in depositStream {
                switch status {
                case .pending:
                    print("⏳ Deposit pending...")
                case .minted(let proofs):
                    print("✅ Deposit completed! Received \(proofs.count) proofs")
                    depositCompleted = true
                case .expired:
                    XCTFail("Deposit expired before payment")
                case .cancelled:
                    XCTFail("Deposit was cancelled")
                }
            }
        } catch {
            if !depositCompleted {
                XCTFail("Deposit monitoring error: \(error)")
            }
        }
        
        // 5. Wait for and validate the 7375 event
        await fulfillment(of: [eventExpectation], timeout: 30.0)
        
        XCTAssertNotNil(received7375Event, "Should have received a 7375 event")
        
        if let event = received7375Event {
            // Verify event properties
            XCTAssertEqual(event.kind, EventKind.cashuToken)
            XCTAssertEqual(event.pubkey, pubkey)
            
            // Check that it's encrypted
            XCTAssertFalse(event.content.isEmpty, "Event should have encrypted content")
            print("\n✅ Event has encrypted content of length: \(event.content.count)")
            
            // Manual verification: Try to fetch the event directly from each relay
            print("\n🔍 Verifying event publication by fetching from each relay...")
            let verifyFilter = NDKFilter(ids: [event.id])
            
            // Check each relay individually
            let allRelays = await ndk.pool.relays
            print("Checking \(allRelays.count) relay(s):")
            
            for relay in allRelays {
                guard await relay.isConnected else {
                    print("   ⏭️ Skipping disconnected relay: \(relay.url)")
                    continue
                }
                // Fetch from specific relay
                let relaySet = Set([relay.url])
                do {
                    if let _ = try await ndk.fetchEvent(verifyFilter, relays: relaySet, timeoutSeconds: 5) {
                        publishedRelays.insert(relay.url)
                        print("   ✅ Found event on \(relay.url)")
                    } else {
                        print("   ❌ NOT found on \(relay.url)")
                    }
                } catch {
                    print("   ❌ Error fetching from \(relay.url): \(error)")
                }
            }
            
            print("\n📊 Event publication summary:")
            print("   - Event ID: \(event.id)")
            print("   - Published to \(publishedRelays.count) relay(s):")
            for relay in publishedRelays {
                print("     ✅ \(relay)")
            }
            
            XCTAssertFalse(publishedRelays.isEmpty, "Event should be published to at least one relay")
        }
        
        // Check final wallet balance
        let balance = try await wallet.getBalance()
        XCTAssertEqual(balance, randomAmount, "Wallet balance should match deposited amount")
        print("\n💰 Final wallet balance: \(balance ?? 0) sats")
        
        print("\n🎉 E2E test completed successfully!")
        print("   - Created new keypair")
        print("   - Created nutsack wallet") 
        print("   - Deposited \(randomAmount) sats via Lightning")
        print("   - Verified 7375 event was created")
        print("   - Event published to \(publishedRelays.count) relay(s)")
    }
}