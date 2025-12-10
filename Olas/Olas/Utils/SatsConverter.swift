import Foundation

/// Pure utility for converting between sats and fiat
enum SatsConverter {
    private static let satsPerBTC: Double = 100_000_000.0

    /// Convert sats to fiat value
    /// - Parameters:
    ///   - sats: Amount in satoshis
    ///   - btcRate: BTC price in fiat currency
    /// - Returns: Fiat value
    static func satsToFiat(_ sats: Int64, btcRate: Double) -> Double {
        (Double(sats) / satsPerBTC) * btcRate
    }

    /// Convert fiat to sats
    /// - Parameters:
    ///   - fiat: Fiat amount
    ///   - btcRate: BTC price in fiat currency
    /// - Returns: Amount in satoshis (0 if rate is invalid)
    static func fiatToSats(_ fiat: Double, btcRate: Double) -> Int64 {
        guard btcRate > 0 else { return 0 }
        return Int64((fiat / btcRate) * satsPerBTC)
    }

    /// Format sats with thousands separator
    static func formatSats(_ sats: Int64, formatter: NumberFormatter? = nil) -> String {
        let fmt = formatter ?? {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            return f
        }()
        return fmt.string(from: NSNumber(value: sats)) ?? "\(sats)"
    }

    /// Format fiat with currency symbol
    static func formatFiat(_ value: Double, currencyCode: String, formatter: NumberFormatter? = nil) -> String {
        let fmt = formatter ?? {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.maximumFractionDigits = 2
            return f
        }()
        fmt.currencyCode = currencyCode
        return fmt.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
