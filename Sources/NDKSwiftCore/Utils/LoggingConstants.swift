/// Common logging constants for consistent log formatting
public enum LoggingConstants {
    // MARK: - Log Prefixes (Emoji indicators for quick visual scanning)

    /// Success indicator
    public static let success = "✅"

    /// Error/failure indicator
    public static let error = "❌"

    /// Info/note indicator
    public static let info = "📝"

    /// Warning indicator
    public static let warning = "⚠️"

    /// Debug indicator
    public static let debug = "🔍"

    /// Network/connection indicator
    public static let network = "🌐"

    /// Security/encryption indicator
    public static let security = "🔒"

    /// Timer/performance indicator
    public static let timer = "⏱️"

    /// Wallet/payment indicator
    public static let wallet = "💰"

    /// Event/message indicator
    public static let event = "📨"

    /// Target/goal indicator
    public static let target = "🎯"

    /// Sync indicator
    public static let sync = "🔄"

    /// Lightning indicator
    public static let lightning = "⚡"

    /// Configuration indicator
    public static let config = "⚙️"

    /// Cache indicator
    public static let cache = "💾"

    /// Database indicator
    public static let database = "🗄️"

    /// Relay indicator
    public static let relay = "📡"

    /// NIP-05 verification indicator
    public static let verification = "✓"

    // MARK: - Common Log Message Templates

    public enum Messages {
        /// Generic formatter for log messages with optional details
        private static func format(_ prefix: String, _ operation: String, details: String? = nil, detailsFormat: (String) -> String = { ": \($0)" }) -> String {
            let base = "\(prefix) \(operation)"
            return details.map { "\(base)\(detailsFormat($0))" } ?? base
        }

        /// Format a success message
        public static func success(_ operation: String, details: String? = nil) -> String {
            format(LoggingConstants.success, operation, details: details)
        }

        /// Format an error message
        public static func error(_ operation: String, details: String? = nil) -> String {
            format(LoggingConstants.error, operation, details: details)
        }

        /// Format an info message
        public static func info(_ operation: String, details: String? = nil) -> String {
            format(LoggingConstants.info, operation, details: details)
        }

        /// Format a network operation message
        public static func network(_ operation: String, relay: String? = nil) -> String {
            format(LoggingConstants.network, operation, details: relay) { " [\($0)]" }
        }

        /// Format a wallet operation message
        public static func wallet(_ operation: String, amount: Int? = nil) -> String {
            format(LoggingConstants.wallet, operation, details: amount.map(String.init)) { " - \($0) sats" }
        }
    }
}
