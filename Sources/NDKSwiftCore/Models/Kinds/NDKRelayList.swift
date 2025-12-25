/// Relay access modes for relay list entries
public enum NDKRelayAccess: String, CaseIterable {
    case read
    case write

    public var marker: String? {
        return rawValue
    }
}

/// Represents a relay entry in a relay list with access permissions
public struct NDKRelayListEntry {
    public let relay: NDKRelay
    public let access: Set<NDKRelayAccess>

    public init(relay: NDKRelay, access: Set<NDKRelayAccess> = [.read, .write]) {
        self.relay = relay
        self.access = access
    }

    public init(url: String, access: Set<NDKRelayAccess> = [.read, .write]) {
        relay = NDKRelay(url: url)
        self.access = access
    }

    /// Whether this relay supports reading
    public var canRead: Bool {
        return access.contains(.read)
    }

    /// Whether this relay supports writing
    public var canWrite: Bool {
        return access.contains(.write)
    }

    /// Convert to Tag representation
    public func toTag() -> Tag {
        var tag = ["r", relay.url]
        let accessMarkers = access.compactMap { $0.marker }
        tag.append(contentsOf: accessMarkers)
        return tag
    }
}

/// Specialized list for managing user relay preferences (NIP-65, kind 10002)
/// Provides read/write relay separation and relay set integration
public class NDKRelayList: NDKList {
    /// The kind for relay lists (NIP-65)
    public static let kind: Kind = EventKind.relayList

    /// Initialize a new relay list
    override public init(ndk: NDK? = nil) {
        super.init(ndk: ndk)
        kind = NDKRelayList.kind
    }

    /// Create an NDKRelayList from an existing NDKEvent
    public static func fromEvent(_ event: NDKEvent, ndk: NDK? = nil) -> NDKRelayList {
        let relayList = NDKRelayList(ndk: ndk)
        relayList.id = event.id
        relayList.pubkey = event.pubkey
        relayList.createdAt = event.createdAt
        relayList.kind = event.kind
        relayList.tags = event.tags
        relayList.content = event.content
        relayList.signature = event.sig
        return relayList
    }

    /// All relay entries in this list with their access permissions
    public var relayEntries: [NDKRelayListEntry] {
        let relayTags = tags.filter { !$0.isEmpty && $0[0] == "r" }
        return relayTags.compactMap { tag in
            guard tag.count > 1 else { return nil }
            let url = tag[1]
            guard !url.isEmpty else { return nil }

            // Parse access markers from additional elements
            var access: Set<NDKRelayAccess> = []
            for i in 2 ..< tag.count {
                let marker = tag[i]
                if marker == "both" {
                    // "both" marker means read and write
                    access = [.read, .write]
                    break
                } else if let relayAccess = NDKRelayAccess(rawValue: marker) {
                    access.insert(relayAccess)
                }
            }

            // If no access markers specified, assume both read and write
            if access.isEmpty {
                access = [.read, .write]
            }

            // Normalize the URL to ensure consistent relay identification
            let normalizedURL = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
            return NDKRelayListEntry(url: normalizedURL, access: access)
        }
    }

    /// All relays that support reading
    public var readRelays: [NDKRelay] {
        return relayEntries
            .filter { $0.canRead }
            .map { $0.relay }
    }

    /// All relays that support writing
    public var writeRelays: [NDKRelay] {
        return relayEntries
            .filter { $0.canWrite }
            .map { $0.relay }
    }

    /// All relay URLs in this list
    public var relayURLs: [String] {
        return relayEntries.map { $0.relay.url }
    }

    /// Set the complete list of relay entries
    public func setRelays(_ entries: [NDKRelayListEntry]) {
        // Remove all existing relay tags
        tags.removeAll { !$0.isEmpty && $0[0] == "r" }

        // Add new relay entries
        for entry in entries {
            tags.append(entry.toTag())
        }

        // Update timestamp
        createdAt = Timestamp.now
    }

    /// Add a relay with specified access permissions
    @discardableResult
    public func addRelay(_ url: String, access: Set<NDKRelayAccess> = [.read, .write]) -> NDKRelayList {
        // Normalize the URL
        let normalizedURL = URLNormalizer.tryNormalizeRelayUrl(url) ?? url

        // Check if relay already exists
        guard !relayURLs.contains(normalizedURL) else {
            return self
        }

        let entry = NDKRelayListEntry(url: normalizedURL, access: access)
        tags.append(entry.toTag())

        // Update timestamp
        createdAt = Timestamp.now

        return self
    }

    /// Add a relay for reading only
    @discardableResult
    public func addReadRelay(_ url: String) -> NDKRelayList {
        return addRelay(url, access: [.read])
    }

    /// Add a relay for writing only
    @discardableResult
    public func addWriteRelay(_ url: String) -> NDKRelayList {
        return addRelay(url, access: [.write])
    }

    /// Remove a relay by URL
    @discardableResult
    public func removeRelay(_ url: String) -> NDKRelayList {
        let normalizedURL = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
        tags.removeAll { tag in
            tag.count > 1 && tag[0] == "r" && tag[1] == normalizedURL
        }

        // Update timestamp
        createdAt = Timestamp.now

        return self
    }

    /// Update access permissions for an existing relay
    @discardableResult
    public func updateRelayAccess(_ url: String, access: Set<NDKRelayAccess>) -> NDKRelayList {
        let normalizedURL = URLNormalizer.tryNormalizeRelayUrl(url) ?? url

        // Find and update the relay tag
        for i in 0 ..< tags.count {
            if tags[i].count > 1 && tags[i][0] == "r" && tags[i][1] == normalizedURL {
                var newTag = ["r", normalizedURL]
                let accessMarkers = access.compactMap { $0.marker }
                newTag.append(contentsOf: accessMarkers)
                tags[i] = newTag
                break
            }
        }

        // Update timestamp
        createdAt = Timestamp.now

        return self
    }

    /// Check if a relay is in this list
    public func hasRelay(_ url: String) -> Bool {
        let normalizedURL = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
        return relayURLs.contains(normalizedURL)
    }

    /// Get access permissions for a specific relay
    public func accessFor(relay url: String) -> Set<NDKRelayAccess>? {
        let normalizedURL = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
        return relayEntries.first { $0.relay.url == normalizedURL }?.access
    }

    /// Create a relay set from this relay list for use with NDK
    public func toRelaySet() -> Set<NDKRelay> {
        return Set(relayEntries.map { $0.relay })
    }

    /// Create read relay set
    public func readRelaySet() -> Set<NDKRelay> {
        return Set(readRelays)
    }

    /// Create write relay set
    public func writeRelaySet() -> Set<NDKRelay> {
        return Set(writeRelays)
    }

    /// Merge another relay list into this one
    @discardableResult
    public func merge(with other: NDKRelayList) -> NDKRelayList {
        for entry in other.relayEntries where !hasRelay(entry.relay.url) {
            tags.append(entry.toTag())
        }

        // Update timestamp
        createdAt = Timestamp.now

        return self
    }

    /// Create a relay list from a set of relays with default read/write access
    public static func from(relays: [String], ndk: NDK? = nil) -> NDKRelayList {
        let relayList = NDKRelayList(ndk: ndk)

        for url in relays {
            relayList.addRelay(url)
        }

        return relayList
    }

    /// Create a relay list with separate read and write relays
    public static func from(readRelays: [String], writeRelays: [String], ndk: NDK? = nil) -> NDKRelayList {
        let relayList = NDKRelayList(ndk: ndk)

        for url in readRelays {
            relayList.addReadRelay(url)
        }

        for url in writeRelays {
            relayList.addWriteRelay(url)
        }

        return relayList
    }
}

// MARK: - Integration with NDK

public extension NDK {
    /// Fetch the relay list for a specific user
    func fetchRelayList(for user: NDKUser) async throws -> NDKRelayList? {
        let filter = NDKFilter(authors: [user.pubkey], kinds: [EventKind.relayList])

        // Use NDKSubscription with long maxAge for relay lists
        let dataSource = NDKSubscription(
            ndk: self,
            filter: filter,
            maxAge: TimeConstants.day // 24 hours - relay lists rarely change
        )

        // Collect all relay list events and use the most recent
        let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionMedium)
        guard let event = events.mostRecent else { return nil }
        return NDKRelayList.fromEvent(event)
    }

    /// Fetch the relay list for the current user
    func fetchRelayList() async throws -> NDKRelayList? {
        guard let signer else { return nil }
        let pubkey = try await signer.pubkey
        guard let currentUser = getUser(pubkey) else { return nil }
        return try await fetchRelayList(for: currentUser)
    }

    /// Publish a relay list
    func publishRelayList(_ relayList: NDKRelayList) async throws {
        _ = try requireSigner()

        try await relayList.sign()
        let event = relayList.toNDKEvent()
        _ = try await publish(event)
    }
}

public extension NDKUser {
    /// Fetch this user's relay list
    func fetchRelayListEvent() async throws -> NDKRelayList? {
        return try await ndk.fetchRelayList(for: self)
    }
}
