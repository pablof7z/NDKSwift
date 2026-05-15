import Foundation


/// Represents a change in the unpublished events store
public enum UnpublishedChange: Sendable {
    /// A new event was added to unpublished tracking
    case eventAdded(eventId: String, kind: Int, targetRelays: [String])
    /// A relay successfully published an event
    case relayPublished(eventId: String, relay: String)
    /// A relay failed to publish an event
    case relayFailed(eventId: String, relay: String, reason: String)
    /// An event was removed from tracking (fully published or expired)
    case eventRemoved(eventId: String)
}

/// Storage for unpublished events using JSONL format
/// This is a "dumb" storage layer - it just stores/retrieves what it's told.
/// Threshold logic and decisions about what needs retry live in NDK-core.
public actor UnpublishedStore {
    /// Record of an unpublished event with per-relay state
    public struct UnpublishedEventRecord: Codable, Sendable {
        public let event: String  // Raw signed JSON event (as published)
        public var publishedRelays: [String]  // Successfully published to these
        public var pendingRelays: [String: String]  // Relay URL -> failure reason (empty string = pending)

        public var eventId: String? {
            // Extract event ID from raw JSON
            guard let data = event.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else {
                return nil
            }
            return id
        }

        public var kind: Int? {
            // Extract kind from raw JSON
            guard let data = event.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let kind = json["kind"] as? Int else {
                return nil
            }
            return kind
        }
    }

    private let fileURL: URL
    private var records: [String: UnpublishedEventRecord]  // eventId -> record

    /// Stream of unpublished store changes for event-driven observation
    private let changeStream: AsyncStream<UnpublishedChange>
    private let changeContinuation: AsyncStream<UnpublishedChange>.Continuation

    /// Public accessor for unpublished changes stream
    public var changes: AsyncStream<UnpublishedChange> {
        changeStream
    }

    init(cachePath: String?, migrateLegacyDefault: Bool = false) throws {
        // Initialize the change stream
        (changeStream, changeContinuation) = AsyncStream<UnpublishedChange>.makeStream()

        // Determine file location
        let shouldMigrateLegacy = migrateLegacyDefault || cachePath == nil
        let url: URL
        if let cachePath = cachePath {
            let cacheURL = URL(fileURLWithPath: cachePath)
            try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
            url = cacheURL.appendingPathComponent("unpublished.jsonl")
        } else {
            let durableDir = try Self.defaultDurableDirectory()
            try FileManager.default.createDirectory(at: durableDir, withIntermediateDirectories: true)
            url = durableDir.appendingPathComponent("unpublished.jsonl")
        }

        self.fileURL = url
        if shouldMigrateLegacy {
            try Self.migrateLegacyCacheFileIfNeeded(to: url)
        }

        // Load existing records synchronously during initialization
        var loadedRecords: [String: UnpublishedEventRecord] = [:]

        if FileManager.default.fileExists(atPath: url.path) {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines).filter { !$0.isEmpty }

            for line in lines {
                guard let data = line.data(using: .utf8),
                      let record = try? JSONDecoder().decode(UnpublishedEventRecord.self, from: data),
                      let eventId = record.eventId else {
                    continue
                }
                loadedRecords[eventId] = record
            }
        }

        self.records = loadedRecords
    }

    private static func defaultDurableDirectory() throws -> URL {
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(
                domain: "UnpublishedStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not find application support directory"]
            )
        }
        return appSupportDir.appendingPathComponent("NDKSwift", isDirectory: true)
    }

    private static func legacyCacheFileURL() -> URL? {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cacheDir
            .appendingPathComponent("NDKSwift", isDirectory: true)
            .appendingPathComponent("unpublished.jsonl")
    }

    private static func migrateLegacyCacheFileIfNeeded(to targetURL: URL) throws {
        guard let legacyURL = legacyCacheFileURL(),
              legacyURL.standardizedFileURL != targetURL.standardizedFileURL,
              FileManager.default.fileExists(atPath: legacyURL.path),
              !FileManager.default.fileExists(atPath: targetURL.path) else {
            return
        }

        let parent = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: legacyURL, to: targetURL)
    }

    // MARK: - File Operations

    /// Write all records to JSONL file
    private func writeToFile() throws {
        let encoder = JSONEncoder()
        var lines: [String] = []

        for record in records.values {
            let data = try encoder.encode(record)
            if let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }

        let contents = lines.joined(separator: "\n")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Append a new record to JSONL file
    private func appendToFile(_ record: UnpublishedEventRecord) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        guard let line = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "UnpublishedStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode record"])
        }

        let lineWithNewline = line + "\n"

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            defer { try? fileHandle.close() }
            fileHandle.seekToEndOfFile()
            if let data = lineWithNewline.data(using: .utf8) {
                fileHandle.write(data)
            }
        } else {
            try lineWithNewline.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Public Methods (called by NDK-core)

    /// Add an unpublished event (NDK-core already decided this needs tracking)
    func add(_ event: NDKEvent, publishedRelays: [String], pendingRelays: [String: String]) throws {
        // Serialize event to raw JSON
        let eventJSON = try JSONCoding.encodeToString(event)

        let record = UnpublishedEventRecord(
            event: eventJSON,
            publishedRelays: publishedRelays,
            pendingRelays: pendingRelays
        )

        // Store in memory
        records[event.id] = record

        // Append to file
        try appendToFile(record)

        // Emit change notification
        changeContinuation.yield(.eventAdded(
            eventId: event.id,
            kind: event.kind,
            targetRelays: Array(pendingRelays.keys)
        ))
    }

    /// Mark a relay as successfully published
    func markRelayPublished(eventId: String, relay: String) throws {
        guard var record = records[eventId] else { return }

        // Move from pending to published
        record.pendingRelays.removeValue(forKey: relay)
        if !record.publishedRelays.contains(relay) {
            record.publishedRelays.append(relay)
        }

        // Emit relay published notification
        changeContinuation.yield(.relayPublished(eventId: eventId, relay: relay))

        // If no more pending relays, remove the event from tracking
        if record.pendingRelays.isEmpty {
            records.removeValue(forKey: eventId)
            try writeToFile()
            changeContinuation.yield(.eventRemoved(eventId: eventId))
        } else {
            // Update in memory and rewrite file
            records[eventId] = record
            try writeToFile()
        }
    }

    /// Update failure reason for a relay
    func markRelayFailed(eventId: String, relay: String, reason: String) throws {
        guard var record = records[eventId] else { return }

        // Update failure reason
        record.pendingRelays[relay] = reason

        // Update in memory
        records[eventId] = record

        // Rewrite file
        try writeToFile()

        // Emit change notification
        changeContinuation.yield(.relayFailed(eventId: eventId, relay: relay, reason: reason))
    }

    /// Remove an event from tracking (called by NDK-core when threshold is met)
    func remove(eventId: String) throws {
        records.removeValue(forKey: eventId)
        try writeToFile()

        // Emit change notification
        changeContinuation.yield(.eventRemoved(eventId: eventId))
    }

    /// Get event confirmation state
    func getEventConfirmationState(eventId: String) -> EventConfirmationState? {
        guard let record = records[eventId] else { return nil }

        // If any relay has published, return confirmed with first published relay
        if let firstPublished = record.publishedRelays.first {
            return .confirmed(fromRelay: firstPublished)
        }

        // If no relays have published, return optimistic
        return .optimistic
    }

    /// Get unpublished events (events that still have pending relays to publish to)
    func getUnpublishedEvents(maxAge: TimeInterval, limit: Int?) -> [(event: NDKEvent, targetRelays: Set<String>)] {
        if let limit = limit, limit <= 0 {
            return []
        }

        let now = Date().timeIntervalSince1970
        let cutoff = now - maxAge

        var results: [(event: NDKEvent, targetRelays: Set<String>)] = []

        for record in records.values {
            // Skip events with no pending relays - they're fully published
            if record.pendingRelays.isEmpty {
                continue
            }

            // Parse event from raw JSON
            guard let data = record.event.data(using: .utf8),
                  let event = try? JSONCoding.decode(NDKEvent.self, from: data) else {
                continue
            }

            // Check age
            if Double(event.createdAt) < cutoff {
                continue
            }

            // Return only pending relays as target relays
            let targetRelays = Set(record.pendingRelays.keys)

            results.append((event: event, targetRelays: targetRelays))

            // Check limit
            if let limit = limit, results.count >= limit {
                break
            }
        }

        return results
    }

    /// Clear all unpublished events
    func clear() throws {
        records.removeAll()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Get all unpublished event records with full relay status
    /// Used by TUI to display detailed per-relay publish status
    func getAllRecords() -> [String: UnpublishedEventRecord] {
        records
    }
}
