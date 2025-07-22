import Foundation
import NDKSwift

// REPL Commands
enum Command {
    case balance
    case deposit(amount: Int64, mintUrl: String?)
    case check(mintUrl: String?)
    case validate(dryRun: Bool, mintUrl: String?)
    case mints
    case quit
    case help
    case unknown(String)
    
    static func parse(_ input: String) -> Command {
        let parts = input.split(separator: " ")
        guard let command = parts.first?.lowercased() else { return .unknown("") }
        
        switch command {
        case "balance", "b":
            return .balance
        case "deposit", "d":
            if parts.count > 1, let amount = Int64(parts[1]) {
                let mintUrl = parts.count > 2 ? String(parts[2]) : nil
                return .deposit(amount: amount, mintUrl: mintUrl)
            }
            return .unknown("Invalid deposit command. Usage: deposit <amount> [mint_url]")
        case "check", "c":
            let mintUrl = parts.count > 1 ? String(parts[1]) : nil
            return .check(mintUrl: mintUrl)
        case "validate", "v":
            var dryRun = false
            var mintUrl: String?
            var currentIndex = 1
            
            while currentIndex < parts.count {
                let part = String(parts[currentIndex])
                if part == "-d" || part == "--dry-run" {
                    dryRun = true
                } else if !part.starts(with: "-") {
                    mintUrl = part
                    break
                }
                currentIndex += 1
            }
            
            return .validate(dryRun: dryRun, mintUrl: mintUrl)
        case "mints", "m":
            return .mints
        case "quit", "q", "exit":
            return .quit
        case "help", "h":
            return .help
        default:
            return .unknown("Unknown command: \(command)")
        }
    }
}

@main
struct NIP60WalletREPL {
    static func main() async {
        print("🌰 NIP-60 Wallet REPL")
        print("=====================")
        
        // Parse command line arguments
        let args = CommandLine.arguments
        var nsec: String?
        
        if args.count > 1 {
            nsec = args[1]
        }
        
        // Create or use provided key
        let signer: NDKPrivateKeySigner
        if let nsec = nsec {
            do {
                signer = try NDKPrivateKeySigner(nsec: nsec)
                let pubkey = try await signer.pubkey
                print("✅ Using provided key: \(pubkey)")
            } catch {
                print("❌ Invalid nsec provided: \(error)")
                return
            }
        } else {
            do {
                signer = try NDKPrivateKeySigner.generate()
                print("🔑 Generated new key pair:")
                let pubkey = try await signer.pubkey
                print("   Public key: \(pubkey)")
                print("   Nsec: \(try signer.nsec)")
                print("")
            } catch {
                print("❌ Failed to generate key pair: \(error)")
                return
            }
        }
        
        // Initialize NDK
        let ndk = NDK(signer: signer)
        
        // Add relay
        await ndk.addRelay("wss://relay.primal.net")
        await ndk.connect()
        print("📡 Connected to relay.primal.net")
        
        // Initialize wallet with test mints
        let mintUrls = [
            "https://nofees.testnut.cashu.space",
            "https://testnut.cashu.space"
        ]
        
        let relayUrls = [
            "wss://relay.primal.net"
        ]
        
        print("🏦 Initializing wallet with mints:")
        for url in mintUrls {
            print("   - \(url)")
        }
        
        // Initialize NIP-60 wallet
        let wallet: NIP60Wallet
        do {
            wallet = try NIP60Wallet(ndk: ndk)
            
            // Setup wallet with mints and relays
            print("🔄 Setting up wallet...")
            try await wallet.setup(
                mints: mintUrls,
                relays: relayUrls,
                publishMintList: true
            )
            print("✅ Wallet setup complete")
            
            // Load wallet (starts subscriptions)
            try await wallet.load()
        } catch {
            print("❌ Failed to initialize wallet: \(error)")
            return
        }
        
        print("")
        print("Wallet initialized! Type 'help' for available commands.")
        print("")
        
        // REPL loop
        await runREPL(wallet: wallet)
        
        // Disconnect
        await ndk.disconnect()
    }
    
    static func runREPL(wallet: NIP60Wallet) async {
        while true {
            print("wallet> ", terminator: "")
            fflush(stdout)
            
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !input.isEmpty else {
                continue
            }
            
            let command = Command.parse(input)
            
            switch command {
            case .balance:
                await showBalance(wallet: wallet)
                
            case .deposit(let amount, let mintUrl):
                await createDeposit(wallet: wallet, amount: amount, mintUrl: mintUrl)
                
            case .check(let mintUrl):
                await checkProofs(wallet: wallet, mintUrl: mintUrl)
                
            case .validate(let dryRun, let mintUrl):
                await validateProofs(wallet: wallet, dryRun: dryRun, mintUrl: mintUrl)
                
            case .mints:
                await showMints(wallet: wallet)
                
            case .help:
                showHelp()
                
            case .quit:
                print("Goodbye! 👋")
                return
                
            case .unknown(let message):
                print("❌ \(message)")
                print("Type 'help' for available commands.")
            }
            
            print("")
        }
    }
    
    static func showBalance(wallet: NIP60Wallet) async {
        print("💰 Fetching balance...")
        
        do {
            let balance = try await wallet.getBalance() ?? 0
            
            print("\n📊 Wallet Balance")
            print("================")
            print("Total: \(balance) sats")
            
            // Get balance by mint
            let mintBalances = await wallet.getBalancesByMint()
            if !mintBalances.isEmpty {
                print("\nBy mint:")
                for (mintUrl, mintBalance) in mintBalances {
                    print("  • \(mintUrl): \(mintBalance) sats")
                }
            }
        } catch {
            print("❌ Error fetching balance: \(error)")
        }
    }
    
    static func createDeposit(wallet: NIP60Wallet, amount: Int64, mintUrl: String?) async {
        print("💸 Creating deposit for \(amount) sats...")
        
        do {
            // Use provided mint URL or get from available mints
            let mintUrlString: String
            if let providedUrl = mintUrl {
                mintUrlString = providedUrl
                print("🏦 Using provided mint: \(mintUrlString)")
                
                // Ensure the mint is properly loaded
                if let mintUrl = URL(string: mintUrlString) {
                    print("🔄 Loading mint data...")
                    let mint = try await wallet.mints.loadMint(url: mintUrl)
                    print("✅ Mint loaded successfully")
                    print("📋 Available keysets: \(mint.keysets.count)")
                    for keyset in mint.keysets {
                        print("   - Keyset ID: \(keyset.keysetID), Unit: \(keyset.unit)")
                    }
                }
            } else {
                let mintUrls = await wallet.mints.getMintURLs()
                guard let firstMint = mintUrls.first else {
                    print("❌ No mints available")
                    return
                }
                mintUrlString = firstMint
                print("🏦 Using default mint: \(mintUrlString)")
            }
            
            let quote = try await wallet.requestMint(amount: amount, mintURL: mintUrlString)
            
            print("\n✅ Deposit created!")
            print("==================")
            print("Quote ID: \(quote.quoteId)")
            print("Amount: \(amount) sats")
            print("Mint: \(mintUrlString)")
            print("\n⚡ Lightning Invoice:")
            print("\(quote.invoice)")
            print("\n⏳ This quote will expire. Pay it to complete the deposit.")
            
            // Start monitoring the quote
            print("\n🔄 Monitoring payment status...")
            print("Press Enter to check manually, or Ctrl+C to stop monitoring")
            
            // Create manual check trigger
            let (triggerStream, triggerContinuation) = AsyncStream<Void>.makeStream()
            
            // Start keyboard monitor task
            let keyboardTask = Task {
                while !Task.isCancelled {
                    if readLine() != nil {
                        // User pressed Enter
                        triggerContinuation.yield()
                    }
                }
                triggerContinuation.finish()
            }
            
            // Monitor the deposit
            do {
                for try await status in await wallet.monitorDeposit(quote: quote, timeout: 300, manualCheckTrigger: triggerStream) {
                    switch status {
                    case .pending:
                        print("⏳ Waiting for payment...")
                    case .minted(let proofs):
                        print("✅ Payment received! Minted \(proofs.count) proofs")
                        let newBalance = try await wallet.getBalance() ?? 0
                        print("💰 New balance: \(newBalance) sats")
                        keyboardTask.cancel()
                        return
                    case .expired:
                        print("❌ Quote expired")
                        keyboardTask.cancel()
                        return
                    case .cancelled:
                        print("❌ Quote cancelled") 
                        keyboardTask.cancel()
                        return
                    }
                }
            } catch {
                print("❌ Error monitoring deposit: \(error)")
            }
            
            // Clean up keyboard task
            keyboardTask.cancel()
        } catch {
            print("❌ Error creating deposit: \(error)")
        }
    }
    
    static func checkProofs(wallet: NIP60Wallet, mintUrl: String?) async {
        print("🔍 Checking proof states...")
        
        do {
            if let providedUrl = mintUrl {
                // Check specific mint
                guard let url = URL(string: providedUrl) else {
                    print("❌ Invalid mint URL: \(providedUrl)")
                    return
                }
                
                print("🏦 Checking proofs with mint: \(providedUrl)")
                
                let proofStates = try await wallet.checkProofStates(mintURL: url)
                
                if proofStates.isEmpty {
                    print("ℹ️ No proofs found for this mint")
                } else {
                    print("\n📋 Proof States for \(providedUrl)")
                    print("=====================================")
                    
                    var spentCount = 0
                    var unspentCount = 0
                    var pendingCount = 0
                    
                    for (proofC, state) in proofStates {
                        let stateEmoji: String
                        let stateText: String
                        
                        switch state {
                        case .unspent:
                            stateEmoji = "✅"
                            stateText = "UNSPENT"
                            unspentCount += 1
                        case .spent:
                            stateEmoji = "❌"
                            stateText = "SPENT"
                            spentCount += 1
                        case .pending:
                            stateEmoji = "⏳"
                            stateText = "PENDING"
                            pendingCount += 1
                        }
                        
                        print("\(stateEmoji) \(proofC.prefix(8))... : \(stateText)")
                    }
                    
                    print("\nSummary:")
                    print("--------")
                    print("✅ Unspent: \(unspentCount)")
                    print("❌ Spent: \(spentCount)")
                    print("⏳ Pending: \(pendingCount)")
                    print("📊 Total: \(proofStates.count)")
                }
            } else {
                // Check all mints
                let mintUrls = await wallet.mints.getMintURLs()
                
                if mintUrls.isEmpty {
                    print("ℹ️ No mints configured")
                    return
                }
                
                print("🏦 Checking proofs across all \(mintUrls.count) mints...")
                
                var totalProofs = 0
                var totalSpent = 0
                var totalUnspent = 0
                var totalPending = 0
                
                for mintUrlString in mintUrls {
                    guard let url = URL(string: mintUrlString) else { continue }
                    
                    do {
                        let proofStates = try await wallet.checkProofStates(mintURL: url)
                        
                        if !proofStates.isEmpty {
                            print("\n📋 Mint: \(mintUrlString)")
                            print("=====================================")
                            
                            var mintSpent = 0
                            var mintUnspent = 0
                            var mintPending = 0
                            
                            for (_, state) in proofStates {
                                totalProofs += 1
                                
                                switch state {
                                case .unspent:
                                    mintUnspent += 1
                                    totalUnspent += 1
                                case .spent:
                                    mintSpent += 1
                                    totalSpent += 1
                                case .pending:
                                    mintPending += 1
                                    totalPending += 1
                                }
                            }
                            
                            print("✅ Unspent: \(mintUnspent)")
                            print("❌ Spent: \(mintSpent)")
                            print("⏳ Pending: \(mintPending)")
                            print("📊 Total: \(proofStates.count)")
                        }
                    } catch {
                        print("\n⚠️ Error checking mint \(mintUrlString): \(error)")
                    }
                }
                
                print("\n🌐 Overall Summary")
                print("==================")
                print("✅ Total Unspent: \(totalUnspent)")
                print("❌ Total Spent: \(totalSpent)")
                print("⏳ Total Pending: \(totalPending)")
                print("📊 Total Proofs: \(totalProofs)")
                print("🏦 Mints Checked: \(mintUrls.count)")
            }
            
            // Optionally reconcile states
            print("\n🔄 Reconciling proof states...")
            _ = try await wallet.checkAndReconcileProofStates()
            print("✅ Reconciliation complete")
            
        } catch {
            print("❌ Error checking proofs: \(error)")
        }
    }
    
    static func validateProofs(wallet: NIP60Wallet, dryRun: Bool, mintUrl: String?) async {
        print("🔐 Validating proofs\(dryRun ? " (dry run - no changes will be made)" : "")...")
        
        do {
            if let providedUrl = mintUrl {
                // Validate specific mint
                guard let url = URL(string: providedUrl) else {
                    print("❌ Invalid mint URL: \(providedUrl)")
                    return
                }
                
                print("🏦 Validating proofs with mint: \(providedUrl)")
                
                // Check proof states for this mint
                let proofStates = try await wallet.checkProofStates(mintURL: url)
                
                if proofStates.isEmpty {
                    print("ℹ️ No proofs found for this mint")
                    return
                }
                
                print("\n📋 Proof States for \(providedUrl)")
                print("=====================================")
                
                var spentCount = 0
                var unspentCount = 0
                var pendingCount = 0
                var spentProofs: [String] = []
                
                for (proofC, state) in proofStates {
                    let stateEmoji: String
                    let stateText: String
                    
                    switch state {
                    case .unspent:
                        stateEmoji = "✅"
                        stateText = "VALID (unspent)"
                        unspentCount += 1
                    case .spent:
                        stateEmoji = "❌"
                        stateText = "INVALID (spent)"
                        spentCount += 1
                        spentProofs.append(proofC)
                    case .pending:
                        stateEmoji = "⏳"
                        stateText = "PENDING"
                        pendingCount += 1
                    }
                    
                    print("\(stateEmoji) \(proofC.prefix(8))... : \(stateText)")
                }
                
                print("\nValidation Summary:")
                print("------------------")
                print("✅ Valid (unspent): \(unspentCount)")
                print("❌ Invalid (spent): \(spentCount)")
                print("⏳ Pending: \(pendingCount)")
                print("📊 Total: \(proofStates.count)")
                
                if !dryRun && spentCount > 0 {
                    print("\n🗑️ Removing \(spentCount) spent proofs...")
                    // The reconciliation will handle removing spent proofs
                    _ = try await wallet.checkAndReconcileProofStates()
                    print("✅ Spent proofs removed")
                }
            } else {
                // Validate all mints
                print("🌐 Validating proofs across all mints...")
                
                if dryRun {
                    // For dry run, check each mint individually without reconciliation
                    let mintUrls = await wallet.mints.getMintURLs()
                    
                    if mintUrls.isEmpty {
                        print("ℹ️ No mints configured")
                        return
                    }
                    
                    var totalProofs = 0
                    var totalSpent = 0
                    var totalUnspent = 0
                    var totalPending = 0
                    
                    for mintUrlString in mintUrls {
                        guard let url = URL(string: mintUrlString) else { continue }
                        
                        do {
                            let proofStates = try await wallet.checkProofStates(mintURL: url)
                            
                            if !proofStates.isEmpty {
                                print("\n📋 Mint: \(mintUrlString)")
                                print("=====================================")
                                
                                var mintSpent = 0
                                var mintUnspent = 0
                                var mintPending = 0
                                
                                for (_, state) in proofStates {
                                    totalProofs += 1
                                    
                                    switch state {
                                    case .unspent:
                                        mintUnspent += 1
                                        totalUnspent += 1
                                    case .spent:
                                        mintSpent += 1
                                        totalSpent += 1
                                    case .pending:
                                        mintPending += 1
                                        totalPending += 1
                                    }
                                }
                                
                                print("✅ Valid (unspent): \(mintUnspent)")
                                print("❌ Invalid (spent): \(mintSpent)")
                                print("⏳ Pending: \(mintPending)")
                                print("📊 Total: \(proofStates.count)")
                            }
                        } catch {
                            print("\n⚠️ Error validating mint \(mintUrlString): \(error)")
                        }
                    }
                    
                    print("\n🌐 Overall Validation Summary")
                    print("=============================")
                    print("✅ Total Valid (unspent): \(totalUnspent)")
                    print("❌ Total Invalid (spent): \(totalSpent)")
                    print("⏳ Total Pending: \(totalPending)")
                    print("📊 Total Proofs: \(totalProofs)")
                    print("🏦 Mints Validated: \(mintUrls.count)")
                } else {
                    // For non-dry run, use the built-in validateProofs method
                    let result = try await wallet.validateProofs()
                    
                    print("\n📊 Validation Results")
                    print("====================")
                    print("📊 Total checked: \(result.totalChecked)")
                    print("❌ Spent proofs removed: \(result.spentProofs.count)")
                    print("⏳ Pending proofs: \(result.pendingProofs.count)")
                    print("⚠️ Errors: \(result.errors)")
                    
                    let validProofs = result.totalChecked - result.spentProofs.count - result.pendingProofs.count
                    print("✅ Valid proofs: \(validProofs)")
                    
                    if result.spentProofs.count > 0 {
                        print("\n✅ Wallet state updated - \(result.spentProofs.count) spent proofs removed")
                    }
                    
                    if result.errors > 0 {
                        print("\n⚠️ Some errors occurred during validation. Check logs for details.")
                    }
                }
            }
        } catch {
            print("❌ Error validating proofs: \(error)")
        }
    }
    
    static func showMints(wallet: NIP60Wallet) async {
        print("🏦 Configured Mints")
        print("==================")
        
        let mintUrls = await wallet.mints.getMintURLs()
        
        if mintUrls.isEmpty {
            print("No mints configured")
        } else {
            for (index, mintUrl) in mintUrls.enumerated() {
                // Get balance for this mint
                if let url = URL(string: mintUrl) {
                    let balance = await wallet.getBalance(mint: url)
                    print("\(index + 1). \(mintUrl)")
                    print("   Balance: \(balance) sats")
                }
            }
            print("\nTotal mints: \(mintUrls.count)")
        }
    }
    
    static func showHelp() {
        print("""
        
        Available Commands:
        ==================
        balance, b                    - Show wallet balance
        check, c [mint_url]           - Check proof states (all mints if no URL provided)
        validate, v [-d] [mint_url]   - Validate proofs and remove spent ones (-d for dry run)
        deposit <amount> [mint_url]   - Create a deposit quote for specified amount (in sats)
        mints, m                      - Show configured mints and their balances
        help, h                       - Show this help message
        quit, q, exit                 - Exit the REPL
        
        Examples:
        =========
        wallet> balance
        wallet> mints                                 # Show all configured mints
        wallet> check
        wallet> check https://nofees.testnut.cashu.space
        wallet> validate                              # Validate all proofs and remove spent ones
        wallet> validate -d                           # Dry run - check all proofs without changes
        wallet> validate https://testnut.cashu.space  # Validate proofs for specific mint
        wallet> validate -d https://testnut.cashu.space # Dry run for specific mint
        wallet> deposit 1000
        wallet> deposit 100 https://nofees.testnut.cashu.space
        wallet> quit
        
        """)
    }
}