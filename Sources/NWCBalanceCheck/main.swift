import Foundation
import NDKSwift

// Create an async main function
@main
struct NWCBalanceCheck {
    static func main() async {
        print("🔍 Checking NWC Wallet Balance...")
        print("=================================\n")
        
        let connectionURI = "nostr+walletconnect://80b93a43f0cd322ebdf4ef349baba9970881298976cfd393cfcec85024f6744c?relay=wss://relay.primal.net&relay=wss://relay.damus.io&relay=wss://relay.8333.space/&relay=wss://nos.lol&secret=a6af65b6b002efeed42cd99b93c7dd3f7642e8708910ff6a233b2d2f77f2b06a"
        
        print("Starting main function...")
        
        do {
            // Initialize NDK
            print("About to initialize NDK...")
            let ndk = NDK()
            print("NDK initialized")
            
            // Add relays and connect
            print("1️⃣ Adding relays to NDK...")
            _ = ndk.addRelay("wss://relay.primal.net")
            _ = ndk.addRelay("wss://relay.damus.io")
            _ = ndk.addRelay("wss://relay.8333.space/")
            _ = ndk.addRelay("wss://nos.lol")
            
            print("2️⃣ Connecting NDK to relays...")
            await ndk.connect()
            
            // Wait a moment for connections to establish
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Parse connection URI
            print("\n3️⃣ Parsing connection URI...")
            let parsedURI = try NWCConnectionURI(uri: connectionURI)
            print("✅ Wallet: \(parsedURI.walletPubkey)")
            print("✅ Relays: \(parsedURI.relayURLs.count)")
            
            // Create wallet
            print("\n4️⃣ Creating NWC wallet...")
            let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: connectionURI)
            
            // Connect with timeout
            print("\n5️⃣ Connecting to wallet service...")
            
            // Use a simple timeout approach
            let connectTask = Task {
                try await wallet.connect()
            }
            
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                connectTask.cancel()
                print("⏱️ Connection attempt timed out after 15 seconds")
            }
            
            do {
                try await connectTask.value
                timeoutTask.cancel()
                print("✅ Connected!")
            } catch {
                timeoutTask.cancel()
                if error is CancellationError {
                    print("❌ Connection was cancelled (timeout)")
                    throw NDKError.timeout(operation: "NWC connection", seconds: 15)
                } else {
                    throw error
                }
            }
            
            // Get wallet info
            print("\n6️⃣ Getting wallet info...")
            let info = try await wallet.getInfo()
            print("✅ Wallet capabilities: \(info.methods.joined(separator: ", "))")
            if let network = info.network {
                print("✅ Network: \(network)")
            }
            
            // Check balance
            print("\n7️⃣ Checking balance...")
            let balance: GetBalanceResponse = try await wallet.getBalance()
            let balanceMsat = balance.balance
            let balanceSats = balanceMsat / 1000  // Convert msat to sats
            
            print("\n💰 BALANCE: \(balanceMsat) msat")
            print("💰 BALANCE: \(balanceSats) sats")
            
            // Format nicely
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            if let formatted = formatter.string(from: NSNumber(value: balanceSats)) {
                print("💰 FORMATTED: \(formatted) sats")
            }
            
            // Convert to BTC
            let btc = Double(balanceSats) / 100_000_000
            print("💰 BTC: \(String(format: "%.8f", btc)) BTC")
            
            // List recent transactions
            print("\n8️⃣ Checking recent transactions...")
            do {
                let transactions = try await wallet.listTransactions(
                    from: nil,
                    until: nil,
                    limit: 3,
                    offset: nil,
                    unpaid: false,
                    type: nil
                )
                
                if transactions.isEmpty {
                    print("📜 No recent transactions")
                } else {
                    print("📜 Recent transactions:")
                    for (i, tx) in transactions.enumerated() {
                        let type = tx.type == .incoming ? "⬇️ Received" : "⬆️ Sent"
                        let date = Date(timeIntervalSince1970: TimeInterval(tx.createdAt))
                        print("   \(i+1). \(type) \(tx.amount) sats on \(date)")
                    }
                }
            } catch {
                print("📜 Could not fetch transactions: \(error)")
            }
            
            // Disconnect
            await wallet.disconnect()
            print("\n✅ Done!")
            
        } catch {
            print("\n❌ Error: \(error)")
        }
    }
}
