import Foundation

/// Represents an item in the Negentropy set reconciliation protocol
public struct NegentropyItem: Comparable, Hashable {
    /// 32-byte identifier (typically event ID for Nostr)
    public let id: Data
    
    /// Timestamp for ordering (unix timestamp)
    public let timestamp: UInt64
    
    public init(id: Data, timestamp: UInt64) {
        precondition(id.count == 32, "Negentropy item ID must be exactly 32 bytes")
        self.id = id
        self.timestamp = timestamp
    }
    
    /// Initialize from hex string ID
    public init(hexId: String, timestamp: UInt64) throws {
        guard let idData = hexId.hexDecoded(), idData.count == 32 else {
            throw NegentropyError.invalidItemId
        }
        self.id = idData
        self.timestamp = timestamp
    }
    
    /// Initialize from Nostr event
    public init(event: NDKEvent) throws {
        guard let idData = event.id.hexDecoded(), idData.count == 32 else {
            throw NegentropyError.invalidItemId
        }
        self.id = idData
        self.timestamp = UInt64(event.createdAt)
    }
    
    // MARK: - Comparable
    
    public static func < (lhs: NegentropyItem, rhs: NegentropyItem) -> Bool {
        // Sort by timestamp first, then by ID for stability
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.id.lexicographicallyPrecedes(rhs.id)
    }
    
    public static func == (lhs: NegentropyItem, rhs: NegentropyItem) -> Bool {
        return lhs.timestamp == rhs.timestamp && lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestamp)
    }
}

/// Errors specific to Negentropy operations
public enum NegentropyError: LocalizedError {
    case invalidItemId
    case invalidBounds
    case encodingError
    case decodingError
    case protocolError(String)
    case frameSizeExceeded
    
    public var errorDescription: String? {
        switch self {
        case .invalidItemId:
            return "Invalid item ID - must be 32 bytes"
        case .invalidBounds:
            return "Invalid range bounds"
        case .encodingError:
            return "Failed to encode Negentropy message"
        case .decodingError:
            return "Failed to decode Negentropy message"
        case .protocolError(let message):
            return "Negentropy protocol error: \(message)"
        case .frameSizeExceeded:
            return "Frame size limit exceeded"
        }
    }
}

// Extension for hex encoding/decoding
extension String {
    func hexDecoded() -> Data? {
        var data = Data()
        var hex = self
        
        // Remove 0x prefix if present
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        
        // Ensure even number of characters
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }
        
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        return data
    }
}