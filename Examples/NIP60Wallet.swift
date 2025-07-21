import Foundation
import NDKSwift

// REPL Commands
enum Command {
    case balance
    case deposit(amount: Int64)
    case quit
    case help
    case unknown(String)
    
    static func parse(_ input: String) -> Command {
        let parts = input.lowercased().split(separator: " ")
        guard let command = parts.first else { return .unknown("") }
        
        switch command {
        case "balance", "b":
            return .balance
        case "deposit", "d":
            if parts.count > 1, let amount = Int64(parts[1]) {
                return .deposit(amount: amount)
            }
            return .unknown("Invalid deposit command. Usage: deposit <amount>")
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
        
        print("🏦 Initializing wallet with mints:")
        for url in mintUrls {
            print("   - \(url)")
        }
        
        // Initialize NIP-60 wallet
        let wallet: NIP60Wallet
        do {
            wallet = try NIP60Wallet(ndk: ndk)
            
            // Add mints to the wallet
            for mintUrlString in mintUrls {
                guard let mintUrl = URL(string: mintUrlString) else {
                    print("⚠️ Invalid mint URL: \(mintUrlString)")
                    continue
                }
                await wallet.mints.addMintURL(url: mintUrl)
            }
            
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
                
            case .deposit(let amount):
                await createDeposit(wallet: wallet, amount: amount)
                
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
    
    static func createDeposit(wallet: NIP60Wallet, amount: Int64) async {
        print("💸 Creating deposit for \(amount) sats...")
        
        do {
            // Get available mints
            let mintUrls = await wallet.mints.getMintURLs()
            guard let mintUrlString = mintUrls.first else {
                print("❌ No mints available")
                return
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
            print("The wallet will automatically detect the payment and mint tokens.")
        } catch {
            print("❌ Error creating deposit: \(error)")
        }
    }
    
    static func showHelp() {
        print("""
        
        Available Commands:
        ==================
        balance, b          - Show wallet balance
        deposit <amount>, d - Create a deposit quote for specified amount (in sats)
        help, h            - Show this help message
        quit, q, exit      - Exit the REPL
        
        Examples:
        =========
        wallet> balance
        wallet> deposit 1000
        wallet> quit
        
        """)
    }
}