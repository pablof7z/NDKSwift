import CashuSwift
@testable import NDKSwiftCore
import XCTest

final class NIP60SimpleWalletE2ETest: XCTestCase {
    func testSimpleWalletDepositAnd7375Event() async throws {
        // Create NDK instance
        let ndk = NDK(cache: try await NDKTestFactory.createTestCache())

        // Add a single relay
        let relay = await ndk.pool.addRelay("wss://relay.damus.io")
        try? await relay.connect()

        // Create signer and wallet
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        ndk.signer = signer

        print("✅ Created pubkey: \(pubkey)")

        // Create wallet
        let wallet = try NIP60Wallet(ndk: ndk)

        // Setup wallet - this should create a 17375 event
        try await wallet.setup(
            mints: ["https://testnut.cashu.space"],
            relays: ["wss://relay.damus.io"],
            publishMintList: false
        )

        print("✅ Wallet setup complete")

        // Create deposit
        let amount: Int64 = 50
        let quote = try await wallet.requestMint(
            amount: amount,
            mintURL: "https://testnut.cashu.space",
            persistQuote: true
        )

        print("✅ Created deposit quote: \(quote.quoteId)")

        // Set up subscription for 7375 events
        var received7375 = false
        let filter = NDKFilter(authors: [pubkey], kinds: [EventKind.cashuToken])
        let dataSource = ndk.subscribe(
            filter: filter,
            maxAge: 0, // Real-time monitoring
            cachePolicy: .networkOnly
        )

        // Monitor for 7375 event
        Task {
            for await event in dataSource.events {
                if event.kind == EventKind.cashuToken {
                    print("✅ Received 7375 event: \(event.id)")
                    received7375 = true
                }
            }
        }

        // Monitor deposit (testnut auto-settles)
        let depositStream = await wallet.monitorDeposit(
            quote: quote,
            timeout: 30.0
        )

        for try await status in depositStream {
            if case let .minted(amount) = status {
                print("✅ Deposit completed with \(amount) sats")
                break
            }
        }

        // Wait a bit for event propagation
        try await Task.sleep(nanoseconds: 3 * TimeConstants.nanosecondsPerSecond)

        // Verify
        XCTAssertTrue(received7375, "Should have received a 7375 event")

        let balance = try await wallet.getBalance()
        XCTAssertEqual(balance, amount, "Balance should match deposit")

        print("\n✅ Test passed! Created wallet, deposited \(amount) sats, and verified 7375 event")
    }
}
