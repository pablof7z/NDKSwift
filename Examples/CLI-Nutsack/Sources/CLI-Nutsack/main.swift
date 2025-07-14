import Foundation
import NDKSwift

@main
@MainActor
struct CLINutsack {
    static func main() async throws {
        print("⚡ NIP-60 Wallet Calculator")
        print("=".repeated(27))
        print()
        
        // Get private key
        let privateKey = try getPrivateKey()
        
        // Initialize wallet manager
        let walletManager = try WalletManager()
        try await walletManager.initialize(privateKey: privateKey)
        
        // Show main menu
        let menu = NavigableMenu()
        try await menu.show(
            items: createMainMenu(walletManager: walletManager),
            title: "⚡ NIP-60 Wallet Calculator"
        )
    }
    
    static func getPrivateKey() throws -> String {
        // Check for environment variable first
        if let nsec = ProcessInfo.processInfo.environment["NOSTR_NSEC"] {
            return nsec
        }
        
        print("Enter your nsec or hex private key (or press Enter to generate new):")
        
        if let input = readLine(), !input.isEmpty {
            // Handle both nsec and hex formats
            return input
        }
        
        // Generate new key
        print("🔑 Generating new wallet key...")
        let signer = try NDKPrivateKeySigner.generate()
        let publicKey = try signer.publicKey()
        print("✅ Generated new key:")
        print("   Public key: \(publicKey)")
        print("   Private key: \(signer.privateKeyHex!)")
        print("\n⚠️  Save your private key securely!")
        print("\nPress Enter to continue...")
        _ = readLine()
        
        return signer.privateKeyHex!
    }
    
    static func createMainMenu(walletManager: WalletManager) -> [MenuItem] {
        return [
            .action("💰 Balance & Tokens", icon: nil) {
                try await showBalance(walletManager: walletManager)
            },
            .submenu("🏦 Manage Mints", icon: nil, items: createMintMenu(walletManager: walletManager)),
            .action("📤 Send Tokens") {
                try await sendTokens(walletManager: walletManager)
            },
            .action("📥 Receive & Claim") {
                try await receiveAndClaim(walletManager: walletManager)
            },
            .action("⚡ Nutzaps") {
                try await nutzapMenu(walletManager: walletManager)
            },
            .action("📊 Transaction History") {
                try await TransactionView.showHistory(
                    ndk: walletManager.getNDK(),
                    wallet: walletManager.getWallet()!
                )
            },
            .submenu("⚙️ Settings", items: createSettingsMenu(walletManager: walletManager)),
            .separator,
            .action("🚪 Exit") {
                print("👋 Goodbye!")
                exit(0)
            }
        ]
    }
    
    static func createMintMenu(walletManager: WalletManager) -> [MenuItem] {
        return [
            .action("📋 View Current Mints") {
                try await viewMints(walletManager: walletManager)
            },
            .action("➕ Add Mint") {
                try await addMint(walletManager: walletManager)
            },
            .action("➖ Remove Mint") {
                try await removeMint(walletManager: walletManager)
            },
            .action("🔧 Add Test Mints") {
                try await addTestMints(walletManager: walletManager)
            }
        ]
    }
    
    static func createSettingsMenu(walletManager: WalletManager) -> [MenuItem] {
        return [
            .action("🔑 Show Wallet Info") {
                try await showWalletInfo(walletManager: walletManager)
            },
            .action("🔄 Consolidate Proofs") {
                try await consolidateProofs(walletManager: walletManager)
            },
            .action("🧹 Clean Spent Proofs") {
                try await cleanSpentProofs(walletManager: walletManager)
            },
            .action("📊 Proof Statistics") {
                try await showProofStats(walletManager: walletManager)
            }
        ]
    }
    
    // Menu action implementations
    static func showBalance(walletManager: WalletManager) async throws {
        print("💰 WALLET BALANCE")
        print("=".repeated(50))
        
        let (total, byMint) = try await walletManager.getBalance()
        
        print("\nTotal: \(formatSats(total))\n")
        
        if !byMint.isEmpty {
            print("By Mint:")
            for (mint, balance) in byMint {
                let percentage = total > 0 ? (Double(balance) / Double(total) * 100) : 0
                let mintName = mint.split(separator: "/").last.map(String.init) ?? mint
                print("├─ \(mintName)")
                print("│  └─ \(formatSats(balance)) (\(String(format: "%.1f", percentage))%)")
            }
        }
        
        // Check pending nutzaps
        if let processor = walletManager.getNutzapProcessor() {
            let pending = await processor.getPendingCount()
            if pending > 0 {
                print("\n⏳ Pending Nutzaps: \(pending)")
            }
        }
    }
    
    static func viewMints(walletManager: WalletManager) async throws {
        print("🏦 CURRENT MINTS")
        print("=".repeated(50))
        
        let mintUrls = await walletManager.getMintURLs()
        
        if mintUrls.isEmpty {
            print("\n📭 No mints configured")
        } else {
            let (_, byMint) = try await walletManager.getBalance()
            
            for (index, mint) in mintUrls.enumerated() {
                print("\n\(index + 1). \(mint)")
                
                // Show balance for this mint
                if let balance = byMint[mint] {
                    print("   Balance: \(formatSats(balance))")
                }
            }
        }
    }
    
    static func addMint(walletManager: WalletManager) async throws {
        print("➕ ADD MINT")
        print("=".repeated(50))
        print("\nEnter mint URL (e.g., https://mint.example.com):")
        
        guard let input = readLine(), !input.isEmpty else {
            print("❌ No mint URL provided")
            return
        }
        
        // Validate URL
        guard let url = URL(string: input), url.scheme?.hasPrefix("http") == true else {
            print("❌ Invalid URL format")
            return
        }
        
        let currentMints = await walletManager.getMintURLs()
        
        if currentMints.contains(input) {
            print("⚠️  This mint is already in your list")
            return
        }
        
        // Add mint
        var newMints = currentMints
        newMints.append(input)
        
        try await walletManager.updateMints(newMints)
        print("✅ Added mint: \(input)")
    }
    
    static func removeMint(walletManager: WalletManager) async throws {
        let mints = await walletManager.getMintURLs()
        
        if mints.isEmpty {
            print("❌ No mints to remove")
            return
        }
        
        print("➖ REMOVE MINT")
        print("=".repeated(50))
        
        for (index, mint) in mints.enumerated() {
            print("\(index + 1). \(mint)")
        }
        
        print("\nEnter mint number to remove:")
        guard let input = readLine(), let index = Int(input), index > 0, index <= mints.count else {
            print("❌ Invalid selection")
            return
        }
        
        var newMints = mints
        let removed = newMints.remove(at: index - 1)
        
        try await walletManager.updateMints(newMints)
        print("✅ Removed mint: \(removed)")
    }
    
    static func addTestMints(walletManager: WalletManager) async throws {
        let testMints = [
            "https://testnut.cashu.space",
            "https://nofees.testnut.cashu.space"
        ]
        
        let currentMints = await walletManager.getMintURLs()
        var newMints = currentMints
        var added = 0
        
        for mint in testMints {
            if !newMints.contains(mint) {
                newMints.append(mint)
                added += 1
            }
        }
        
        if added > 0 {
            try await walletManager.updateMints(newMints)
            print("✅ Added \(added) test mint(s)")
        } else {
            print("⚠️  Test mints already configured")
        }
    }
    
    static func sendTokens(walletManager: WalletManager) async throws {
        print("📤 SEND TOKENS")
        print("=".repeated(50))
        print("\n⚠️  Token sending not yet implemented")
        print("Use Nutzaps to send ecash to other users")
    }
    
    static func receiveAndClaim(walletManager: WalletManager) async throws {
        print("📥 RECEIVE & CLAIM")
        print("=".repeated(50))
        
        // Show wallet's P2PK pubkey for receiving
        if let wallet = walletManager.getWallet() {
            if let p2pk = try? await wallet.getP2PKPubkey() {
                print("\nYour P2PK pubkey for receiving nutzaps:")
                print(p2pk)
                print("")
            }
        }
        
        print("Checking for incoming nutzaps...")
        
        // Check if nutzap preferences are published
        if let wallet = walletManager.getWallet() {
            let hasPrefs = try await wallet.hasPublishedNutzapPreferences()
            if !hasPrefs {
                print("\n⚠️  You haven't published nutzap preferences yet!")
                print("Publishing now...")
                try await wallet.publishNutzapPreferences()
                print("✅ Nutzap preferences published")
            } else {
                print("✅ Nutzap preferences are published")
            }
        }
        
        print("\n📊 Your wallet is monitoring for incoming nutzaps")
        print("They will be automatically redeemed when received")
    }
    
    static func nutzapMenu(walletManager: WalletManager) async throws {
        print("⚡ NUTZAPS")
        print("=".repeated(50))
        
        print("\n1. Send Nutzap")
        print("2. Discover Nutzap Users")
        print("3. Back")
        
        print("\nSelect option:")
        guard let input = readLine() else { return }
        
        switch input {
        case "1":
            try await sendNutzap(walletManager: walletManager)
        case "2":
            try await discoverNutzapUsers(walletManager: walletManager)
        default:
            break
        }
    }
    
    static func sendNutzap(walletManager: WalletManager) async throws {
        print("⚡ SEND NUTZAP")
        print("=".repeated(50))
        
        print("\nEnter recipient npub:")
        guard let npubInput = readLine(), !npubInput.isEmpty else {
            print("❌ No recipient provided")
            return
        }
        
        // Convert npub to pubkey if needed
        let recipientPubkey: String
        if npubInput.hasPrefix("npub1") {
            // Decode npub - this is a simplified version, real implementation would use proper bech32 decoding
            print("❌ Please provide hex pubkey (npub decoding not implemented yet)")
            return
        } else {
            recipientPubkey = npubInput
        }
        
        print("Enter amount in sats:")
        guard let amountInput = readLine(), let amount = Int(amountInput), amount > 0 else {
            print("❌ Invalid amount")
            return
        }
        
        print("Add a comment (optional):")
        let comment = readLine()
        
        print("\n📤 Sending \(amount) sats to \(npubInput)...")
        
        do {
            let eventId = try await walletManager.sendNutzap(
                to: recipientPubkey,
                amount: amount,
                comment: comment?.isEmpty == false ? comment : nil
            )
            
            print("✅ Nutzap sent successfully!")
            print("Event ID: \(eventId)")
            
            // Show updated balance
            try await showBalance(walletManager: walletManager)
        } catch {
            print("❌ Error: \(error.localizedDescription)")
        }
    }
    
    static func discoverNutzapUsers(walletManager: WalletManager) async throws {
        print("🔍 DISCOVER NUTZAP USERS")
        print("=".repeated(50))
        print("Searching for users with nutzap preferences...\n")
        
        let ndk = walletManager.getNDK()
        
        // Fetch nutzap preference events
        let filter = NDKFilter(
            kinds: [10019], // nutzapPreferences
            limit: 50
        )
        
        let events = try await ndk.fetchEvents(filter)
        
        if events.isEmpty {
            print("📭 No users with nutzap support found")
            return
        }
        
        print("Found \(events.count) users with nutzap support:\n")
        
        // Display users
        for (index, event) in events.enumerated() {
            let displayPubkey = event.pubkey.prefix(20) + "..." + event.pubkey.suffix(8)
            
            print("\(index + 1). \(displayPubkey)")
            
            // Show mints
            let mints = event.tags.filter { $0.first == "mint" }.compactMap { $0.dropFirst().first }
            if !mints.isEmpty {
                print("   Mints: \(mints.joined(separator: ", "))")
            }
            
            // Show P2PK pubkey
            if let p2pk = event.tags.first(where: { $0.first == "pubkey" && $0.count > 1 })?.dropFirst().first {
                print("   P2PK: \(p2pk.prefix(16))...")
            }
            print("")
        }
    }
    
    static func showWalletInfo(walletManager: WalletManager) async throws {
        guard let wallet = walletManager.getWallet() else { return }
        guard let pubkey = try await walletManager.getNDK().signer?.publicKey() else { return }
        
        print("🔑 WALLET INFO")
        print("=".repeated(50))
        
        print("\nYour pubkey: \(pubkey)")
        
        if let p2pk = try? await wallet.getP2PKPubkey() {
            print("P2PK pubkey: \(p2pk)")
        }
        
        let mints = await walletManager.getMintURLs()
        print("\nMints: \(mints.count)")
        for mint in mints {
            print("  • \(mint)")
        }
    }
    
    static func consolidateProofs(walletManager: WalletManager) async throws {
        print("🔄 CONSOLIDATING PROOFS")
        print("=".repeated(50))
        print("\n⚠️  Proof consolidation not yet implemented")
    }
    
    static func cleanSpentProofs(walletManager: WalletManager) async throws {
        print("🧹 CLEANING SPENT PROOFS")
        print("=".repeated(50))
        print("\n⚠️  Spent proof cleaning not yet implemented")
    }
    
    static func showProofStats(walletManager: WalletManager) async throws {
        print("📊 PROOF STATISTICS")
        print("=".repeated(50))
        print("\n⚠️  Proof statistics not yet implemented")
    }
    
    static func formatSats(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: amount)) ?? "\(amount)") sats"
    }
}

enum CLIError: Error, LocalizedError {
    case invalidPrivateKey
    
    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "Invalid private key format"
        }
    }
}