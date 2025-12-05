import Foundation

/// NostrDB-based cache implementation for NDKSwift
///
/// This actor provides persistent event storage using nostrdb as the backend.
/// It implements the NDKCache protocol and provides high-performance event
/// storage with native nostrdb querying capabilities.
///
/// ## Features
/// - Fast event storage and retrieval using nostrdb's C-based engine
/// - Persistent storage with LMDB backend
/// - High-performance event indexing
/// - Memory-efficient event management
///
/// ## Usage
/// ```swift
/// let cache = try await NDKNostrDBCache(path: "path/to/db")
/// try await cache.saveEvent(event)
/// let event = await cache.getEvent(id: eventId)
/// ```
public actor NDKNostrDBCache: NDKCache {
    private var ndb: Ndb?
    private var events: [String: NDKEvent] = [:]

    /// Initialize a new NostrDB cache
    /// - Parameter path: Optional path to the database directory. If nil, uses the default location.
    /// - Throws: NDKNostrDBCacheError if the database cannot be opened
    public init(path: String? = nil) async throws {
        self.ndb = Ndb(path: path)
        if self.ndb == nil {
            throw NDKNostrDBCacheError.failedToOpen
        }
    }

    // MARK: - Event Operations

    public func saveEvent(_ event: NDKEvent) async throws {
        guard let ndb = ndb else {
            throw NDKNostrDBCacheError.notInitialized
        }

        // Convert NDKEvent to JSON for nostrdb processing
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NDKNostrDBCacheError.encodingFailed
        }

        // Process the event through nostrdb
        _ = ndb.process_event(json)
        // Note: process_event returns false for duplicates or invalid events
        // This is not necessarily an error, so we don't throw

        // Also keep in memory for queryEvents (until we implement full nostrdb queries)
        events[event.id] = event
    }

    public func getEvent(id: String) async -> NDKEvent? {
        guard let ndb = ndb else { return nil }

        // Convert hex ID to NdbNoteId
        guard let idData = hexToData(id) else { return nil }
        let noteId = NdbNoteId(idData)

        // Lookup the note from nostrdb
        guard let txn = ndb.lookup_note(noteId) else {
            // Fall back to in-memory cache if not in nostrdb yet
            return events[id]
        }

        let note = txn.unsafeUnownedValue
        guard let note = note else {
            return events[id]
        }

        // Convert NdbNote to NDKEvent
        return convertToNDKEvent(note)
    }

    public func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        // TODO: Convert NDKFilter to nostrdb query and execute
        // For now, do basic in-memory filtering
        var results = Array(events.values)

        // Filter by IDs
        if let ids = filter.ids {
            results = results.filter { ids.contains($0.id) }
        }

        // Filter by authors
        if let authors = filter.authors {
            results = results.filter { authors.contains($0.pubkey) }
        }

        // Filter by kinds
        if let kinds = filter.kinds {
            results = results.filter { kinds.contains($0.kind) }
        }

        // Filter by timestamp
        if let since = filter.since {
            results = results.filter { $0.createdAt >= since }
        }

        if let until = filter.until {
            results = results.filter { $0.createdAt <= until }
        }

        // Sort by created_at descending (most recent first)
        results.sort { $0.createdAt > $1.createdAt }

        // Apply limit
        if let limit = filter.limit {
            results = Array(results.prefix(limit))
        }

        return results
    }

    public func deleteEvent(id: String) async throws {
        // Note: NostrDB doesn't support deletion of individual events
        // Events are immutable once stored in LMDB
        // We only remove from in-memory cache
        events.removeValue(forKey: id)
    }

    // MARK: - Cache Management

    public func clear() async throws {
        // Note: NostrDB doesn't provide a clear/reset API
        // To clear the database, you would need to delete the LMDB files
        // We can only clear the in-memory cache
        events.removeAll()
    }

    // MARK: - Reactive Observation

    public func observeEvents(
        matching filter: NDKFilter,
        includeExisting: Bool
    ) async -> AsyncThrowingStream<[NDKEvent], Error> {
        // TODO: Implement with NostrDB subscription API
        // For now, return existing events only
        return AsyncThrowingStream { continuation in
            Task {
                if includeExisting {
                    do {
                        let existing = try await queryEvents(filter)
                        if !existing.isEmpty {
                            continuation.yield(existing)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
        }
    }

    public func observeProfile(
        pubkey: String,
        includeExisting: Bool
    ) async -> AsyncThrowingStream<NDKUserMetadata?, Error> {
        // TODO: Implement with NostrDB profile observation
        // For now, return existing profile only
        return AsyncThrowingStream { continuation in
            Task {
                if includeExisting {
                    if let profile = await getProfileMetadata(pubkey: pubkey) {
                        let metadata = NDKUserMetadata(
                            pubkey: pubkey,
                            parsedMetadata: profile.metadata,
                            updatedAt: profile.updatedAt,
                            eventId: profile.eventId
                        )
                        continuation.yield(metadata)
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Profile Metadata Operations

    public func getProfileMetadata(pubkey: String) async -> (metadata: [String: Any], updatedAt: Timestamp, eventId: String)? {
        // TODO: Query profile from NostrDB
        // For now, query kind 0 events from memory
        let kind0Events = events.values.filter { $0.kind == EventKind.metadata && $0.pubkey == pubkey }

        guard let latestEvent = kind0Events.max(by: { $0.createdAt < $1.createdAt }) else {
            return nil
        }

        // Parse metadata from JSON content
        guard let data = latestEvent.content.data(using: .utf8),
              let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return (metadata: metadata, updatedAt: latestEvent.createdAt, eventId: latestEvent.id)
    }

    // MARK: - Helper Methods

    /// Convert NdbNote to NDKEvent
    private func convertToNDKEvent(_ note: NdbNote) -> NDKEvent? {
        // Convert tags using built-in helper
        let tags = note.tags.strings()

        // Convert ID, pubkey, and sig to hex strings
        let id = dataToHex(note.id.id)
        let pubkey = dataToHex(note.pubkey.data)
        let sig = dataToHex(note.sig.data)

        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: Timestamp(note.created_at),
            kind: Kind(note.kind),
            tags: tags,
            content: note.content,
            sig: sig
        )
    }

    /// Convert hex string to Data
    private func hexToData(_ hex: String) -> Data? {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let byteString = String(hex[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        return data.count == hex.count / 2 ? data : nil
    }

    /// Convert Data to hex string
    private func dataToHex(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Error Types

/// Errors that can occur when using NDKNostrDBCache
public enum NDKNostrDBCacheError: Error {
    case failedToOpen
    case notInitialized
    case encodingFailed
}
