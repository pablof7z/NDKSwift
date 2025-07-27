import XCTest
@testable import NDKSwift

final class NWCTests: XCTestCase {
    
    // MARK: - Connection URI Tests
    
    func testParseValidNWCConnectionURI() throws {
        let uri = "nostr+walletconnect://abcd1234?relay=wss://relay.example.com&secret=test_secret"
        let connection = try NWCConnectionURI(uri: uri)
        
        XCTAssertEqual(connection.pubkey, "abcd1234")
        XCTAssertEqual(connection.relay, "wss://relay.example.com")
        XCTAssertEqual(connection.secret, "test_secret")
    }
    
    func testParseNWCConnectionURIWithLudAddress() throws {
        let uri = "nostr+walletconnect://abcd1234?relay=wss://relay.example.com&secret=test_secret&lud16=test@example.com"
        let connection = try NWCConnectionURI(uri: uri)
        
        XCTAssertEqual(connection.pubkey, "abcd1234")
        XCTAssertEqual(connection.relay, "wss://relay.example.com")
        XCTAssertEqual(connection.secret, "test_secret")
        XCTAssertEqual(connection.lud16, "test@example.com")
    }
    
    func testParseInvalidNWCConnectionURI() {
        let invalidURIs = [
            "invalid://abcd1234",
            "nostr+walletconnect://",
            "nostr+walletconnect://abcd1234",  // Missing required params
            "nostr+walletconnect://abcd1234?relay=wss://relay.example.com",  // Missing secret
            "nostr+walletconnect://abcd1234?secret=test_secret"  // Missing relay
        ]
        
        for uri in invalidURIs {
            XCTAssertThrowsError(try NWCConnectionURI(uri: uri)) { error in
                XCTAssertTrue(error is NDKError)
            }
        }
    }
    
    // MARK: - NWC Wallet Initialization Tests
    
    func testNWCWalletInitialization() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let uri = "nostr+walletconnect://abcd1234?relay=wss://relay.example.com&secret=test_secret"
        
        let wallet = try await NDKNWCWallet(ndk: ndk, uri: uri)
        
        XCTAssertEqual(wallet.walletPubkey, "abcd1234")
        XCTAssertEqual(wallet.relayUrl, "wss://relay.example.com")
        XCTAssertNotNil(wallet.connectionSecret)
    }
    
    func testNWCWalletRequiresSigner() async throws {
        let ndk = NDK()  // No signer
        let uri = "nostr+walletconnect://abcd1234?relay=wss://relay.example.com&secret=test_secret"
        
        do {
            _ = try await NDKNWCWallet(ndk: ndk, uri: uri)
            XCTFail("Should throw error when NDK has no signer")
        } catch {
            XCTAssertTrue(error is NDKError)
        }
    }
    
    // MARK: - Request Builder Tests
    
    func testBuildPayInvoiceRequest() throws {
        let invoice = "lnbc100n1pjkl7sdpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypq"
        let request = NWCRequestBuilder.buildPayInvoiceRequest(invoice: invoice)
        
        XCTAssertEqual(request.method, "pay_invoice")
        XCTAssertNotNil(request.params["invoice"] as? String)
        XCTAssertEqual(request.params["invoice"] as? String, invoice)
    }
    
    func testBuildGetBalanceRequest() throws {
        let request = NWCRequestBuilder.buildGetBalanceRequest()
        
        XCTAssertEqual(request.method, "get_balance")
        XCTAssertTrue(request.params.isEmpty)
    }
    
    func testBuildMakeInvoiceRequest() throws {
        let amount = 1000
        let description = "Test invoice"
        let request = NWCRequestBuilder.buildMakeInvoiceRequest(
            amountMsat: amount,
            description: description
        )
        
        XCTAssertEqual(request.method, "make_invoice")
        XCTAssertEqual(request.params["amount"] as? Int, amount)
        XCTAssertEqual(request.params["description"] as? String, description)
    }
    
    func testBuildGetInfoRequest() throws {
        let request = NWCRequestBuilder.buildGetInfoRequest()
        
        XCTAssertEqual(request.method, "get_info")
        XCTAssertTrue(request.params.isEmpty)
    }
    
    // MARK: - Response Handler Tests
    
    func testHandleSuccessfulPaymentResponse() throws {
        let responseContent = """
        {
            "result_type": "pay_invoice",
            "result": {
                "preimage": "test_preimage_12345"
            }
        }
        """
        
        let result = try NWCResponseHandler.parseResponse(responseContent)
        
        switch result {
        case .payInvoice(let preimage):
            XCTAssertEqual(preimage, "test_preimage_12345")
        default:
            XCTFail("Expected payInvoice response")
        }
    }
    
    func testHandleBalanceResponse() throws {
        let responseContent = """
        {
            "result_type": "get_balance",
            "result": {
                "balance": 50000
            }
        }
        """
        
        let result = try NWCResponseHandler.parseResponse(responseContent)
        
        switch result {
        case .getBalance(let balance):
            XCTAssertEqual(balance, 50000)
        default:
            XCTFail("Expected getBalance response")
        }
    }
    
    func testHandleErrorResponse() throws {
        let responseContent = """
        {
            "result_type": "error",
            "error": {
                "code": "RATE_LIMITED",
                "message": "Too many requests"
            }
        }
        """
        
        XCTAssertThrowsError(try NWCResponseHandler.parseResponse(responseContent)) { error in
            guard let nwcError = error as? NWCError else {
                XCTFail("Expected NWCError")
                return
            }
            XCTAssertEqual(nwcError.code, "RATE_LIMITED")
            XCTAssertEqual(nwcError.message, "Too many requests")
        }
    }
    
    // MARK: - Type Tests
    
    func testNWCCapabilities() {
        let capabilities = NWCCapabilities()
        
        // Test default capabilities
        XCTAssertTrue(capabilities.canPayInvoice)
        XCTAssertTrue(capabilities.canMakeInvoice)
        XCTAssertTrue(capabilities.canGetBalance)
        XCTAssertTrue(capabilities.canGetInfo)
        XCTAssertFalse(capabilities.canListTransactions)
        XCTAssertFalse(capabilities.canMultiPay)
    }
    
    func testNWCErrorTypes() {
        let errors: [NWCError] = [
            NWCError(code: "RATE_LIMITED", message: "Too many requests"),
            NWCError(code: "NOT_IMPLEMENTED", message: "Method not supported"),
            NWCError(code: "INSUFFICIENT_BALANCE", message: "Not enough funds"),
            NWCError(code: "PAYMENT_FAILED", message: "Payment failed"),
            NWCError(code: "INTERNAL", message: "Internal error")
        ]
        
        for error in errors {
            XCTAssertFalse(error.code.isEmpty)
            XCTAssertFalse(error.message.isEmpty)
            XCTAssertTrue(error.localizedDescription.contains(error.code))
            XCTAssertTrue(error.localizedDescription.contains(error.message))
        }
    }
}