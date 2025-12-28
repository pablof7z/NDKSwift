/// Cache for storing already verified event signatures
/// This prevents re-verification of the same event across different relays
actor NDKSignatureVerificationCache {
    /// Cache of verified signatures: eventId -> signature
    private var verifiedSignatures: [EventID: Signature] = [:]

    /// Maximum number of signatures to cache
    private let maxCacheSize: Int

    /// Order of insertion for LRU eviction
    private var insertionOrder: [EventID] = []

    /// Hit/miss tracking for statistics
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0

    public init(maxCacheSize: Int = 10000) {
        self.maxCacheSize = maxCacheSize
    }

    /// Fast check if an event has been verified (regardless of signature)
    /// - Parameter eventId: The event ID to check
    /// - Returns: true if the event has been verified previously
    public func hasVerifiedEvent(eventId: EventID) -> Bool {
        return verifiedSignatures[eventId] != nil
    }

    /// Check if an event signature has been verified
    /// - Parameters:
    ///   - eventId: The event ID to check
    ///   - signature: The signature to verify against
    /// - Returns: true if the signature matches the cached verified signature
    public func isVerified(eventId: EventID, signature: Signature) -> Bool {
        guard let cachedSignature = verifiedSignatures[eventId] else {
            cacheMisses += 1
            return false
        }
        if cachedSignature == signature {
            cacheHits += 1
            return true
        } else {
            cacheMisses += 1
            return false
        }
    }

    /// Add a verified signature to the cache
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - signature: The verified signature
    public func addVerifiedSignature(eventId: EventID, signature: Signature) {
        // Check if already cached
        if verifiedSignatures[eventId] != nil {
            // Move to end of insertion order
            insertionOrder.removeAll { $0 == eventId }
            insertionOrder.append(eventId)
            return
        }

        // Add new signature
        verifiedSignatures[eventId] = signature
        insertionOrder.append(eventId)

        // Evict oldest if cache is full
        if insertionOrder.count > maxCacheSize {
            if let oldestEventId = insertionOrder.first {
                insertionOrder.removeFirst()
                verifiedSignatures.removeValue(forKey: oldestEventId)
            }
        }
    }

    /// Clear the entire cache
    public func clear() {
        verifiedSignatures.removeAll()
        insertionOrder.removeAll()
    }

    /// Get cache statistics
    public func getStats() -> (cacheSize: Int, hitRate: Double, hits: Int, misses: Int) {
        let cacheSize = verifiedSignatures.count
        let totalAccesses = cacheHits + cacheMisses
        let hitRate = totalAccesses > 0 ? Double(cacheHits) / Double(totalAccesses) : 0.0
        return (cacheSize, hitRate, cacheHits, cacheMisses)
    }
}
