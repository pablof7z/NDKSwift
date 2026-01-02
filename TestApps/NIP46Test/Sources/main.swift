import Foundation
import NDKSwiftCore

@main
struct NIP46Test {
    static func main() async throws {
        // Enable debug logging
        NDKLogger.setLogLevel(.debug)
        NDKLogger.setLogHandler { message in
            print(message)
        }

        print("NIP-46 Test App")
        print("===============\n")

        // Get bunker URL from command line args or prompt
        let bunkerUrl: String
        if CommandLine.arguments.count > 1 {
            bunkerUrl = CommandLine.arguments[1]
        } else {
            print("Enter your bunker:// URL:")
            print("> ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !input.isEmpty else {
                print("No bunker URL provided")
                return
            }
            bunkerUrl = input
        }

        print("\nBunker URL: \(bunkerUrl)\n")

        // Create NDK instance
        print("Creating NDK instance...")
        let ndk = NDK(relayURLs: ["wss://relay.primal.net", "wss://relay.damus.io"])

        // Create bunker signer
        print("Creating bunker signer...")
        let bunkerSigner: NDKBunkerSigner
        do {
            bunkerSigner = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: bunkerUrl)
            print("Bunker signer created successfully")
        } catch {
            print("Failed to create bunker signer: \(error)")
            return
        }

        // Connect to relays FIRST (before setting signer to avoid race condition)
        print("\nConnecting to relays...")
        await ndk.connect()
        print("Connected to relays")

        // Now set the signer and connect it
        ndk.signer = bunkerSigner

        // Connect bunker signer
        print("\nConnecting to remote signer...")
        print("(This may require approval in your signer app)")

        // Listen for auth URL in case user needs to approve
        Task {
            for await authUrl in await bunkerSigner.authUrlPublisher.values {
                print("\n[AUTH] Authorization required!")
                print("[AUTH] Open this URL: \(authUrl)")
            }
        }

        do {
            let user = try await bunkerSigner.connect()
            print("Connected to remote signer!")
            print("User pubkey: \(user)")
        } catch {
            print("Failed to connect to remote signer: \(error)")
            return
        }

        // Create and sign a kind 2121 event
        print("\nCreating kind 2121 event...")

        do {
            let (event, publishResult) = try await ndk.publish { builder in
                builder
                    .content("Test event from NIP-46 test app - \(Date())")
                    .kind(2121)
                    .tag(["client", "NDKSwift NIP-46 Test"])
            }

            print("\nEvent published successfully!")
            print("Event ID: \(event.id)")
            print("Event kind: \(event.kind)")
            print("Event content: \(event.content)")
            print("Event signature: \(event.sig)")
            print("\nPublished to \(publishResult.count) relay(s):")
            for relay in publishResult {
                print("  - \(relay.url)")
            }
        } catch {
            print("Failed to publish event: \(error)")
        }

        // Wait a moment before disconnecting
        print("\nWaiting 2 seconds...")
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Disconnect
        print("\nDisconnecting...")
        await bunkerSigner.disconnect()
        await ndk.disconnect()

        print("\nTest completed!")
    }
}
