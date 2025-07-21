#!/usr/bin/env swift

import Foundation
@testable import NDKSwift

// Run basic E2E test as a standalone script
@main
struct BasicE2ERunner {
    static func main() async throws {
        print("Starting basic E2E test runner at \(timestamp())")
        
        // Create NDK instances
        let publisherNDK = NDK(cache: MemoryCache())
        let subscriberNDK = NDK(cache: MemoryCache())
        
        // Create signer
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        publisherNDK.signer = signer
        
        print("[\(timestamp())] Generated keypair, pubkey: \(pubkey)")
        
        // Add relays
        let relayURLs = [
            "wss://relay.damus.io",
            "wss://relay.nostr.band",
            "wss://nos.lol"
        ]
        
        for relay in relayURLs {
            await publisherNDK.addRelay(relay)
            await subscriberNDK.addRelay(relay)
        }
        
        // Connect
        print("[\(timestamp())] Connecting to relays...")
        await publisherNDK.connect()
        await subscriberNDK.connect()
        
        // Wait for connections
        let pubConnected = await publisherNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        let subConnected = await subscriberNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        guard pubConnected > 0, subConnected > 0 else {
            print("[\(timestamp())] ❌ Failed to connect to relays")
            exit(1)
        }
        
        print("[\(timestamp())] ✅ Connected to relays")
        
        // Create event
        let content = "Hello from NDKSwift E2E test at \(Date())"
        let event = try await publisherNDK.event()
            .content(content)
            .kind(EventKind.textNote)
            .build()
        
        print("[\(timestamp())] Created event: \(event.id)")
        
        // Subscribe before publishing
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.textNote],
            limit: 10
        )
        
        let dataSource = subscriberNDK.observe(filter: filter)
        var receivedEvent = false
        
        // Start observing
        Task {
            print("[\(timestamp())] Starting subscription...")
            for await receivedEvent in dataSource.events {
                print("[\(timestamp())] 📝 Received event: \(receivedEvent.id)")
                if receivedEvent.id == event.id {
                    print("[\(timestamp())] ✅ Found our event!")
                    receivedEvent = true
                    break
                }
            }
        }
        
        // Wait a bit for subscription to establish
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Publish
        print("[\(timestamp())] Publishing event...")
        let publishedRelays = try await publisherNDK.publish(event)
        print("[\(timestamp())] Published to \(publishedRelays.count) relays")
        
        // Wait for event to be received
        let timeout = Date().addingTimeInterval(10.0)
        while !receivedEvent && Date() < timeout {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        if receivedEvent {
            print("[\(timestamp())] ✅ Test passed!")
        } else {
            print("[\(timestamp())] ❌ Test failed - event not received")
        }
        
        // Disconnect
        await publisherNDK.disconnect()
        await subscriberNDK.disconnect()
        
        print("[\(timestamp())] Test completed")
    }
    
    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}