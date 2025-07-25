import Foundation

// MARK: - String Extensions for Common Operations

public extension String {
    /// Returns true if string has content after trimming whitespace
    var hasContent: Bool {
        return !self.trimmed.isEmpty
    }
    
    /// Returns the string trimmed of whitespace and newlines
    var trimmed: String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Returns the string normalized (trimmed and lowercased)
    var normalized: String {
        return self.trimmed.lowercased()
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
    /// Convert a hex pubkey to npub format
    static func toNpub(_ pubkey: String) throws -> String {
        return try Bech32.npub(from: pubkey)
    }
    
    /// Convert an npub to hex pubkey
    static func fromNpub(_ npub: String) throws -> String? {
        return try Bech32.pubkey(from: npub)
    }
}