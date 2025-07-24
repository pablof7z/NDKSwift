import XCTest
@testable import NDKSwift
import CashuSwift

final class NIP60NutzapE2ETests: XCTestCase {
    
    func testSimple() throws {
        print("Simple test running!")
        XCTAssertTrue(true)
    }
    var ndk1: NDK!
    var ndk2: NDK!
    var wallet1: NIP60Wallet!
    var wallet2: NIP60Wallet!
    var signer1: NDKPrivateKeySigner!
    var signer2: NDKPrivateKeySigner!
    var pubkey1: String!
    var pubkey2: String!
    
    override func setUp() async throws {
        print("\n🚀 NIP60NutzapE2ETests setUp() starting...")
        try await super.setUp()
        
        // Skip test in CI environment
        #if os(macOS) || os(iOS)
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            print("⏭️ Skipping test - CI environment detected")
            throw XCTSkip("Skipping e2e test in CI environment")
        }
        #endif
        print("✅ Not in CI environment, proceeding with test")
        
        // 1. Create two pubkeys
        signer1 = try NDKPrivateKeySigner.generate()
        signer2 = try NDKPrivateKeySigner.generate()
        
        pubkey1 = try await signer1.pubkey
        pubkey2 = try await signer2.pubkey
        
        print("✅ Created two pubkeys:")
        print("   Pubkey1: \(pubkey1!)")
        print("   Pubkey2: \(pubkey2!)")
        
        // Create separate NDK instances with in-memory cache
        let cache1 = MemoryCache()
        let cache2 = MemoryCache()
        
        ndk1 = NDK(cache: cache1)
        ndk2 = NDK(cache: cache2)
        
        ndk1.signer = signer1
        ndk2.signer = signer2
        
        // Add test relays to both NDK instances
        let relay1_1 = await ndk1.pool.addRelay(RelayConstants.damus)
        let relay1_2 = await ndk1.pool.addRelay(RelayConstants.primal)
        let relay1_3 = await ndk1.pool.addRelay(RelayConstants.nostrBand)
        
        let relay2_1 = await ndk2.pool.addRelay(RelayConstants.damus)
        let relay2_2 = await ndk2.pool.addRelay(RelayConstants.primal)
        let relay2_3 = await ndk2.pool.addRelay(RelayConstants.nostrBand)
        
        // Connect to relays explicitly
        print("🔌 Connecting relays for NDK1...")
        let relays1 = [relay1_1, relay1_2, relay1_3]
        for relay in relays1 {
            try? await relay.connect()
        }
        
        print("🔌 Connecting relays for NDK2...")
        let relays2 = [relay2_1, relay2_2, relay2_3]
        for relay in relays2 {
            try? await relay.connect()
        }
        
        // Wait for relay connections
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Check connection status
        print("📡 NDK1 relay status:")
        print("   - \(relay1_1.url): \(await relay1_1.isConnected ? "connected" : "disconnected")")
        print("   - \(relay1_2.url): \(await relay1_2.isConnected ? "connected" : "disconnected")")
        print("   - \(relay1_3.url): \(await relay1_3.isConnected ? "connected" : "disconnected")")
        
        print("📡 NDK2 relay status:")
        print("   - \(relay2_1.url): \(await relay2_1.isConnected ? "connected" : "disconnected")")
        print("   - \(relay2_2.url): \(await relay2_2.isConnected ? "connected" : "disconnected")")
        print("   - \(relay2_3.url): \(await relay2_3.isConnected ? "connected" : "disconnected")")
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
    }
    
    func testFullNutzapFlow() async throws {
        print("\n🎬 STARTING FULL NUTZAP FLOW TEST")
        print("=====================================")
        
        // 2. Create nutsack wallets for both pubkeys
        print("\n📦 Creating wallets...")
        wallet1 = try NIP60Wallet(ndk: ndk1)
        wallet2 = try NIP60Wallet(ndk: ndk2)
        print("✅ Wallets created")
        
        let testMint = "https://testnut.cashu.space"
        let relays = [RelayConstants.damus, RelayConstants.primal]
        
        // Setup wallets - both publish mint list for nutzap compatibility
        print("\n🔧 Setting up wallet1...")
        do {
            try await wallet1.setup(
                mints: [testMint],
                relays: relays,
                publishMintList: true
            )
            print("✅ Wallet1 setup complete")
        } catch {
            print("❌ Wallet1 setup failed: \(error)")
            throw error
        }
        
        print("\n🔧 Setting up wallet2...")
        do {
            try await wallet2.setup(
                mints: [testMint],
                relays: relays,
                publishMintList: true
            )
            print("✅ Wallet2 setup complete")
        } catch {
            print("❌ Wallet2 setup failed: \(error)")
            throw error
        }
        
        print("✅ Created nutsack wallets for both pubkeys")
        
        // Load wallets to start subscriptions
        print("\n📡 Loading wallets to start subscriptions...")
        try await wallet1.load()
        print("✅ Wallet1 loaded and subscriptions started")
        try await wallet2.load()
        print("✅ Wallet2 loaded and subscriptions started")
        
        // Wait for wallet setup to propagate
        print("\n⏳ Waiting for wallet setup to propagate (3 seconds)...")
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        print("✅ Setup propagation complete")
        
        // 3. Create deposit on testnut.cashu.space for a random amount
        let depositAmount = Int64.random(in: 42...100) // Random sats between 42-100 (need at least 2x for nutzap)
        print("\n💰 DEPOSIT PHASE")
        print("================")
        print("🎲 Creating deposit for \(depositAmount) sats")
        
        print("📝 Requesting mint quote...")
        let quote: CashuMintQuote
        do {
            quote = try await wallet1.requestMint(
                amount: depositAmount,
                mintURL: testMint,
                persistQuote: true
            )
            print("✅ Quote received")
        } catch {
            print("❌ Failed to request mint: \(error)")
            throw error
        }
        
        print("⚡ Lightning invoice: \(quote.invoice)")
        print("📋 Quote ID: \(quote.quoteId)")
        print("💡 Testnut autosettles invoices - waiting for payment...")
        
        // Create expectations
        let deposit7375Expectation = expectation(description: "7375 event published after deposit")
        let nutzap9321Expectation = expectation(description: "9321 nutzap event published")
        let redeem7375Expectation = expectation(description: "7375 event published after redemption")
        
        var depositEvent: NDKEvent?
        var nutzapEvent: NDKEvent?
        var redeemEvent: NDKEvent?
        
        // 4. Subscribe to monitor for 7375 events from pubkey1
        print("\n📡 SUBSCRIPTION SETUP")
        print("====================")
        print("Setting up 7375 event subscription for pubkey1...")
        let filter7375_1 = NDKFilter(
            authors: [pubkey1],
            kinds: [EventKind.cashuToken]
        )
        
        let dataSource7375_1 = ndk1.observe(
            filter: filter7375_1,
            maxAge: 0, // Real-time monitoring
            cachePolicy: .networkOnly
        )
        print("✅ Data source created for pubkey1's 7375 events")
        
        Task {
            print("👂 Listening for pubkey1's 7375 events...")
            for await event in dataSource7375_1.events {
                print("📨 Pubkey1 published 7375 event: \(event.id)")
                if depositEvent == nil {
                    depositEvent = event
                    deposit7375Expectation.fulfill()
                }
            }
        }
        
        // Subscribe to 9321 nutzap events
        let filter9321 = NDKFilter(
            kinds: [EventKind.nutzap],
            tags: ["p": Set([pubkey2])]
        )
        
        let dataSource9321 = ndk1.observe(
            filter: filter9321,
            maxAge: 0, // Real-time monitoring
            cachePolicy: .networkOnly
        )
        
        Task {
            for await event in dataSource9321.events {
                print("📨 Nutzap event published: \(event.id)")
                if nutzapEvent == nil {
                    nutzapEvent = event
                    nutzap9321Expectation.fulfill()
                }
            }
        }
        
        // Subscribe to 7375 events from pubkey2
        let filter7375_2 = NDKFilter(
            authors: [pubkey2],
            kinds: [EventKind.cashuToken]
        )
        
        let dataSource7375_2 = ndk2.observe(
            filter: filter7375_2,
            maxAge: 0, // Real-time monitoring
            cachePolicy: .networkOnly
        )
        
        Task {
            for await event in dataSource7375_2.events {
                print("📨 Pubkey2 published 7375 event: \(event.id)")
                if redeemEvent == nil {
                    redeemEvent = event
                    redeem7375Expectation.fulfill()
                }
            }
        }
        
        // Monitor deposit status
        print("\n💳 DEPOSIT MONITORING")
        print("=====================")
        print("⏳ Starting deposit monitoring...")
        print("   - Polling interval: 3.0 seconds")
        print("   - Timeout: 30.0 seconds")
        
        let depositStream = await wallet1.monitorDeposit(
            quote: quote,
            timeout: 30.0 // 30 seconds timeout for testing
        )
        
        var depositCompleted = false
        var checkCount = 0
        
        do {
            print("🔄 Beginning deposit status checks...")
            for try await status in depositStream {
                checkCount += 1
                print("\n📊 Deposit check #\(checkCount) at \(Date())")
                
                switch status {
                case .pending:
                    print("   ⏳ Status: PENDING - Invoice not yet paid")
                case .minted(let proofs):
                    print("   ✅ Status: MINTED - Payment confirmed!")
                    print("   💎 Received \(proofs.count) proofs")
                    print("   💰 Total value: \(proofs.reduce(0) { $0 + $1.amount }) sats")
                    depositCompleted = true
                case .expired:
                    print("   ❌ Status: EXPIRED")
                    XCTFail("Deposit expired before payment")
                case .cancelled:
                    print("   ❌ Status: CANCELLED")
                    XCTFail("Deposit was cancelled")
                }
            }
            print("\n✅ Deposit monitoring completed successfully")
        } catch {
            print("\n⚠️ Deposit monitoring ended with error: \(error)")
            if !depositCompleted {
                print("⚠️ Testnut deposit didn't complete within timeout")
                print("⚠️ This could mean:")
                print("   - Testnut auto-settlement is not working")
                print("   - Network issues with the mint")
                print("   - Quote expired")
                XCTFail("Deposit did not complete: \(error)")
                return
            }
        }
        
        // 5. Wait for and validate the 7375 event
        await fulfillment(of: [deposit7375Expectation], timeout: 30.0)
        
        XCTAssertNotNil(depositEvent, "Should have received a 7375 event after deposit")
        
        // Verify deposit event
        if let event = depositEvent {
            XCTAssertEqual(event.kind, EventKind.cashuToken)
            XCTAssertEqual(event.pubkey, pubkey1)
            print("✅ Validated 7375 event published after deposit")
        }
        
        // Check wallet1 balance
        let balance1Before = try await wallet1.getBalance()
        XCTAssertEqual(balance1Before, depositAmount, "Wallet1 balance should match deposited amount")
        print("💰 Wallet1 balance after deposit: \(balance1Before ?? 0) sats")
        
        // 6. Send nutzap for half the deposited amount from pubkey1 to pubkey2
        let nutzapAmount = depositAmount / 2
        print("⚡ Sending nutzap for \(nutzapAmount) sats from pubkey1 to pubkey2")
        
        // Fetch pubkey2's nutzap preferences to get accepted mints
        let preferencesFilter = NDKFilter(
            authors: [pubkey2],
            kinds: [EventKind.nutzapPreferences],
            limit: 1
        )
        
        let dataSource = ndk1.observe(
            filter: preferencesFilter,
            maxAge: 0, // Always fresh for tests
            cachePolicy: .networkOnly
        )
        // Collect all preferences and use the most recent
        let preferencesEvents = await dataSource.collect(timeout: 5.0)
        guard let preferencesEvent = preferencesEvents.sorted(by: { $0.createdAt > $1.createdAt }).first else {
            XCTFail("Pubkey2 should have published nutzap preferences")
            return
        }
        
        // Extract accepted mints from preferences
        let mintTags = preferencesEvent.tags.filter { $0.first == "mint" }
        let acceptedMints = mintTags.compactMap { tag -> URL? in
            guard tag.count > 1 else { return nil }
            return URL(string: tag[1])
        }
        
        XCTAssertFalse(acceptedMints.isEmpty, "Should have at least one accepted mint")
        print("📋 Pubkey2 accepts mints: \(acceptedMints.map { $0.absoluteString })")
        
        // Create nutzap payment request
        let nutzapRequest = NutzapPaymentRequest(
            amountSats: nutzapAmount,
            recipientPubkey: pubkey2,
            recipientP2PK: pubkey2, // Use the same for testing
            acceptedMints: acceptedMints,
            comment: "Test nutzap from E2E test"
        )
        
        // Send nutzap
        let confirmation = try await wallet1.pay(nutzapRequest)
        
        guard let nutzapConfirmation = confirmation as? NutzapConfirmation else {
            XCTFail("Expected NutzapConfirmation")
            return
        }
        
        let sentNutzapEvent = nutzapConfirmation.nutzapEvent
        print("✅ Nutzap sent with event ID: \(sentNutzapEvent.id)")
        
        // 7. Wait for and validate the 9321 event
        await fulfillment(of: [nutzap9321Expectation], timeout: 30.0)
        
        XCTAssertNotNil(nutzapEvent, "Should have received a 9321 nutzap event")
        
        if let event = nutzapEvent {
            XCTAssertEqual(event.kind, EventKind.nutzap)
            XCTAssertEqual(event.pubkey, pubkey1)
            
            // Verify p tag points to pubkey2
            let pTags = event.tags.filter { $0.first == "p" }
            XCTAssertTrue(pTags.contains { $0.count > 1 && $0[1] == pubkey2 })
            
            print("✅ Validated 9321 nutzap event published")
        }
        
        // 8. Process incoming nutzaps for pubkey2
        print("⏳ Processing incoming nutzaps for pubkey2...")
        
        // Give some time for the nutzap to propagate
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // The wallet should automatically process incoming nutzaps through its subscription
        // but let's wait a bit to ensure processing completes
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // 9. Wait for and validate pubkey2's 7375 event
        await fulfillment(of: [redeem7375Expectation], timeout: 30.0)
        
        XCTAssertNotNil(redeemEvent, "Should have received a 7375 event after redemption")
        
        if let event = redeemEvent {
            XCTAssertEqual(event.kind, EventKind.cashuToken)
            XCTAssertEqual(event.pubkey, pubkey2)
            print("✅ Validated 7375 event published after nutzap redemption")
        }
        
        // 10. Validate final balances
        let balance1After = try await wallet1.getBalance()
        let balance2After = try await wallet2.getBalance()
        
        XCTAssertEqual(balance1After, depositAmount - nutzapAmount, "Wallet1 should have sent half")
        XCTAssertEqual(balance2After, nutzapAmount, "Wallet2 should have received half")
        
        print("\n💰 Final balances:")
        print("   Wallet1: \(balance1After ?? 0) sats (started with \(depositAmount), sent \(nutzapAmount))")
        print("   Wallet2: \(balance2After ?? 0) sats (received \(nutzapAmount))")
        
        print("\n🎉 E2E nutzap test completed successfully!")
        print("   ✅ Created two pubkeys")
        print("   ✅ Created nutsack wallets for both")
        print("   ✅ Deposited \(depositAmount) sats to wallet1")
        print("   ✅ Validated 7375 event after deposit")
        print("   ✅ Sent nutzap for \(nutzapAmount) sats")
        print("   ✅ Validated 9321 nutzap event")
        print("   ✅ Pubkey2 redeemed nutzap successfully")
        print("   ✅ Validated 7375 event after redemption")
        print("   ✅ Final balances correct")
    }
}