import CashuSwift
import Foundation
import NDKSwift

// MARK: - Test Configuration

let TEST_MINT_URL = "https://nofees.testnut.cashu.space"
let TEST_AMOUNT_SATS: Int64 = 10000
let NUTZAP_AMOUNT_SATS: Int64 = 21
let TEST_RELAYS = ["wss://relay.damus.io", "wss://relay.primal.net"]
let TIMEOUT_SECONDS = 60.0

// MARK: - Test Errors

enum TestError: Error, LocalizedError {
    case depositTimeout
    case nutzapTimeout
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .depositTimeout:
            return "Deposit was not received within timeout period"
        case .nutzapTimeout:
            return "Nutzap was not received within timeout period"
        case .validationFailed:
            return "Transaction validation failed"
        }
    }
}

// MARK: - Logging Helpers

func log(_ message: String, level: String = "INFO") {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("[\(timestamp)] [\(level)] \(message)")
}

func logSection(_ title: String) {
    print("\n" + String(repeating: "=", count: 60))
    print("=== \(title)")
    print(String(repeating: "=", count: 60))
}

// MARK: - Simple Test Without Deposits

enum Example09_NutzapsAndHistory_Simple {
    static func run() async throws {
        logSection("Simplified Nutzaps and Transaction History Test")
        log("This test bypasses Lightning deposits for simplicity")

        // Set up timeout
        Task {
            try? await Task.sleep(nanoseconds: UInt64(TIMEOUT_SECONDS * 1_000_000_000))
            log("⏰ Test timeout reached!", level: "ERROR")
            fatalError("Test timeout reached")
        }

        do {
            // Phase 1: Setup
            logSection("Phase 1: Setup Wallets")

            log("Creating sender wallet...")
            let senderKey = try NDKPrivateKeySigner.generate()
            let senderNDK = NDK(relayUrls: TEST_RELAYS)
            senderNDK.signer = senderKey
            await senderNDK.connect()

            let senderWallet = try NIP60Wallet(ndk: senderNDK)

            log("Creating receiver wallet...")
            let receiverKey = try NDKPrivateKeySigner.generate()
            let receiverNDK = NDK(relayUrls: TEST_RELAYS)
            receiverNDK.signer = receiverKey
            await receiverNDK.connect()

            let receiverWallet = try NIP60Wallet(ndk: receiverNDK)

            let senderPubkey = try await senderKey.pubkey
            let receiverPubkey = try await receiverKey.pubkey

            log("Sender pubkey: \(senderPubkey)")
            log("Receiver pubkey: \(receiverPubkey)")

            // Setup wallets with mint
            log("Setting up wallets...")
            try await senderWallet.setup(mints: [TEST_MINT_URL], relays: TEST_RELAYS, publishMintList: true)
            try await receiverWallet.setup(mints: [TEST_MINT_URL], relays: TEST_RELAYS, publishMintList: true)

            // Load wallets
            log("Loading wallets...")
            try await senderWallet.load()
            try await receiverWallet.load()

            // Wait for setup to propagate
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            // Phase 2: Create Test Tokens
            logSection("Phase 2: Create Test Tokens")

            log("Creating test tokens directly (bypassing Lightning)...")

            // For testing, we'll simulate having tokens by checking the balance
            let initialBalance = try await senderWallet.getBalance() ?? 0
            log("Initial sender balance: \(initialBalance) sats")

            if initialBalance == 0 {
                log("❌ This test requires the sender wallet to have tokens", level: "ERROR")
                log("Please run the full test with Lightning deposit first", level: "ERROR")
                throw TestError.validationFailed
            }

            // Phase 3: Send Nutzap
            logSection("Phase 3: Send Nutzap")

            // Create a test event to nutzap
            let testEvent = try await receiverNDK.event()
                .content("Test note from receiver")
                .kind(1)
                .build(signer: receiverKey)

            let publishResult = try await receiverNDK.publish(testEvent)
            log("Published test event: \(testEvent.id)")

            // Monitor transaction history
            log("Starting transaction monitoring...")

            var senderTransactionCount = await senderWallet.getTransactionHistory().count
            var receiverTransactionCount = await receiverWallet.getTransactionHistory().count

            log("Initial sender transactions: \(senderTransactionCount)")
            log("Initial receiver transactions: \(receiverTransactionCount)")

            // Get receiver's P2PK key
            log("Fetching receiver's mint list...")
            let mintListFilter = NDKFilter(
                authors: [receiverPubkey],
                kinds: [10019],
                limit: 1
            )

            let mintListDataSource = NDKSubscription(
                ndk: senderNDK,
                filter: mintListFilter,
                maxAge: 0,
                cachePolicy: .networkOnly,
                subscriptionId: "fetch-mintlist"
            )

            // Collect all mint list events and use the most recent
            let mintListEvents = await mintListDataSource.collect(timeout: 3.0)
            guard let mintListEvent = mintListEvents.sorted(by: { $0.createdAt > $1.createdAt }).first else {
                log("❌ Receiver has no mint list", level: "ERROR")
                throw TestError.validationFailed
            }

            guard let p2pkTag = mintListEvent.tags.first(where: { $0.count >= 2 && $0[0] == "pubkey" }),
                  p2pkTag.count >= 2
            else {
                log("❌ Receiver mint list has no P2PK pubkey", level: "ERROR")
                throw TestError.validationFailed
            }
            let recipientP2PKKey = p2pkTag[1]
            log("Found recipient P2PK key: \(recipientP2PKKey)")

            // Send nutzap
            log("Sending \(NUTZAP_AMOUNT_SATS) sat nutzap...")

            let senderMints = await senderWallet.mints.getAllMints()
            let proofStateManager = senderWallet.proofStateManager
            let senderEventManager = senderWallet.eventManager

            let nutzapEvent = try await Nutzap.send(
                wallet: senderWallet,
                amount: NUTZAP_AMOUNT_SATS,
                to: receiverPubkey,
                recipientP2PKKey: recipientP2PKKey,
                comment: "Test nutzap!",
                eventId: testEvent.id,
                mints: senderMints,
                proofStateManager: proofStateManager,
                eventManager: senderEventManager,
                ndk: senderNDK,
                signer: senderKey
            )

            log("✅ Nutzap sent! Event ID: \(nutzapEvent.id)")

            // Phase 4: Monitor Transactions
            logSection("Phase 4: Monitor Transaction Updates")

            // Monitor for new transactions
            var nutzapFound = false
            let startTime = Date()

            while !nutzapFound, Date().timeIntervalSince(startTime) < 20 {
                let senderHistory = await senderWallet.getTransactionHistory()
                let receiverHistory = await receiverWallet.getTransactionHistory()

                log("Sender transactions: \(senderHistory.count), Receiver transactions: \(receiverHistory.count)")

                // Check for nutzap sent transaction
                if let sentNutzap = senderHistory.first(where: { $0.type == .nutzapSent }) {
                    log("✅ Found sent nutzap transaction: \(sentNutzap.amount) sats, status: \(sentNutzap.status.rawValue)")
                }

                // Check for received nutzap
                if let receivedNutzap = receiverHistory.first(where: { $0.type == .nutzapReceived }) {
                    log("✅ Found received nutzap transaction: \(receivedNutzap.amount) sats, status: \(receivedNutzap.status.rawValue)")
                    nutzapFound = true
                }

                if !nutzapFound {
                    log("Waiting for nutzap to be received...")
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                }
            }

            // Final validation
            logSection("Final Validation")

            let finalSenderHistory = await senderWallet.getTransactionHistory()
            let finalReceiverHistory = await receiverWallet.getTransactionHistory()

            log("Final sender transactions: \(finalSenderHistory.count)")
            log("Final receiver transactions: \(finalReceiverHistory.count)")

            // Print all transactions
            log("\nSender transactions:")
            for tx in finalSenderHistory {
                log("  - \(tx.type.displayName): \(tx.amount) sats [\(tx.status.rawValue)] ID: \(tx.id)")
            }

            log("\nReceiver transactions:")
            for tx in finalReceiverHistory {
                log("  - \(tx.type.displayName): \(tx.amount) sats [\(tx.status.rawValue)] ID: \(tx.id)")
            }

            if nutzapFound {
                logSection("✅ TEST PASSED!")
                log("Nutzap was successfully sent and received")
                log("Transaction history is working correctly")
            } else {
                logSection("❌ TEST FAILED!")
                log("Nutzap was not received within timeout", level: "ERROR")
                throw TestError.nutzapTimeout
            }

            // Cleanup
            await senderWallet.stop()
            await receiverWallet.stop()

        } catch {
            log("❌ Test failed with error: \(error)", level: "ERROR")
            throw error
        }
    }
}
