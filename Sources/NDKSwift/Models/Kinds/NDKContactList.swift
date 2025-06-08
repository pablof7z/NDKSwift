import Foundation

/// Represents a contact entry in a contact list with optional metadata
public struct NDKContactEntry {
    public let user: NDKUser
    public let relayURL: String?
    public let petname: String?

    public init(user: NDKUser, relayURL: String? = nil, petname: String? = nil) {
        self.user = user
        self.relayURL = relayURL
        self.petname = petname
    }

    public init(pubkey: String, relayURL: String? = nil, petname: String? = nil) {
        self.user = NDKUser(pubkey: pubkey)
        self.relayURL = relayURL
        self.petname = petname
    }

    /// Convert to Tag representation
    public func toTag() -> Tag {
        var tag = ["p", user.pubkey]

        if let relayURL = relayURL, !relayURL.isEmpty {
            tag.append(relayURL)
        } else {
            tag.append("")
        }

        if let petname = petname, !petname.isEmpty {
            tag.append(petname)
        }

        return tag
    }

    /// Create from a Tag
    public static func from(tag: Tag) -> NDKContactEntry? {
        guard tag.count > 1, tag[0] == "p", !tag[1].isEmpty else { return nil }

        let pubkey = tag[1]
        let relayURL = tag.count > 2 && !tag[2].isEmpty ? tag[2] : nil
        let petname = tag.count > 3 && !tag[3].isEmpty ? tag[3] : nil

        return NDKContactEntry(pubkey: pubkey, relayURL: relayURL, petname: petname)
    }
}

/// Specialized list for managing contacts/follows (NIP-02, kind 3)
/// Provides contact management with petnames and relay hints
public class NDKContactList: NDKList {
    /// Contact list kind (3)
    public static let kind = 3

    /// Initialize a new contact list
    override public convenience init(ndk: NDK? = nil) {
        self.init(ndk: ndk, kind: 3)
    }

    /// Create an NDKContactList from an existing NDKEvent
    public static func fromEvent(_ event: NDKEvent) -> NDKContactList {
        let contactList = NDKContactList(ndk: event.ndk)
        contactList.id = event.id
        contactList.pubkey = event.pubkey
        contactList.createdAt = event.createdAt
        contactList.kind = event.kind
        contactList.tags = event.tags
        contactList.content = event.content
        contactList.signature = event.sig
        return contactList
    }

    /// All contact entries in this list
    public var contacts: [NDKContactEntry] {
        let contactTags = tags.filter { $0.count > 1 && $0[0] == "p" }
        return contactTags.compactMap { NDKContactEntry.from(tag: $0) }
    }

    /// All contact pubkeys
    public var contactPubkeys: [String] {
        return contacts.map { $0.user.pubkey }
    }

    /// All contacts as NDKUser objects
    public var contactUsers: [NDKUser] {
        return contacts.map { contact in
            let user = contact.user
            user.ndk = self.ndk
            return user
        }
    }

    /// Number of contacts in this list
    public var contactCount: Int {
        return contacts.count
    }

    /// Set the complete list of contact entries
    public func setContacts(_ entries: [NDKContactEntry]) {
        // Remove all existing contact tags
        tags.removeAll { $0.count > 1 && $0[0] == "p" }

        // Add new contact entries
        for entry in entries {
            tags.append(entry.toTag())
        }

        // Update timestamp
        createdAt = Timestamp(Date().timeIntervalSince1970)
    }

    /// Add a contact to this list
    @discardableResult
    public func addContact(_ contact: NDKContactEntry) -> NDKContactList {
        // Check if contact already exists
        guard !isFollowing(contact.user.pubkey) else {
            return self
        }

        tags.append(contact.toTag())

        // Update timestamp
        createdAt = Timestamp(Date().timeIntervalSince1970)

        return self
    }

    /// Add a contact by pubkey
    @discardableResult
    public func addContact(pubkey: String, relayURL: String? = nil, petname: String? = nil) -> NDKContactList {
        let contact = NDKContactEntry(pubkey: pubkey, relayURL: relayURL, petname: petname)
        return addContact(contact)
    }

    /// Add a contact by NDKUser
    @discardableResult
    public func addContact(user: NDKUser, relayURL: String? = nil, petname: String? = nil) -> NDKContactList {
        let contact = NDKContactEntry(user: user, relayURL: relayURL, petname: petname)
        return addContact(contact)
    }

    /// Remove a contact by pubkey
    @discardableResult
    public func removeContact(pubkey: String) -> NDKContactList {
        tags.removeAll { tag in
            tag.count > 1 && tag[0] == "p" && tag[1] == pubkey
        }

        // Update timestamp
        createdAt = Timestamp(Date().timeIntervalSince1970)

        return self
    }

    /// Remove a contact by NDKUser
    @discardableResult
    public func removeContact(user: NDKUser) -> NDKContactList {
        return removeContact(pubkey: user.pubkey)
    }

    /// Check if following a specific pubkey
    public func isFollowing(_ pubkey: String) -> Bool {
        return contactPubkeys.contains(pubkey)
    }

    /// Check if following a specific user
    public func isFollowing(_ user: NDKUser) -> Bool {
        return isFollowing(user.pubkey)
    }

    /// Get contact entry for a specific pubkey
    public func contactEntry(for pubkey: String) -> NDKContactEntry? {
        return contacts.first { $0.user.pubkey == pubkey }
    }

    /// Get contact entry for a specific user
    public func contactEntry(for user: NDKUser) -> NDKContactEntry? {
        return contactEntry(for: user.pubkey)
    }

    /// Get petname for a specific pubkey
    public func petname(for pubkey: String) -> String? {
        return contactEntry(for: pubkey)?.petname
    }

    /// Get petname for a specific user
    public func petname(for user: NDKUser) -> String? {
        return petname(for: user.pubkey)
    }

    /// Update petname for an existing contact
    @discardableResult
    public func updatePetname(for pubkey: String, petname: String?) -> NDKContactList {
        guard let index = tags.firstIndex(where: { $0.count > 1 && $0[0] == "p" && $0[1] == pubkey }) else {
            return self
        }

        let existingTag = tags[index]
        let relayURL = existingTag.count > 2 ? existingTag[2] : ""

        var newTag = ["p", pubkey, relayURL]
        if let petname = petname, !petname.isEmpty {
            newTag.append(petname)
        }

        tags[index] = newTag

        // Update timestamp
        createdAt = Timestamp(Date().timeIntervalSince1970)

        return self
    }

    /// Update relay URL for an existing contact
    @discardableResult
    public func updateRelayURL(for pubkey: String, relayURL: String?) -> NDKContactList {
        guard let index = tags.firstIndex(where: { $0.count > 1 && $0[0] == "p" && $0[1] == pubkey }) else {
            return self
        }

        let existingTag = tags[index]
        let petname = existingTag.count > 3 ? existingTag[3] : ""

        var newTag = ["p", pubkey, relayURL ?? ""]
        if !petname.isEmpty {
            newTag.append(petname)
        }

        tags[index] = newTag

        // Update timestamp
        createdAt = Timestamp(Date().timeIntervalSince1970)

        return self
    }

    /// Get contacts with petnames
    public var contactsWithPetnames: [NDKContactEntry] {
        return contacts.filter { $0.petname != nil && !$0.petname!.isEmpty }
    }

    /// Get contacts with relay URLs
    public var contactsWithRelayURLs: [NDKContactEntry] {
        return contacts.filter { $0.relayURL != nil && !$0.relayURL!.isEmpty }
    }

    /// Create a filter to fetch events from all contacts
    public func createContactFilter(kinds: [Int] = [1], since: Timestamp? = nil, until: Timestamp? = nil, limit: Int? = nil) -> NDKFilter {
        var filter = NDKFilter(authors: contactPubkeys, kinds: kinds)
        filter.since = since
        filter.until = until
        filter.limit = limit
        return filter
    }

    /// Merge another contact list into this one
    @discardableResult
    public func merge(with other: NDKContactList) -> NDKContactList {
        for contact in other.contacts {
            if !isFollowing(contact.user.pubkey) {
                addContact(contact)
            }
        }

        return self
    }

    /// Create a contact list from an array of pubkeys
    public static func from(pubkeys: [String], ndk: NDK? = nil) -> NDKContactList {
        let contactList = NDKContactList(ndk: ndk)

        for pubkey in pubkeys {
            contactList.addContact(pubkey: pubkey)
        }

        return contactList
    }

    /// Create a contact list from an array of users
    public static func from(users: [NDKUser], ndk: NDK? = nil) -> NDKContactList {
        let contactList = NDKContactList(ndk: ndk)

        for user in users {
            contactList.addContact(user: user)
        }

        return contactList
    }
}

// MARK: - Integration with NDK

public extension NDK {
    /// Fetch the contact list for a specific user
    func fetchContactList(for user: NDKUser) async throws -> NDKContactList? {
        let filter = NDKFilter(authors: [user.pubkey], kinds: [3], limit: 1)
        let events = try await fetchEvents(filters: [filter])

        guard let event = events.first else { return nil }
        return NDKContactList.fromEvent(event)
    }

    /// Fetch the contact list for the current user
    func fetchContactList() async throws -> NDKContactList? {
        guard let signer = signer else { return nil }
        let pubkey = try await signer.pubkey
        let currentUser = NDKUser(pubkey: pubkey)
        return try await fetchContactList(for: currentUser)
    }

    /// Publish a contact list
    func publishContactList(_ contactList: NDKContactList) async throws {
        guard signer != nil else {
            throw NDKError.crypto("no_signer", "No signer configured")
        }

        try await contactList.sign()
        let event = contactList.toNDKEvent()
        try await publish(event)
    }

    /// Follow a user (add to contact list)
    func follow(_ user: NDKUser) async throws {
        let contactList = try await fetchContactList() ?? NDKContactList(ndk: self)
        contactList.addContact(user: user)

        try await publishContactList(contactList)
    }

    /// Unfollow a user (remove from contact list)
    func unfollow(_ user: NDKUser) async throws {
        guard let contactList = try await fetchContactList() else { return }
        contactList.removeContact(user: user)

        try await publishContactList(contactList)
    }

    /// Check if currently following a user
    func isFollowing(_ user: NDKUser) async throws -> Bool {
        guard let contactList = try await fetchContactList() else { return false }
        return contactList.isFollowing(user)
    }
}

public extension NDKUser {
    /// Fetch this user's contact list
    func fetchContactList() async throws -> NDKContactList? {
        guard let ndk = ndk else { return nil }
        return try await ndk.fetchContactList(for: self)
    }

    /// Get the list of users this user follows
    func following() async throws -> [NDKUser] {
        guard let contactList = try await fetchContactList() else { return [] }
        return contactList.contactUsers
    }

    /// Check if this user follows another user
    func isFollowing(_ other: NDKUser) async throws -> Bool {
        guard let contactList = try await fetchContactList() else { return false }
        return contactList.isFollowing(other)
    }
}
