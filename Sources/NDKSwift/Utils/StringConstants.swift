/// Common string constants used throughout NDKSwift
public enum StringConstants {
    
    /// Operation names for logging and debugging
    public enum Operations {
        public static let publishEvent = "Publish event"
        public static let connect = "Connect"
        public static let disconnect = "Disconnect"
        public static let subscribe = "Subscribe"
        public static let unsubscribe = "Unsubscribe"
        public static let retryOperation = "Retry operation"
    }
    
    /// Transaction descriptions
    public enum Transactions {
        public static let lightningPayment = "Lightning payment"
        public static let lightningDeposit = "Lightning deposit"
        public static let sendTokens = "Send tokens"
        public static let receiveEcash = "Receive ecash"
        public static let mintTokens = "Mint tokens"
        public static let swapTokens = "Swap tokens"
    }
    
    /// WebSocket close reasons
    public enum WebSocketCloseReasons {
        public static let normal = "Normal closure"
        public static let goingAway = "Going away"
        public static let protocolError = "Protocol error"
        public static let unsupportedData = "Unsupported data"
        public static let invalidPayload = "Invalid payload"
        public static let policyViolation = "Policy violation"
        public static let messageTooBig = "Message too big"
        public static let internalError = "Internal error"
        public static let serviceRestart = "Service restart"
        public static let tryAgainLater = "Try again later"
        public static let badGateway = "Bad gateway"
    }
    
    /// Display formatting constants
    public enum DisplayFormatting {
        /// Standard length for truncated hex identifiers (pubkeys, event IDs, etc.)
        public static let hexPrefixLength = 8
        
        /// Standard length for truncated npub/nsec identifiers
        public static let bech32PrefixLength = 16
        
        /// Maximum characters to show in debug log content previews
        public static let debugLogPreviewLength = 100
    }
}