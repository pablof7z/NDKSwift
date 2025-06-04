#!/usr/bin/env swift

import Foundation
import NDKSwift

// This script demonstrates how to test the bunker connection with debugging

@main
struct TestBunkerConnection {
    static func main() async {
        print("=== Testing NDKSwift Bunker Connection ===\n")
        
        // Create NDK instance
        let ndk = NDK()
        ndk.debugMode = true
        
        // Example bunker URLs - replace with your actual bunker URL
        let exampleUrls = [
            "bunker://bunker-pubkey?relay=wss://relay.nsec.app&secret=your-secret",
            "bunker://bunker-pubkey?relay=wss://relay.nsecbunker.com",
        ]
        
        print("Example bunker URL formats:")
        for url in exampleUrls {
            print("  - \(url)")
        }
        
        print("\nTo test bunker connection:")
        print("1. Start the iOS app")
        print("2. Click 'Login with Bunker'")
        print("3. Enter your bunker URL")
        print("4. Watch the Xcode console for debug output")
        
        print("\nDebug output will show:")
        print("- [ViewModel] messages from the iOS app")
        print("- [BunkerSigner] messages from bunker connection")
        print("- [RPC] messages from the RPC client")
        print("- Relay connection status")
        
        print("\nCommon issues to check:")
        print("1. Ensure the relay URL in the bunker string is correct")
        print("2. Check that the bunker pubkey is valid")
        print("3. Verify the secret matches what's configured in your bunker")
        print("4. Make sure the relay is accessible and supports NIP-46")
        
        print("\nFor nsec.app users:")
        print("- Get your bunker URL from https://nsec.app")
        print("- Make sure to include the relay parameter")
        print("- The URL should look like: bunker://pubkey?relay=wss://relay.nsec.app&secret=xxx")
    }
}