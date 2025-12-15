import Foundation

/// Represents an item in the Negentropy set reconciliation protocol.
///
/// A `NegentropyItem` encapsulates a unique identifier and timestamp for efficient
/// set reconciliation. Items are ordered first by timestamp, then by ID for stable sorting.
///
/// ## Usage
///
/// ```swift
/// // Create from raw data
/// let id = Data(repeating: 0x42, count: 32)
/// let item = NegentropyItem(id: id, timestamp: 1234567890)
///
/// // Create from hex string
/// let hexItem = try NegentropyItem(hexId: "abcd...", timestamp: 1234567890)
///
/// // Create from Nostr event
/// let eventItem = try NegentropyItem(event: someNDKEvent)
/// ```
///
/// ## Performance Notes
///
/// - Items are compared frequently during reconciliation
/// - Use efficient timestamp-based filtering when possible
/// - 32-byte IDs ensure cryptographic uniqueness
public struct NegentropyItem: Comparable, Hashable, Sendable {
    /// 32-byte identifier (typically event ID for Nostr)
    public let id: Data

    /// Timestamp for ordering (unix timestamp)
    public let timestamp: UInt64

    /// Creates a new Negentropy item with the specified ID and timestamp.
    ///
    /// - Parameters:
    ///   - id: 32-byte unique identifier (e.g., SHA256 hash)
    ///   - timestamp: Unix timestamp for temporal ordering
    ///
    /// - Precondition: `id` must be exactly 32 bytes
    public init(id: Data, timestamp: UInt64) {
        precondition(id.count == 32, "Negentropy item ID must be exactly 32 bytes")
        self.id = id
        self.timestamp = timestamp
    }

    /// Creates a new Negentropy item from a hex-encoded ID string.
    ///
    /// - Parameters:
    ///   - hexId: Hex-encoded string representing a 32-byte ID
    ///   - timestamp: Unix timestamp for temporal ordering
    ///
    /// - Throws: `NegentropyError.invalidItemId` if the hex string is invalid or not 32 bytes
    ///
    /// - Note: Hex string can include "0x" prefix and is case-insensitive
    public init(hexId: String, timestamp: UInt64) throws {
        do {
            let idData = try HexValidator.validate32ByteHex(hexId)
            id = idData
            self.timestamp = timestamp
        } catch {
            throw NegentropyError.invalidItemId
        }
    }

    /// Creates a new Negentropy item from a Nostr event.
    ///
    /// - Parameter event: The Nostr event to convert
    ///
    /// - Throws: `NegentropyError.invalidItemId` if the event ID is invalid
    ///
    /// - Note: Uses the event's `createdAt` timestamp and hex-decoded `id`
    public init(event: NDKEvent) throws {
        do {
            let idData = try HexValidator.validate32ByteHex(event.id)
            id = idData
            timestamp = UInt64(event.createdAt)
        } catch {
            throw NegentropyError.invalidItemId
        }
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
public enum NegentropyError: LocalizedError, Sendable {
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
        case let .protocolError(message):
            return "Negentropy protocol error: \(message)"
        case .frameSizeExceeded:
            return "Frame size limit exceeded"
        }
    }
}
