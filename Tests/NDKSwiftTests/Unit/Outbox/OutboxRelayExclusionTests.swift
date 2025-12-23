@testable import NDKSwiftCore
import XCTest

final class OutboxRelayExclusionTests: XCTestCase {
    /// Test that outbox relays are excluded from data queries for unknown authors
    func testOutboxRelaysExcludedFromUnknownAuthorQueries() async throws {
        // Create NDK with outbox configuration
        let ndk = NDK()

        // Add regular relay
        await ndk.addRelay("wss://relay.example.com")

        // Connect (which adds outbox relays)
        await ndk.connect()

        // Wait for connections
        await ndk.waitForRelayConnections(minimumRelays: 2, timeout: 5)

        // Create filter for unknown author
        let unknownAuthor = "unknownpubkey123"
        let filter = NDKFilter(authors: [unknownAuthor], kinds: [1])

        // Get outbox strategy
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)

        // Verify outbox relays are not included in filtersByRelay
        for (relay, _) in strategy.filtersByRelay {
            XCTAssertFalse(
                ndk.outboxConfig.outboxRelays.contains { outboxRelay in
                    outboxRelay.normalizedRelayURL == relay
                },
                "Outbox relay \(relay) should not receive data queries for unknown authors"
            )
        }

        // Verify unknown author is marked correctly
        XCTAssertTrue(strategy.unknownAuthors.contains(unknownAuthor))

        await ndk.disconnect()
    }

    /// Test that normalization works correctly for relay URL comparison
    func testRelayURLNormalization() {
        let urls = [
            ("wss://relay.example.com", "wss://relay.example.com/"),
            ("wss://relay.example.com/", "wss://relay.example.com/"),
            ("WSS://RELAY.EXAMPLE.COM", "wss://relay.example.com/"),
            ("wss://relay.example.com:443", "wss://relay.example.com/"),
            ("ws://relay.example.com:80", "ws://relay.example.com/"),
        ]

        for (input, expected) in urls {
            let normalized = input.normalizedRelayURL
            XCTAssertEqual(normalized, expected, "Failed to normalize \(input)")
        }
    }

    /// Test that ws:// (non-secure) relays are completely filtered from outbox strategy
    func testInsecureRelaysExcludedFromOutboxStrategy() async throws {
        // Create NDK with minimal config
        let ndk = NDK()
        let outbox = ndk.outbox

        // Track an author with both secure and insecure relays
        await outbox.track(
            pubkey: "author_with_insecure_relays",
            readRelays: [
                "wss://secure.relay.com",
                "ws://insecure.relay.com",  // Should be filtered
                "ws://2pbkpndvpeebljfvjew6auq63lndzszqnntct5aqfmazslerzxe75kad.onion",  // Should be filtered
                "wss://another-secure.relay.com"
            ],
            writeRelays: [
                "wss://write-secure.relay.com",
                "ws://write-insecure.relay.com"  // Should be filtered
            ],
            source: .nip65
        )

        // Get outbox strategy
        let filter = NDKFilter(authors: ["author_with_insecure_relays"], kinds: [1])
        let strategy = await outbox.getOutboxStrategy(for: filter)

        // Verify NO ws:// relays appear in filtersByRelay
        for (relay, _) in strategy.filtersByRelay {
            XCTAssertFalse(
                relay.hasPrefix("ws://"),
                "Insecure relay \(relay) should not appear in outbox strategy"
            )
        }

        // Verify secure relays ARE present
        let relays = Set(strategy.filtersByRelay.keys)
        XCTAssertTrue(relays.contains("wss://secure.relay.com/") || relays.contains("wss://secure.relay.com"),
            "Secure relay should be present in strategy")
    }

    /// Test that outbox relay discovery uses only outbox relays when available
    func testOutboxRelayDiscoveryUsesOutboxRelays() async throws {
        // Create NDK with custom outbox configuration
        let outboxConfig = NDKOutboxConfig(
            outboxRelays: ["wss://outbox1.example.com", "wss://outbox2.example.com"]
        )
        let ndk = NDK(outboxConfig: outboxConfig)

        // Add regular relay
        await ndk.addRelay("wss://regular.example.com")

        // Connect
        await ndk.connect()

        // Wait for connections
        await ndk.waitForRelayConnections(minimumRelays: 3, timeout: 5)

        // Verify relay pool state
        let connectedRelays = await ndk.pool.connectedRelayURLs
        XCTAssertTrue(connectedRelays.contains("wss://regular.example.com/"))
        XCTAssertTrue(connectedRelays.contains("wss://outbox1.example.com/"))
        XCTAssertTrue(connectedRelays.contains("wss://outbox2.example.com/"))

        await ndk.disconnect()
    }
}
