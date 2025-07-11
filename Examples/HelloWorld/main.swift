import Foundation
import NDKSwift

@main
struct HelloWorld {
    static func main() async throws {
        print("🚀 NDKSwift HelloWorld Example")
        print("==============================\n")
        
        // Step 1: Generate a new private key
        print("1. Generating new identity...")
        let signer = try NDKPrivateKeySigner.generate()
        let nsec = try signer.nsec
        let npub = try signer.npub
        
        print("   ✅ New identity created:")
        print("   Private key (nsec): \(nsec)")
        print("   Public key (npub): \(npub)")
        print("   ⚠️  Save your nsec securely! It's your identity.\n")
        
        // Step 2: Initialize NDK with a single reliable relay
        print("2. Initializing NDK...")
        let ndk = NDK()
        
        // Add just one relay for simplicity
        ndk.addRelay("wss://relay.damus.io")
        
        // Set the signer
        ndk.signer = signer
        print("   ✅ NDK initialized\n")
        
        // Step 3: Connect to relay
        print("3. Connecting to relay...")
        await ndk.connect()
        
        // Give it a moment to connect
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        print("   ✅ Connected\n")
        
        // Step 4: Create and publish a text note
        print("4. Creating and publishing a text note...")
        
        let note = try await NDKEventBuilder()
            .kind(EventKind.textNote)
            .content("Hello Nostr! 👋 This is my first note published using NDKSwift #helloworld")
            .build(signer: signer)
        
        print("   Event ID: \(note.id)")
        print("   Event tags: \(note.tags)")
        print("   Event content: \(note.content)")
        
        // Try to publish with a timeout
        do {
            let start = Date()
            let publishedRelays = try await withTimeout(seconds: 10) {
                try await ndk.publish(note)
            }
            let elapsed = Date().timeIntervalSince(start)
            print("   ✅ Published to \(publishedRelays.count) relay(s)")
            print("   ⏱️  Time taken: \(String(format: "%.2f", elapsed)) seconds\n")
        } catch {
            print("   ❌ Failed to publish: \(error)\n")
        }
        
        // Step 5: Display the note identifier
        print("5. Note identifiers:")
        let noteId = try Bech32.note(from: note.id)
        print("   note1: \(noteId)")
        print("   Raw ID: \(note.id)\n")
        
        print("🎉 Done! Your note should be visible on Nostr clients.")
        
        // Wait a bit to see relay responses
        print("\nWaiting for relay responses...")
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Disconnect
        await ndk.disconnect()
    }
}

// Helper function for timeout
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw NSError(domain: "Timeout", code: 0, userInfo: [NSLocalizedDescriptionKey: "Operation timed out after \(seconds) seconds"])
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}