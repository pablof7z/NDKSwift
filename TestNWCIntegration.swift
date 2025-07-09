#!/usr/bin/env swift

import Foundation
import NDKSwift

// Test NWC Integration with real connection URI

@main
struct TestNWCIntegration {
    static func main() async {
        print("🚀 NDKSwift NWC Integration Test")
        print("================================\n")
        
        let connectionURI = "nostr+walletconnect://80b93a43f0cd322ebdf4ef349baba9970881298976cfd393cfcec85024f6744c?relay=wss://relay.primal.net&relay=wss://relay.damus.io&relay=wss://relay.8333.space/&relay=wss://nos.lol&secret=a6af65b6b002efeed42cd99b93c7dd3f7642e8708910ff6a233b2d2f77f2b06a"
        
        do {
            // Initialize NDK
            print("1️⃣ Initializing NDK...")
            let ndk = NDK()
            
            // Create NWC wallet
            print("2️⃣ Creating NWC wallet from connection URI...")
            let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: connectionURI)
            
            // Connect to wallet
            print("3️⃣ Connecting to wallet service...")
            try await wallet.connect()
            print("✅ Connected successfully!")
            
            // Get wallet info
            print("\n4️⃣ Fetching wallet information...")
            let info = try await wallet.getInfo()
            print("✅ Wallet Info:")
            print("   Methods: \(info.methods.joined(separator: ", "))")
            if let network = info.network {
                print("   Network: \(network)")
            }
            
            // Check balance
            print("\n5️⃣ Checking wallet balance...")
            let balanceResponse = try await wallet.getBalance()
            print("✅ Balance: \(balanceResponse.balance) sats")
            
            // Format balance
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            if let formatted = formatter.string(from: NSNumber(value: balanceResponse.balance)) {
                print("   Formatted: \(formatted) sats")
            }
            
            // Try to list recent transactions
            if await wallet.supportsMethod(.listTransactions) {
                print("\n6️⃣ Fetching recent transactions...")
                let transactions = try await wallet.listTransactions(
                    from: nil,
                    until: nil,
                    limit: 5,
                    offset: nil,
                    unpaid: false,
                    type: nil
                )
                
                print("✅ Found \(transactions.count) transaction(s)")
                for (index, tx) in transactions.enumerated() {
                    let type = tx.type == .incoming ? "Received" : "Sent"
                    print("   \(index + 1). \(type) \(tx.amount) sats")
                }
            }
            
            // Disconnect
            print("\n7️⃣ Disconnecting...")
            await wallet.disconnect()
            print("✅ Test completed successfully!")
            
        } catch let error as NDKError {
            print("\n❌ NDK Error: \(error)")
        } catch {
            print("\n❌ Error: \(error)")
        }
    }
}
