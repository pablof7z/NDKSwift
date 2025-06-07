import Foundation

/// File-based cache adapter for NDKSwift
/// Uses JSON files for persistent storage without external dependencies
public final class NDKFileCache: NDKCacheAdapter {
    // Protocol requirements
    public var locking: Bool = false
    public var ready: Bool = true

    let cacheDirectory: URL
    private let eventsDirectory: URL
    private let profilesDirectory: URL
    private let unpublishedDirectory: URL
    private let decryptedDirectory: URL
    private let metadataFile: URL

    // In-memory indexes for fast lookups
    private var eventIndex: [String: EventIndexEntry] = [:]
    private var profileIndex: [String: Date] = [:]
    private var tagIndex: [String: Set<String>] = [:] // tag:value -> Set of event IDs
    private var nip05Cache: [String: (pubkey: String, relays: [String], cachedAt: Date)] = [:]
    private var relayStatusCache: [String: NDKRelayConnectionState] = [:]

    // Outbox support
    var unpublishedEventIndex: [String: UnpublishedEventRecord] = [:]
    var outboxItemIndex: [String: NDKOutboxItem] = [:]
    var relayHealthCache: [String: RelayHealthMetrics] = [:]

    // Thread safety
    let queue = DispatchQueue(label: "com.ndkswift.filecache", attributes: .concurrent)

    private struct EventIndexEntry {
        let id: String
        let pubkey: String
        let kind: Kind
        let createdAt: Timestamp
        let tags: [[String]]
        let replaceableId: String?
    }

    private struct CacheMetadata: Codable {
        var version: Int = 1
        var lastUpdated: Date = .init()
        var eventCount: Int = 0
        var profileCount: Int = 0
    }
    
    private struct UnpublishedEventData: Codable {
        let event: NDKEvent
        var relays: [String]
        let lastTryAt: Date
    }

    public init(path: String = "ndk-file-cache") throws {
        // Get documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent(path)

        // Create subdirectories
        self.eventsDirectory = cacheDirectory.appendingPathComponent("events")
        self.profilesDirectory = cacheDirectory.appendingPathComponent("profiles")
        self.unpublishedDirectory = cacheDirectory.appendingPathComponent("unpublished")
        self.decryptedDirectory = cacheDirectory.appendingPathComponent("decrypted")
        self.metadataFile = cacheDirectory.appendingPathComponent("metadata.json")

        // Create directories if they don't exist
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unpublishedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: decryptedDirectory, withIntermediateDirectories: true)

        // Initialize outbox directories
        try initializeOutboxDirectories()

        // Load indexes
        try loadIndexes()
    }

    private func loadIndexes() throws {
        // Load event index
        let eventFiles = try FileManager.default.contentsOfDirectory(at: eventsDirectory, includingPropertiesForKeys: nil)

        for file in eventFiles where file.pathExtension == "json" {
            if let event = try? FileManager.default.loadCodable(NDKEvent.self, from: file) {
                guard let eventId = event.id else { continue }

                let indexEntry = EventIndexEntry(
                    id: eventId,
                    pubkey: event.pubkey,
                    kind: event.kind,
                    createdAt: event.createdAt,
                    tags: event.tags,
                    replaceableId: event.isReplaceable ? event.tagAddress : nil
                )

                eventIndex[eventId] = indexEntry

                // Build tag index
                for tag in event.tags where tag.count >= 2 && tag[0].count == 1 {
                    let key = "\(tag[0]):\(tag[1])"
                    if tagIndex[key] == nil {
                        tagIndex[key] = Set()
                    }
                    tagIndex[key]?.insert(eventId)
                }
            }
        }

        // Load profile index - we keep this as is since we only need modification dates
        let profileFiles = try FileManager.default.contentsOfDirectory(at: profilesDirectory, includingPropertiesForKeys: nil)

        for file in profileFiles where file.pathExtension == "json" {
            let pubkey = file.deletingPathExtension().lastPathComponent
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                profileIndex[pubkey] = modificationDate
            }
        }
    }

    // MARK: - NDKCacheAdapter Protocol

    public func query(subscription: NDKSubscription) async -> [NDKEvent] {
        return queue.sync { [self] in
            var results: [NDKEvent] = []
            var seenIds = Set<String>()

            for filter in subscription.filters {
                let matchingEvents = queryWithFilterSync(filter, subscription: subscription)
                for event in matchingEvents {
                    let eventId = event.id ?? UUID().uuidString
                    if !seenIds.contains(eventId) {
                        seenIds.insert(eventId)
                        results.append(event)
                    }
                }
            }

            return results
        }
    }

    private func queryWithFilterSync(_ filter: NDKFilter, subscription _: NDKSubscription) -> [NDKEvent] {
        var matchingIds = Set<String>()

        // Start with all events if no specific filters
        if filter.ids == nil && filter.authors == nil && filter.kinds == nil && filter.tags == nil {
            matchingIds = Set(eventIndex.keys)
        }

        // Filter by IDs
        if let ids = filter.ids {
            let idSet = Set(ids)
            if matchingIds.isEmpty {
                matchingIds = idSet.intersection(Set(eventIndex.keys))
            } else {
                matchingIds = matchingIds.intersection(idSet)
            }
        }

        // Filter by authors
        if let authors = filter.authors {
            let authorEvents = eventIndex.values
                .filter { authors.contains($0.pubkey) }
                .map { $0.id }

            if matchingIds.isEmpty {
                matchingIds = Set(authorEvents)
            } else {
                matchingIds = matchingIds.intersection(Set(authorEvents))
            }
        }

        // Filter by kinds
        if let kinds = filter.kinds {
            let kindValues = Set(kinds)
            let kindEvents = eventIndex.values
                .filter { kindValues.contains($0.kind) }
                .map { $0.id }

            if matchingIds.isEmpty {
                matchingIds = Set(kindEvents)
            } else {
                matchingIds = matchingIds.intersection(Set(kindEvents))
            }
        }

        // Filter by tags
        if let tags = filter.tags {
            var tagMatchingIds = Set<String>()

            for (tagName, tagValues) in tags {
                if tagName.count == 1 {
                    for value in tagValues {
                        let key = "\(tagName):\(value)"
                        if let ids = tagIndex[key] {
                            tagMatchingIds.formUnion(ids)
                        }
                    }
                }
            }

            if !tagMatchingIds.isEmpty {
                if matchingIds.isEmpty {
                    matchingIds = tagMatchingIds
                } else {
                    matchingIds = matchingIds.intersection(tagMatchingIds)
                }
            }
        }

        // Apply time filters and load events
        var events: [NDKEvent] = []

        for id in matchingIds {
            guard let indexEntry = eventIndex[id] else { continue }

            // Check time constraints
            if let since = filter.since, indexEntry.createdAt < since {
                continue
            }
            if let until = filter.until, indexEntry.createdAt > until {
                continue
            }

            // Load event from file
            let eventFile = eventsDirectory.appendingPathComponent("\(id).json")
            if let event = try? FileManager.default.loadCodable(NDKEvent.self, from: eventFile) {
                // Double-check the event matches the filter
                if filter.matches(event: event) {
                    events.append(event)
                }
            }
        }

        // Sort by created_at descending
        events.sort { $0.createdAt > $1.createdAt }

        // Apply limit
        if let limit = filter.limit {
            events = Array(events.prefix(limit))
        }

        return events
    }

    public func setEvent(_ event: NDKEvent, filters _: [NDKFilter], relay _: NDKRelay?) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                let referenceId = event.isReplaceable ? event.tagAddress : event.id

                // Check if we already have a newer version
                if event.isReplaceable {
                    if let existingEntry = self.eventIndex.values.first(where: { $0.replaceableId == referenceId }),
                       existingEntry.createdAt >= event.createdAt
                    {
                        continuation.resume()
                        return
                    }

                    // Remove old replaceable event
                    if let oldEntry = self.eventIndex.values.first(where: { $0.replaceableId == referenceId }) {
                        self.removeEventSync(oldEntry.id)
                    }
                }

                // Generate ID if needed
                if event.id == nil {
                    _ = try? event.generateID()
                }

                guard let eventId = event.id else {
                    continuation.resume()
                    return
                }

                // Save event to file
                let eventFile = self.eventsDirectory.appendingPathComponent("\(eventId).json")
                do {
                    try FileManager.default.saveCodable(event, to: eventFile)
                } catch {
                    print("Failed to save event: \(error)")
                }

                // Update index
                let indexEntry = EventIndexEntry(
                    id: eventId,
                    pubkey: event.pubkey,
                    kind: event.kind,
                    createdAt: event.createdAt,
                    tags: event.tags,
                    replaceableId: event.isReplaceable ? event.tagAddress : nil
                )
                self.eventIndex[eventId] = indexEntry

                // Update tag index
                for tag in event.tags where tag.count >= 2 && tag[0].count == 1 {
                    let key = "\(tag[0]):\(tag[1])"
                    if self.tagIndex[key] == nil {
                        self.tagIndex[key] = Set()
                    }
                    self.tagIndex[key]?.insert(eventId)
                }

                // Handle special event kinds
                if event.kind == EventKind.deletion {
                    let eventIdsToDelete = event.tags
                        .filter { $0[0] == "e" && $0.count > 1 }
                        .map { $0[1] }
                    for id in eventIdsToDelete {
                        self.removeEventSync(id)
                    }
                } else if event.kind == EventKind.metadata {
                    if let profile = NDKUserProfile.fromMetadataEvent(event) {
                        self.saveProfileSync(pubkey: event.pubkey, profile: profile)
                    }
                }

                continuation.resume()
            }
        }
    }

    private func removeEventSync(_ eventId: String) {
        // Remove from indexes
        if let entry = eventIndex[eventId] {
            eventIndex.removeValue(forKey: eventId)

            // Remove from tag index
            for tag in entry.tags where tag.count >= 2 && tag[0].count == 1 {
                let key = "\(tag[0]):\(tag[1])"
                tagIndex[key]?.remove(eventId)
                if tagIndex[key]?.isEmpty == true {
                    tagIndex.removeValue(forKey: key)
                }
            }
        }

        // Remove file
        let eventFile = eventsDirectory.appendingPathComponent("\(eventId).json")
        try? FileManager.default.removeItem(at: eventFile)
    }

    public func fetchProfile(pubkey: String) async -> NDKUserProfile? {
        let profileFile = profilesDirectory.appendingPathComponent("\(pubkey).json")
        return try? FileManager.default.loadCodable(NDKUserProfile.self, from: profileFile)
    }

    public func saveProfile(pubkey: String, profile: NDKUserProfile) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.saveProfileSync(pubkey: pubkey, profile: profile)
                continuation.resume()
            }
        }
    }

    private func saveProfileSync(pubkey: String, profile: NDKUserProfile) {
        let profileFile = profilesDirectory.appendingPathComponent("\(pubkey).json")

        do {
            try FileManager.default.saveCodable(profile, to: profileFile)
            profileIndex[pubkey] = Date()
        } catch {
            print("Failed to save profile: \(error)")
        }
    }

    public func addUnpublishedEvent(_ event: NDKEvent, relayUrls: [String]) async {
        guard let eventId = event.id else { return }
        let unpublishedFile = unpublishedDirectory.appendingPathComponent("\(eventId).json")

        let record = UnpublishedEventData(
            event: event,
            relays: relayUrls,
            lastTryAt: Date()
        )

        do {
            try FileManager.default.saveCodable(record, to: unpublishedFile)
        } catch {
            print("Failed to save unpublished event: \(error)")
        }
    }

    public func getUnpublishedEvents() async -> [(event: NDKEvent, relays: [String], lastTryAt: Date)] {
        let records = FileManager.default.loadAllCodable(
            UnpublishedEventData.self,
            fromDirectory: unpublishedDirectory
        )
        
        return records.map { record in
            (event: record.event, relays: record.relays, lastTryAt: record.lastTryAt)
        }
    }

    public func discardUnpublishedEvent(_ eventId: String) async {
        let unpublishedFile = unpublishedDirectory.appendingPathComponent("\(eventId).json")
        try? FileManager.default.removeItem(at: unpublishedFile)
    }

    public func clear() async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                // Clear all directories
                try? FileManager.default.removeItem(at: self.eventsDirectory)
                try? FileManager.default.removeItem(at: self.profilesDirectory)
                try? FileManager.default.removeItem(at: self.unpublishedDirectory)
                try? FileManager.default.removeItem(at: self.decryptedDirectory)

                // Recreate directories
                try? FileManager.default.createDirectory(at: self.eventsDirectory, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: self.profilesDirectory, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: self.unpublishedDirectory, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: self.decryptedDirectory, withIntermediateDirectories: true)

                // Clear indexes
                self.eventIndex.removeAll()
                self.profileIndex.removeAll()
                self.tagIndex.removeAll()

                continuation.resume()
            }
        }
    }

    // MARK: - Additional Methods

    public func getDecryptedEvent(eventId: String) async -> NDKEvent? {
        let decryptedFile = decryptedDirectory.appendingPathComponent("\(eventId).json")
        return try? FileManager.default.loadCodable(NDKEvent.self, from: decryptedFile)
    }

    public func addDecryptedEvent(_ event: NDKEvent) async {
        guard let eventId = event.id else { return }
        let decryptedFile = decryptedDirectory.appendingPathComponent("\(eventId).json")

        do {
            try FileManager.default.saveCodable(event, to: decryptedFile)
        } catch {
            print("Failed to save decrypted event: \(error)")
        }
    }

    // MARK: - Additional Protocol Methods

    public func loadNip05(_ nip05: String) async -> (pubkey: PublicKey, relays: [String])? {
        return queue.sync {
            if let cached = nip05Cache[nip05],
               Date().timeIntervalSince(cached.cachedAt) < 3600
            { // Cache for 1 hour
                return (pubkey: cached.pubkey, relays: cached.relays)
            }
            return nil
        }
    }

    public func saveNip05(_ nip05: String, pubkey: PublicKey, relays: [String]) async {
        queue.async(flags: .barrier) {
            self.nip05Cache[nip05] = (pubkey: pubkey, relays: relays, cachedAt: Date())
        }
    }

    public func updateRelayStatus(_ url: RelayURL, status: NDKRelayConnectionState) async {
        queue.async(flags: .barrier) {
            self.relayStatusCache[url] = status
        }
    }

    public func getRelayStatus(_ url: RelayURL) async -> NDKRelayConnectionState? {
        return queue.sync {
            relayStatusCache[url]
        }
    }

    public func getUnpublishedEvents(for relayUrl: RelayURL) async -> [NDKEvent] {
        let records = FileManager.default.loadAllCodable(
            UnpublishedEventData.self,
            fromDirectory: unpublishedDirectory
        )
        
        return records
            .filter { $0.relays.contains(relayUrl) }
            .map { $0.event }
    }

    public func removeUnpublishedEvent(_ eventId: EventID, from relayUrl: RelayURL) async {
        let unpublishedFile = unpublishedDirectory.appendingPathComponent("\(eventId).json")

        // Read the file to check if we should remove it entirely or just update the relay list
        if var record = try? FileManager.default.loadCodable(UnpublishedEventData.self, from: unpublishedFile) {
            record.relays.removeAll { $0 == relayUrl }

            if record.relays.isEmpty {
                // Remove the file entirely if no relays left
                try? FileManager.default.removeItem(at: unpublishedFile)
            } else {
                // Update the file with remaining relays
                do {
                    try FileManager.default.saveCodable(record, to: unpublishedFile)
                } catch {
                    print("Failed to update unpublished event: \(error)")
                }
            }
        }
    }
}


// MARK: - NDKUserProfile Extensions

extension NDKUserProfile {
    static func fromMetadataEvent(_ event: NDKEvent) -> NDKUserProfile? {
        guard event.kind == EventKind.metadata else { return nil }

        do {
            guard let data = event.content.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }

            return NDKUserProfile(
                name: json["name"] as? String,
                displayName: json["display_name"] as? String,
                about: json["about"] as? String,
                picture: json["picture"] as? String,
                banner: json["banner"] as? String,
                nip05: json["nip05"] as? String,
                lud16: json["lud16"] as? String,
                lud06: json["lud06"] as? String,
                website: json["website"] as? String
            )
        } catch {
            return nil
        }
    }
}
