import Foundation

/// Constants for Lightning Network protocol
public enum LightningConstants {
    /// Lightning invoice prefixes for different networks
    public enum Prefixes {
        /// Bitcoin mainnet invoice prefix
        public static let mainnet = "lnbc"

        /// Bitcoin testnet invoice prefix
        public static let testnet = "lntb"

        /// Bitcoin regtest invoice prefix
        public static let regtest = "lnbcrt"

        /// Lightning URL prefix
        public static let lnurl = "lnurl"

        /// All valid Lightning invoice prefixes
        public static let allInvoicePrefixes = [mainnet, testnet, regtest]
    }

    /// Check if a string is a valid Lightning invoice
    /// - Parameter text: The text to check
    /// - Returns: true if the text starts with a valid Lightning invoice prefix
    public static func isLightningInvoice(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return Prefixes.allInvoicePrefixes.contains { lowercased.hasPrefix($0) }
    }

    /// Check if a string is a Lightning URL
    /// - Parameter text: The text to check
    /// - Returns: true if the text starts with the LNURL prefix
    public static func isLNURL(_ text: String) -> Bool {
        text.lowercased().hasPrefix(Prefixes.lnurl)
    }

    /// Extract the network from a Lightning invoice
    /// - Parameter invoice: The Lightning invoice
    /// - Returns: The network name (mainnet, testnet, regtest) or nil if invalid
    public static func network(from invoice: String) -> String? {
        let lowercased = invoice.lowercased()
        if lowercased.hasPrefix(Prefixes.mainnet) { return "mainnet" }
        if lowercased.hasPrefix(Prefixes.testnet) { return "testnet" }
        if lowercased.hasPrefix(Prefixes.regtest) { return "regtest" }
        return nil
    }
}
