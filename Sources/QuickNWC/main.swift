import Foundation

print("Starting QuickNWC...")
fflush(stdout)

import NDKSwift

print("Imports completed...")
fflush(stdout)

let semaphore = DispatchSemaphore(value: 0)
print("Semaphore created...")
fflush(stdout)

Task {
    print("In Task...")
    fflush(stdout)
    
    do {
        print("About to create NDK...")
        fflush(stdout)
        let ndk = NDK()
        print("NDK created")
        fflush(stdout)
        
        // Add and connect to relays
        print("Adding relays...")
        fflush(stdout)
        ndk.addRelay("wss://relay.primal.net")
        ndk.addRelay("wss://relay.damus.io")
        ndk.addRelay("wss://relay.8333.space/")
        ndk.addRelay("wss://nos.lol")
        
        print("Connecting to relays...")
        fflush(stdout)
        await ndk.connect()
        
        // Wait for connections
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        print("Relays connected")
        fflush(stdout)
        
        let connectionURI = "nostr+walletconnect://80b93a43f0cd322ebdf4ef349baba9970881298976cfd393cfcec85024f6744c?relay=wss://relay.primal.net&relay=wss://relay.damus.io&relay=wss://relay.8333.space/&relay=wss://nos.lol&secret=a6af65b6b002efeed42cd99b93c7dd3f7642e8708910ff6a233b2d2f77f2b06a"
        
        print("Creating wallet...")
        fflush(stdout)
        let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: connectionURI)
        print("Wallet created")
        fflush(stdout)
        
        print("Connecting...")
        fflush(stdout)
        
        print("About to call wallet.connect()...")
        fflush(stdout)
        
        try await wallet.connect()
        
        print("Connected!")
        fflush(stdout)
        
        let balance: Int64 = try await wallet.getBalance()
        print("Balance: \(balance) sats")
        
    } catch {
        print("Error: \(error)")
    }
    
    semaphore.signal()
}

print("Waiting...")
fflush(stdout)
semaphore.wait()
print("Done!")