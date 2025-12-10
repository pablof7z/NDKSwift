import XCTest
import Foundation
@testable import NDKSwiftCore

final class NDKListTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        ndk.signer = signer
    }
    
    override func tearDown() async throws {
        ndk = nil
        signer = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        let list = NDKList(ndk: ndk)
        XCTAssertEqual(list.kind, 0)
        XCTAssertTrue(list.allItems.isEmpty)
        XCTAssertTrue(list.publicItems.isEmpty)
        XCTAssertNotNil(list.ndk)
    }
    
    func testInitializationWithKind() {
        let list = NDKList(ndk: ndk, kind: EventKind.muteList)
        XCTAssertEqual(list.kind, EventKind.muteList)
    }
    
    func testSupportedKinds() {
        XCTAssertTrue(NDKList.supportedKinds.contains(EventKind.contacts))
        XCTAssertTrue(NDKList.supportedKinds.contains(EventKind.muteList))
        XCTAssertTrue(NDKList.supportedKinds.contains(EventKind.pinList))
        XCTAssertTrue(NDKList.supportedKinds.contains(EventKind.relayList))
        XCTAssertTrue(NDKList.supportedKinds.contains(EventKind.bookmarkList))
    }
    
    // MARK: - Metadata Tests
    
    func testTitleManagement() {
        let list = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        
        // Test default title
        XCTAssertEqual(list.title, "Bookmarks")
        
        // Set custom title
        list.title = "My Custom Bookmarks"
        XCTAssertEqual(list.title, "My Custom Bookmarks")
        
        // Verify title tag was added
        let titleTag = list.tags.first { $0.count > 1 && $0[0] == "title" }
        XCTAssertNotNil(titleTag)
        XCTAssertEqual(titleTag?[1], "My Custom Bookmarks")
        
        // Remove title
        list.title = nil
        XCTAssertEqual(list.title, "Bookmarks") // Should fall back to default
    }
    
    func testDescriptionManagement() {
        let list = NDKList(ndk: ndk)
        
        XCTAssertNil(list.listDescription)
        
        list.listDescription = "This is a test list"
        XCTAssertEqual(list.listDescription, "This is a test list")
        
        // Verify description tag was added
        let descTag = list.tags.first { $0.count > 1 && $0[0] == "description" }
        XCTAssertNotNil(descTag)
        XCTAssertEqual(descTag?[1], "This is a test list")
        
        // Remove description
        list.listDescription = nil
        XCTAssertNil(list.listDescription)
    }
    
    func testImageManagement() {
        let list = NDKList(ndk: ndk)
        
        XCTAssertNil(list.image)
        
        list.image = "https://example.com/image.jpg"
        XCTAssertEqual(list.image, "https://example.com/image.jpg")
        
        // Verify image tag was added
        let imageTag = list.tags.first { $0.count > 1 && $0[0] == "image" }
        XCTAssertNotNil(imageTag)
        XCTAssertEqual(imageTag?[1], "https://example.com/image.jpg")
    }
    
    // MARK: - Item Management Tests
    
    func testAddUserItem() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.muteList)
        let user = NDKUser(pubkey: "test-pubkey")
        
        try await list.addItem(user)
        
        XCTAssertEqual(list.allItems.count, 1)
        XCTAssertTrue(list.contains("test-pubkey"))
        
        // Verify tag format
        let tag = list.publicItems.first
        XCTAssertEqual(tag, ["p", "test-pubkey"])
    }
    
    func testAddEventItem() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        let event = NDKEvent(
            id: "event-id",
            pubkey: "author-pubkey",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test event",
            sig: "sig"
        )
        
        try await list.addItem(event)
        
        XCTAssertEqual(list.allItems.count, 1)
        XCTAssertTrue(list.contains("event-id"))
        
        // Verify tag format
        let tag = list.publicItems.first
        XCTAssertEqual(tag, ["e", "event-id"])
    }
    
    func testAddParameterizedReplaceableEventItem() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        let event = NDKEvent(
            id: "event-id",
            pubkey: "author-pubkey",
            createdAt: Timestamp.now,
            kind: 30023, // Long-form content
            tags: [["d", "article-id"]],
            content: "Test article",
            sig: "sig"
        )
        
        try await list.addItem(event)
        
        XCTAssertEqual(list.allItems.count, 1)
        XCTAssertTrue(list.contains("30023:author-pubkey:article-id"))
        
        // Verify tag format
        let tag = list.publicItems.first
        XCTAssertEqual(tag, ["a", "30023:author-pubkey:article-id"])
    }
    
    func testAddRelayItem() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.searchRelays)
        let relay = NDKRelay(url: "wss://relay.example.com")
        
        try await list.addItem(relay)
        
        XCTAssertEqual(list.allItems.count, 1)
        XCTAssertTrue(list.contains("wss://relay.example.com"))
        
        // Verify tag format
        let tag = list.publicItems.first
        XCTAssertEqual(tag, ["r", "wss://relay.example.com"])
    }
    
    func testAddItemWithMark() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        let user = NDKUser(pubkey: "test-pubkey")
        
        try await list.addItem(user, mark: "favorite")
        
        let tag = list.publicItems.first
        XCTAssertEqual(tag, ["p", "test-pubkey", "favorite"])
    }
    
    func testAddItemPosition() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        
        // Add items at bottom (default)
        try await list.addItem(NDKUser(pubkey: "user1"))
        try await list.addItem(NDKUser(pubkey: "user2"))
        
        // Add item at top
        try await list.addItem(NDKUser(pubkey: "user3"), position: .top)
        
        let pubkeys = list.publicItems.compactMap { tag in
            tag.count > 1 && tag[0] == "p" ? tag[1] : nil
        }
        
        XCTAssertEqual(pubkeys, ["user3", "user1", "user2"])
    }
    
    func testAddDuplicateItem() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.muteList)
        let user = NDKUser(pubkey: "test-pubkey")
        
        try await list.addItem(user)
        try await list.addItem(user) // Should not add duplicate
        
        XCTAssertEqual(list.allItems.count, 1)
    }
    
    // MARK: - Item Removal Tests
    
    func testRemoveItemByReference() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.muteList)
        
        // Add multiple items
        try await list.addItem(NDKUser(pubkey: "user1"))
        try await list.addItem(NDKUser(pubkey: "user2"))
        try await list.addItem(NDKUser(pubkey: "user3"))
        
        XCTAssertEqual(list.allItems.count, 3)
        
        // Remove by reference
        try await list.removeItem(byReference: "user2")
        
        XCTAssertEqual(list.allItems.count, 2)
        XCTAssertFalse(list.contains("user2"))
        XCTAssertTrue(list.contains("user1"))
        XCTAssertTrue(list.contains("user3"))
    }
    
    func testRemoveItemByIndex() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        
        // Add items
        try await list.addItem(NDKUser(pubkey: "user1"))
        try await list.addItem(NDKUser(pubkey: "user2"))
        try await list.addItem(NDKUser(pubkey: "user3"))
        
        // Remove middle item
        try await list.removeItem(at: 1, encrypted: false)
        
        XCTAssertEqual(list.allItems.count, 2)
        let remainingPubkeys = list.userPubkeys
        XCTAssertEqual(remainingPubkeys, ["user1", "user3"])
    }
    
    // MARK: - Convenience Methods Tests
    
    func testAddHashtag() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.interestList)
        
        try await list.addHashtag("bitcoin")
        try await list.addHashtag("#nostr") // With # prefix
        
        XCTAssertEqual(list.hashtags.sorted(), ["bitcoin", "nostr"])
        
        // Verify tags don't have # prefix
        let hashtagTags = list.publicItems.filter { $0.count > 1 && $0[0] == "t" }
        XCTAssertEqual(hashtagTags.count, 2)
        XCTAssertTrue(hashtagTags.contains(["t", "bitcoin"]))
        XCTAssertTrue(hashtagTags.contains(["t", "nostr"]))
    }
    
    func testAddURL() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        
        try await list.addURL("https://example.com/article1")
        try await list.addURL("https://example.com/article2")
        
        XCTAssertEqual(list.urls.sorted(), [
            "https://example.com/article1",
            "https://example.com/article2"
        ])
    }
    
    // MARK: - Query Methods Tests
    
    func testItemQueries() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        
        // Add various types of items
        try await list.addItem(NDKUser(pubkey: "user1"))
        try await list.addItem(NDKUser(pubkey: "user2"))
        
        let event1 = NDKEvent(id: "event1", pubkey: "author", createdAt: 0, kind: 1, tags: [], content: "", sig: "")
        let event2 = NDKEvent(id: "event2", pubkey: "author", createdAt: 0, kind: 1, tags: [], content: "", sig: "")
        try await list.addItem(event1)
        try await list.addItem(event2)
        
        try await list.addHashtag("bitcoin")
        try await list.addURL("https://example.com")
        
        // Test queries
        XCTAssertEqual(list.userPubkeys.sorted(), ["user1", "user2"])
        XCTAssertEqual(list.eventIds.sorted(), ["event1", "event2"])
        XCTAssertEqual(list.hashtags, ["bitcoin"])
        XCTAssertEqual(list.urls, ["https://example.com"])
    }
    
    // MARK: - Filter Creation Tests
    
    func testFiltersForItems() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        
        // Add users (should create profile filter)
        try await list.addItem(NDKUser(pubkey: "user1"))
        try await list.addItem(NDKUser(pubkey: "user2"))
        
        // Add events (should create event filter)
        let event1 = NDKEvent(id: "event1", pubkey: "author", createdAt: 0, kind: 1, tags: [], content: "", sig: "")
        let event2 = NDKEvent(id: "event2", pubkey: "author", createdAt: 0, kind: 1, tags: [], content: "", sig: "")
        try await list.addItem(event1)
        try await list.addItem(event2)
        
        // Add parameterized replaceable event
        let article = NDKEvent(
            id: "article-id",
            pubkey: "author-pubkey",
            createdAt: 0,
            kind: 30023,
            tags: [["d", "my-article"]],
            content: "",
            sig: ""
        )
        try await list.addItem(article)
        
        let filters = list.filtersForItems()
        
        // Should have 3 filters: events, profiles, and parameterized replaceable
        XCTAssertEqual(filters.count, 3)
        
        // Check event filter
        let eventFilter = filters.first { $0.ids != nil }
        XCTAssertNotNil(eventFilter)
        XCTAssertEqual(eventFilter?.ids?.sorted(), ["event1", "event2"])
        
        // Check profile filter
        let profileFilter = filters.first { $0.kinds == [0] }
        XCTAssertNotNil(profileFilter)
        XCTAssertEqual(profileFilter?.authors?.sorted(), ["user1", "user2"])
        
        // Check parameterized replaceable filter
        let articleFilter = filters.first { $0.kinds == [30023] }
        XCTAssertNotNil(articleFilter)
        XCTAssertEqual(articleFilter?.authors, ["author-pubkey"])
    }
    
    // MARK: - Blacklist/Blocklist Tests
    
    func testMuteListHelpers() {
        let muteList = NDKList(ndk: ndk, kind: EventKind.muteList)
        XCTAssertTrue(muteList.isMuteList)
        XCTAssertFalse(muteList.isBlockedRelaysList)
        
        let otherList = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        XCTAssertFalse(otherList.isMuteList)
    }
    
    func testMintBlacklisting() async throws {
        let muteList = NDKList(ndk: ndk, kind: EventKind.muteList)
        
        try await muteList.addURL("https://mint.example.com")
        try await muteList.addURL("https://fedimint.example.com")
        try await muteList.addURL("https://regular-site.com")
        
        XCTAssertTrue(muteList.isMintBlacklisted("https://mint.example.com"))
        XCTAssertTrue(muteList.isMintBlacklisted("https://fedimint.example.com"))
        XCTAssertFalse(muteList.isMintBlacklisted("https://other-mint.com"))
        
        let blacklistedMints = muteList.blacklistedMints
        XCTAssertEqual(blacklistedMints.count, 2)
        XCTAssertTrue(blacklistedMints.contains("https://mint.example.com"))
        XCTAssertTrue(blacklistedMints.contains("https://fedimint.example.com"))
    }
    
    func testRelayBlocking() async throws {
        let blockedRelaysList = NDKList(ndk: ndk, kind: EventKind.blockedRelays)
        
        try await blockedRelaysList.addURL("wss://blocked-relay.com")
        try await blockedRelaysList.addURL("wss://another-blocked.com/")
        
        // Test with normalization
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("wss://blocked-relay.com/"))
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("WSS://BLOCKED-RELAY.COM"))
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("wss://another-blocked.com"))
        XCTAssertFalse(blockedRelaysList.isRelayBlocked("wss://good-relay.com"))
        
        let blockedRelays = blockedRelaysList.blockedRelays
        XCTAssertEqual(blockedRelays.count, 2)
    }
    
    // MARK: - Event Conversion Tests
    
    func testToNDKEvent() async throws {
        let list = NDKList(ndk: ndk, kind: EventKind.bookmarkList)
        list.id = "test-id"
        list.pubkey = "test-pubkey"
        list.createdAt = 12345
        list.signature = "test-signature"
        list.title = "My Bookmarks"
        
        try await list.addItem(NDKUser(pubkey: "user1"))
        
        let event = list.toNDKEvent()
        
        XCTAssertEqual(event.id, "test-id")
        XCTAssertEqual(event.pubkey, "test-pubkey")
        XCTAssertEqual(event.createdAt, 12345)
        XCTAssertEqual(event.kind, EventKind.bookmarkList)
        XCTAssertEqual(event.sig, "test-signature")
        
        // Check tags include both metadata and items
        XCTAssertTrue(event.tags.contains(["title", "My Bookmarks"]))
        XCTAssertTrue(event.tags.contains(["p", "user1"]))
    }
    
    func testFromEvent() {
        let event = NDKEvent(
            id: "original-id",
            pubkey: "original-pubkey",
            createdAt: 99999,
            kind: EventKind.muteList,
            tags: [
                ["title", "My Mute List"],
                ["p", "muted-user1"],
                ["p", "muted-user2"],
                ["e", "muted-event"]
            ],
            content: "",
            sig: "original-sig"
        )
        
        let list = NDKList.from(event, ndk: ndk)
        
        XCTAssertEqual(list.id, "original-id")
        XCTAssertEqual(list.pubkey, "original-pubkey")
        XCTAssertEqual(list.createdAt, 99999)
        XCTAssertEqual(list.kind, EventKind.muteList)
        XCTAssertEqual(list.signature, "original-sig")
        XCTAssertEqual(list.title, "My Mute List")
        XCTAssertEqual(list.userPubkeys.sorted(), ["muted-user1", "muted-user2"])
        XCTAssertEqual(list.eventIds, ["muted-event"])
    }
}