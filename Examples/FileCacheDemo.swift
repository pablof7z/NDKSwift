import Foundation
import NDKSwift

// Comprehensive File-based Cache Demo for NDKSwift
@main
struct FileCacheDemo {
    static func main() async {
        print("🚀 NDKSwift File-based Cache Demo")
        print("=================================")
        
        do {
            // 1. Initialize File cache
            print("\n📊 1. Initializing File Cache")
            print("=============================")
            
            let cache = try NDKFileCache(path: "demo-file-cache")
            print("✅ File cache initialized at: demo-file-cache")
            
            // 2. Create NDK instance with File cache
            print("\n🏗️ 2. Creating NDK with File Cache")
            print("==================================")
            
            let ndk = NDK(
                relayUrls: [
                    "wss://relay.damus.io",
                    "wss://nos.lol"
                ],
                cacheAdapter: cache
            )
            
            print("✅ NDK created with File cache adapter")
            print("   Cache directory: demo-file-cache")
            print("   Relays: \(ndk.relays.count)")
            
            // 3. Test event caching
            print("\n📝 3. Testing Event Caching")
            print("==========================")
            
            // Create test events
            let testEvents = createTestEvents()
            
            // Cache events
            print("\nCaching \(testEvents.count) test events...")
            for event in testEvents {
                await cache.setEvent(event, filters: [], relay: nil)
            }
            print("✅ Events cached successfully")
            
            // 4. Test event querying
            print("\n🔍 4. Testing Event Queries")
            print("==========================")
            
            // Query all text notes
            let textNoteFilter = NDKFilter(kinds: [EventKind.textNote])
            let textNoteSubscription = NDKSubscription(filters: [textNoteFilter])
            // textNoteSubscription uses ndk internally
            
            let textNotes = await cache.query(subscription: textNoteSubscription)
            print("✅ Found \(textNotes.count) text notes")
            
            // Query by author
            let authorFilter = NDKFilter(
                authors: ["d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"]
            )
            let authorSubscription = NDKSubscription(filters: [authorFilter])
            // authorSubscription uses ndk internally
            
            let authorEvents = await cache.query(subscription: authorSubscription)
            print("✅ Found \(authorEvents.count) events from specific author")
            
            // Query with time range
            let oneHourAgo = Timestamp(Date().timeIntervalSince1970 - 3600)
            let timeFilter = NDKFilter(
                kinds: [EventKind.textNote],
                since: oneHourAgo
            )
            let timeSubscription = NDKSubscription(filters: [timeFilter])
            // timeSubscription uses ndk internally
            
            let recentEvents = await cache.query(subscription: timeSubscription)
            print("✅ Found \(recentEvents.count) events from last hour")
            
            // 5. Test profile caching
            print("\n👤 5. Testing Profile Caching")
            print("============================")
            
            let testProfiles = createTestProfiles()
            
            // Cache profiles
            print("\nCaching \(testProfiles.count) test profiles...")
            for (pubkey, profile) in testProfiles {
                await cache.saveProfile(pubkey: pubkey, profile: profile)
            }
            print("✅ Profiles cached successfully")
            
            // Fetch cached profiles
            for (pubkey, _) in testProfiles {
                if let profile = await cache.fetchProfile(pubkey: pubkey) {
                    print("✅ Retrieved profile: \(profile.displayName ?? profile.name ?? "Unknown")")
                }
            }
            
            // 6. Test unpublished events
            print("\n📤 6. Testing Unpublished Events")
            print("===============================")
            
            let unpublishedEvent = NDKEvent(
                pubkey: "test_pubkey",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                content: "This event is waiting to be published"
            )
            unpublishedEvent.id = "unpublished_\(UUID().uuidString)"
            
            await cache.addUnpublishedEvent(unpublishedEvent, relayUrls: [
                "wss://relay.damus.io",
                "wss://nos.lol"
            ])
            print("✅ Added unpublished event")
            
            let unpublished = await cache.getUnpublishedEvents()
            print("✅ Retrieved \(unpublished.count) unpublished events")
            
            if let first = unpublished.first {
                print("   Event: \(first.event.content)")
                print("   Relays: \(first.relays.joined(separator: ", "))")
                print("   Last try: \(first.lastTryAt)")
                
                // Discard it
                if let eventId = first.event.id {
                    await cache.discardUnpublishedEvent(eventId)
                }
                print("✅ Discarded unpublished event")
            }
            
            // 7. Test replaceable events
            print("\n🔄 7. Testing Replaceable Events")
            print("===============================")
            
            // Create metadata event (replaceable)
            let metadata1 = NDKEvent(
                pubkey: "replaceable_test_pubkey",
                createdAt: Timestamp(Date().timeIntervalSince1970 - 1000),
                kind: EventKind.metadata,
                content: """
                {
                    "name": "oldname",
                    "about": "Old description"
                }
                """
            )
            metadata1.id = "metadata1"
            
            await cache.setEvent(metadata1, filters: [], relay: nil)
            print("✅ Cached first metadata event")
            
            // Create newer metadata event
            let metadata2 = NDKEvent(
                pubkey: "replaceable_test_pubkey",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.metadata,
                content: """
                {
                    "name": "newname",
                    "about": "New description",
                    "picture": "https://example.com/pic.jpg"
                }
                """
            )
            metadata2.id = "metadata2"
            
            await cache.setEvent(metadata2, filters: [], relay: nil)
            print("✅ Cached newer metadata event (should replace old one)")
            
            // Query to verify replacement
            let metadataFilter = NDKFilter(
                authors: ["replaceable_test_pubkey"],
                kinds: [EventKind.metadata]
            )
            let metadataSubscription = NDKSubscription(filters: [metadataFilter])
            // metadataSubscription uses ndk internally
            
            let metadataEvents = await cache.query(subscription: metadataSubscription)
            print("✅ Found \(metadataEvents.count) metadata event(s) (should be 1)")
            
            // 8. Test encrypted events
            print("\n🔐 8. Testing Encrypted Events")
            print("=============================")
            
            let encryptedEvent = NDKEvent(
                pubkey: "test_pubkey",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.encryptedDirectMessage,
                content: "encrypted_content_here"
            )
            encryptedEvent.id = "encrypted_\(UUID().uuidString)"
            
            await cache.setEvent(encryptedEvent, filters: [], relay: nil)
            print("✅ Cached encrypted event")
            
            // Store decrypted version
            let decryptedEvent = NDKEvent(
                pubkey: encryptedEvent.pubkey,
                createdAt: encryptedEvent.createdAt,
                kind: encryptedEvent.kind,
                content: "This is the decrypted content!"
            )
            decryptedEvent.id = encryptedEvent.id
            
            await cache.addDecryptedEvent(decryptedEvent)
            print("✅ Stored decrypted version")
            
            if let eventId = encryptedEvent.id,
               let retrieved = await cache.getDecryptedEvent(eventId: eventId) {
                print("✅ Retrieved decrypted event: \(retrieved.content)")
            }
            
            // 9. Performance test
            print("\n⚡ 9. Performance Test")
            print("=====================")
            
            let startTime = Date()
            
            // Create many events
            let manyEvents = (0..<100).map { i in
                let event = NDKEvent(
                    pubkey: "perf_test_pubkey",
                    createdAt: Timestamp(Date().timeIntervalSince1970 - Double(i)),
                    kind: EventKind.textNote,
                    content: "Performance test event #\(i)"
                )
                event.id = "perf_\(i)"
                event.addTag(["t", "performance"])
                return event
            }
            
            // Cache all events
            for event in manyEvents {
                await cache.setEvent(event, filters: [], relay: nil)
            }
            
            let cacheTime = Date().timeIntervalSince(startTime)
            print("✅ Cached 100 events in \(String(format: "%.3f", cacheTime)) seconds")
            
            // Query performance
            let queryStart = Date()
            let perfFilter = NDKFilter(
                authors: ["perf_test_pubkey"],
                kinds: [EventKind.textNote],
                tags: ["t": Set(["performance"])]
            )
            let perfSubscription = NDKSubscription(filters: [perfFilter])
            // perfSubscription uses ndk internally
            
            let perfResults = await cache.query(subscription: perfSubscription)
            let queryTime = Date().timeIntervalSince(queryStart)
            print("✅ Queried \(perfResults.count) events in \(String(format: "%.3f", queryTime)) seconds")
            
            // 10. Clear specific data
            print("\n🧹 10. Testing Selective Clearing")
            print("================================")
            
            print("Cache contains events before clearing")
            
            // Clear all data
            await cache.clear()
            print("✅ Cleared all cache data")
            
            // Verify cache is empty
            let emptyFilter = NDKFilter()
            let emptySubscription = NDKSubscription(filters: [emptyFilter])
            // emptySubscription uses ndk internally
            
            let remainingEvents = await cache.query(subscription: emptySubscription)
            print("✅ Cache now contains \(remainingEvents.count) events (should be 0)")
            
            print("\n🎉 File Cache Demo Completed!")
            print("=============================")
            print("The File cache adapter provides:")
            print("• Persistent storage across app launches")
            print("• JSON-based storage (no external dependencies)")
            print("• In-memory indexes for fast queries")
            print("• Support for all NDK event types")
            print("• Profile caching with timestamps")
            print("• Unpublished event management")
            print("• Replaceable event handling")
            print("• Encrypted event storage")
            print("• Thread-safe operations")
            print("• Easy debugging (human-readable files)")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    // Helper function to create test events
    static func createTestEvents() -> [NDKEvent] {
        let pubkeys = [
            "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        ]
        
        var events: [NDKEvent] = []
        
        // Create text notes
        for i in 0..<10 {
            let event = NDKEvent(
                pubkey: pubkeys[i % pubkeys.count],
                createdAt: Timestamp(Date().timeIntervalSince1970 - Double(i * 60)),
                kind: EventKind.textNote,
                content: "Test note #\(i) - Testing File cache functionality 🎉"
            )
            event.id = "test_event_\(i)"
            
            // Add some tags
            event.addTag(["t", "test"])
            event.addTag(["t", "filecache"])
            if i % 2 == 0 {
                event.addTag(["p", pubkeys[(i + 1) % pubkeys.count]])
            }
            
            events.append(event)
        }
        
        // Create some reactions
        for i in 0..<5 {
            let event = NDKEvent(
                pubkey: pubkeys[i % pubkeys.count],
                createdAt: Timestamp(Date().timeIntervalSince1970 - Double(i * 30)),
                kind: EventKind.reaction,
                content: i % 2 == 0 ? "+" : "🎉"
            )
            event.id = "reaction_\(i)"
            event.addTag(["e", "test_event_\(i)"])
            events.append(event)
        }
        
        return events
    }
    
    // Helper function to create test profiles
    static func createTestProfiles() -> [(String, NDKUserProfile)] {
        return [
            (
                "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
                NDKUserProfile(
                    name: "alice",
                    displayName: "Alice",
                    about: "Testing File cache with NDKSwift",
                    picture: "https://example.com/alice.jpg",
                    nip05: "alice@example.com"
                )
            ),
            (
                "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
                NDKUserProfile(
                    name: "bob",
                    displayName: "Bob",
                    about: "Another test user for File cache demo",
                    picture: "https://example.com/bob.jpg",
                    banner: "https://example.com/bob-banner.jpg",
                    website: "https://bob.example.com"
                )
            ),
            (
                "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
                NDKUserProfile(
                    name: "charlie",
                    displayName: "Charlie",
                    about: "Third test user",
                    lud16: "charlie@getalby.com"
                )
            )
        ]
    }
}