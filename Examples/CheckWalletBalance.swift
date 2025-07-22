import Foundation
import NDKSwift

@main
struct CheckWalletBalance {
    static func main() async throws {
        print("Testing wallet balance loading...")
        
        let nsec = "nsec1km9e4tlfxn7ue98kk5s4jjdr3s75kmt4mjykcytnupjfffqjmydsg5dtad"
        let signer = try NDKPrivateKeySigner(nsec: nsec)
        let pubkey = try await signer.pubkey
        print("Pubkey: \(pubkey)")
        
        let ndk = NDK(relayUrls: ["wss://relay.primal.net"])
        ndk.signer = signer
        await ndk.connect()
        
        let wallet = try NIP60Wallet(ndk: ndk)
        print("Loading wallet...")
        try await wallet.load()
        
        // Check balance immediately
        let balance1 = try await wallet.getBalance() ?? 0
        print("Balance immediately after load: \(balance1) sats")
        
        // Wait and check again
        for i in 1...10 {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            let balance = try await wallet.getBalance() ?? 0
            print("Balance check \(i): \(balance) sats")
            
            if balance > 0 {
                print("✅ Balance loaded! Final balance: \(balance) sats")
                break
            }
        }
        
        // Check mints
        let mints = await wallet.mints.getMintURLs()
        print("Mints: \(mints)")
        
        // Force exit
        exit(0)
    }
}