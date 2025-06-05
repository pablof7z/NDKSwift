import Foundation

/// Cache for storing already verified event signatures
/// This prevents re-verification of the same event across different relays
actor NDKSignatureVerificationCache {
    /// Cache of verified signatures: eventId -> signature
    private var verifiedSignatures: [EventID: Signature] = [:]

    /// Maximum number of signatures to cache
    private let maxCacheSize: Int

    /// Order of insertion for LRU eviction
    private var insertionOrder: [EventID] = []

    public init(maxCacheSize: Int = 10000) {
        self.maxCacheSize = maxCacheSize
    }

    /// Check if an event signature has been verified
    /// - Parameters:
    ///   - eventId: The event ID to check
    ///   - signature: The signature to verify against
    /// - Returns: true if the signature matches the cached verified signature
    public func isVerified(eventId: EventID, signature: Signature) -> Bool {
        guard let cachedSignature = verifiedSignatures[eventId] else {
            return false
        }
        return cachedSignature == signature
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
    public func getStats() -> (cacheSize: Int, hitRate: Double) {
        let cacheSize = verifiedSignatures.count
        // Hit rate would need to be tracked with hit/miss counters
        return (cacheSize, 0.0)
    }
}
