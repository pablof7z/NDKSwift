// Example06_OutboxModel.swift
// This example demonstrates NIP-65 outbox model implementation
// It observes kind:1 events for a specific pubkey and shows how NDK
// automatically fetches the user's relay list (kind:10002) and routes
// requests to the appropriate relays

import Foundation
import NDKSwift

public func runOutboxExample() async throws {
    // Fiatjaf's public key
    let fiatjafPubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"

    // Create NDK instance with initial relay
    let ndk = NDK(relayUrls: ["wss://purplepag.es"])
    print("Connecting to wss://purplepag.es...")
    await ndk.connect()
    print("Connected successfully!\n")

    // Create a filter for kind:1 events from fiatjaf with limit 1
    let filter = NDKFilter(
        authors: [fiatjafPubkey],
        kinds: [1],
        limit: 1
    )

    print("Creating observer for kind:1 events from fiatjaf...")
    print("NDK will automatically fetch the user's relay list (kind:10002)")
    print("and route the REQ to appropriate relays per NIP-65\n")

    // Create observer using the observe API
    let observer = ndk.subscribe(filter: filter)

    print("Observer created. Waiting for events...\n")

    // Process events
    for await event in observer.events {
        print("Received event:")
        print("- ID: \(event.id)")
        print("- Created at: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)))")
        print("- Content: \(event.content)")
        print("")

        // Since we have limit:1, we can break after first event
        break
    }

    print("\nFetching user's relay list (kind:10002) directly to inspect...")
    let relayListFilter = NDKFilter(
        authors: [fiatjafPubkey],
        kinds: [EventKind.relayList]
    )

    // Use observe to fetch a single event
    let relayListObserver = ndk.subscribe(filter: relayListFilter)
    var relayListEvent: NDKEvent?

    for await event in relayListObserver.events {
        relayListEvent = event
        break // Just get the first one
    }

    if let relayListEvent = relayListEvent {
        print("User's relay list (kind:10002):")
        print("- Event ID: \(relayListEvent.id)")

        // Parse relay list
        var writeRelays: [String] = []
        var readRelays: [String] = []

        for tag in relayListEvent.tags {
            if tag.count >= 2, tag[0] == "r" {
                let relay = tag[1]
                if tag.count >= 3 {
                    if tag[2] == "write" {
                        writeRelays.append(relay)
                    } else if tag[2] == "read" {
                        readRelays.append(relay)
                    }
                } else {
                    // No marker means both read and write
                    writeRelays.append(relay)
                    readRelays.append(relay)
                }
            }
        }

        print("\nRead relays (where we fetch events from):")
        for relay in readRelays {
            print("- \(relay)")
        }

        print("\nWrite relays (where user publishes to):")
        for relay in writeRelays {
            print("- \(relay)")
        }

        print("\nNDK automatically used the read relays to fetch kind:1 events!")
    } else {
        print("No relay list found for user")
    }

    // Show final relay pool state
    print("\nFinal relay pool state:")
    let relays = await ndk.relays
    for relay in relays {
        print("- \(relay.url)")
    }
}
