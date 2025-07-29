
/// Centralized constants for commonly used Nostr relay URLs
public enum RelayConstants {

    // MARK: - WebSocket Schemes

    /// WebSocket scheme constants
    public enum WebSocketScheme {
        /// Secure WebSocket scheme
        public static let secure = "wss://"

        /// Insecure WebSocket scheme
        public static let insecure = "ws://"

        /// Check if a URL string uses WebSocket scheme
        /// - Parameter url: The URL string to check
        /// - Returns: true if the URL starts with ws:// or wss://
        public static func isWebSocketURL(_ url: String) -> Bool {
            let lowercased = url.lowercased()
            return lowercased.hasPrefix(secure) || lowercased.hasPrefix(insecure)
        }
        
        /// Add WebSocket scheme to URL if missing
        /// - Parameter url: The URL string to process
        /// - Returns: URL with WebSocket scheme added if it was missing
        public static func ensureWebSocketScheme(_ url: String) -> String {
            let trimmed = url.trimmed
            if !isWebSocketURL(trimmed) {
                return secure + trimmed
            }
            return trimmed
        }
    }

    // MARK: - Popular Public Relays

    /// Damus relay - One of the most popular Nostr relays
    public static let damus = "wss://relay.damus.io"

    /// Nostr Band relay - Popular relay with good analytics
    public static let nostrBand = "wss://relay.nostr.band"

    /// nos.lol relay - Fast and reliable public relay
    public static let nosLol = "wss://nos.lol"

    /// Primal relay - Popular relay with good performance
    public static let primal = "wss://relay.primal.net"

    /// Snort Social relay
    public static let snortSocial = "wss://relay.snort.social"

    /// Nostr Wine relay
    public static let nostrWine = "wss://nostr.wine"

    /// Current.fyi relay
    public static let currentFyi = "wss://relay.current.fyi"

    /// Oxtr.dev relay - Developer-friendly relay
    public static let oxtrDev = "wss://nostr.oxtr.dev"

    // MARK: - Specialized Relays

    // MARK: - Documentation Examples

    /// Example relay URL for documentation and examples
    public static let example = "wss://relay.example.com"

    // MARK: - Common Relay Sets

    /// Default set of relays for general use
    public static let defaultRelays: [String] = [
        damus,
        nostrBand,
        nosLol
    ]

    /// Extended set of relays for broader reach
    public static let extendedRelays: [String] = [
        damus,
        nostrBand,
        nosLol,
        primal,
        snortSocial
    ]

    /// Relays commonly used for testing
    public static let testRelays: [String] = [
        damus,
        nostrBand,
        nosLol
    ]

    /// Relays optimized for wallet operations
    public static let walletRelays: [String] = [
        primal,
        damus,
        nostrBand
    ]

    /// Default outbox relays
    public static let defaultOutboxRelays: Set<String> = [
        "wss://relay.nostr.band"
    ]
}