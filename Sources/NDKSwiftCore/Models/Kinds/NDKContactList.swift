import Foundation

/// Represents a contact entry in a contact list with optional metadata
public struct NDKContactEntry {
    public let pubkey: PublicKey
    public let relayURL: String?
    public let petname: String?

    public init(pubkey: PublicKey, relayURL: String? = nil, petname: String? = nil) {
        self.pubkey = pubkey
        self.relayURL = relayURL
        self.petname = petname
    }

    /// Convert to Tag representation
    public func toTag() -> Tag {
        var tag = ["p", pubkey]

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
public class NDKContactList: NDKList, Equatable {
    public static func == (lhs: NDKContactList, rhs: NDKContactList) -> Bool {
        lhs.id == rhs.id
    }

    /// Contact list kind (3)
    public static let kind = EventKind.contacts

    /// Initialize a new contact list
    override public init(ndk: NDK? = nil) {
        super.init(ndk: ndk)
        kind = EventKind.contacts
    }

    /// Create an NDKContactList from an existing NDKEvent
    public static func fromEvent(_ event: NDKEvent, ndk: NDK? = nil) -> NDKContactList {
        let contactList = NDKContactList(ndk: ndk)
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
        return contacts.map { $0.pubkey }
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
        createdAt = Timestamp.now
    }

    /// Add a contact to this list
    @discardableResult
    public func addContact(_ contact: NDKContactEntry) -> NDKContactList {
        // Check if contact already exists
        guard !isFollowing(contact.pubkey) else {
            return self
        }

        tags.append(contact.toTag())

        // Update timestamp
        createdAt = Timestamp.now

        return self
    }

    /// Add a contact by pubkey
    @discardableResult
    public func addContact(pubkey: String, relayURL: String? = nil, petname: String? = nil) -> NDKContactList {
        let contact = NDKContactEntry(pubkey: pubkey, relayURL: relayURL, petname: petname)
        return addContact(contact)
    }

    /// Remove a contact by pubkey
    @discardableResult
    public func removeContact(pubkey: String) -> NDKContactList {
        tags.removeAll { tag in
            tag.count > 1 && tag[0] == "p" && tag[1] == pubkey
        }

        // Update timestamp
        createdAt = Timestamp.now

        return self
    }

    /// Check if following a specific pubkey
    public func isFollowing(_ pubkey: String) -> Bool {
        return contactPubkeys.contains(pubkey)
    }

    /// Get contact entry for a specific pubkey
    public func contactEntry(for pubkey: String) -> NDKContactEntry? {
        return contacts.first { $0.pubkey == pubkey }
    }

    /// Get petname for a specific pubkey
    public func petname(for pubkey: String) -> String? {
        return contactEntry(for: pubkey)?.petname
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
        createdAt = Timestamp.now

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
        createdAt = Timestamp.now

        return self
    }

    /// Get contacts with petnames
    public var contactsWithPetnames: [NDKContactEntry] {
        return contacts.filter { contact in
            guard let petname = contact.petname else { return false }
            return !petname.isEmpty
        }
    }

    /// Get contacts with relay URLs
    public var contactsWithRelayURLs: [NDKContactEntry] {
        return contacts.filter { contact in
            guard let relayURL = contact.relayURL else { return false }
            return !relayURL.isEmpty
        }
    }

    /// Create a filter to fetch events from all contacts
    public func createContactFilter(kinds: [Int] = [EventKind.textNote], since: Timestamp? = nil, until: Timestamp? = nil, limit: Int? = nil) -> NDKFilter {
        var filter = NDKFilter(authors: contactPubkeys, kinds: kinds)
        filter.since = since
        filter.until = until
        filter.limit = limit
        return filter
    }

    /// Merge another contact list into this one
    @discardableResult
    public func merge(with other: NDKContactList) -> NDKContactList {
        for contact in other.contacts where !isFollowing(contact.pubkey) {
            addContact(contact)
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

}

