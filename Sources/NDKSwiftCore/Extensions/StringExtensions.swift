import Foundation

// MARK: - String Extensions for Common Operations

public extension String {
    /// Returns nil if the string is empty, otherwise returns the string itself
    var nilIfEmpty: String? {
        return isEmpty ? nil : self
    }

    /// Returns true if string has content after trimming whitespace
    var hasContent: Bool {
        return ValidationHelpers.hasContent(self)
    }

    /// Returns the string trimmed of whitespace and newlines
    var trimmed: String {
        return ValidationHelpers.trim(self)
    }

    /// Returns the string normalized (trimmed and lowercased)
    var normalized: String {
        return ValidationHelpers.normalize(self)
    }

    /// Checks if string starts with any of the given prefixes (case-insensitive)
    func startsWithAny(of prefixes: [String]) -> Bool {
        let normalized = self.normalized
        return prefixes.contains { normalized.hasPrefix($0.normalized) }
    }
}

// MARK: - String Validation Extensions

public extension String {
    /// Check if the string is a valid WebSocket URL
    var isWebSocketURL: Bool {
        return RelayConstants.WebSocketScheme.isWebSocketURL(self)
    }

    /// Check if the string is a valid URL
    var isValidURL: Bool {
        return URL(string: self) != nil
    }

    /// Check if the string is valid 32-byte hex
    var isValid32ByteHex: Bool {
        return HexValidator.isValid32ByteHex(self)
    }

    /// Check if the string is valid 64-byte hex
    var isValid64ByteHex: Bool {
        return HexValidator.isValid64ByteHex(self)
    }
}

// MARK: - Nostr Format Conversion Extensions

public extension String {
    /// Convert this hex pubkey to npub format
    var npub: String {
        get throws {
            try Bech32.npub(from: self)
        }
    }

    /// Convert a hex pubkey to npub format
    static func toNpub(_ pubkey: String) throws -> String {
        return try Bech32.npub(from: pubkey)
    }

    /// Convert an npub to hex pubkey
    static func fromNpub(_ npub: String) throws -> String? {
        return try Bech32.pubkey(from: npub)
    }

    /// Attempts to normalize a relay URL, returning the original string if normalization fails
    var normalizedRelayURL: String {
        URLNormalizer.tryNormalizeRelayUrl(self) ?? self
    }

    /// Formats a relay URL for display by removing the WebSocket scheme prefix and trailing slash
    var formattedRelayURL: String {
        var formatted = self

        // Remove WebSocket scheme prefix
        if formatted.hasPrefix("wss://") {
            formatted = String(formatted.dropFirst(6))
        } else if formatted.hasPrefix("ws://") {
            formatted = String(formatted.dropFirst(5))
        }

        // Remove trailing slash
        if formatted.hasSuffix("/") {
            formatted = String(formatted.dropLast())
        }

        return formatted
    }

    /// Truncates a relay URL for compact display
    func truncatedRelayURL(maxLength: Int = 25) -> String {
        let formatted = formattedRelayURL
        if formatted.count > maxLength {
            return String(formatted.prefix(maxLength - 3)) + "..."
        }
        return formatted
    }
}

// MARK: - Collection Extensions

public extension Collection {
    /// Returns nil if the collection is empty, otherwise returns the collection itself
    var nilIfEmpty: Self? {
        return isEmpty ? nil : self
    }
}

public extension Collection where Element == String {
    /// Returns nil if the collection is empty, otherwise returns a Set of the elements
    var setOrNil: Set<String>? {
        return isEmpty ? nil : Set(self)
    }
}
