import Foundation

/// Centralized constants for Bech32 Human Readable Parts (HRP) used in Nostr
public enum Bech32HRP {

    // MARK: - Basic Nostr Entities

    /// Public key encoding (32-byte public key)
    public static let npub = "npub"

    /// Private key encoding (32-byte private key)
    public static let nsec = "nsec"

    /// Note/Event ID encoding (32-byte event ID)
    public static let note = "note"

    // MARK: - Extended Entities

    /// Event encoding with additional metadata (TLV format)
    public static let nevent = "nevent"

    /// Parameterized replaceable event encoding (TLV format)
    public static let naddr = "naddr"

    /// Profile encoding with relay hints (TLV format)
    public static let nprofile = "nprofile"

    /// Relay encoding (for relay URLs)
    public static let nrelay = "nrelay"

    // MARK: - Lightning Network

    /// Lightning URL encoding
    public static let lnurl = "lnurl"

    // MARK: - Helper Functions

    /// Check if a string is a valid Nostr bech32 entity
    /// - Parameter string: The string to check
    /// - Returns: true if the string starts with a known Nostr HRP
    public static func isNostrEntity(_ string: String) -> Bool {
        let lowercased = string.lowercased()
        return lowercased.hasPrefix(npub) ||
               lowercased.hasPrefix(nsec) ||
               lowercased.hasPrefix(note) ||
               lowercased.hasPrefix(nevent) ||
               lowercased.hasPrefix(naddr) ||
               lowercased.hasPrefix(nprofile) ||
               lowercased.hasPrefix(nrelay) ||
               lowercased.hasPrefix(lnurl)
    }

    /// Get the entity type from a bech32 string
    /// - Parameter string: The bech32 string
    /// - Returns: The HRP if it's a known Nostr entity, nil otherwise
    public static func entityType(from string: String) -> String? {
        let lowercased = string.lowercased()

        for hrp in [npub, nsec, note, nevent, naddr, nprofile, nrelay, lnurl] {
            if lowercased.hasPrefix(hrp) {
                return hrp
            }
        }

        return nil
    }
}