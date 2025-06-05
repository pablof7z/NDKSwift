@testable import NDKSwift
import XCTest

final class NDKContactListTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var contactList: NDKContactList!

    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        contactList = NDKContactList(ndk: ndk)
    }

    override func tearDown() async throws {
        ndk = nil
        signer = nil
        contactList = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testContactListInitialization() {
        XCTAssertEqual(contactList.kind, 3)
        XCTAssertEqual(contactList.ndk, ndk)
        XCTAssertTrue(contactList.contacts.isEmpty)
    }

    func testFromEvent() {
        let event = NDKEvent(ndk: ndk)
        event.kind = 3
        event.tags = [
            NDKTag(type: "p", value: "pubkey1", additionalInfo: ["wss://relay1.com", "Alice"]),
            NDKTag(type: "p", value: "pubkey2", additionalInfo: ["", "Bob"]),
            NDKTag(type: "p", value: "pubkey3"),
        ]

        let contactList = NDKContactList.from(event)

        XCTAssertEqual(contactList.kind, 3)
        XCTAssertEqual(contactList.contacts.count, 3)
    }

    // MARK: - Contact Management Tests

    func testAddContactByPubkey() {
        contactList.addContact(pubkey: "user123")

        XCTAssertEqual(contactList.contacts.count, 1)
        XCTAssertTrue(contactList.isFollowing("user123"))
        XCTAssertEqual(contactList.contactPubkeys, ["user123"])
    }

    func testAddContactWithMetadata() {
        contactList.addContact(pubkey: "user123", relayURL: "wss://relay.example.com", petname: "Alice")

        let contact = contactList.contacts.first!
        XCTAssertEqual(contact.user.pubkey, "user123")
        XCTAssertEqual(contact.relayURL, "wss://relay.example.com")
        XCTAssertEqual(contact.petname, "Alice")
    }

    func testAddContactUser() {
        let user = NDKUser(pubkey: "user123")
        contactList.addContact(user: user, petname: "Bob")

        XCTAssertEqual(contactList.contacts.count, 1)
        XCTAssertTrue(contactList.isFollowing(user))

        let contact = contactList.contacts.first!
        XCTAssertEqual(contact.petname, "Bob")
    }

    func testAddContactEntry() {
        let user = NDKUser(pubkey: "user123")
        let entry = NDKContactEntry(user: user, relayURL: "wss://relay.com", petname: "Charlie")

        contactList.addContact(entry)

        XCTAssertEqual(contactList.contacts.count, 1)
        XCTAssertEqual(contactList.contacts.first!.petname, "Charlie")
    }

    func testRemoveContactByPubkey() {
        contactList.addContact(pubkey: "user123")
        XCTAssertTrue(contactList.isFollowing("user123"))

        contactList.removeContact(pubkey: "user123")
        XCTAssertFalse(contactList.isFollowing("user123"))
        XCTAssertTrue(contactList.contacts.isEmpty)
    }

    func testRemoveContactByUser() {
        let user = NDKUser(pubkey: "user123")
        contactList.addContact(user: user)
        XCTAssertTrue(contactList.isFollowing(user))

        contactList.removeContact(user: user)
        XCTAssertFalse(contactList.isFollowing(user))
        XCTAssertTrue(contactList.contacts.isEmpty)
    }

    func testDuplicateContactPrevention() {
        contactList.addContact(pubkey: "user123")
        contactList.addContact(pubkey: "user123") // Should not add duplicate

        XCTAssertEqual(contactList.contacts.count, 1)
    }

    // MARK: - Contact Entry Tests

    func testContactEntryCreation() {
        let user = NDKUser(pubkey: "user123")
        let entry = NDKContactEntry(user: user, relayURL: "wss://relay.com", petname: "Alice")

        XCTAssertEqual(entry.user.pubkey, "user123")
        XCTAssertEqual(entry.relayURL, "wss://relay.com")
        XCTAssertEqual(entry.petname, "Alice")
    }

    func testContactEntryToTag() {
        let entry = NDKContactEntry(pubkey: "user123", relayURL: "wss://relay.com", petname: "Alice")
        let tag = entry.toTag()

        XCTAssertEqual(tag.type, "p")
        XCTAssertEqual(tag.value, "user123")
        XCTAssertEqual(tag.additionalInfo[0], "wss://relay.com")
        XCTAssertEqual(tag.additionalInfo[1], "Alice")
    }

    func testContactEntryToTagWithEmptyFields() {
        let entry = NDKContactEntry(pubkey: "user123")
        let tag = entry.toTag()

        XCTAssertEqual(tag.type, "p")
        XCTAssertEqual(tag.value, "user123")
        XCTAssertTrue(tag.additionalInfo.isEmpty || tag.additionalInfo[0].isEmpty)
    }

    func testContactEntryFromTag() {
        let tag = NDKTag(type: "p", value: "user123", additionalInfo: ["wss://relay.com", "Alice"])
        let entry = NDKContactEntry.from(tag: tag)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry!.user.pubkey, "user123")
        XCTAssertEqual(entry!.relayURL, "wss://relay.com")
        XCTAssertEqual(entry!.petname, "Alice")
    }

    func testContactEntryFromTagWithMissingData() {
        let tag = NDKTag(type: "p", value: "user123", additionalInfo: [""])
        let entry = NDKContactEntry.from(tag: tag)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry!.user.pubkey, "user123")
        XCTAssertNil(entry!.relayURL)
        XCTAssertNil(entry!.petname)
    }

    // MARK: - Metadata Management Tests

    func testContactQueries() {
        contactList.addContact(pubkey: "user1", relayURL: "wss://relay1.com", petname: "Alice")
        contactList.addContact(pubkey: "user2", petname: "Bob")
        contactList.addContact(pubkey: "user3")

        XCTAssertEqual(contactList.contactCount, 3)
        XCTAssertEqual(contactList.contactPubkeys.count, 3)
        XCTAssertEqual(contactList.contactUsers.count, 3)
    }

    func testContactEntryLookup() {
        contactList.addContact(pubkey: "user123", petname: "Alice")

        let entry = contactList.contactEntry(for: "user123")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry!.petname, "Alice")

        let user = NDKUser(pubkey: "user123")
        let entryByUser = contactList.contactEntry(for: user)
        XCTAssertNotNil(entryByUser)
        XCTAssertEqual(entryByUser!.petname, "Alice")
    }

    func testPetnameQueries() {
        contactList.addContact(pubkey: "user123", petname: "Alice")

        XCTAssertEqual(contactList.petname(for: "user123"), "Alice")

        let user = NDKUser(pubkey: "user123")
        XCTAssertEqual(contactList.petname(for: user), "Alice")

        XCTAssertNil(contactList.petname(for: "unknown"))
    }

    func testUpdatePetname() {
        contactList.addContact(pubkey: "user123", petname: "Alice")
        XCTAssertEqual(contactList.petname(for: "user123"), "Alice")

        contactList.updatePetname(for: "user123", petname: "Alicia")
        XCTAssertEqual(contactList.petname(for: "user123"), "Alicia")

        contactList.updatePetname(for: "user123", petname: nil)
        XCTAssertNil(contactList.petname(for: "user123"))
    }

    func testUpdateRelayURL() {
        contactList.addContact(pubkey: "user123", relayURL: "wss://old-relay.com")

        let entry = contactList.contactEntry(for: "user123")
        XCTAssertEqual(entry!.relayURL, "wss://old-relay.com")

        contactList.updateRelayURL(for: "user123", relayURL: "wss://new-relay.com")

        let updatedEntry = contactList.contactEntry(for: "user123")
        XCTAssertEqual(updatedEntry!.relayURL, "wss://new-relay.com")
    }

    // MARK: - Filtering Tests

    func testContactsWithPetnames() {
        contactList.addContact(pubkey: "user1", petname: "Alice")
        contactList.addContact(pubkey: "user2")
        contactList.addContact(pubkey: "user3", petname: "Charlie")

        let contactsWithPetnames = contactList.contactsWithPetnames
        XCTAssertEqual(contactsWithPetnames.count, 2)
        XCTAssertTrue(contactsWithPetnames.contains { $0.petname == "Alice" })
        XCTAssertTrue(contactsWithPetnames.contains { $0.petname == "Charlie" })
    }

    func testContactsWithRelayURLs() {
        contactList.addContact(pubkey: "user1", relayURL: "wss://relay1.com")
        contactList.addContact(pubkey: "user2")
        contactList.addContact(pubkey: "user3", relayURL: "wss://relay3.com")

        let contactsWithRelays = contactList.contactsWithRelayURLs
        XCTAssertEqual(contactsWithRelays.count, 2)
        XCTAssertTrue(contactsWithRelays.contains { $0.relayURL == "wss://relay1.com" })
        XCTAssertTrue(contactsWithRelays.contains { $0.relayURL == "wss://relay3.com" })
    }

    // MARK: - Filter Creation Tests

    func testCreateContactFilter() {
        contactList.addContact(pubkey: "user1")
        contactList.addContact(pubkey: "user2")
        contactList.addContact(pubkey: "user3")

        let filter = contactList.createContactFilter(kinds: [1], limit: 100)

        XCTAssertEqual(filter.kinds, [1])
        XCTAssertEqual(filter.authors?.count, 3)
        XCTAssertTrue(filter.authors!.contains("user1"))
        XCTAssertTrue(filter.authors!.contains("user2"))
        XCTAssertTrue(filter.authors!.contains("user3"))
        XCTAssertEqual(filter.limit, 100)
    }

    // MARK: - Bulk Operations Tests

    func testSetContacts() {
        let entries = [
            NDKContactEntry(pubkey: "user1", petname: "Alice"),
            NDKContactEntry(pubkey: "user2", petname: "Bob"),
            NDKContactEntry(pubkey: "user3", relayURL: "wss://relay.com"),
        ]

        contactList.setContacts(entries)

        XCTAssertEqual(contactList.contacts.count, 3)
        XCTAssertTrue(contactList.isFollowing("user1"))
        XCTAssertTrue(contactList.isFollowing("user2"))
        XCTAssertTrue(contactList.isFollowing("user3"))
    }

    func testMergeContactLists() {
        contactList.addContact(pubkey: "user1")

        let other = NDKContactList(ndk: ndk)
        other.addContact(pubkey: "user2")
        other.addContact(pubkey: "user1") // Duplicate

        contactList.merge(with: other)

        XCTAssertEqual(contactList.contacts.count, 2)
        XCTAssertTrue(contactList.isFollowing("user1"))
        XCTAssertTrue(contactList.isFollowing("user2"))
    }

    // MARK: - Factory Methods Tests

    func testFromPubkeys() {
        let pubkeys = ["user1", "user2", "user3"]
        let contactList = NDKContactList.from(pubkeys: pubkeys, ndk: ndk)

        XCTAssertEqual(contactList.contacts.count, 3)
        XCTAssertEqual(contactList.ndk, ndk)

        for pubkey in pubkeys {
            XCTAssertTrue(contactList.isFollowing(pubkey))
        }
    }

    func testFromUsers() {
        let users = [
            NDKUser(pubkey: "user1"),
            NDKUser(pubkey: "user2"),
            NDKUser(pubkey: "user3"),
        ]

        let contactList = NDKContactList.from(users: users, ndk: ndk)

        XCTAssertEqual(contactList.contacts.count, 3)

        for user in users {
            XCTAssertTrue(contactList.isFollowing(user))
        }
    }

    // MARK: - Tag Parsing Tests

    func testParsingExistingTags() {
        let event = NDKEvent(ndk: ndk)
        event.kind = 3
        event.tags = [
            NDKTag(type: "p", value: "user1"),
            NDKTag(type: "p", value: "user2", additionalInfo: ["wss://relay.com"]),
            NDKTag(type: "p", value: "user3", additionalInfo: ["", "Alice"]),
            NDKTag(type: "p", value: "user4", additionalInfo: ["wss://relay.com", "Bob"]),
        ]

        let contactList = NDKContactList.from(event)

        XCTAssertEqual(contactList.contacts.count, 4)

        // Test different tag formats
        let contact1 = contactList.contactEntry(for: "user1")!
        XCTAssertNil(contact1.relayURL)
        XCTAssertNil(contact1.petname)

        let contact2 = contactList.contactEntry(for: "user2")!
        XCTAssertEqual(contact2.relayURL, "wss://relay.com")
        XCTAssertNil(contact2.petname)

        let contact3 = contactList.contactEntry(for: "user3")!
        XCTAssertNil(contact3.relayURL)
        XCTAssertEqual(contact3.petname, "Alice")

        let contact4 = contactList.contactEntry(for: "user4")!
        XCTAssertEqual(contact4.relayURL, "wss://relay.com")
        XCTAssertEqual(contact4.petname, "Bob")
    }

    // MARK: - Edge Cases Tests

    func testEmptyContactList() {
        XCTAssertEqual(contactList.contactCount, 0)
        XCTAssertTrue(contactList.contactPubkeys.isEmpty)
        XCTAssertTrue(contactList.contactUsers.isEmpty)
        XCTAssertFalse(contactList.isFollowing("anyone"))
    }

    func testInvalidContactEntry() {
        let invalidTag = NDKTag(type: "e", value: "event123") // Wrong tag type
        let entry = NDKContactEntry.from(tag: invalidTag)

        XCTAssertNil(entry)
    }

    func testEmptyPubkeyContactEntry() {
        let invalidTag = NDKTag(type: "p", value: "") // Empty pubkey
        let entry = NDKContactEntry.from(tag: invalidTag)

        XCTAssertNil(entry)
    }
}
