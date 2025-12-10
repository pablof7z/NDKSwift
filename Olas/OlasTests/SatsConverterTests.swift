import Foundation
import Testing
@testable import Olas

@Suite("SatsConverter")
struct SatsConverterTests {

    // MARK: - satsToFiat

    @Test("1 BTC returns the BTC rate")
    func satsToFiat_oneBTC_returnsRate() {
        let oneBTC: Int64 = 100_000_000
        let rate = 50_000.0

        let result = SatsConverter.satsToFiat(oneBTC, btcRate: rate)

        #expect(abs(result - 50_000.0) < 0.01)
    }

    @Test("0.5 BTC returns half the rate")
    func satsToFiat_halfBTC_returnsHalfRate() {
        let halfBTC: Int64 = 50_000_000
        let rate = 100_000.0

        let result = SatsConverter.satsToFiat(halfBTC, btcRate: rate)

        #expect(abs(result - 50_000.0) < 0.01)
    }

    @Test("1000 sats at $100k/BTC equals $1")
    func satsToFiat_oneThousandSats_returnsSmallFiat() {
        let sats: Int64 = 1_000
        let rate = 100_000.0

        let result = SatsConverter.satsToFiat(sats, btcRate: rate)

        #expect(abs(result - 1.0) < 0.01)
    }

    @Test("Zero sats returns zero fiat")
    func satsToFiat_zeroSats_returnsZero() {
        let result = SatsConverter.satsToFiat(0, btcRate: 50_000.0)

        #expect(result == 0.0)
    }

    @Test("Zero rate returns zero fiat")
    func satsToFiat_zeroRate_returnsZero() {
        let result = SatsConverter.satsToFiat(100_000_000, btcRate: 0.0)

        #expect(result == 0.0)
    }

    // MARK: - fiatToSats

    @Test("$50k at $50k/BTC equals 1 BTC")
    func fiatToSats_oneBTCWorth_returnsOneBTC() {
        let fiat = 50_000.0
        let rate = 50_000.0

        let result = SatsConverter.fiatToSats(fiat, btcRate: rate)

        #expect(result == 100_000_000)
    }

    @Test("$1 at $100k/BTC equals 1000 sats")
    func fiatToSats_oneDollar_returnsCorrectSats() {
        let fiat = 1.0
        let rate = 100_000.0

        let result = SatsConverter.fiatToSats(fiat, btcRate: rate)

        #expect(result == 1_000)
    }

    @Test("Zero fiat returns zero sats")
    func fiatToSats_zeroFiat_returnsZero() {
        let result = SatsConverter.fiatToSats(0.0, btcRate: 50_000.0)

        #expect(result == 0)
    }

    @Test("Zero rate returns zero sats")
    func fiatToSats_zeroRate_returnsZero() {
        let result = SatsConverter.fiatToSats(100.0, btcRate: 0.0)

        #expect(result == 0)
    }

    @Test("Negative rate returns zero sats")
    func fiatToSats_negativeRate_returnsZero() {
        let result = SatsConverter.fiatToSats(100.0, btcRate: -50_000.0)

        #expect(result == 0)
    }

    // MARK: - Roundtrip

    @Test("Sats -> fiat -> sats preserves value")
    func roundtrip_satsToFiatToSats_preservesValue() {
        let originalSats: Int64 = 12_345_678
        let rate = 67_890.0

        let fiat = SatsConverter.satsToFiat(originalSats, btcRate: rate)
        let roundtripSats = SatsConverter.fiatToSats(fiat, btcRate: rate)

        #expect(roundtripSats == originalSats)
    }

    @Test("Fiat -> sats -> fiat preserves value within precision")
    func roundtrip_fiatToSatsToFiat_preservesValue() {
        let originalFiat = 123.45
        let rate = 50_000.0

        let sats = SatsConverter.fiatToSats(originalFiat, btcRate: rate)
        let roundtripFiat = SatsConverter.satsToFiat(sats, btcRate: rate)

        #expect(abs(roundtripFiat - originalFiat) < 0.01)
    }

    // MARK: - formatSats

    @Test("Large numbers have thousands separator")
    func formatSats_largeNumber_hasThousandsSeparator() {
        let result = SatsConverter.formatSats(1_234_567)

        #expect(result.contains(",") || result.contains(" ") || result.contains("."))
    }

    @Test("Zero formats as '0'")
    func formatSats_zero_returnsZero() {
        let result = SatsConverter.formatSats(0)

        #expect(result == "0")
    }

    // MARK: - formatFiat

    @Test("USD format includes dollar symbol")
    func formatFiat_USD_hasDollarSign() {
        let result = SatsConverter.formatFiat(123.45, currencyCode: "USD")

        #expect(result.contains("$") || result.contains("USD"))
    }

    @Test("EUR format includes euro symbol")
    func formatFiat_EUR_hasEuroSign() {
        let result = SatsConverter.formatFiat(123.45, currencyCode: "EUR")

        #expect(result.contains("€") || result.contains("EUR"))
    }

    @Test("Fiat rounds to two decimals")
    func formatFiat_roundsToTwoDecimals() {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")

        let result = SatsConverter.formatFiat(123.456789, currencyCode: "USD", formatter: formatter)

        #expect(result == "$123.46")
    }
}
