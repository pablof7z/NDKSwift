import NDKSwift
import Foundation

// Example: Basic usage of NDKSwift models

func demonstrateBasicUsage() {
    // Create an NDK instance
    let ndk = NDK(relayUrls: [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band"
    ])
    
    // Create a user
    let alice = NDKUser(pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e")
    
    // Set profile
    let profile = NDKUserProfile(
        name: "alice",
        displayName: "Alice",
        about: "Nostr enthusiast and developer",
        picture: "https://example.com/alice.jpg",
        nip05: "alice@example.com"
    )
    alice.updateProfile(profile)
    
    // Create an event
    let textNote = NDKEvent(
        pubkey: alice.pubkey,
        createdAt: Timestamp(Date().timeIntervalSince1970),
        kind: EventKind.textNote,
        content: "Hello Nostr! 🎉"
    )
    
    // Add tags
    textNote.addTag(["t", "introductions"])
    textNote.addTag(["t", "nostr"])
    
    // Tag another user
    let bob = NDKUser(pubkey: "e0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59f")
    textNote.tag(user: bob, marker: "mention")
    
    // Generate event ID
    do {
        let eventId = try textNote.generateID()
        print("Event ID: \(eventId)")
    } catch {
        print("Error generating event ID: \(error)")
    }
    
    // Create filters for subscriptions
    let textNoteFilter = NDKFilter(
        kinds: [EventKind.textNote],
        limit: 20
    )
    
    let alicePostsFilter = NDKFilter(
        authors: [alice.pubkey],
        kinds: [EventKind.textNote, EventKind.longFormContent]
    )
    
    // Filter with time range
    let recentFilter = NDKFilter(
        kinds: [EventKind.textNote],
        since: Timestamp(Date().timeIntervalSince1970 - 3600), // Last hour
        limit: 50
    )
    
    // Check if an event matches a filter
    if textNoteFilter.matches(event: textNote) {
        print("Event matches text note filter")
    }
    
    // Relay management
    let relay = ndk.relays.first!
    print("Relay URL: \(relay.url)")
    print("Normalized URL: \(relay.normalizedURL)")
    print("Is connected: \(relay.isConnected)")
    
    // Observe relay connection state
    relay.observeConnectionState { state in
        switch state {
        case .disconnected:
            print("Relay disconnected")
        case .connecting:
            print("Relay connecting...")
        case .connected:
            print("Relay connected!")
        case .disconnecting:
            print("Relay disconnecting...")
        case .failed(let error):
            print("Relay connection failed: \(error)")
        }
    }
}

// Example: Working with event tags
func demonstrateEventTags() {
    let event = NDKEvent(
        pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
        createdAt: Timestamp(Date().timeIntervalSince1970),
        kind: EventKind.textNote,
        tags: [
            ["e", "event123", "wss://relay.example.com", "root"],
            ["e", "event456", "wss://relay.example.com", "reply"],
            ["p", "pubkey789"],
            ["t", "nostr"],
            ["t", "development"]
        ],
        content: "This is a reply with tags"
    )
    
    // Get specific tags
    let eTags = event.tags(withName: "e")
    print("Found \(eTags.count) event tags")
    
    let tTags = event.tags(withName: "t")
    print("Hashtags: \(tTags.map { $0[1] }.joined(separator: ", "))")
    
    // Check if it's a reply
    if event.isReply {
        print("This is a reply to event: \(event.replyEventId ?? "unknown")")
    }
    
    // Get all referenced events and pubkeys
    print("Referenced events: \(event.referencedEventIds)")
    print("Referenced pubkeys: \(event.referencedPubkeys)")
}

// Example: Filter merging
func demonstrateFilterMerging() {
    let filter1 = NDKFilter(
        authors: ["alice123", "bob456", "charlie789"],
        kinds: [1, 2, 3, 4],
        since: 1000,
        until: 5000
    )
    
    let filter2 = NDKFilter(
        authors: ["bob456", "charlie789", "dave012"],
        kinds: [2, 3, 4, 5],
        since: 2000,
        until: 4000
    )
    
    if let merged = filter1.merged(with: filter2) {
        print("Merged filter:")
        print("  Authors: \(merged.authors ?? [])")
        print("  Kinds: \(merged.kinds ?? [])")
        print("  Since: \(merged.since ?? 0)")
        print("  Until: \(merged.until ?? 0)")
    } else {
        print("Filters cannot be merged (no overlap)")
    }
}