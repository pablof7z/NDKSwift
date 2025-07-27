import XCTest
@testable import NDKSwift

final class NDKContactListTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        signer = try NDKPrivateKeySigner(privateKey: "test-private-key")
        ndk.signer = signer
    }
    
    override func tearDown() async throws {
        ndk = nil
        signer = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        let contactList = NDKContactList(ndk: ndk)
        XCTAssertEqual(contactList.kind, 3)
        XCTAssertEqual(contactList.contactCount, 0)
        XCTAssertTrue(contactList.contacts.isEmpty)
    }
    
    func testFromEvent() {
        let event = NDKEvent(
            id: "test-id",
            pubkey: "test-pubkey",
            createdAt: Timestamp.now,
            kind: 3,
            tags: [
                ["p", "pubkey1", "wss://relay1.com", "Alice"],
                ["p", "pubkey2", "", "Bob"],
                ["p", "pubkey3"]
            ],
            content: "",
            sig: "test-sig"
        )
        
        let contactList = NDKContactList.fromEvent(event, ndk: ndk)
        XCTAssertEqual(contactList.id, "test-id")
        XCTAssertEqual(contactList.pubkey, "test-pubkey")
        XCTAssertEqual(contactList.kind, 3)
        XCTAssertEqual(contactList.contactCount, 3)
    }
    
    // MARK: - Contact Management Tests
    
    func testAddContact() {
        let contactList = NDKContactList(ndk: ndk)
        
        // Add contact by pubkey
        contactList.addContact(pubkey: "pubkey1")
        XCTAssertEqual(contactList.contactCount, 1)
        XCTAssertTrue(contactList.isFollowing("pubkey1"))
        
        // Add same contact again - should not duplicate
        contactList.addContact(pubkey: "pubkey1")
        XCTAssertEqual(contactList.contactCount, 1)
        
        // Add contact with relay and petname
        contactList.addContact(pubkey: "pubkey2", relayURL: "wss://relay.com", petname: "Alice")
        XCTAssertEqual(contactList.contactCount, 2)
        
        let entry = contactList.contactEntry(for: "pubkey2")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.relayURL, "wss://relay.com")
        XCTAssertEqual(entry?.petname, "Alice")
    }
    
    func testAddContactByUser() {
        let contactList = NDKContactList(ndk: ndk)
        let user = NDKUser(pubkey: "pubkey1")
        
        contactList.addContact(user: user, relayURL: "wss://relay.com", petname: "Bob")
        XCTAssertEqual(contactList.contactCount, 1)
        XCTAssertTrue(contactList.isFollowing(user))
        
        let entry = contactList.contactEntry(for: user)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.petname, "Bob")
    }
    
    func testRemoveContact() {
        let contactList = NDKContactList(ndk: ndk)
        
        // Add contacts
        contactList.addContact(pubkey: "pubkey1")
        contactList.addContact(pubkey: "pubkey2")
        XCTAssertEqual(contactList.contactCount, 2)
        
        // Remove by pubkey
        contactList.removeContact(pubkey: "pubkey1")
        XCTAssertEqual(contactList.contactCount, 1)
        XCTAssertFalse(contactList.isFollowing("pubkey1"))
        XCTAssertTrue(contactList.isFollowing("pubkey2"))
        
        // Remove by user
        let user = NDKUser(pubkey: "pubkey2")
        contactList.removeContact(user: user)
        XCTAssertEqual(contactList.contactCount, 0)
    }
    
    // MARK: - Petname Tests
    
    func testPetnameManagement() {
        let contactList = NDKContactList(ndk: ndk)
        
        // Add contact with petname
        contactList.addContact(pubkey: "pubkey1", petname: "Alice")
        XCTAssertEqual(contactList.petname(for: "pubkey1"), "Alice")
        
        // Update petname
        contactList.updatePetname(for: "pubkey1", petname: "Alice Updated")
        XCTAssertEqual(contactList.petname(for: "pubkey1"), "Alice Updated")
        
        // Remove petname
        contactList.updatePetname(for: "pubkey1", petname: nil)
        XCTAssertNil(contactList.petname(for: "pubkey1"))
        
        // Test with user object
        let user = NDKUser(pubkey: "pubkey1")
        contactList.updatePetname(for: "pubkey1", petname: "Alice Final")
        XCTAssertEqual(contactList.petname(for: user), "Alice Final")
    }
    
    // MARK: - Relay URL Tests
    
    func testRelayURLManagement() {
        let contactList = NDKContactList(ndk: ndk)
        
        // Add contact with relay URL
        contactList.addContact(pubkey: "pubkey1", relayURL: "wss://relay1.com")
        let entry1 = contactList.contactEntry(for: "pubkey1")
        XCTAssertEqual(entry1?.relayURL, "wss://relay1.com")
        
        // Update relay URL
        contactList.updateRelayURL(for: "pubkey1", relayURL: "wss://relay2.com")
        let entry2 = contactList.contactEntry(for: "pubkey1")
        XCTAssertEqual(entry2?.relayURL, "wss://relay2.com")
        
        // Remove relay URL
        contactList.updateRelayURL(for: "pubkey1", relayURL: nil)
        let entry3 = contactList.contactEntry(for: "pubkey1")
        XCTAssertNil(entry3?.relayURL)
    }
    
    // MARK: - Contact Query Tests
    
    func testContactQueries() {
        let contactList = NDKContactList(ndk: ndk)
        
        // Add various contacts
        contactList.addContact(pubkey: "pubkey1", relayURL: "wss://relay1.com", petname: "Alice")
        contactList.addContact(pubkey: "pubkey2", petname: "Bob")
        contactList.addContact(pubkey: "pubkey3", relayURL: "wss://relay3.com")
        contactList.addContact(pubkey: "pubkey4")
        
        // Test contact queries
        XCTAssertEqual(contactList.contactPubkeys.sorted(), ["pubkey1", "pubkey2", "pubkey3", "pubkey4"])
        XCTAssertEqual(contactList.contactUsers.count, 4)
        
        // Test filtered queries
        let withPetnames = contactList.contactsWithPetnames
        XCTAssertEqual(withPetnames.count, 2)
        XCTAssertTrue(withPetnames.contains { $0.user.pubkey == "pubkey1" })
        XCTAssertTrue(withPetnames.contains { $0.user.pubkey == "pubkey2" })
        
        let withRelays = contactList.contactsWithRelayURLs
        XCTAssertEqual(withRelays.count, 2)
        XCTAssertTrue(withRelays.contains { $0.user.pubkey == "pubkey1" })
        XCTAssertTrue(withRelays.contains { $0.user.pubkey == "pubkey3" })
    }
    
    // MARK: - Filter Creation Tests
    
    func testCreateContactFilter() {
        let contactList = NDKContactList(ndk: ndk)
        contactList.addContact(pubkey: "pubkey1")
        contactList.addContact(pubkey: "pubkey2")
        
        // Default filter
        let filter1 = contactList.createContactFilter()
        XCTAssertEqual(filter1.authors, ["pubkey1", "pubkey2"])
        XCTAssertEqual(filter1.kinds, [1])
        
        // Custom filter
        let filter2 = contactList.createContactFilter(
            kinds: [4, 7],
            since: 1000,
            until: 2000,
            limit: 100
        )
        XCTAssertEqual(filter2.authors, ["pubkey1", "pubkey2"])
        XCTAssertEqual(filter2.kinds, [4, 7])
        XCTAssertEqual(filter2.since, 1000)
        XCTAssertEqual(filter2.until, 2000)
        XCTAssertEqual(filter2.limit, 100)
    }
    
    // MARK: - Merge Tests
    
    func testMergeContactLists() {
        let list1 = NDKContactList(ndk: ndk)
        list1.addContact(pubkey: "pubkey1")
        list1.addContact(pubkey: "pubkey2")
        
        let list2 = NDKContactList(ndk: ndk)
        list2.addContact(pubkey: "pubkey2") // Duplicate
        list2.addContact(pubkey: "pubkey3")
        list2.addContact(pubkey: "pubkey4")
        
        list1.merge(with: list2)
        
        XCTAssertEqual(list1.contactCount, 4)
        XCTAssertTrue(list1.isFollowing("pubkey1"))
        XCTAssertTrue(list1.isFollowing("pubkey2"))
        XCTAssertTrue(list1.isFollowing("pubkey3"))
        XCTAssertTrue(list1.isFollowing("pubkey4"))
    }
    
    // MARK: - Factory Method Tests
    
    func testCreateFromPubkeys() {
        let pubkeys = ["pubkey1", "pubkey2", "pubkey3"]
        let contactList = NDKContactList.from(pubkeys: pubkeys, ndk: ndk)
        
        XCTAssertEqual(contactList.contactCount, 3)
        XCTAssertEqual(contactList.contactPubkeys.sorted(), pubkeys.sorted())
    }
    
    func testCreateFromUsers() {
        let users = [
            NDKUser(pubkey: "pubkey1"),
            NDKUser(pubkey: "pubkey2"),
            NDKUser(pubkey: "pubkey3")
        ]
        let contactList = NDKContactList.from(users: users, ndk: ndk)
        
        XCTAssertEqual(contactList.contactCount, 3)
        XCTAssertTrue(contactList.isFollowing(users[0]))
        XCTAssertTrue(contactList.isFollowing(users[1]))
        XCTAssertTrue(contactList.isFollowing(users[2]))
    }
    
    // MARK: - Timestamp Update Tests
    
    func testTimestampUpdates() {
        let contactList = NDKContactList(ndk: ndk)
        let initialTimestamp = contactList.createdAt
        
        // Wait a tiny bit to ensure timestamp changes
        Thread.sleep(forTimeInterval: 0.001)
        
        // Adding contact should update timestamp
        contactList.addContact(pubkey: "pubkey1")
        XCTAssertGreaterThan(contactList.createdAt, initialTimestamp)
        
        let timestamp2 = contactList.createdAt
        Thread.sleep(forTimeInterval: 0.001)
        
        // Removing contact should update timestamp
        contactList.removeContact(pubkey: "pubkey1")
        XCTAssertGreaterThan(contactList.createdAt, timestamp2)
    }
    
    // MARK: - Tag Format Tests
    
    func testContactEntryTagFormat() {
        // Test full tag
        let entry1 = NDKContactEntry(pubkey: "pubkey1", relayURL: "wss://relay.com", petname: "Alice")
        let tag1 = entry1.toTag()
        XCTAssertEqual(tag1, ["p", "pubkey1", "wss://relay.com", "Alice"])
        
        // Test tag with empty relay URL
        let entry2 = NDKContactEntry(pubkey: "pubkey2", petname: "Bob")
        let tag2 = entry2.toTag()
        XCTAssertEqual(tag2, ["p", "pubkey2", "", "Bob"])
        
        // Test minimal tag
        let entry3 = NDKContactEntry(pubkey: "pubkey3")
        let tag3 = entry3.toTag()
        XCTAssertEqual(tag3, ["p", "pubkey3", ""])
    }
    
    func testContactEntryFromTag() {
        // Test full tag
        let tag1 = ["p", "pubkey1", "wss://relay.com", "Alice"]
        let entry1 = NDKContactEntry.from(tag: tag1)
        XCTAssertNotNil(entry1)
        XCTAssertEqual(entry1?.user.pubkey, "pubkey1")
        XCTAssertEqual(entry1?.relayURL, "wss://relay.com")
        XCTAssertEqual(entry1?.petname, "Alice")
        
        // Test tag with empty relay URL
        let tag2 = ["p", "pubkey2", "", "Bob"]
        let entry2 = NDKContactEntry.from(tag: tag2)
        XCTAssertNotNil(entry2)
        XCTAssertEqual(entry2?.user.pubkey, "pubkey2")
        XCTAssertNil(entry2?.relayURL)
        XCTAssertEqual(entry2?.petname, "Bob")
        
        // Test minimal tag
        let tag3 = ["p", "pubkey3"]
        let entry3 = NDKContactEntry.from(tag: tag3)
        XCTAssertNotNil(entry3)
        XCTAssertEqual(entry3?.user.pubkey, "pubkey3")
        XCTAssertNil(entry3?.relayURL)
        XCTAssertNil(entry3?.petname)
        
        // Test invalid tags
        XCTAssertNil(NDKContactEntry.from(tag: []))
        XCTAssertNil(NDKContactEntry.from(tag: ["e", "event-id"]))
        XCTAssertNil(NDKContactEntry.from(tag: ["p"]))
        XCTAssertNil(NDKContactEntry.from(tag: ["p", ""]))
    }
}