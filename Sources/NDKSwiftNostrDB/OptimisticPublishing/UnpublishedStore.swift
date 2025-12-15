import Foundation
import NDKSwiftCore

/// Storage for unpublished events using JSONL format
/// This is a "dumb" storage layer - it just stores/retrieves what it's told.
/// Threshold logic and decisions about what needs retry live in NDK-core.
actor UnpublishedStore {
    /// Record of an unpublished event with per-relay state
    struct UnpublishedEventRecord: Codable {
        let event: String  // Raw signed JSON event (as published)
        var publishedRelays: [String]  // Successfully published to these
        var pendingRelays: [String: String]  // Relay URL -> failure reason

        var eventId: String? {
            // Extract event ID from raw JSON
            guard let data = event.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else {
                return nil
            }
            return id
        }
    }

    private let fileURL: URL
    private var records: [String: UnpublishedEventRecord]  // eventId -> record

    init(cachePath: String?) throws {
        // Determine file location
        let url: URL
        if let cachePath = cachePath {
            let cacheURL = URL(fileURLWithPath: cachePath)
            url = cacheURL.appendingPathComponent("unpublished.jsonl")
        } else {
            // Use default cache directory
            guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                throw NSError(domain: "UnpublishedStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find cache directory"])
            }
            let ndkCache = cacheDir.appendingPathComponent("NDKSwift")
            try FileManager.default.createDirectory(at: ndkCache, withIntermediateDirectories: true)
            url = ndkCache.appendingPathComponent("unpublished.jsonl")
        }

        self.fileURL = url

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
    }

    /// Mark a relay as successfully published
    func markRelayPublished(eventId: String, relay: String) throws {
        guard var record = records[eventId] else { return }

        // Move from pending to published
        record.pendingRelays.removeValue(forKey: relay)
        if !record.publishedRelays.contains(relay) {
            record.publishedRelays.append(relay)
        }

        // Update in memory
        records[eventId] = record

        // Rewrite file (infrequent operation)
        try writeToFile()
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
    }

    /// Remove an event from tracking (called by NDK-core when threshold is met)
    func remove(eventId: String) throws {
        records.removeValue(forKey: eventId)
        try writeToFile()
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

    /// Get unpublished events
    func getUnpublishedEvents(maxAge: TimeInterval, limit: Int?) -> [(event: NDKEvent, targetRelays: Set<String>)] {
        let now = Date().timeIntervalSince1970
        let cutoff = now - maxAge

        var results: [(event: NDKEvent, targetRelays: Set<String>)] = []

        for record in records.values {
            // Parse event from raw JSON
            guard let data = record.event.data(using: .utf8),
                  let event = try? JSONCoding.decode(NDKEvent.self, from: data) else {
                continue
            }

            // Check age
            if Double(event.createdAt) < cutoff {
                continue
            }

            // Combine published and pending relays as target relays
            let targetRelays = Set(record.publishedRelays + Array(record.pendingRelays.keys))

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
}
