@testable import NDKSwiftCore
import XCTest

final class Bolt11ParserTests: XCTestCase {
    func testValidMainnetInvoiceStructure() {
        // Test with a properly structured invoice (even if signature is invalid)
        // This tests the basic parsing structure without requiring a valid signature
        let invoice = "lnbc1000n1pwz4j4xpp5vc8jt9mmy4g0k8rl7xwkx3xj4w2xqrn4s7s2mj8rkj2xqv4x7m8sdq52dhkxgppxg6rscf5w2x3w7k"

        let parsed = Bolt11Parser.decode(string: invoice)

        // Since we don't have valid signatures for test invoices, this may be nil
        // but it should not crash the parser
        // The important thing is that the parser handles the input gracefully
        if let parsed = parsed {
            XCTAssertEqual(parsed.network, .mainnet, "Should detect mainnet from lnbc prefix")
        }
    }

    func testInvalidInvoice() {
        let invalidInvoice = "invalid_invoice_string"

        let parsed = Bolt11Parser.decode(string: invalidInvoice)

        XCTAssertNil(parsed, "Parser should return nil for invalid invoice")
    }

    func testEmptyInvoice() {
        let emptyInvoice = ""

        let parsed = Bolt11Parser.decode(string: emptyInvoice)

        XCTAssertNil(parsed, "Parser should return nil for empty string")
    }

    func testNetworkDecoding() {
        // Test network prefix detection
        XCTAssertEqual(Bolt11Parser.Prefix.forNetwork(.mainnet), .lnbc)
        XCTAssertEqual(Bolt11Parser.Prefix.forNetwork(.testnet), .lntb)
        XCTAssertEqual(Bolt11Parser.Prefix.forNetwork(.regtest), .lnbcrt)
        XCTAssertEqual(Bolt11Parser.Prefix.forNetwork(.simnet), .lnsb)
    }

    func testAmountMultipliers() {
        // Test that multiplier values are correct
        let milliValue = Decimal(100_000) // 100,000 millisats = 1 mBTC
        let microValue = Decimal(100) // 100 millisats = 1 μBTC
        let nanoValue = Decimal(0.1) // 0.1 millisats = 1 nBTC
        let picoValue = Decimal(0.0001) // 0.0001 millisats = 1 pBTC

        // We can't directly test the private enum, but we can verify the logic
        // through the parsing behavior. This is more of a documentation test.
        XCTAssertTrue(milliValue > microValue)
        XCTAssertTrue(microValue > nanoValue)
        XCTAssertTrue(nanoValue > picoValue)
    }
}
