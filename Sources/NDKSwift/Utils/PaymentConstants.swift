import Foundation

/// Constants for payment and wallet operations
public enum PaymentConstants {

    // MARK: - Unit Conversions

    /// Number of millisatoshis per satoshi
    public static let millisatsPerSat: Int64 = 1000

    /// Number of satoshis per Bitcoin
    public static let satsPerBitcoin: Int64 = 100_000_000

    /// Number of millisatoshis per Bitcoin
    public static let millisatsPerBitcoin: Int64 = satsPerBitcoin * millisatsPerSat

    // MARK: - Conversion Methods

    /// Convert satoshis to millisatoshis
    public static func satsToMillisats(_ sats: Int64) -> Int64 {
        return sats * millisatsPerSat
    }

    /// Convert millisatoshis to satoshis
    public static func millisatsToSats(_ millisats: Int64) -> Int64 {
        return millisats / millisatsPerSat
    }

    // MARK: - Zap Constants

    /// Default timeout for waiting for zap receipts (in seconds)
    public static let zapReceiptTimeout: TimeInterval = 30

    // MARK: - Cashu Constants

    /// Default fee buffer for cross-mint transfers (in satoshis)
    public static let defaultCashuFeeBuffer: Int64 = 1000

    // MARK: - Lightning Invoice Multipliers

    /// Multipliers for different Lightning invoice denominations
    public enum InvoiceMultiplier {
        /// Millisatoshis (base unit)
        public static let millisats: Int64 = 1
        /// Microsatoshis to millisatoshis
        public static let microsatsToMillisats: Int64 = 1000
        /// Nanosatoshis to millisatoshis
        public static let nanosatsToMillisats: Int64 = 1_000_000
        /// Picosatoshis to millisatoshis
        public static let picosatsToMillisats: Int64 = 1_000_000_000
        /// Bitcoin to millisatoshis
        public static let bitcoinToMillisats: Int64 = millisatsPerBitcoin
    }
}