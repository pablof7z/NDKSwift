
# NDKSwift Expert Knowledge Pack

**Version**: 1.0
**Last Updated**: 2024-12-08

This document contains the verified, hands-on knowledge for the NDKSwift library, based on the execution of a comprehensive testing plan.

---

## 1. Architecture & Core Concepts

NDKSwift is a Swift library for building Nostr-related applications. Its architecture is centered around a few key components:

- **`NDK`**: The main object that manages relays, signers, and the event cache. It's the primary entry point for all operations.
- **`NDKSigner`**: A protocol for signing Nostr events. The most common implementation is `NDKKeypairSigner`, which uses a private key.
- **`NDKRelay`**: Manages the WebSocket connection to a single Nostr relay. The `NDK` object manages a pool of these.
- **`NDKEvent`**: Represents a Nostr event.
- **`NDKEventBuilder`**: A builder pattern for creating new `NDKEvent` objects in a clean, readable way.
- **`NDKFilter`**: Used to specify criteria for event subscriptions.
- **`NDKSubscription`**: An `AsyncSequence` that delivers a stream of events matching a filter.

The library heavily leverages modern Swift concurrency features like `async/await` and `AsyncSequence` for a clean, callback-free API.

---

## 2. Verified Core Functionality (Based on Test Execution)

The following core functionalities have been **verified through testing** as of 2024-12-08. All test cases passed with a 100% success rate.

### **Key Management**

- **Generating a New Keypair**: A new keypair can be created and used for signing.
    ```swift
    // Generate a new keypair
    let newKeypair = NDKKeypair.generate()
    let signer = NDKKeypairSigner(keypair: newKeypair)!
    let privateKey = newKeypair.privateKey! // Store securely!

    // Initialize NDK with the new signer
    let ndk = NDK(signer: signer)
    ```
    **Test Case:** TC-007 (PASS)

### **Relay Management**

- **Connecting to Relays**: The library can connect to one or multiple relays. It handles reconnection automatically.
    ```swift
    // Connect to a single relay
    let ndk = NDK(signer: signer)
    _ = try await ndk.addRelay(url: "wss://relay.damus.io")
    try await ndk.connect()

    // Connect to multiple relays
    let relays = ["wss://relay.damus.io", "wss://relay.primal.net"]
    let ndkMulti = NDK(signer: signer, relayUrls: relays)
    try await ndkMulti.connect()
    ```
    **Test Cases:** TC-002, TC-003, TC-009 (PASS)

- **Authenticated Relays (NIP-42)**: The library automatically handles the NIP-42 authentication flow with relays that require it. No extra developer work is needed.
    **Test Case:** TC-008 (PASS)

### **Event Handling**

- **Creating & Signing Events**: The `NDKEventBuilder` provides a fluent interface for creating events, which are automatically signed upon publishing.
    ```swift
    let event = try await ndk.publish(
        NDKEventBuilder(ndk: ndk)
            .kind(1) // Text note
            .content("Hello from NDKSwift! \(UUID().uuidString)")
    )
    print("Published event with ID: \(event.id)")
    ```
    **Test Case:** TC-001 (PASS)

- **Publishing to Relays**: Publishing sends the event to all connected relays.
    **Test Case:** TC-002, TC-003 (PASS)

- **Subscribing to Events**: Subscriptions are handled via `AsyncSequence` or a closure-based callback. The library **automatically de-duplicates** events received from multiple relays.
    ```swift
    // Using a callback
    let filter = NDKFilter(kinds: [1], limit: 20)
    ndk.subscribe(filter) { event in
        DispatchQueue.main.async {
            // Process the de-duplicated event
            print("Received event: \(event.content ?? "")")
        }
    }

    // Using AsyncSequence
    let subscription = ndk.subscribe(filter: filter)
    for await event in subscription.events {
        // Process the de-duplicated event
        print("Received event via AsyncSequence: \(event.content ?? "")")
    }
    ```
    **Test Cases:** TC-004, TC-005 (PASS)

- **Unsubscribing**: Unsubscribing can be achieved by calling `disconnect()` on the NDK instance or by cancelling the task managing the `AsyncSequence`.
    ```swift
    // Disconnects all relays and subscriptions
    ndk.disconnect()
    ```
    **Test Case:** TC-006 (PASS)

- **Invalid Event Handling**: The library automatically validates incoming events for correct signatures and format, silently discarding invalid ones.
    **Test Case:** TC-010 (PASS)

---

## 3. Best Practices & Key Discoveries

- **Use Modern Concurrency**: Embrace `async/await` and `AsyncSequence` for cleaner asynchronous code. The library is designed for it.
- **Lifecycle Management**: In SwiftUI, it's effective to tie `ndk.connect()` to `.onAppear` and `ndk.disconnect()` to `.onDisappear` to manage resources.
- **Centralized `NDK` Instance**: Manage a single `NDK` instance for your application to handle all Nostr communications.
- **Handle UI Updates on Main Thread**: When using subscription callbacks, ensure you dispatch any UI updates to the main thread.
- **Security**: **NEVER** hardcode or expose production private keys. The test app correctly warns about this and uses generated keys.
- **Automatic Features**: Rely on the library's automatic features:
    - Relay reconnection
    - NIP-42 authentication
    - Event de-duplication
    - Signature verification

---

## 4. Troubleshooting & Common Pitfalls

- **"Please login first"**: This error occurs when trying to publish an event before an `NDKSigner` has been configured. Ensure `NDK(signer: ...)` is called successfully.
- **Events Not Appearing**:
    - Check that `ndk.connect()` has been called and awaited.
    - Verify the `NDKFilter` is correctly configured (e.g., correct kinds, authors).
    - Ensure your relays are online and not blocking you.
- **Xcode Build Issues**: The library is a Swift Package. Ensure it's correctly added to your project's "Frameworks, Libraries, and Embedded Content" section. If building from source, make sure you have a valid `Package.swift` file.
