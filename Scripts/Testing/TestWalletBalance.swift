import Foundation
import NDKSwift

@main
struct TestWalletBalance {
    static func main() async throws {
        print("Testing wallet balance...")
        
        let nsec = "nsec1km9e4tlfxn7ue98kk5s4jjdr3s75kmt4mjykcytnupjfffqjmydsg5dtad"
        let signer = try NDKPrivateKeySigner(nsec: nsec)
        let pubkey = try await signer.pubkey
        print("Pubkey: \(pubkey)")
        
        let ndk = NDK(relayUrls: [RelayConstants.primal])
        ndk.signer = signer
        await ndk.connect()
        
        let wallet = try NIP60Wallet(ndk: ndk)
        print("Loading wallet...")
        try await wallet.load()
        
        // Wait a bit for wallet to load
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        let balance = try await wallet.getBalance() ?? 0
        print("Balance: \(balance) sats")
        
        // Check mints
        let mints = await wallet.mints.getAllMints()
        print("Mints: \(mints)")
    }
}