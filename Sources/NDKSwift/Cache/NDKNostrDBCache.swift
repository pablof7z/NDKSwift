import Foundation

/// NostrDB-based cache implementation for NDKSwift
///
/// This actor provides persistent event storage using nostrdb as the backend.
/// It implements the NDKCache protocol and provides high-performance event
/// storage with native nostrdb querying capabilities.
///
/// ## Implementation Status
/// This is a stub implementation. The full integration with NostrDB C library
/// will be completed in a follow-up task. For now, it provides protocol-compliant
/// behavior using the default implementations from NDKCache.
///
/// ## Future Features
/// - Fast event storage and retrieval using nostrdb's C-based engine
/// - Native filter-to-query conversion
/// - Automatic event indexing for full-text search
/// - Memory-efficient event management
///
/// ## Usage
/// ```swift
/// let cache = NDKNostrDBCache(path: "path/to/db")
/// try await cache.saveEvent(event)
/// let events = try await cache.queryEvents(filter)
/// ```
public actor NDKNostrDBCache: NDKCache {
    private let path: String?
    private var events: [String: NDKEvent] = [:]

    /// Initialize a new NostrDB cache
    /// - Parameter path: Optional path to the database directory. If nil, uses the default location.
    public init(path: String? = nil) {
        self.path = path
    }

    // MARK: - Event Operations

    public func saveEvent(_ event: NDKEvent) async throws {
        // TODO: Integrate with NostrDB C library
        // For now, store in memory
        events[event.id] = event
    }

    public func getEvent(id: String) async -> NDKEvent? {
        // TODO: Query from NostrDB
        // For now, return from memory
        return events[id]
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
        // TODO: Handle deletion in NostrDB
        // For now, remove from memory
        events.removeValue(forKey: id)
    }

    // MARK: - Cache Management

    public func clear() async throws {
        // TODO: Clear NostrDB database
        // For now, clear memory
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
}
