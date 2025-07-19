import Foundation
import CryptoKit

/// Accumulator for computing incremental hashes over sorted sets of items
/// This is the core data structure for Negentropy's fingerprinting
public struct NegentropyAccumulator {
    private var hash: SHA256
    private var itemCount: Int = 0
    
    public init() {
        self.hash = SHA256()
    }
    
    /// Add an item to the accumulator
    /// Items must be added in sorted order
    public mutating func add(_ item: NegentropyItem) {
        // Add timestamp (8 bytes, little-endian)
        var timestamp = item.timestamp.littleEndian
        withUnsafeBytes(of: &timestamp) { bytes in
            hash.update(data: Data(bytes))
        }
        
        // Add ID (32 bytes)
        hash.update(data: item.id)
        
        itemCount += 1
    }
    
    /// Add multiple items (must be sorted)
    public mutating func addAll<S: Sequence>(_ items: S) where S.Element == NegentropyItem {
        for item in items {
            add(item)
        }
    }
    
    /// Get the current fingerprint
    public func fingerprint() -> Data {
        // Create a copy to avoid mutating the accumulator
        let hashCopy = hash
        return Data(hashCopy.finalize())
    }
    
    /// Get the number of items accumulated
    public var count: Int {
        return itemCount
    }
    
    /// Create accumulator from a sorted array of items
    public static func from(_ items: [NegentropyItem]) -> NegentropyAccumulator {
        var accumulator = NegentropyAccumulator()
        accumulator.addAll(items)
        return accumulator
    }
}

/// Range of items with bounds and fingerprint
public struct NegentropyRange {
    /// Lower bound (inclusive), nil means unbounded
    public let lower: NegentropyItem?
    
    /// Upper bound (exclusive), nil means unbounded  
    public let upper: NegentropyItem?
    
    /// Fingerprint of all items in this range
    public let fingerprint: Data
    
    /// Number of items in this range
    public let count: Int
    
    public init(lower: NegentropyItem?, upper: NegentropyItem?, fingerprint: Data, count: Int) {
        self.lower = lower
        self.upper = upper
        self.fingerprint = fingerprint
        self.count = count
    }
    
    /// Check if an item falls within this range
    public func contains(_ item: NegentropyItem) -> Bool {
        if let lower = lower, item < lower {
            return false
        }
        if let upper = upper, item >= upper {
            return false
        }
        return true
    }
    
    /// Split this range at a midpoint
    public func split(at midpoint: NegentropyItem) -> (NegentropyRange, NegentropyRange) {
        let lowerRange = NegentropyRange(
            lower: lower,
            upper: midpoint,
            fingerprint: Data(), // Will be computed by the storage
            count: 0
        )
        
        let upperRange = NegentropyRange(
            lower: midpoint,
            upper: upper,
            fingerprint: Data(), // Will be computed by the storage
            count: 0
        )
        
        return (lowerRange, upperRange)
    }
}

/// Storage protocol for Negentropy items
public protocol NegentropyStorage {
    /// Get all items in a range
    func getItems(in range: NegentropyRange) async throws -> [NegentropyItem]
    
    /// Get fingerprint and count for a range
    func getRangeInfo(_ range: NegentropyRange) async throws -> (fingerprint: Data, count: Int)
    
    /// Add new items to storage
    func addItems(_ items: [NegentropyItem]) async throws
    
    /// Remove items from storage
    func removeItems(_ ids: [Data]) async throws
}

/// Extension to compute fingerprints for arrays of items
extension Array where Element == NegentropyItem {
    /// Compute the fingerprint for this array of items
    /// Items must be sorted
    public func fingerprint() -> Data {
        return NegentropyAccumulator.from(self).fingerprint()
    }
}