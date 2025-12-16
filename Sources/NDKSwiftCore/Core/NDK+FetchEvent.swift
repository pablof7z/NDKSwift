import Foundation

// MARK: - Event Fetching

extension NDK {
    /// Fetch a single event by identifier with intelligent caching and relay selection.
    ///
    /// This method provides a modern, observable API for fetching individual events.
    /// For non-replaceable events, it returns cached versions immediately without network fetch.
    /// For replaceable events, it returns cached version immediately and updates when newer version arrives.
    ///
    /// Supports multiple identifier formats:
    /// - Hex event ID (64 characters)
    /// - `note1...` (bech32 encoded event ID)
    /// - `nevent1...` (bech32 event with relay hints)
    /// - `naddr1...` (parameterized replaceable event address)
    ///
    /// The method automatically:
    /// - Checks cache first for efficiency
    /// - Skips network fetch for cached non-replaceable events
    /// - Extracts and uses relay hints from bech32 identifiers
    /// - Updates observable event when newer version arrives (for replaceable events)
    ///
    /// ## Example
    /// ```swift
    /// // Fetch by nevent with relay hints
    /// let fetched = ndk.fetchEvent("nevent1qqs...")
    /// // UI binds to fetched.event - updates automatically if newer version arrives
    ///
    /// // Fetch by hex ID
    /// let fetched = ndk.fetchEvent("a1b2c3d4...")
    /// ```
    ///
    /// - Parameter identifier: Event identifier (hex, note1, nevent1, naddr1)
    /// - Returns: Observable event that updates when newer versions arrive
    @MainActor
    public func fetchEvent(_ identifier: String) -> NDKFetchedEvent {
        return NDKFetchedEvent(ndk: self, identifier: identifier)
    }

    /// Fetch a single event from a NIP-10 tag reference with relay and pubkey hints.
    ///
    /// This method supports both "e" and "a" tag formats:
    /// - "e" tag: `["e", "event-id", "relay-hint", "marker", "pubkey-hint"]` (regular events)
    /// - "a" tag: `["a", "kind:pubkey:d-tag", "relay-hint", "marker"]` (addressable events)
    ///
    /// The method uses a priority-based relay selection:
    /// 1. Relay hint from tag (element [2])
    /// 2. Pubkey hint with outbox model (element [4] for "e" tags) - queries author's write relays
    /// 3. All connected relays as fallback
    ///
    /// ## Examples
    /// ```swift
    /// // Fetch from "e" tag with relay and pubkey hints
    /// let eTag = ["e", "abc123...", "wss://relay.com", "reply", "author-pubkey"]
    /// let fetched = ndk.fetchEvent(tag: eTag)
    ///
    /// // Fetch from "a" tag for addressable event
    /// let aTag = ["a", "30023:pubkey123...:identifier", "wss://relay.com"]
    /// let fetched = ndk.fetchEvent(tag: aTag)
    /// ```
    ///
    /// - Parameter tag: NIP-10 tag array ("e" or "a")
    /// - Returns: Observable event that updates when newer versions arrive
    @MainActor
    public func fetchEvent(tag: Tag) -> NDKFetchedEvent {
        return NDKFetchedEvent(ndk: self, tag: tag)
    }
}
