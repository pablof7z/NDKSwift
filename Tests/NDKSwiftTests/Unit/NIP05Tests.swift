import XCTest
@testable import NDKSwift
import CashuSwift

final class NIP05Tests: XCTestCase {
    var ndk: NDK!
    var cache: TestableCache!
    
    override func setUp() async throws {
        try await super.setUp()
        cache = TestableCache()
        ndk = NDK(cache: cache)
    }
    
    func testNIP05CacheOperations() async throws {
        // Test saving a NIP-05 entry
        let entry = NIP05CacheEntry(
            identifier: "alice@example.com",
            pubkey: "pubkey123",
            status: .verified,
            nip46Relays: ["wss://relay.example.com"],
            claimedAt: Date(),
            verifiedAt: Date(),
            lastCheckAt: Date(),
            errorMessage: nil,
            httpStatusCode: 200
        )
        
        try await cache.saveNIP05Entry(entry)
        
        // Test retrieving the entry
        let retrieved = await cache.getNIP05Entry("alice@example.com")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.pubkey, "pubkey123")
        XCTAssertEqual(retrieved?.status, .verified)
        
        // Test getting by pubkey
        let byPubkey = await cache.getNIP05ForPubkey("pubkey123")
        XCTAssertEqual(byPubkey, "alice@example.com")
    }
    
    func testNIP05SearchFunctionality() async throws {
        // Save multiple entries
        let entries = [
            NIP05CacheEntry(
                identifier: "alice@example.com",
                pubkey: "pubkey1",
                status: .verified,
                nip46Relays: nil,
                claimedAt: Date()
            ),
            NIP05CacheEntry(
                identifier: "bob@example.com",
                pubkey: "pubkey2",
                status: .verified,
                nip46Relays: nil,
                claimedAt: Date()
            ),
            NIP05CacheEntry(
                identifier: "alice@nostr.com",
                pubkey: "pubkey3",
                status: .unverified,
                nip46Relays: nil,
                claimedAt: Date()
            )
        ]
        
        for entry in entries {
            try await cache.saveNIP05Entry(entry)
        }
        
        // Test search
        let aliceResults = await cache.searchNIP05("alice", limit: 10)
        XCTAssertEqual(aliceResults.count, 2)
        XCTAssertTrue(aliceResults.contains(where: { $0.identifier == "alice@example.com" }))
        XCTAssertTrue(aliceResults.contains(where: { $0.identifier == "alice@nostr.com" }))
        
        let exampleResults = await cache.searchNIP05("@example", limit: 10)
        XCTAssertEqual(exampleResults.count, 2)
        XCTAssertTrue(exampleResults.contains(where: { $0.identifier == "alice@example.com" }))
        XCTAssertTrue(exampleResults.contains(where: { $0.identifier == "bob@example.com" }))
    }
    
    func testNIP05VerificationStates() async throws {
        let identifier = "test@example.com"
        let pubkey = "testpubkey"
        
        // Test unverified state
        let unverified = NIP05CacheEntry(
            identifier: identifier,
            pubkey: pubkey,
            status: .unverified,
            nip46Relays: nil,
            claimedAt: Date()
        )
        try await cache.saveNIP05Entry(unverified)
        
        let needsVerification = await cache.needsNIP05Verification(identifier, maxAge: 86400)
        XCTAssertTrue(needsVerification, "Unverified entries should need verification")
        
        // Update to verified
        var verified = unverified
        verified.status = .verified
        verified.verifiedAt = Date()
        verified.lastCheckAt = Date()
        try await cache.saveNIP05Entry(verified)
        
        let needsVerificationAfter = await cache.needsNIP05Verification(identifier, maxAge: 86400)
        XCTAssertFalse(needsVerificationAfter, "Recently verified entries should not need verification")
        
        // Test invalidation
        try await cache.invalidateNIP05(identifier, actualPubkey: "differentpubkey")
        let invalidated = await cache.getNIP05Entry(identifier)
        XCTAssertEqual(invalidated?.status, .invalid)
        
        // The correct pubkey should now be saved
        let correctPubkey = await cache.getNIP05ForPubkey("differentpubkey")
        XCTAssertEqual(correctPubkey, identifier)
    }
    
    func testRateLimiting() async throws {
        let domain = "example.com"
        
        // First check should be allowed
        let canCheck1 = await cache.canCheckNIP05Domain(domain)
        XCTAssertTrue(canCheck1)
        
        // Record the check
        try await cache.recordNIP05DomainCheck(domain)
        
        // Immediate second check should be rate limited
        let canCheck2 = await cache.canCheckNIP05Domain(domain)
        XCTAssertFalse(canCheck2)
    }
}

// Simple testable cache implementation
actor TestableCache: NDKCache {
    private var events: [String: NDKEvent] = [:]
    private var nip05Entries: [String: NIP05CacheEntry] = [:]
    private var nip05ByPubkey: [String: String] = [:]
    private var domainChecks: [String: Date] = [:]
    
    func saveEvent(_ event: NDKEvent) async throws {
        events[event.id] = event
    }
    
    func getEvent(id: String) async -> NDKEvent? {
        return events[id]
    }
    
    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        return Array(events.values).filter { event in
            filter.matches(event: event)
        }
    }
    
    func deleteEvent(id: String) async throws {
        events.removeValue(forKey: id)
    }
    
    // Profile operations are now handled through event storage
    
    func clear() async throws {
        events.removeAll()
        nip05Entries.removeAll()
        nip05ByPubkey.removeAll()
        domainChecks.removeAll()
    }
    
    func confirmEvent(eventId: String, onRelay relay: String) async throws {
        // No-op for testing
    }
    
    func processEvent(_ event: NDKEvent, from relay: String, subscriptionId: String) async throws {
        try await saveEvent(event)
    }
    
    func getRelayPreferences(
        pubkey: String
    ) async -> (writeRelays: [String]?, readRelays: [String]?, fetchedAt: Date, expiresAt: Date, checkedRelays: Set<String>?)? {
        return nil
    }
    
    func saveRelayPreferences(pubkey: String, writeRelays: [String]?, readRelays: [String]?, fetchedAt: Date, expiresAt: Date, checkedRelays: Set<String>?) async throws {
        // No-op for testing
    }
    
    // NIP-05 implementations
    func saveNIP05Entry(_ entry: NIP05CacheEntry) async throws {
        nip05Entries[entry.identifier] = entry
        if entry.status == .verified {
            nip05ByPubkey[entry.pubkey] = entry.identifier
        }
    }
    
    func getNIP05Entry(_ identifier: String) async -> NIP05CacheEntry? {
        return nip05Entries[identifier]
    }
    
    func getNIP05ForPubkey(_ pubkey: String) async -> String? {
        return nip05ByPubkey[pubkey]
    }
    
    func searchNIP05(_ query: String, limit: Int) async -> [NIP05CacheEntry] {
        return Array(nip05Entries.values.filter { entry in
            entry.identifier.lowercased().contains(query.lowercased())
        }.prefix(limit))
    }
    
    func needsNIP05Verification(_ identifier: String, maxAge: TimeInterval) async -> Bool {
        guard let entry = nip05Entries[identifier] else { return true }
        
        switch entry.status {
        case .unverified:
            return true
        case .verified:
            guard let lastCheck = entry.lastCheckAt else { return true }
            return Date().timeIntervalSince(lastCheck) > maxAge
        case .invalid, .expired, .failed:
            return false
        }
    }
    
    func invalidateNIP05(_ identifier: String, actualPubkey: String?) async throws {
        if var entry = nip05Entries[identifier] {
            entry.status = .invalid
            nip05Entries[identifier] = entry
            nip05ByPubkey.removeValue(forKey: entry.pubkey)
        }
        
        if let actualPubkey = actualPubkey {
            let newEntry = NIP05CacheEntry(
                identifier: identifier,
                pubkey: actualPubkey,
                status: .verified,
                nip46Relays: nil,
                claimedAt: Date(),
                verifiedAt: Date(),
                lastCheckAt: Date()
            )
            try await saveNIP05Entry(newEntry)
        }
    }
    
    func canCheckNIP05Domain(_ domain: String) async -> Bool {
        guard let lastCheck = domainChecks[domain] else { return true }
        return Date().timeIntervalSince(lastCheck) > 60 // 1 minute rate limit
    }
    
    func recordNIP05DomainCheck(_ domain: String) async throws {
        domainChecks[domain] = Date()
    }
    
    // MARK: - Missing NDKCache Protocol Requirements
    
    func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        // No-op for testing
    }
    
    func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        return nil
    }
    
    func getUnpublishedEvents(maxAge: TimeInterval, limit: Int?) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        return []
    }
    
    func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String? {
        return nil
    }
    
    func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async {
        // No-op for testing
    }
    
    func clearDecryptedContent() async {
        // No-op for testing
    }
    
    func clearDecryptedContent(for viewerPubkey: String) async {
        // No-op for testing
    }
    
    func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        // No-op for testing
    }
    
    func getMintInfo(url: String) async -> NDKMintInfo? {
        return nil
    }
    
    func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool {
        return true
    }
    
    func invalidateMintCache(url: String) async throws {
        // No-op for testing
    }
    
    func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws {
        // No-op for testing
    }
    
    func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws {
        // No-op for testing
    }
    
    func getKeyset(id: String) async -> CashuSwift.Keyset? {
        return nil
    }
    
    func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        return []
    }
    
    func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset] {
        return []
    }
    
    func areKeysetsStale(mintUrl: String, maxAge: TimeInterval) async -> Bool {
        return true
    }
    
    func getEventsByTimeRange(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [NDKEvent] {
        return []
    }
    
    func getEventIdsWithTimestamps(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [(id: String, timestamp: Timestamp)] {
        return []
    }
    
    func hasEvents(ids: [String]) async -> [String: Bool] {
        return ids.reduce(into: [:]) { result, id in
            result[id] = events[id] != nil
        }
    }
    
    func observeEvents(matching filter: NDKFilter, includeExisting: Bool) async -> AsyncThrowingStream<[NDKEvent], Error> {
        // Return an empty stream for testing
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
    
    func getRelaySources(eventId: String) async -> Set<String> {
        return []
    }
    
    func getLastFetchTime(for filter: NDKFilter) async -> Date? {
        return nil
    }
    
    func recordFetchTime(for filter: NDKFilter, timestamp: Date) async {
        // No-op for testing
    }
    
    func saveNIP05Claim(identifier: String, pubkey: String, claimedAt: Date) async throws {
        let entry = NIP05CacheEntry(
            identifier: identifier,
            pubkey: pubkey,
            status: .unverified,
            nip46Relays: nil,
            claimedAt: claimedAt
        )
        try await saveNIP05Entry(entry)
    }
    
    func saveNIP05Resolution(_ entry: NIP05CacheEntry) async throws {
        try await saveNIP05Entry(entry)
    }
    
    func getNIP05Entries(pubkey: String) async -> [NIP05CacheEntry] {
        return nip05Entries.values.filter { $0.pubkey == pubkey }
    }
    
    func getUnverifiedNIP05s(limit: Int) async -> [NIP05CacheEntry] {
        return Array(nip05Entries.values.filter { $0.status == .unverified }.prefix(limit))
    }
    
    func canVerifyDomain(_ domain: String) async -> Bool {
        return await canCheckNIP05Domain(domain)
    }
    
    func recordDomainVerificationAttempt(_ domain: String) async {
        try? await recordNIP05DomainCheck(domain)
    }
    
    func saveProfileMetadata(pubkey: String, metadata: [String: Any], updatedAt: Timestamp, eventId: String) async throws {
        // No-op for testing - profiles are stored as events
    }
    
    func getProfileMetadata(pubkey: String) async -> (metadata: [String: Any], updatedAt: Timestamp, eventId: String)? {
        return nil // No-op for testing
    }
    
    func getMultipleProfileMetadata(pubkeys: [String]) async -> [String: (metadata: [String: Any], updatedAt: Timestamp, eventId: String)] {
        return [:] // No-op for testing
    }
    
    func observeProfile(pubkey: String, includeExisting: Bool) async -> AsyncThrowingStream<NDKUserMetadata?, Error> {
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
