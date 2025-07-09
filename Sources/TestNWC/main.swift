import Foundation

// Print immediately before any imports
fputs("TestNWC starting...\n", stdout)
fflush(stdout)

import NDKSwift

fputs("NDKSwift imported\n", stdout)
fflush(stdout)

print("Starting TestNWC...")

// Simple test to debug NWC
let semaphore = DispatchSemaphore(value: 0)

Task {
    print("Task started")
    
    do {
        print("Creating NDK...")
        let ndk = NDK()
        
        print("Adding relays...")
        _ = ndk.addRelay("wss://relay.primal.net")
        _ = ndk.addRelay("wss://relay.damus.io")
        
        print("Connecting to relays...")
        await ndk.connect()
        
        print("Waiting for connections...")
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        print("Checking relay states:")
        for relay in await ndk.relays {
            print("  \(relay.url): \(relay.connectionState)")
        }
        
        print("Creating NWC wallet...")
        let connectionURI = "nostr+walletconnect://80b93a43f0cd322ebdf4ef349baba9970881298976cfd393cfcec85024f6744c?relay=wss://relay.primal.net&relay=wss://relay.damus.io&secret=a6af65b6b002efeed42cd99b93c7dd3f7642e8708910ff6a233b2d2f77f2b06a"
        
        let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: connectionURI)
        print("Wallet created")
        
        print("Connecting wallet...")
        try await wallet.connect()
        print("Wallet connected!")
        
        print("Getting balance...")
        let balance: Int64 = try await wallet.getBalance()
        print("Balance: \(balance) msat")
        
    } catch {
        print("Error: \(error)")
    }
    
    semaphore.signal()
}

print("Waiting for task...")
semaphore.wait()
print("Done!")