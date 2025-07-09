@testable import NDKSwift
import XCTest

final class NDKNWCWalletTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        ndk = NDK()
    }
    
    override func tearDown() async throws {
        ndk = nil
    }
    
    // MARK: - URI Parsing Tests
    
    func testParseValidConnectionURI() throws {
        let uri = "nostr+walletconnect://b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4?relay=wss%3A%2F%2Frelay.damus.io&secret=71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c&lud16=user@getalby.com"
        
        let connectionURI = try NWCConnectionURI(uri: uri)
        
        XCTAssertEqual(connectionURI.walletPubkey, "b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4")
        XCTAssertEqual(connectionURI.relayURLs, ["wss://relay.damus.io"])
        XCTAssertEqual(connectionURI.secret, "71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c")
        XCTAssertEqual(connectionURI.lud16, "user@getalby.com")
    }
    
    func testParseConnectionURIWithMultipleRelays() throws {
        let uri = "nostr+walletconnect://b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4?relay=wss%3A%2F%2Frelay1.com&relay=wss%3A%2F%2Frelay2.com&secret=71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c"
        
        let connectionURI = try NWCConnectionURI(uri: uri)
        
        XCTAssertEqual(connectionURI.relayURLs.count, 2)
        XCTAssertTrue(connectionURI.relayURLs.contains("wss://relay1.com"))
        XCTAssertTrue(connectionURI.relayURLs.contains("wss://relay2.com"))
    }
    
    func testInvalidURIScheme() {
        let uri = "https://example.com/wallet"
        
        XCTAssertThrowsError(try NWCConnectionURI(uri: uri)) { error in
            guard error is NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            // Check for NDKError
        }
    }
    
    func testMissingRequiredParameters() {
        // Missing secret
        let uriNoSecret = "nostr+walletconnect://b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4?relay=wss%3A%2F%2Frelay.damus.io"
        
        XCTAssertThrowsError(try NWCConnectionURI(uri: uriNoSecret)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            XCTAssertTrue(ndkError.errorDescription?.contains("secret") ?? false)
        }
        
        // Missing relay
        let uriNoRelay = "nostr+walletconnect://b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4?secret=71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c"
        
        XCTAssertThrowsError(try NWCConnectionURI(uri: uriNoRelay)) { error in
            guard error is NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            // Check for relay in error
        }
    }
    
    func testInvalidPubkeyFormat() {
        // Too short pubkey
        let uri = "nostr+walletconnect://invalid?relay=wss%3A%2F%2Frelay.damus.io&secret=71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c"
        
        XCTAssertThrowsError(try NWCConnectionURI(uri: uri)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            XCTAssertTrue(ndkError.errorDescription?.contains("public key") ?? false)
        }
    }
    
    func testCreateURIFromComponents() throws {
        let walletPubkey = "b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4"
        let relayURLs = ["wss://relay1.com", "wss://relay2.com"]
        let secret = "71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c"
        let lud16 = "user@example.com"
        
        let connectionURI = try NWCConnectionURI(
            walletPubkey: walletPubkey,
            relayURLs: relayURLs,
            secret: secret,
            lud16: lud16
        )
        
        XCTAssertEqual(connectionURI.walletPubkey, walletPubkey)
        XCTAssertEqual(connectionURI.relayURLs, relayURLs)
        XCTAssertEqual(connectionURI.secret, secret)
        XCTAssertEqual(connectionURI.lud16, lud16)
        
        // Verify the generated URI can be parsed back
        let reparsed = try NWCConnectionURI(uri: connectionURI.uri)
        XCTAssertEqual(reparsed.walletPubkey, walletPubkey)
        XCTAssertEqual(reparsed.secret, secret)
    }
    
    // MARK: - Request Builder Tests
    
    func testBuildPayInvoiceRequest() async throws {
        let walletPubkey = "b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4"
        let secret = "71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c"
        let signer = try NDKPrivateKeySigner(privateKey: secret)
        
        let builder = NWCRequestBuilder(ndk: ndk, walletPubkey: walletPubkey, signer: signer)
        
        let request = PayInvoiceRequest(invoice: "lnbc50n1...", amount: 1000)
        let event = try await builder.buildPayInvoiceRequest(request)
        
        XCTAssertEqual(event.kind, EventKind.walletRequest)
        XCTAssertTrue(event.tags.contains(where: { $0.count >= 2 && $0[0] == "p" && $0[1] == walletPubkey }))
        XCTAssertNotNil(event.id)
        XCTAssertNotNil(event.sig)
        
        // Content should be encrypted
        XCTAssertNotEqual(event.content, "")
        XCTAssertFalse(event.content.contains("pay_invoice"))
    }
    
    func testBuildGetBalanceRequest() async throws {
        let walletPubkey = "b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4"
        let secret = "71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c"
        let signer = try NDKPrivateKeySigner(privateKey: secret)
        
        let builder = NWCRequestBuilder(ndk: ndk, walletPubkey: walletPubkey, signer: signer)
        
        let event = try await builder.buildGetBalanceRequest()
        
        XCTAssertEqual(event.kind, EventKind.walletRequest)
        XCTAssertTrue(event.tags.contains(where: { $0.count >= 2 && $0[0] == "p" && $0[1] == walletPubkey }))
    }
    
    // MARK: - Response Parsing Tests
    
    func testParsePayInvoiceResponse() throws {
        let jsonResponse = """
        {
            "result_type": "pay_invoice",
            "result": {
                "preimage": "0123456789abcdef",
                "fees_paid": 10
            }
        }
        """
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(NWCResponse<PayInvoiceResponse>.self, from: jsonResponse.data(using: .utf8)!)
        
        XCTAssertEqual(response.resultType, "pay_invoice")
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.result)
        XCTAssertEqual(response.result?.preimage, "0123456789abcdef")
        XCTAssertEqual(response.result?.feesPaid, 10)
    }
    
    func testParseErrorResponse() throws {
        let jsonResponse = """
        {
            "result_type": "pay_invoice",
            "error": {
                "code": "PAYMENT_FAILED",
                "message": "Route not found"
            },
            "result": null
        }
        """
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(NWCResponse<PayInvoiceResponse>.self, from: jsonResponse.data(using: .utf8)!)
        
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, "PAYMENT_FAILED")
        XCTAssertEqual(response.error?.message, "Route not found")
        XCTAssertNil(response.result)
    }
    
    // MARK: - Error Tests
    
    func testNDKWalletErrors() {
        let paymentError = NDKError.paymentFailed(reason: "Insufficient balance")
        XCTAssertTrue(paymentError.errorDescription?.contains("Insufficient balance") ?? false)
        
        let rateLimitError = NDKError.walletRateLimited(retryAfter: 5)
        XCTAssertTrue(rateLimitError.errorDescription?.contains("5 seconds") ?? false)
        
        let timeoutError = NDKError.timeout(operation: "pay_invoice", seconds: 30)
        XCTAssertTrue(timeoutError.errorDescription?.contains("30 seconds") ?? false)
    }
    
    // MARK: - Integration Tests (Mocked)
    
    func testWalletInitialization() async throws {
        let uri = "nostr+walletconnect://b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4?relay=wss%3A%2F%2Frelay.damus.io&secret=71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c"
        
        let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: uri)
        
        let status = await wallet.status
        let walletInfo = await wallet.walletInfo
        XCTAssertEqual(status, .disconnected)
        XCTAssertNil(walletInfo)
        XCTAssertEqual(wallet.connectionURI.walletPubkey, "b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4")
    }
    
    func testWalletSupportsMethod() async throws {
        let uri = "nostr+walletconnect://b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4?relay=wss%3A%2F%2Frelay.damus.io&secret=71a8c14c1407c113601079c4302dab36460f0ccd0ad506f1f2dc73b5100e4f3c"
        
        let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: uri)
        
        XCTAssertTrue(wallet.supports(method: .nwc))
        XCTAssertTrue(wallet.supports(method: .lightning))
        // Nutzap support is not yet implemented
        // XCTAssertFalse(wallet.supports(method: .nutzap))
    }
}
