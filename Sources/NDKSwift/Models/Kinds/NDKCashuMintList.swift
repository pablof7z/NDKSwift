import Foundation

/// Represents a NIP-60 Cashu mint list event (kind 10019)
public struct NDKCashuMintList {
    /// The underlying event
    public var event: NDKEvent
    
    /// The NDK instance
    public var ndk: NDK {
        return event.ndk ?? NDK()
    }
    
    /// Initialize a new mint list
    public init(ndk: NDK) {
        self.event = NDKEvent(content: "", tags: [])
        self.event.ndk = ndk
        self.event.kind = EventKind.cashuMintList
    }
    
    /// Create from an existing event
    public static func from(_ event: NDKEvent) -> NDKCashuMintList? {
        guard event.kind == EventKind.cashuMintList else { return nil }
        
        var mintList = NDKCashuMintList(ndk: event.ndk ?? NDK())
        mintList.event = event
        
        return mintList
    }
    
    /// Get mint URLs from the event
    public var mints: [String] {
        return event.tags
            .filter { $0.first == "mint" }
            .compactMap { $0[safe: 1] }
    }
    
    /// Add a mint URL
    public mutating func addMint(_ url: String) {
        // Remove existing mint tag for this URL if any
        event.tags = event.tags.filter { !($0.first == "mint" && $0[safe: 1] == url) }
        // Add new mint tag
        event.tags.append(["mint", url])
    }
    
    /// Remove a mint URL
    public mutating func removeMint(_ url: String) {
        event.tags = event.tags.filter { !($0.first == "mint" && $0[safe: 1] == url) }
    }
    
    /// Get relay URLs for publishing nutzaps
    public var relays: [String] {
        // Look for relay tags
        return event.tags
            .filter { $0.first == "relay" }
            .compactMap { $0[safe: 1] }
    }
    
    /// Add a relay URL
    public mutating func addRelay(_ url: String) {
        // Remove existing relay tag for this URL if any
        event.tags = event.tags.filter { !($0.first == "relay" && $0[safe: 1] == url) }
        // Add new relay tag
        event.tags.append(["relay", url])
    }
    
    /// Check if P2PK is supported
    public var p2pk: Bool {
        // Check for P2PK tag
        return event.tags.contains { $0.first == "p2pk" }
    }
    
    /// Set P2PK support
    public mutating func setP2PK(_ supported: Bool) {
        // Remove existing p2pk tag
        event.tags = event.tags.filter { $0.first != "p2pk" }
        
        if supported {
            event.tags.append(["p2pk"])
        }
    }
    
    /// Sign the mint list
    public mutating func sign() async throws {
        try await event.sign()
    }
}