#!/usr/bin/env swift

import Foundation
import NDKSwift

// Create a simple reaction demo
Task {
    print("NDKSwift Reaction Demo")
    print("=====================")

    // Initialize NDK
    let ndk = NDK(relayURLs: ["wss://relay.damus.io"])

    // Create a test signer
    let privateKey = try Crypto.generatePrivateKey()
    let signer = NDKPrivateKeySigner(privateKey: privateKey)
    ndk.signer = signer

    try print("Created test user with pubkey: \(await signer.pubkey)")

    // Connect to relay
    print("\nConnecting to relay...")
    await ndk.connect()

    // Wait a moment for connection
    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

    // Create a test event
    let testEvent = NDKEvent(
        content: "Hello Nostr! This is a test event for reactions 🚀",
        tags: []
    )
    testEvent.ndk = ndk

    print("\nCreating and publishing test event...")
    try await testEvent.sign()
    let publishedRelays = try await ndk.publish(testEvent)
    print("Published to \(publishedRelays.count) relay(s)")

    if let eventId = testEvent.id {
        print("Event ID: \(eventId)")
        try print("Event bech32: \(testEvent.encode())")
    }

    // Wait a moment
    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

    // React to the event
    print("\nReacting to the event...")

    // React with various emojis
    let reactions = ["❤️", "+", "🤙", "🔥", "💯"]

    for reaction in reactions {
        print("  Sending reaction: \(reaction)")
        let reactionEvent = try await testEvent.react(content: reaction)
        print("  ✓ Reaction sent with ID: \(reactionEvent.id ?? "unknown")")

        // Small delay between reactions
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }

    print("\nAll reactions sent successfully!")

    // Disconnect
    await ndk.disconnect()
    print("\nDisconnected from relay. Demo complete!")

    exit(0)
}

// Keep the script running
RunLoop.main.run()
