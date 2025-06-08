import Foundation

/// Utilities for working with Nostr identifiers (hex and bech32)
public enum NostrIdentifier {
    
    /// Create a filter from a hex ID or bech32 identifier
    /// - Parameter identifier: A hex event ID or bech32 encoded string (note1..., nevent1..., naddr1...)
    /// - Returns: An NDKFilter configured to fetch the specified event
    /// - Throws: NDKError if the identifier is invalid
    public static func createFilter(from identifier: String) throws -> NDKFilter {
        // Check if it's a bech32 string
        if Bech32.isBech32(identifier) {
            let decoded = try ContentTagger.decodeNostrEntity(identifier)
            
            switch decoded.type {
            case "note", "nevent":
                guard let eventId = decoded.eventId else {
                    throw NDKError.validation("invalid_input", "Invalid \(decoded.type) format")
                }
                return NDKFilter(ids: [eventId])
                
            case "naddr":
                guard let pubkey = decoded.pubkey,
                      let kind = decoded.kind,
                      let dTag = decoded.identifier else {
                    throw NDKError.validation("invalid_input", "Invalid naddr format")
                }
                return NDKFilter(
                    authors: [pubkey],
                    kinds: [kind],
                    tags: ["d": Set([dTag])]
                )
                
            default:
                throw NDKError.validation("invalid_input", "Unsupported bech32 type: \(decoded.type)")
            }
        } else {
            // Assume it's a hex event ID
            guard identifier.count == 64 else {
                throw NDKError.validation("invalid_input", "Invalid event ID: must be 64-character hex or valid bech32")
            }
            return NDKFilter(ids: [identifier])
        }
    }
}