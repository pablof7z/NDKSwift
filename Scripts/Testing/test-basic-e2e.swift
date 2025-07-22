#!/usr/bin/env swift

import Foundation
@testable import NDKSwift

// Run basic E2E test as a standalone script
@main
struct BasicE2ERunner {
    static func main() async throws {
        NDKLogger.log(.info, category: .general, "Starting basic E2E test runner")
        
        // Create NDK instances
        let publisherNDK = NDK(cache: MemoryCache())
        let subscriberNDK = NDK(cache: MemoryCache())
        
        // Create signer
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        publisherNDK.signer = signer
        
        NDKLogger.log(.info, category: .signer, "Generated keypair, pubkey: \(pubkey)")
        
        // Add relays
        let relayURLs = RelayConstants.testRelays
        
        for relay in relayURLs {
            await publisherNDK.addRelay(relay)
            await subscriberNDK.addRelay(relay)
        }
        
        // Connect
        NDKLogger.log(.info, category: .connection, "Connecting to relays...")
        await publisherNDK.connect()
        await subscriberNDK.connect()
        
        // Wait for connections
        let pubConnected = await publisherNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        let subConnected = await subscriberNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        guard pubConnected > 0, subConnected > 0 else {
            NDKLogger.log(.error, category: .connection, "❌ Failed to connect to relays")
            exit(1)
        }
        
        NDKLogger.log(.info, category: .connection, "✅ Connected to relays")
        
        // Create event
        let content = "Hello from NDKSwift E2E test at \(Date())"
        let event = try await publisherNDK.event()
            .content(content)
            .kind(EventKind.textNote)
            .build()
        
        NDKLogger.log(.info, category: .event, "Created event: \(event.id)")
        
        // Subscribe before publishing
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.textNote],
            limit: 10
        )
        
        let dataSource = subscriberNDK.observe(filter: filter)
        var eventReceived = false
        
        // Start observing
        Task {
            NDKLogger.log(.info, category: .subscription, "Starting subscription...")
            for await receivedEvent in dataSource.events {
                NDKLogger.log(.debug, category: .subscription, "📝 Received event: \(receivedEvent.id)")
                if receivedEvent.id == event.id {
                    NDKLogger.log(.info, category: .subscription, "✅ Found our event!")
                    eventReceived = true
                    break
                }
            }
        }
        
        // Wait a bit for subscription to establish
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Publish
        NDKLogger.log(.info, category: .event, "Publishing event...")
        let publishedRelays = try await publisherNDK.publish(event)
        NDKLogger.log(.info, category: .event, "Published to \(publishedRelays.count) relays")
        
        // Wait for event to be received
        let timeout = Date().addingTimeInterval(10.0)
        while !eventReceived && Date() < timeout {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        if eventReceived {
            NDKLogger.log(.info, category: .general, "✅ Test passed!")
        } else {
            NDKLogger.log(.error, category: .general, "❌ Test failed - event not received")
        }
        
        // Disconnect
        await publisherNDK.disconnect()
        await subscriberNDK.disconnect()
        
        NDKLogger.log(.info, category: .general, "Test completed")
    }
}