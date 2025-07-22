import Foundation

/// Manages NIP-05 resolution with caching, deduplication, and performance optimizations
public actor NIP05Manager {
    private let ndk: NDK
    private let cache: NDKCache
    private let memoryCache: LRUCache<String, NIP05CacheEntry>
    private let domainRateLimiter: LRUCache<String, Date>
    
    /// In-flight requests to prevent duplicate network calls
    private var inFlightRequests: [String: Task<NDKUser?, Error>] = [:]
    
    /// Default TTL for cache entries (24 hours)
    public static let defaultTTL: TimeInterval = TimeConstants.nip05CacheTTL
    
    /// Rate limit per domain (10 requests per hour)
    private static let domainRateLimit: TimeInterval = NetworkConstants.nip05RateLimit
    
    /// Maximum response size to prevent DoS (1MB)
    private static let maxResponseSize = NetworkConstants.maxNIP05ResponseSize
    
    public init(ndk: NDK) {
        self.ndk = ndk
        self.cache = ndk.cache
        self.memoryCache = LRUCache(capacity: NetworkConstants.nip05CacheCapacity, defaultTTL: TimeConstants.hour)
        self.domainRateLimiter = LRUCache(capacity: NetworkConstants.domainRateLimiterCapacity, defaultTTL: TimeConstants.hour)
    }
    
    // MARK: - Public API
    
    /// Resolve a NIP-05 identifier to a user
    /// - Parameters:
    ///   - identifier: The NIP-05 identifier (e.g., "alice@example.com")
    ///   - forceVerify: If true, bypasses cache and forces network verification
    ///   - maxAge: Maximum age of cached data to consider fresh (default: 24 hours)
    /// - Returns: The NDKUser if found and verified, nil otherwise
    public func resolveUser(
        identifier: String,
        forceVerify: Bool = false,
        maxAge: TimeInterval = defaultTTL
    ) async throws -> NDKUser? {
        let normalizedIdentifier = identifier.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if there's already an in-flight request
        if let existingTask = inFlightRequests[normalizedIdentifier] {
            NDKLogger.log(.debug, category: .general, "🔄 NIP-05: Using existing in-flight request for \(normalizedIdentifier)")
            return try await existingTask.value
        }
        
        // Create new task for this request
        let task = Task<NDKUser?, Error> {
            try await performResolveUser(
                identifier: normalizedIdentifier,
                forceVerify: forceVerify,
                maxAge: maxAge
            )
        }
        
        // Store the task to prevent duplicate requests
        inFlightRequests[normalizedIdentifier] = task
        
        // Clean up the task when done
        defer {
            inFlightRequests.removeValue(forKey: normalizedIdentifier)
        }
        
        return try await task.value
    }
    
    /// Search for NIP-05 identifiers by prefix
    /// - Parameters:
    ///   - query: The search query
    ///   - limit: Maximum number of results
    /// - Returns: Array of cache entries matching the query
    public func search(
        _ query: String,
        limit: Int = 10
    ) async -> [NIP05CacheEntry] {
        let normalizedQuery = query.lowercased()
        
        // First check memory cache for exact matches or prefixes
        let memoryResults = await memoryCache.allItems()
            .compactMap { _, entry in entry }
            .filter { $0.identifier.lowercased().hasPrefix(normalizedQuery) }
            .prefix(limit)
        
        if memoryResults.count >= limit {
            return Array(memoryResults)
        }
        
        // Fall back to database for more results
        let dbResults = await cache.searchNIP05(normalizedQuery, limit: limit - memoryResults.count)
        
        // Combine results, removing duplicates
        var combined = Array(memoryResults)
        let existingIdentifiers = Set(combined.map { $0.identifier })
        combined.append(contentsOf: dbResults.filter { !existingIdentifiers.contains($0.identifier) })
        
        return Array(combined.prefix(limit))
    }
    
    /// Verify a NIP-05 identifier for a specific user
    /// - Parameters:
    ///   - identifier: The NIP-05 identifier
    ///   - expectedPubkey: The expected public key
    ///   - maxAge: Maximum age before re-verification is needed
    /// - Returns: True if verified and matches the expected pubkey
    public func verify(
        identifier: String,
        expectedPubkey: String,
        maxAge: TimeInterval = defaultTTL
    ) async throws -> Bool {
        guard let user = try await resolveUser(identifier: identifier, maxAge: maxAge) else {
            return false
        }
        return user.pubkey == expectedPubkey
    }
    
    /// Process a metadata event to extract NIP-05 identifier
    /// - Parameters:
    ///   - event: The kind:0 metadata event
    ///   - profile: The parsed user profile
    public func processMetadataEvent(
        _ event: NDKEvent,
        profile: NDKUserProfile
    ) async {
        guard let nip05 = profile.nip05,
              !nip05.isEmpty else { return }
        
        let normalizedNip05 = nip05.lowercased()
        
        // Check if we already have this in memory cache
        if let existing = await memoryCache.get(normalizedNip05),
           existing.pubkey == event.pubkey,
           existing.status == .verified {
            return
        }
        
        // Create unverified entry for proactive caching
        let entry = NIP05CacheEntry(
            identifier: normalizedNip05,
            pubkey: event.pubkey,
            status: .unverified,
            nip46Relays: nil,
            claimedAt: Date()
        )
        
        // Save to both caches
        await memoryCache.set(normalizedNip05, value: entry)
        try? await cache.saveNIP05Claim(normalizedNip05, pubkey: event.pubkey, retrievedAt: Date())
        
        NDKLogger.log(.debug, category: .general, "📝 NIP-05: Cached unverified entry for \(normalizedNip05)")
    }
    
    /// Batch verify stale NIP-05 entries
    /// - Parameter limit: Maximum number of entries to verify
    public func batchVerifyStaleEntries(limit: Int = 10) async {
        // Get unverified entries from database
        let unverifiedEntries = await cache.searchNIP05("", limit: limit)
            .filter { $0.status == .unverified }
            .prefix(limit)
        
        await withTaskGroup(of: Void.self) { group in
            for entry in unverifiedEntries {
                group.addTask {
                    do {
                        _ = try await self.resolveUser(
                            identifier: entry.identifier,
                            forceVerify: true
                        )
                    } catch {
                        NDKLogger.log(.error, category: .general, "❌ NIP-05: Batch verification failed for \(entry.identifier): \(error)")
                    }
                }
            }
        }
    }
    
    /// Clear cache entries
    public func clearCache(onlyInvalid: Bool = false) async throws {
        if onlyInvalid {
            // Clear only invalid entries from memory
            let allItems = await memoryCache.allItems()
            for (key, entry) in allItems {
                if entry.status == .invalid || entry.status == .failed {
                    await memoryCache.delete(key)
                }
            }
        } else {
            // Clear all entries
            await memoryCache.clear()
        }
        
        // Note: Database clearing should be done through NDKCache protocol
    }
    
    /// Get cache statistics
    public func getCacheStatistics() async -> NIP05CacheStatistics {
        let memoryItems = await memoryCache.allItems()
        let verified = memoryItems.values.filter { $0.status == .verified }.count
        let unverified = memoryItems.values.filter { $0.status == .unverified }.count
        let invalid = memoryItems.values.filter { $0.status == .invalid }.count
        let failed = memoryItems.values.filter { $0.status == .failed }.count
        
        return NIP05CacheStatistics(
            totalEntries: memoryItems.count,
            verifiedEntries: verified,
            unverifiedEntries: unverified,
            invalidEntries: invalid,
            failedEntries: failed,
            memoryHitRate: await memoryCache.getHitRate()
        )
    }
    
    // MARK: - Private Implementation
    
    private func performResolveUser(
        identifier: String,
        forceVerify: Bool,
        maxAge: TimeInterval
    ) async throws -> NDKUser? {
        // Step 1: Check memory cache
        if !forceVerify {
            if let cached = await checkMemoryCache(identifier: identifier, maxAge: maxAge) {
                if cached.status == .verified, let user = cached.toUser(ndk: ndk) {
                    NDKLogger.log(.debug, category: .general, "✅ NIP-05: Memory cache hit for \(identifier)")
                    return user
                } else if cached.status == .invalid || cached.status == .failed {
                    NDKLogger.log(.debug, category: .general, "❌ NIP-05: Cached failure for \(identifier)")
                    return nil
                }
            }
        }
        
        // Step 2: Check database cache
        if !forceVerify {
            if let cached = await checkDatabaseCache(identifier: identifier, maxAge: maxAge) {
                // Update memory cache
                await memoryCache.set(identifier, value: cached)
                
                if cached.status == .verified, let user = cached.toUser(ndk: ndk) {
                    NDKLogger.log(.debug, category: .general, "✅ NIP-05: Database cache hit for \(identifier)")
                    return user
                } else if cached.status == .invalid || cached.status == .failed {
                    NDKLogger.log(.debug, category: .general, "❌ NIP-05: Cached failure for \(identifier)")
                    return nil
                }
            }
        }
        
        // Step 3: Perform network verification
        return try await performNetworkVerification(identifier: identifier)
    }
    
    private func checkMemoryCache(
        identifier: String,
        maxAge: TimeInterval
    ) async -> NIP05CacheEntry? {
        guard let cached = await memoryCache.get(identifier) else { return nil }
        
        // Check if needs verification
        if await cache.needsNIP05Verification(identifier, maxAge: maxAge) {
            return nil
        }
        
        return cached
    }
    
    private func checkDatabaseCache(
        identifier: String,
        maxAge: TimeInterval
    ) async -> NIP05CacheEntry? {
        guard let cached = await cache.getNIP05Entry(identifier) else { return nil }
        
        // Check if needs verification
        if await cache.needsNIP05Verification(identifier, maxAge: maxAge) {
            return nil
        }
        
        return cached
    }
    
    private func performNetworkVerification(
        identifier: String
    ) async throws -> NDKUser? {
        // Parse identifier
        let parts = identifier.split(separator: "@")
        guard parts.count == 2 else {
            throw NDKError.invalidDataFormat("NIP-05 identifier", details: "Expected format: name@domain")
        }
        
        let name = String(parts[0])
        let domain = String(parts[1])
        
        // Check rate limiting
        let canCheck = await cache.canVerifyDomain(domain)
        if !canCheck {
            throw NDKError.rateLimited(message: "Too many requests to \(domain)")
        }
        
        // Record domain check
        await cache.recordDomainVerificationAttempt(domain)
        
        // Construct URL
        let normalizedName = name == "_" ? "" : name
        let urlString = "https://\(domain)/.well-known/nostr.json?name=\(normalizedName)"
        guard let url = URL(string: urlString) else {
            throw NDKError.invalidDataFormat("NIP-05 identifier", details: "Expected format: name@domain")
        }
        
        NDKLogger.log(.info, category: .general, "🌐 NIP-05: Fetching \(urlString)")
        
        // Perform network request
        var request = URLRequest(url: url)
        request.timeoutInterval = NetworkConstants.timeoutRelayInfo
        request.setValue("NDKSwift", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response size
        guard data.count <= Self.maxResponseSize else {
            throw NDKError.invalidResponse(from: "NIP-05 response too large")
        }
        
        // Check HTTP status
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        guard statusCode == 200 else {
            // Cache failed attempt
            let failedEntry = NIP05CacheEntry(
                identifier: identifier,
                pubkey: "",
                status: .failed,
                nip46Relays: nil,
                claimedAt: Date(),
                verifiedAt: nil,
                lastCheckAt: Date(),
                errorMessage: "HTTP \(statusCode)",
                httpStatusCode: statusCode
            )
            await memoryCache.set(identifier, value: failedEntry)
            try? await cache.saveNIP05Resolution(failedEntry)
            
            throw NDKError.serverError(relay: domain, code: statusCode, message: "HTTP \(statusCode)")
        }
        
        // Parse JSON response
        guard let json = try? JSONCoding.parseDictionary(from: data),
              let names = json["names"] as? [String: String],
              let pubkey = names[name] else {
            // Cache invalid format
            let invalidEntry = NIP05CacheEntry(
                identifier: identifier,
                pubkey: "",
                status: .invalid,
                nip46Relays: nil,
                claimedAt: Date(),
                verifiedAt: nil,
                lastCheckAt: Date(),
                errorMessage: "Invalid JSON format"
            )
            await memoryCache.set(identifier, value: invalidEntry)
            try? await cache.saveNIP05Resolution(invalidEntry)
            
            throw NDKError.invalidResponse(from: "NIP-05 name not found")
        }
        
        // Extract NIP-46 relays if present
        let nip46Relays = (json["nip46"] as? [String: [String]])?[pubkey]
        
        // Create verified entry
        let verifiedEntry = NIP05CacheEntry(
            identifier: identifier,
            pubkey: pubkey,
            status: .verified,
            nip46Relays: nip46Relays,
            claimedAt: Date(),
            verifiedAt: Date(),
            lastCheckAt: Date(),
            httpStatusCode: 200
        )
        
        // Save to both caches
        await memoryCache.set(identifier, value: verifiedEntry)
        try? await cache.saveNIP05Resolution(verifiedEntry)
        
        NDKLogger.log(.info, category: .general, "✅ NIP-05: Verified \(identifier) -> \(pubkey)")
        
        // Create and return user
        let user = NDKUser(pubkey: pubkey)
        user.ndk = ndk
        return user
    }
}

// MARK: - Supporting Types

public struct NIP05CacheStatistics {
    public let totalEntries: Int
    public let verifiedEntries: Int
    public let unverifiedEntries: Int
    public let invalidEntries: Int
    public let failedEntries: Int
    public let memoryHitRate: Double
}

extension NIP05CacheEntry {
    func toUser(ndk: NDK) -> NDKUser? {
        guard status == .verified, !pubkey.isEmpty else { return nil }
        let user = NDKUser(pubkey: pubkey)
        user.ndk = ndk
        return user
    }
}

// MARK: - Additional Error Helpers

extension NDKError {
    static let invalidNIP05Format = { (identifier: String) in 
        NDKError.invalidDataFormat("NIP-05 identifier", details: "Invalid format: \(identifier)")
    }
    static let invalidNIP05Response = NDKError.invalidResponse(from: "NIP-05")
}