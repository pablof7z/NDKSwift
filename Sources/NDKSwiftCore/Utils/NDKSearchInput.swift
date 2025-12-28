import Foundation

/// Classifies user input for search routing
///
/// This enum represents the different types of search inputs that can be detected
/// from user text input, allowing the search system to route appropriately.
public enum NDKSearchInputType: Equatable, Sendable {
    /// Plain text search - searches both events and profiles
    case text(String)

    /// Profile-only search (input starts with @)
    case profileOnly(String)

    /// Hashtag search - deferred until user submits
    case hashtag(String)

    /// NIP-05 identifier (user@domain.com format)
    case nip05(String)

    /// npub bech32 encoded public key
    case npub(pubkey: String)

    /// nprofile bech32 encoded profile with optional relay hints
    case nprofile(pubkey: String, relays: [String])

    /// note bech32 encoded event ID
    case note(eventId: String)

    /// nevent bech32 encoded event with optional relay hints and author
    case nevent(eventId: String, relays: [String], author: String?)

    /// Empty input
    case empty

    /// Returns the raw query string for text-based searches
    public var searchQuery: String? {
        switch self {
        case .text(let query), .profileOnly(let query):
            return query
        case .hashtag(let tag):
            return tag
        default:
            return nil
        }
    }

    /// Whether this input type triggers immediate navigation (no search results shown)
    public var triggersNavigation: Bool {
        switch self {
        case .npub, .nprofile, .note, .nevent, .nip05:
            return true
        default:
            return false
        }
    }

    /// Whether search should be deferred until explicit submission
    public var requiresSubmit: Bool {
        switch self {
        case .hashtag:
            return true
        default:
            return false
        }
    }
}

/// Utilities for classifying search input
public enum NDKSearchInput {
    /// Classify input string into the appropriate search type
    /// - Parameter input: The raw user input string
    /// - Returns: The classified input type
    public static func classify(_ input: String) -> NDKSearchInputType {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty input
        guard !trimmed.isEmpty else {
            return .empty
        }

        // Check for @ prefix (profile search)
        if trimmed.hasPrefix("@") {
            let query = String(trimmed.dropFirst())
            // But also check if it looks like a NIP-05 after the @
            // e.g., "@pablo@nostr.band" should extract "pablo@nostr.band"
            if looksLikeNIP05(query) {
                return .nip05(query)
            }
            return .profileOnly(query)
        }

        // Check for # prefix (hashtag)
        if trimmed.hasPrefix("#") {
            let tag = String(trimmed.dropFirst())
            guard !tag.isEmpty else { return .empty }
            return .hashtag(tag)
        }

        // Check for bech32 nostr identifiers
        let lowercased = trimmed.lowercased()

        if lowercased.hasPrefix("npub1") {
            if let pubkey = decodeNpub(trimmed) {
                return .npub(pubkey: pubkey)
            }
        }

        if lowercased.hasPrefix("nprofile1") {
            if let (pubkey, relays) = decodeNprofile(trimmed) {
                return .nprofile(pubkey: pubkey, relays: relays)
            }
        }

        if lowercased.hasPrefix("note1") {
            if let eventId = decodeNote(trimmed) {
                return .note(eventId: eventId)
            }
        }

        if lowercased.hasPrefix("nevent1") {
            if let (eventId, relays, author) = decodeNevent(trimmed) {
                return .nevent(eventId: eventId, relays: relays, author: author)
            }
        }

        // Check for NIP-05 identifier (contains @ and looks like domain)
        if looksLikeNIP05(trimmed) {
            return .nip05(trimmed)
        }

        // Default: plain text search
        return .text(trimmed)
    }

    /// Check if input looks like a NIP-05 identifier
    /// A NIP-05 looks like: name@domain.tld or just domain.tld
    /// - Parameter input: The input string to check
    /// - Returns: true if it looks like a NIP-05 identifier
    public static func looksLikeNIP05(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Must contain @ for email-style, or be a domain
        if trimmed.contains("@") {
            // Email-style: user@domain.tld
            let parts = trimmed.split(separator: "@")
            guard parts.count == 2 else { return false }

            let domain = String(parts[1])
            return isValidDomain(domain)
        } else {
            // Just a domain: domain.tld (will be resolved as _@domain.tld)
            return isValidDomain(trimmed)
        }
    }

    /// Check if a string looks like a valid domain
    private static func isValidDomain(_ domain: String) -> Bool {
        // Must have at least one dot
        guard domain.contains(".") else { return false }

        // Must not start or end with a dot
        guard !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }

        // Split by dots and validate each part
        let parts = domain.split(separator: ".")
        guard parts.count >= 2 else { return false }

        // Each part must be valid (alphanumeric + hyphens, not starting/ending with hyphen)
        for part in parts {
            let partString = String(part)
            guard !partString.isEmpty else { return false }
            guard !partString.hasPrefix("-"), !partString.hasSuffix("-") else { return false }

            // Only allow alphanumeric and hyphens
            let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
            guard partString.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else { return false }
        }

        // TLD must be at least 2 characters
        guard let tld = parts.last, tld.count >= 2 else { return false }

        return true
    }

    // MARK: - Bech32 Decoding

    /// Decode an npub bech32 string to hex pubkey
    private static func decodeNpub(_ npub: String) -> String? {
        guard Bech32.isBech32(npub) else { return nil }

        do {
            let decoded = try ContentTagger.decodeNostrEntity(npub)
            guard decoded.type == "npub" else { return nil }
            return decoded.pubkey
        } catch {
            return nil
        }
    }

    /// Decode an nprofile bech32 string to pubkey and relays
    private static func decodeNprofile(_ nprofile: String) -> (pubkey: String, relays: [String])? {
        guard Bech32.isBech32(nprofile) else { return nil }

        do {
            let decoded = try ContentTagger.decodeNostrEntity(nprofile)
            guard decoded.type == "nprofile", let pubkey = decoded.pubkey else { return nil }
            return (pubkey, decoded.relays ?? [])
        } catch {
            return nil
        }
    }

    /// Decode a note bech32 string to hex event ID
    private static func decodeNote(_ note: String) -> String? {
        guard Bech32.isBech32(note) else { return nil }

        do {
            let decoded = try ContentTagger.decodeNostrEntity(note)
            guard decoded.type == "note" else { return nil }
            return decoded.eventId
        } catch {
            return nil
        }
    }

    /// Decode an nevent bech32 string to event ID, relays, and optional author
    private static func decodeNevent(_ nevent: String) -> (eventId: String, relays: [String], author: String?)? {
        guard Bech32.isBech32(nevent) else { return nil }

        do {
            let decoded = try ContentTagger.decodeNostrEntity(nevent)
            guard decoded.type == "nevent", let eventId = decoded.eventId else { return nil }
            return (eventId, decoded.relays ?? [], decoded.pubkey)
        } catch {
            return nil
        }
    }
}
