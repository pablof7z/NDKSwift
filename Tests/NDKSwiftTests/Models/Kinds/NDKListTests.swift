@testable import NDKSwift
import XCTest

final class NDKListTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var testUser: NDKUser!

    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        signer = NDKPrivateKeySigner.generate()
        testUser = NDKUser(pubkey: signer.publicKey)
        testUser.ndk = ndk
        ndk.signer = signer
    }

    override func tearDown() async throws {
        ndk = nil
        signer = nil
        testUser = nil
        try await super.tearDown()
    }

    // MARK: - Basic NDKList Tests

    func testListInitialization() {
        let list = NDKList(ndk: ndk, kind: 10001)

        XCTAssertEqual(list.kind, 10001)
        XCTAssertEqual(list.ndk, ndk)
        XCTAssertTrue(list.tags.isEmpty)
        XCTAssertTrue(list.content.isEmpty)
    }

    func testListTitleManagement() {
        let list = NDKList(ndk: ndk, kind: 10001)

        // Test default title
        XCTAssertEqual(list.title, "Pinned")

        // Test setting custom title
        list.title = "My Custom List"
        XCTAssertEqual(list.title, "My Custom List")
        XCTAssertTrue(list.tags.contains { $0.type == "title" && $0.value == "My Custom List" })

        // Test clearing title
        list.title = nil
        XCTAssertEqual(list.title, "Pinned") // Should fall back to default
    }

    func testListMetadata() {
        let list = NDKList(ndk: ndk, kind: 30000)

        list.listDescription = "A test list"
        list.image = "https://example.com/image.jpg"

        XCTAssertEqual(list.listDescription, "A test list")
        XCTAssertEqual(list.image, "https://example.com/image.jpg")

        XCTAssertTrue(list.tags.contains { $0.type == "description" && $0.value == "A test list" })
        XCTAssertTrue(list.tags.contains { $0.type == "image" && $0.value == "https://example.com/image.jpg" })
    }

    func testFromEvent() {
        let originalEvent = NDKEvent(ndk: ndk)
        originalEvent.kind = 10003
        originalEvent.tags = [
            NDKTag(type: "title", value: "Test List"),
            NDKTag(type: "e", value: "event123"),
            NDKTag(type: "p", value: "pubkey123"),
        ]
        originalEvent.content = "test content"

        let list = NDKList.from(originalEvent)

        XCTAssertEqual(list.kind, 10003)
        XCTAssertEqual(list.title, "Test List")
        XCTAssertEqual(list.content, "test content")
        XCTAssertEqual(list.tags.count, 3)
    }

    // MARK: - List Item Management Tests

    func testAddingUsers() async throws {
        let list = NDKList(ndk: ndk, kind: 30000)
        let user = NDKUser(pubkey: "user123")

        try await list.addItem(user)

        XCTAssertTrue(list.contains("user123"))
        XCTAssertEqual(list.userPubkeys, ["user123"])
        XCTAssertTrue(list.tags.contains { $0.type == "p" && $0.value == "user123" })
    }

    func testAddingEvents() async throws {
        let list = NDKList(ndk: ndk, kind: 10003)
        let event = NDKEvent(ndk: ndk)
        event.id = "event123"
        event.kind = 1

        try await list.addItem(event)

        XCTAssertTrue(list.contains("event123"))
        XCTAssertEqual(list.eventIds, ["event123"])
        XCTAssertTrue(list.tags.contains { $0.type == "e" && $0.value == "event123" })
    }

    func testAddingParameterizedReplaceableEvents() async throws {
        let list = NDKList(ndk: ndk, kind: 10003)
        let event = NDKEvent(ndk: ndk)
        event.kind = 30023
        event.pubkey = "author123"
        event.tags = [NDKTag(type: "d", value: "article-slug")]

        try await list.addItem(event)

        let expectedReference = "30023:author123:article-slug"
        XCTAssertTrue(list.contains(expectedReference))
        XCTAssertTrue(list.tags.contains { $0.type == "a" && $0.value == expectedReference })
    }

    func testAddingHashtags() async throws {
        let list = NDKList(ndk: ndk, kind: 10015)

        try await list.addHashtag("nostr")
        try await list.addHashtag("#bitcoin")

        XCTAssertEqual(list.hashtags, ["nostr", "bitcoin"])
        XCTAssertTrue(list.tags.contains { $0.type == "t" && $0.value == "nostr" })
        XCTAssertTrue(list.tags.contains { $0.type == "t" && $0.value == "bitcoin" })
    }

    func testAddingURLs() async throws {
        let list = NDKList(ndk: ndk, kind: 10003)

        try await list.addURL("https://example.com")

        XCTAssertEqual(list.urls, ["https://example.com"])
        XCTAssertTrue(list.tags.contains { $0.type == "r" && $0.value == "https://example.com" })
    }

    func testItemWithMark() async throws {
        let list = NDKList(ndk: ndk, kind: 10003)
        let user = NDKUser(pubkey: "user123")

        try await list.addItem(user, mark: "bookmark")

        let userTag = list.tags.first { $0.type == "p" && $0.value == "user123" }
        XCTAssertNotNil(userTag)
        XCTAssertTrue(userTag!.additionalInfo.contains("bookmark"))
    }

    func testPositionInsertion() async throws {
        let list = NDKList(ndk: ndk, kind: 10003)
        list.title = "Test List" // This will be first

        let user1 = NDKUser(pubkey: "user1")
        let user2 = NDKUser(pubkey: "user2")
        let user3 = NDKUser(pubkey: "user3")

        try await list.addItem(user1, position: .bottom)
        try await list.addItem(user2, position: .top)
        try await list.addItem(user3, position: .bottom)

        let userTags = list.tags.filter { $0.type == "p" }
        XCTAssertEqual(userTags[0].value, "user2") // Added to top
        XCTAssertEqual(userTags[1].value, "user1") // Original bottom
        XCTAssertEqual(userTags[2].value, "user3") // New bottom
    }

    func testRemoveItemByReference() async throws {
        let list = NDKList(ndk: ndk, kind: 10003)
        let user = NDKUser(pubkey: "user123")

        try await list.addItem(user)
        XCTAssertTrue(list.contains("user123"))

        try await list.removeItem(byReference: "user123")
        XCTAssertFalse(list.contains("user123"))
        XCTAssertTrue(list.userPubkeys.isEmpty)
    }

    func testDuplicateItemPrevention() async throws {
        let list = NDKList(ndk: ndk, kind: 10003)
        let user = NDKUser(pubkey: "user123")

        try await list.addItem(user)
        try await list.addItem(user) // Should not add duplicate

        XCTAssertEqual(list.userPubkeys.count, 1)
        XCTAssertEqual(list.tags.filter { $0.type == "p" }.count, 1)
    }

    // MARK: - Filter Generation Tests

    func testFiltersForItems() async throws {
        let list = NDKList(ndk: ndk, kind: 10003)

        // Add various item types
        let user = NDKUser(pubkey: "user123")
        let event = NDKEvent(ndk: ndk)
        event.id = "event123"
        event.kind = 1

        let paramEvent = NDKEvent(ndk: ndk)
        paramEvent.kind = 30023
        paramEvent.pubkey = "author123"
        paramEvent.tags = [NDKTag(type: "d", value: "article")]

        try await list.addItem(user)
        try await list.addItem(event)
        try await list.addItem(paramEvent)

        let filters = list.filtersForItems()

        // Should generate filters for each type
        XCTAssertTrue(filters.count >= 3)

        // Check for event ID filter
        XCTAssertTrue(filters.contains { $0.ids?.contains("event123") == true })

        // Check for profile filter
        XCTAssertTrue(filters.contains { $0.kinds?.contains(0) == true && $0.authors?.contains("user123") == true })

        // Check for parameterized replaceable event filter
        XCTAssertTrue(filters.contains { $0.kinds?.contains(30023) == true && $0.authors?.contains("author123") == true })
    }

    // MARK: - Encrypted Items Tests

    func testEncryptedItemStorage() async throws {
        let list = NDKList(ndk: ndk, kind: 10000)
        let user = NDKUser(pubkey: "user123")

        try await list.addItem(user, encrypted: true)

        // Should not appear in public items
        XCTAssertFalse(list.publicItems.contains { $0.type == "p" && $0.value == "user123" })

        // Should appear in all items
        XCTAssertTrue(list.allItems.contains { $0.type == "p" && $0.value == "user123" })

        // Content should not be empty (contains encrypted data)
        XCTAssertFalse(list.content.isEmpty)
    }

    // MARK: - List Item Protocol Tests

    func testNDKUserListItem() {
        let user = NDKUser(pubkey: "user123")
        let tag = user.toListTag()

        XCTAssertEqual(tag.type, "p")
        XCTAssertEqual(tag.value, "user123")
        XCTAssertEqual(user.reference, "user123")
    }

    func testNDKEventListItem() {
        let event = NDKEvent()
        event.id = "event123"
        event.kind = 1

        let tag = event.toListTag()

        XCTAssertEqual(tag.type, "e")
        XCTAssertEqual(tag.value, "event123")
        XCTAssertEqual(event.reference, "event123")
    }

    func testNDKRelayListItem() {
        let relay = NDKRelay(url: "wss://relay.example.com")
        let tag = relay.toListTag()

        XCTAssertEqual(tag.type, "r")
        XCTAssertEqual(tag.value, "wss://relay.example.com")
        XCTAssertEqual(relay.reference, "wss://relay.example.com")
    }

    func testStringListItem() {
        let hashtag = NDKStringListItem(tagType: "t", value: "nostr")
        let tag = hashtag.toListTag()

        XCTAssertEqual(tag.type, "t")
        XCTAssertEqual(tag.value, "nostr")
        XCTAssertEqual(hashtag.reference, "nostr")
    }

    // MARK: - Supported Kinds Tests

    func testSupportedKinds() {
        let expectedKinds = [3, 10000, 10001, 10002, 10003, 10004, 10005, 10006, 10007, 10015, 10030, 30000, 30001, 30002, 30063]

        for kind in expectedKinds {
            XCTAssertTrue(NDKList.supportedKinds.contains(kind), "Kind \(kind) should be supported")
        }
    }

    func testDefaultTitles() {
        let testCases: [(kind: Int, expectedTitle: String)] = [
            (3, "Contacts"),
            (10000, "Muted"),
            (10001, "Pinned"),
            (10002, "Relays"),
            (10003, "Bookmarks"),
            (10015, "Interests"),
        ]

        for testCase in testCases {
            let list = NDKList(ndk: ndk, kind: testCase.kind)
            XCTAssertEqual(list.title, testCase.expectedTitle, "Kind \(testCase.kind) should have title '\(testCase.expectedTitle)'")
        }
    }
}
