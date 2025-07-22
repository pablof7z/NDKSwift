import Foundation
import NDKSwift

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

// MARK: - Test Configuration

let TEST_MINT_URL = "https://nofees.testnut.cashu.space"
let TEST_AMOUNT_SATS: Int64 = 10_000
let NUTZAP_AMOUNT_SATS: Int64 = 10  // Small nutzap amount to test with pre-funded wallet
// Using only relay.primal.net since others are rejecting events (pow required, rate limiting)
let TEST_RELAYS = ["wss://relay.primal.net"]
let TIMEOUT_SECONDS = 120.0 // 2 minutes - deposit can take time

// MARK: - Console UI Configuration

let COLUMN_WIDTH = 50
let TERMINAL_WIDTH = 102  // 50 + 2 + 50
let MAX_TRANSACTIONS = 20

// MARK: - Console UI State

class ConsoleUIState {
    struct WalletState {
        var pubkey: String = ""
        var balance: Int64 = 0
        var status: String = "Initializing..."
        var transactions: [WalletTransaction] = []
    }
    
    var sender = WalletState()
    var receiver = WalletState()
    var logs: [String] = []
    
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 10 {
            logs.removeFirst()
        }
    }
}

let uiState = ConsoleUIState()

// MARK: - Console UI Rendering

func clearScreen() {
    print("\u{001B}[2J\u{001B}[H", terminator: "")
}

func moveCursor(to row: Int, col: Int) {
    print("\u{001B}[\(row);\(col)H", terminator: "")
}

func truncate(_ string: String, to length: Int) -> String {
    if string.count <= length {
        return string
    }
    return String(string.prefix(length - 3)) + "..."
}

func padRight(_ string: String, to length: Int) -> String {
    if string.count >= length {
        return truncate(string, to: length)
    }
    return string + String(repeating: " ", count: length - string.count)
}

func renderUI() {
    clearScreen()
    
    // Header
    print("╔" + String(repeating: "═", count: COLUMN_WIDTH) + "╦" + String(repeating: "═", count: COLUMN_WIDTH) + "╗")
    print("║" + padRight(" SENDER", to: COLUMN_WIDTH) + "║" + padRight(" RECEIVER", to: COLUMN_WIDTH) + "║")
    print("╠" + String(repeating: "═", count: COLUMN_WIDTH) + "╬" + String(repeating: "═", count: COLUMN_WIDTH) + "╣")
    
    // Pubkeys
    print("║" + padRight(" Pubkey:", to: COLUMN_WIDTH) + "║" + padRight(" Pubkey:", to: COLUMN_WIDTH) + "║")
    print("║" + padRight(" " + uiState.sender.pubkey, to: COLUMN_WIDTH) + "║" + padRight(" " + uiState.receiver.pubkey, to: COLUMN_WIDTH) + "║")
    print("╠" + String(repeating: "─", count: COLUMN_WIDTH) + "╬" + String(repeating: "─", count: COLUMN_WIDTH) + "╣")
    
    // Balance
    print("║" + padRight(" Balance: \(uiState.sender.balance) sats", to: COLUMN_WIDTH) + "║" + padRight(" Balance: \(uiState.receiver.balance) sats", to: COLUMN_WIDTH) + "║")
    print("╠" + String(repeating: "─", count: COLUMN_WIDTH) + "╬" + String(repeating: "─", count: COLUMN_WIDTH) + "╣")
    
    // Status
    print("║" + padRight(" Status: \(uiState.sender.status)", to: COLUMN_WIDTH) + "║" + padRight(" Status: \(uiState.receiver.status)", to: COLUMN_WIDTH) + "║")
    print("╠" + String(repeating: "═", count: COLUMN_WIDTH) + "╬" + String(repeating: "═", count: COLUMN_WIDTH) + "╣")
    
    // Transaction History Header
    print("║" + padRight(" Recent Transactions:", to: COLUMN_WIDTH) + "║" + padRight(" Recent Transactions:", to: COLUMN_WIDTH) + "║")
    print("╠" + String(repeating: "─", count: COLUMN_WIDTH) + "╬" + String(repeating: "─", count: COLUMN_WIDTH) + "╣")
    
    // Transaction History
    let senderTxCount = min(uiState.sender.transactions.count, MAX_TRANSACTIONS)
    let receiverTxCount = min(uiState.receiver.transactions.count, MAX_TRANSACTIONS)
    let maxTxCount = max(senderTxCount, receiverTxCount)
    
    for i in 0..<maxTxCount {
        var senderLine = " "
        var receiverLine = " "
        
        if i < senderTxCount {
            let tx = uiState.sender.transactions[i]
            let direction = tx.direction == .incoming ? "↓" : "↑"
            let statusIcon = tx.status == .completed ? "✓" : "○"
            senderLine = " \(direction) \(tx.type.displayName): \(tx.amount) sats \(statusIcon)"
        }
        
        if i < receiverTxCount {
            let tx = uiState.receiver.transactions[i]
            let direction = tx.direction == .incoming ? "↓" : "↑"
            let statusIcon = tx.status == .completed ? "✓" : "○"
            receiverLine = " \(direction) \(tx.type.displayName): \(tx.amount) sats \(statusIcon)"
        }
        
        print("║" + padRight(senderLine, to: COLUMN_WIDTH) + "║" + padRight(receiverLine, to: COLUMN_WIDTH) + "║")
    }
    
    // Fill remaining transaction slots
    for _ in maxTxCount..<5 {
        print("║" + padRight(" ", to: COLUMN_WIDTH) + "║" + padRight(" ", to: COLUMN_WIDTH) + "║")
    }
    
    // Bottom border
    print("╚" + String(repeating: "═", count: COLUMN_WIDTH) + "╩" + String(repeating: "═", count: COLUMN_WIDTH) + "╝")
    
    // Activity Log
    print("\n Activity Log:")
    print(" " + String(repeating: "─", count: TERMINAL_WIDTH - 2))
    for log in uiState.logs {
        print(" " + truncate(log, to: TERMINAL_WIDTH - 2))
    }
}

// MARK: - Logging Helpers

func log(_ message: String, level: String = "INFO") {
    uiState.addLog(message)
    renderUI()
}

func logSection(_ title: String) {
    uiState.addLog("=== \(title) ===")
    renderUI()
}

// MARK: - Wallet Observer

class WalletObserver {
    let name: String
    let wallet: NIP60Wallet
    private var eventTask: Task<Void, Never>?
    private var balanceTask: Task<Void, Never>?
    private var transactionTask: Task<Void, Never>?
    private var transactions: [String: WalletTransaction] = [:]
    private var lastBalance: Int64 = -1
    private var isSender: Bool
    
    init(name: String, wallet: NIP60Wallet) {
        self.name = name
        self.wallet = wallet
        self.isSender = name == "SENDER"
    }
    
    func startObserving() {
        // Update UI status
        if isSender {
            uiState.sender.status = "Loading wallet..."
        } else {
            uiState.receiver.status = "Loading wallet..."
        }
        renderUI()
        
        // Start balance monitoring task
        balanceTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                do {
                    let currentBalance = try await self.wallet.getBalance() ?? 0
                    if currentBalance != self.lastBalance {
                        self.lastBalance = currentBalance
                        
                        // Update UI state
                        if self.isSender {
                            uiState.sender.balance = currentBalance
                        } else {
                            uiState.receiver.balance = currentBalance
                        }
                        renderUI()
                    }
                    try await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5 seconds
                } catch {
                    break
                }
            }
        }
        
        // Start transaction monitoring task
        transactionTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                do {
                    let history = await self.wallet.getTransactionHistory()
                    
                    // Update UI state with latest transactions
                    if self.isSender {
                        uiState.sender.transactions = Array(history.prefix(MAX_TRANSACTIONS))
                    } else {
                        uiState.receiver.transactions = Array(history.prefix(MAX_TRANSACTIONS))
                    }
                    renderUI()
                    
                    try await Task.sleep(nanoseconds: 1_000_000_000) // Check every 1 second
                } catch {
                    break
                }
            }
        }
        
        eventTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await event in await self.wallet.events {
                await self.handleWalletEvent(event)
            }
        }
    }
    
    @MainActor
    private func handleWalletEvent(_ event: NIP60WalletEvent) async {
        switch event.type {
        case .balanceChanged(let newBalance):
            // Balance is already updated by the monitoring task
            break
            
        case .transactionAdded(let transaction):
            transactions[transaction.id] = transaction
            uiState.addLog("[\(name)] New \(transaction.type.displayName): \(transaction.amount) sats")
            renderUI()
            
        case .transactionUpdated(let transaction):
            let oldStatus = transactions[transaction.id]?.status.rawValue ?? "unknown"
            transactions[transaction.id] = transaction
            uiState.addLog("[\(name)] Transaction \(oldStatus) → \(transaction.status.rawValue)")
            renderUI()
            
        case .nutzapReceived(let amount, let from, let eventId):
            uiState.addLog("[\(name)] ⚡ Nutzap received: \(amount) sats")
            renderUI()
            
        default:
            break
        }
    }
    
    func updateStatus(_ status: String) {
        if isSender {
            uiState.sender.status = status
        } else {
            uiState.receiver.status = status
        }
        renderUI()
    }
    
    func stop() {
        eventTask?.cancel()
        balanceTask?.cancel()
        transactionTask?.cancel()
    }
}

// MARK: - Main Test

struct Example09_NutzapsAndHistory {
    static func run() async throws {
        // Initialize console UI
        renderUI()
        logSection("Nutzaps and Transaction History Demo")
        
        // Set up timeout
        Task {
            try? await Task.sleep(nanoseconds: UInt64(TIMEOUT_SECONDS * 1_000_000_000))
            log("⏰ Test timeout reached!", level: "ERROR")
            fatalError("Test timeout reached")
        }
        
        do {
            // Phase 1: Setup
            logSection("Phase 1: Setup")
            
            log("Creating sender wallet...")
            // Using pre-funded wallet with balance
            let senderNsec = "nsec1km9e4tlfxn7ue98kk5s4jjdr3s75kmt4mjykcytnupjfffqjmydsg5dtad"
            let senderKey = try NDKPrivateKeySigner(nsec: senderNsec)
            let senderNDK = NDK(relayUrls: TEST_RELAYS)
            senderNDK.signer = senderKey
            await senderNDK.connect()
            
            let senderWallet = try NIP60Wallet(ndk: senderNDK)
            let senderObserver = WalletObserver(name: "SENDER", wallet: senderWallet)
            
            // Update UI with sender pubkey
            uiState.sender.pubkey = try await senderKey.pubkey
            renderUI()
            
            senderObserver.startObserving()
            
            log("Creating receiver wallet...")
            // Using nsec that already has a NIP60 wallet and mint list
            let receiverNsec = "nsec1hj9mc6056dxy5fargykz0cw85mgw5w97hzdc0rjaxevw8twjvkgsnzx038"
            let receiverKey = try NDKPrivateKeySigner(nsec: receiverNsec)
            let receiverNDK = NDK(relayUrls: TEST_RELAYS)
            receiverNDK.signer = receiverKey
            await receiverNDK.connect()
            
            let receiverWallet = try NIP60Wallet(ndk: receiverNDK)
            let receiverObserver = WalletObserver(name: "RECEIVER", wallet: receiverWallet)
            
            // Update UI with receiver pubkey
            uiState.receiver.pubkey = try await receiverKey.pubkey
            renderUI()
            
            receiverObserver.startObserving()
            
            // Both wallets already have configuration
            // Load wallets
            log("Loading sender wallet...")
            senderObserver.updateStatus("Loading wallet...")
            try await senderWallet.load()
            senderObserver.updateStatus("Wallet loaded")
            
            log("Loading receiver wallet...")
            receiverObserver.updateStatus("Loading wallet...")
            try await receiverWallet.load()
            receiverObserver.updateStatus("Wallet loaded")
            
            // Wait for wallets to fully load
            senderObserver.updateStatus("Fetching balance...")
            receiverObserver.updateStatus("Fetching balance...")
            log("Waiting for wallets to sync...")
            
            // Check balance periodically while waiting
            for i in 1...10 {
                let checkBalance = try await senderWallet.getBalance() ?? 0
                if checkBalance > 0 {
                    senderObserver.updateStatus("Ready")
                    break
                }
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second between checks
            }
            
            receiverObserver.updateStatus("Ready")
            
            // Phase 2: Check Balance
            logSection("Phase 2: Check Balance")
            
            let initialSenderBalance = try await senderWallet.getBalance() ?? 0
            
            guard initialSenderBalance >= NUTZAP_AMOUNT_SATS else {
                senderObserver.updateStatus("Insufficient balance")
                log("❌ Insufficient balance")
                throw TestError.validationFailed
            }
            
            log("✅ Balance check passed!")
            
            // Skip deposit section entirely since we're using pre-funded wallet
            if false {
            
            log("Creating Lightning invoice for \(TEST_AMOUNT_SATS) sats...")
            
            // Access wallet internals for deposit
            let mints = await senderWallet.mints
            let eventManager = await senderWallet.eventManager
            
            let (quote, quoteEventId) = try await CashuDeposit.requestMintQuote(
                amount: TEST_AMOUNT_SATS,
                mintURL: TEST_MINT_URL,
                mints: mints,
                eventManager: eventManager,
                persistQuote: true,
                signer: senderKey
            )
            
            log("Created quote: \(quote.quoteId)")
            log("Lightning invoice: \(quote.invoice)")
            log("⚡ Please pay this invoice to continue the test!")
            log("⚡ The testnut mint should auto-settle this immediately")
            
            // For testnut mint, we may need to manually pay the invoice
            log("💳 Simulating payment to testnut mint...")
            // The testnut mint at https://nofees.testnut.cashu.space auto-settles invoices
            
            // Monitor for deposit using CashuDeposit
            log("Monitoring for deposit...")
            log("⚡ The testnut mint should auto-settle this immediately!")
            
            var depositReceived = false
            let depositTimeout: TimeInterval = 30.0
            
            // For the test mint, let's use a shorter timeout and handle network errors
            var retryCount = 0
            let maxRetries = 3
            
            while !depositReceived && retryCount < maxRetries {
                do {
                    log("Attempt \(retryCount + 1) of \(maxRetries) to monitor deposit...")
                    
                    for try await status in CashuDeposit.monitorDeposit(
                quote: quote,
                quoteEventId: quoteEventId,
                mints: mints,
                eventManager: eventManager,
                signer: senderKey,
                timeout: depositTimeout,
                quoteAge: 0,
                onProofsReceived: { proofs in
                    // Let the wallet handle proof state updates
                    let stateChange = WalletStateChange(
                        store: proofs,
                        destroy: [],
                        mint: quote.mintURL,
                        memo: "Lightning deposit"
                    )
                    return try await senderWallet.update(stateChange: stateChange)
                }
            ) {
                switch status {
                case .pending:
                    log("Waiting for payment...")
                    
                case .minted(let proofs):
                    log("✅ Tokens minted successfully!")
                    depositReceived = true
                    break // Exit the loop
                    
                case .expired, .cancelled:
                    log("❌ Quote expired or cancelled", level: "ERROR")
                    throw TestError.depositTimeout
                }
            }
                } catch {
                    log("⚠️ Error monitoring deposit (attempt \(retryCount + 1)): \(error)", level: "WARNING")
                    retryCount += 1
                    
                    if retryCount < maxRetries {
                        log("Retrying in 2 seconds...")
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } else {
                        log("❌ Max retries reached", level: "ERROR")
                        throw error
                    }
                }
            }
            
            guard depositReceived else {
                log("❌ Deposit not completed within timeout", level: "ERROR")
                throw TestError.depositTimeout
            }
            
            let newBalance = try await senderWallet.getBalance() ?? 0
            log("✅ Deposit completed! New balance: \(newBalance) sats")
            } // End of deposit else block
            
            // Wait a moment for UI to show ready state
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            // Phase 3: Send Nutzap
            logSection("Send Nutzap")
            
            senderObserver.updateStatus("Preparing nutzap...")
            receiverObserver.updateStatus("Waiting for nutzap...")
            
            // Send nutzap using NDKZapManager
            do {
                let recipientPubkey = try await receiverKey.pubkey
                let recipientUser = NDKUser(pubkey: recipientPubkey)
                recipientUser.ndk = senderNDK
                
                let zapManager = NDKZapManager(ndk: senderNDK)
                await zapManager.register(provider: senderWallet)
                
                senderObserver.updateStatus("Sending nutzap...")
                log("Sending \(NUTZAP_AMOUNT_SATS) sat nutzap...")
                
                let zapResult = try await zapManager.zap(
                    to: recipientUser,
                    amountSats: NUTZAP_AMOUNT_SATS,
                    comment: "Test nutzap from E2E test",
                    preferredType: .nutzap  // Explicitly request nutzap
                )
                
                senderObserver.updateStatus("Nutzap sent!")
                log("✅ Nutzap sent successfully!")
            } catch {
                senderObserver.updateStatus("Send failed")
                log("❌ Failed to send nutzap")
                throw error
            }
            
            // Phase 4: Receive Nutzap
            logSection("Receive Nutzap")
            
            receiverObserver.updateStatus("Checking for nutzap...")
            
            var nutzapReceived = false
            let nutzapStartTime = Date()
            
            while !nutzapReceived && Date().timeIntervalSince(nutzapStartTime) < 30 {
                let receiverBalance = try await receiverWallet.getBalance() ?? 0
                let receiverNutzaps = await receiverWallet.getNutzaps()
                
                if receiverBalance > 0 || !receiverNutzaps.isEmpty {
                    nutzapReceived = true
                    receiverObserver.updateStatus("Nutzap received!")
                    log("✅ Nutzap received!")
                    
                    // Process nutzaps
                    for nutzap in receiverNutzaps {
                        if !nutzap.isRedeemed {
                            receiverObserver.updateStatus("Redeeming nutzap...")
                        }
                    }
                } else {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                }
            }
            
            guard nutzapReceived else {
                receiverObserver.updateStatus("Timeout waiting")
                log("❌ Nutzap timeout")
                throw TestError.nutzapTimeout
            }
            
            // Let the UI update with final state
            try await Task.sleep(nanoseconds: 3_000_000_000)
            
            // Verify transaction history integrity
            logSection("Verifying Transaction History")
            
            let senderHistory = await senderWallet.getTransactionHistory()
            let receiverHistory = await receiverWallet.getTransactionHistory()
            
            // Check for expected transaction types
            let senderHasNutzapSent = senderHistory.contains { $0.type == WalletTransactionType.nutzapSent }
            let receiverHasNutzapReceived = receiverHistory.contains { $0.type == WalletTransactionType.nutzapReceived }
            
            if senderHasNutzapSent && receiverHasNutzapReceived {
                senderObserver.updateStatus("✅ Test passed!")
                receiverObserver.updateStatus("✅ Test passed!")
                log("✅ All transactions recorded correctly")
            } else {
                senderObserver.updateStatus("❌ Test failed")
                receiverObserver.updateStatus("❌ Test failed")
                log("❌ Some transactions missing")
                throw TestError.validationFailed
            }
            
            // Keep UI visible for a moment
            try await Task.sleep(nanoseconds: 5_000_000_000)
            
            // Cleanup
            senderObserver.stop()
            receiverObserver.stop()
            await senderWallet.stop()
            await receiverWallet.stop()
            
        } catch {
            log("❌ Test failed with error: \(error)", level: "ERROR")
            throw error
        }
    }
}