import Foundation
import NDKSwift

enum Example10_FetchEvent {
    static func run() async throws {
        print("⚠️  NDKSwift Example: Fetch Single Events (RARELY NEEDED)")
        print("=========================================================")
        print("")
        print("⚠️  IMPORTANT: This API is for RARE edge cases only!")
        print("⚠️  Most of the time you should use subscribe() with streaming.")
        print("⚠️  Only use fetchEvent when there's NOTHING to show without the event.")
        print("")
        print("✅ Acceptable: Article detail page - can't show article without content")
        print("❌ NOT acceptable: Event previews, profiles, threads - show placeholder & stream")
        print("")

        // Setup NDK with cache
        let ndk = NDK(
            relayUrls: [
                RelayConstants.damus,
                RelayConstants.primal,
                RelayConstants.nosLol,
            ],
            cache: MemoryCache()
        )

        print("✅ Created NDK instance with cache")
        print("\n📡 Connecting to relays...")
        await ndk.connect()

        let (connected, _) = await ndk.getRelayConnectionSummary()
        print("📊 Connected to \(connected) relays\n")

        // Example 1: Fetch by hex event ID
        print("📝 Example 1: Fetch by hex event ID")
        print("-----------------------------------")
        let hexId = "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"
        let fetched1 = ndk.fetchEvent(hexId)

        // Wait briefly for the fetch
        try await Task.sleep(for: .milliseconds(500))

        if let event = fetched1.event {
            print("✅ Found event: \(event.content.prefix(50))...")
        } else if let error = fetched1.error {
            print("⚠️  Error: \(error.localizedDescription)")
        } else if fetched1.isLoading {
            print("⏳ Still loading...")
        }

        // Example 2: Fetch by note1 (bech32)
        print("\n📝 Example 2: Fetch by note1 (bech32)")
        print("-------------------------------------")
        let note1 = "note19yx9aknwfwxyu3f3x6nr24pygnj0jtzw6x7gttq8k4a5kyp58k9qd78x46"
        let fetched2 = ndk.fetchEvent(note1)

        try await Task.sleep(for: .milliseconds(500))

        if let event = fetched2.event {
            print("✅ Found event: \(event.content.prefix(50))...")
        } else if fetched2.isLoading {
            print("⏳ Still loading...")
        } else {
            print("⚠️  Event not found")
        }

        // Example 3: Fetch from NIP-10 tag
        print("\n📝 Example 3: Fetch from NIP-10 tag")
        print("-----------------------------------")
        // "e" tag format: ["e", "event-id", "relay-hint", "marker", "pubkey-hint"]
        let eTag: Tag = ["e", hexId, "wss://relay.damus.io", "reply", "pubkey123"]
        let fetched3 = ndk.fetchEvent(tag: eTag)

        try await Task.sleep(for: .milliseconds(500))

        print("Using relay hint: wss://relay.damus.io")
        if let event = fetched3.event {
            print("✅ Found event from tag")
        } else if fetched3.isLoading {
            print("⏳ Still loading...")
        } else {
            print("⚠️  Event not found")
        }

        // Example 4: Demonstrate cache-first behavior
        print("\n📝 Example 4: Cache-first behavior")
        print("----------------------------------")

        // Create and publish an event first
        let testEvent = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test event for cache demo")
            .build()

        // Save to cache
        try await ndk.cache?.saveEvent(testEvent)
        print("✅ Saved event to cache: \(testEvent.id.prefix(16))...")

        // Fetch it - should return instantly from cache
        let cachedFetch = ndk.fetchEvent(testEvent.id)

        // Check immediately (no sleep needed for cached events)
        if cachedFetch.event != nil {
            print("⚡ Event loaded instantly from cache!")
            print("   Loading state: \(cachedFetch.isLoading)")
        }

        // Example 5: Fetch addressable event (naddr)
        print("\n📝 Example 5: Fetch addressable event")
        print("-------------------------------------")
        let naddrExample = "naddr1qq..." // Would be a real naddr1 address
        print("Format: naddr1... (kind:pubkey:d-tag)")
        print("Uses kind + author + d-tag for identification")
        print("Always fetches latest version from network")

        // Cleanup
        print("\n👋 Disconnecting...")
        await ndk.disconnect()

        print("\n⚠️  When to Use fetchEvent (1% of cases):")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ Article detail page (/article/[id]) - NOTHING to show without article")
        print("✅ Dedicated event viewer (/e/[id]) - the whole page IS the event")
        print("✅ Critical dependency - operation B truly cannot proceed without event A")

        print("\n❌ When NOT to Use fetchEvent (99% of cases):")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("❌ Event previews (quote posts, mentions) → Show placeholder, stream progressively")
        print("❌ Thread/reply chains → Stream and update as events arrive")
        print("❌ User profiles in timeline → Show pubkey, enhance with metadata stream")
        print("❌ Notification feeds → Stream with for await loops")
        print("❌ Any UI that can show SOMETHING without the event")

        print("\n📚 Technical Details:")
        print("━━━━━━━━━━━━━━━━━━━━")
        print("• Returns NDKFetchedEvent with observable properties")
        print("• Non-replaceable events: cached versions skip network")
        print("• Replaceable events: update when newer found")
        print("• Supports hex, note1, nevent1, naddr1 identifiers")
        print("• Uses relay hints from bech32 and outbox model")

        print("\n🎯 Core Philosophy:")
        print("━━━━━━━━━━━━━━━━━━")
        print("NDKSwift embraces event-streaming with progressive UI updates.")
        print("Always show SOMETHING immediately, then enhance as data arrives.")
        print("Reserve fetchEvent for the rare cases where blocking is unavoidable.")
    }
}
