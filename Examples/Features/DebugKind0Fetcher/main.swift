import Foundation
import NDKSwift

// To run this example with the NDKSwift library:
// 1. Build the project: swift build
// 2. Run: swift run --package-path . DebugKind0Fetcher <npub>

@main
struct DebugKind0Fetcher {
    static func main() async throws {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: swift run DebugKind0Fetcher <npub>")
            print("Example: swift run DebugKind0Fetcher npub1...")
            return
        }
        
        let npubInput = CommandLine.arguments[1]
        
        // Convert npub to hex if needed
        let pubkeyHex: String
        if npubInput.hasPrefix("npub1") {
            do {
                pubkeyHex = try Bech32.pubkey(from: npubInput)
            } catch {
                print("❌ Invalid npub format: \(error)")
                return
            }
        } else {
            pubkeyHex = npubInput
        }
        
        print("🔍 Debug Kind:0 Fetcher")
        print("======================")
        print("Target pubkey: \(pubkeyHex)")
        print("Relay: wss://relay.primal.net")
        print("")
        
        // Initialize NDK with debugging enabled
        let ndk = NDK(
            relayUrls: ["wss://relay.primal.net"],
            signer: nil
        )
        
        // Enable debugging
        ndk.debugMode = true
        
        print("🔄 Connecting to relay...")
        
        // Connect to relay
        await ndk.connect()
        
        // Wait a moment for connection
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        print("🔍 Fetching profile using NDK Data Source...")
        
        // Use NDK's declarative API to fetch the profile
        let profileDataSource = NDKSubscription<NDKUserProfile>(
            ndk: ndk,
            filter: NDKFilter(
                authors: [pubkeyHex],
                kinds: [0]
            )
        ) { event in
            guard let data = event.content.data(using: .utf8),
                  let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: data) else {
                return nil
            }
            return profile
        }
        
        // Wait for data to arrive
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        let profiles = profileDataSource.data
        if let profile = profiles.first {
            print("✅ Found profile for pubkey")
            print("")
            print("📋 Profile Details:")
            print("   Pubkey: \(pubkeyHex)")
            print("   Name: \(profile.name ?? "N/A")")
            print("   Display Name: \(profile.displayName ?? "N/A")")
            print("   About: \(profile.about ?? "N/A")")
            print("   Picture: \(profile.picture ?? "N/A")")
            print("   Banner: \(profile.banner ?? "N/A")")
            print("   Website: \(profile.website ?? "N/A")")
            print("   NIP-05: \(profile.nip05 ?? "N/A")")
            print("   LUD-16: \(profile.lud16 ?? "N/A")")
            print("   LUD-06: \(profile.lud06 ?? "N/A")")
        } else {
            print("❌ No profile found for this pubkey")
        }
        
        print("")
        print("🏁 Debug session complete")
    }
}