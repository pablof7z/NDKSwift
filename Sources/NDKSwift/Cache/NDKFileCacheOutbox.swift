import Foundation

/// Extension to NDKFileCache for outbox support
extension NDKFileCache: NDKOutboxCacheAdapter {
    
    // MARK: - Unpublished Event Management
    
    public func storeUnpublishedEvent(
        _ event: NDKEvent,
        targetRelays: Set<String>,
        publishConfig: OutboxPublishConfig?
    ) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                let record = UnpublishedEventRecord(
                    event: event,
                    targetRelays: targetRelays,
                    publishConfig: publishConfig.map { StoredPublishConfig(from: $0) }
                )
                
                guard let eventId = event.id else {
                    continuation.resume()
                    return
                }
                
                let filePath = self.outboxDirectory
                    .appendingPathComponent("\(eventId).json")
                
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(record)
                    try data.write(to: filePath)
                    
                    // Update index
                    self.unpublishedEventIndex[eventId] = record
                } catch {
                    print("Failed to store unpublished event: \(error)")
                }
                
                continuation.resume()
            }
        }
    }
    
    public func getAllUnpublishedEvents() async -> [UnpublishedEventRecord] {
        await withCheckedContinuation { continuation in
            queue.async {
                let records = Array(self.unpublishedEventIndex.values)
                continuation.resume(returning: records)
            }
        }
    }
    
    public func updateUnpublishedEventStatus(
        eventId: String,
        relayURL: String,
        status: RelayPublishStatus
    ) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                guard var record = self.unpublishedEventIndex[eventId] else {
                    continuation.resume()
                    return
                }
                
                // Create mutable copy with updated status
                var updatedStatuses = record.relayStatuses
                updatedStatuses[relayURL] = status
                
                let updatedRecord = UnpublishedEventRecord(
                    event: record.event,
                    targetRelays: record.targetRelays,
                    relayStatuses: updatedStatuses,
                    createdAt: record.createdAt,
                    lastAttemptAt: Date(),
                    publishConfig: record.publishConfig,
                    overallStatus: self.calculateOverallStatus(
                        statuses: updatedStatuses,
                        config: record.publishConfig
                    )
                )
                
                // Save to file
                let filePath = self.outboxDirectory
                    .appendingPathComponent("\(eventId).json")
                
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(updatedRecord)
                    try data.write(to: filePath)
                    
                    // Update index
                    self.unpublishedEventIndex[eventId] = updatedRecord
                } catch {
                    print("Failed to update unpublished event status: \(error)")
                }
                
                continuation.resume()
            }
        }
    }
    
    public func markEventAsPublished(eventId: String) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                // Remove from unpublished index
                self.unpublishedEventIndex.removeValue(forKey: eventId)
                
                // Delete file
                let filePath = self.outboxDirectory
                    .appendingPathComponent("\(eventId).json")
                
                try? FileManager.default.removeItem(at: filePath)
                
                continuation.resume()
            }
        }
    }
    
    public func getEventsForRetry(olderThan interval: TimeInterval) async -> [UnpublishedEventRecord] {
        await withCheckedContinuation { continuation in
            queue.async {
                let records = self.unpublishedEventIndex.values.filter { record in
                    record.shouldRetry(after: interval)
                }
                continuation.resume(returning: Array(records))
            }
        }
    }
    
    public func cleanupPublishedEvents(olderThan age: TimeInterval) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                let cutoffDate = Date().addingTimeInterval(-age)
                
                let toRemove = self.unpublishedEventIndex.filter { (_, record) in
                    record.overallStatus == .succeeded &&
                    record.lastAttemptAt ?? record.createdAt < cutoffDate
                }
                
                for (eventId, _) in toRemove {
                    self.unpublishedEventIndex.removeValue(forKey: eventId)
                    
                    let filePath = self.outboxDirectory
                        .appendingPathComponent("\(eventId).json")
                    try? FileManager.default.removeItem(at: filePath)
                }
                
                continuation.resume()
            }
        }
    }
    
    // MARK: - Outbox Relay Information
    
    public func storeOutboxItem(_ item: NDKOutboxItem) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                let filePath = self.outboxRelayDirectory
                    .appendingPathComponent("\(item.pubkey).json")
                
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(item)
                    try data.write(to: filePath)
                    
                    // Update index
                    self.outboxItemIndex[item.pubkey] = item
                } catch {
                    print("Failed to store outbox item: \(error)")
                }
                
                continuation.resume()
            }
        }
    }
    
    public func getOutboxItem(for pubkey: String) async -> NDKOutboxItem? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.outboxItemIndex[pubkey])
            }
        }
    }
    
    public func updateRelayHealth(url: String, health: RelayHealthMetrics) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.relayHealthCache[url] = health
                
                // Persist to file
                let fileName = url.replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: ":", with: "_")
                let filePath = self.relayHealthDirectory
                    .appendingPathComponent("\(fileName).json")
                
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(health)
                    try data.write(to: filePath)
                } catch {
                    print("Failed to store relay health: \(error)")
                }
                
                continuation.resume()
            }
        }
    }
    
    public func getRelayHealth(url: String) async -> RelayHealthMetrics? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.relayHealthCache[url])
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func calculateOverallStatus(
        statuses: [String: RelayPublishStatus],
        config: StoredPublishConfig?
    ) -> PublishStatus {
        let successCount = statuses.values.filter { $0 == .succeeded }.count
        let failureCount = statuses.values.filter {
            if case .failed = $0 { return true }
            return false
        }.count
        let pendingCount = statuses.values.filter {
            $0 == .pending || $0 == .inProgress
        }.count
        
        let minRequired = config?.minSuccessfulRelays ?? 1
        
        if successCount >= minRequired {
            return .succeeded
        } else if pendingCount == 0 && successCount < minRequired {
            return .failed
        } else if pendingCount > 0 {
            return .inProgress
        } else {
            return .pending
        }
    }
}

// MARK: - Additional Properties for Outbox Support

extension NDKFileCache {
    // Additional directories for outbox
    var outboxDirectory: URL {
        cacheDirectory.appendingPathComponent("outbox")
    }
    
    var outboxRelayDirectory: URL {
        cacheDirectory.appendingPathComponent("outbox_relays")
    }
    
    var relayHealthDirectory: URL {
        cacheDirectory.appendingPathComponent("relay_health")
    }
}

// MARK: - Initialize Outbox Directories

extension NDKFileCache {
    func initializeOutboxDirectories() throws {
        try FileManager.default.createDirectory(
            at: outboxDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outboxRelayDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: relayHealthDirectory,
            withIntermediateDirectories: true
        )
        
        // Load existing outbox data
        loadOutboxData()
    }
    
    private func loadOutboxData() {
        // Load unpublished events
        if let files = try? FileManager.default.contentsOfDirectory(
            at: outboxDirectory,
            includingPropertiesForKeys: nil
        ) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let record = try? decoder.decode(UnpublishedEventRecord.self, from: data),
                   let eventId = record.event.id {
                    unpublishedEventIndex[eventId] = record
                }
            }
        }
        
        // Load outbox items
        if let files = try? FileManager.default.contentsOfDirectory(
            at: outboxRelayDirectory,
            includingPropertiesForKeys: nil
        ) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let item = try? decoder.decode(NDKOutboxItem.self, from: data) {
                    outboxItemIndex[item.pubkey] = item
                }
            }
        }
        
        // Load relay health
        if let files = try? FileManager.default.contentsOfDirectory(
            at: relayHealthDirectory,
            includingPropertiesForKeys: nil
        ) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let health = try? decoder.decode(RelayHealthMetrics.self, from: data) {
                    relayHealthCache[health.url] = health
                }
            }
        }
    }
}