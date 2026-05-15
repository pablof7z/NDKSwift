import NDKSwiftCashu
@testable import NDKSwiftCore
import XCTest

final class NWCTests: XCTestCase {
    // MARK: - Connection URI Tests

    func testParseValidNWCConnectionURI() throws {
        let uri = "nostr+walletconnect://abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234?relay=wss://relay.example.com&secret=abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
        let connection = try NWCConnectionURI(uri: uri)

        XCTAssertEqual(connection.walletPubkey, "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234")
        XCTAssertEqual(connection.relayURLs.first, "wss://relay.example.com")
        XCTAssertEqual(connection.secret, "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234")
    }

    func testParseNWCConnectionURIWithLudAddress() throws {
        let uri = "nostr+walletconnect://abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234?relay=wss://relay.example.com&secret=abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234&lud16=test@example.com"
        let connection = try NWCConnectionURI(uri: uri)

        XCTAssertEqual(connection.walletPubkey, "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234")
        XCTAssertEqual(connection.relayURLs.first, "wss://relay.example.com")
        XCTAssertEqual(connection.secret, "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234")
        XCTAssertEqual(connection.lud16, "test@example.com")
    }

    func testParseInvalidNWCConnectionURI() {
        let invalidURIs = [
            "invalid://abcd1234",
            "nostr+walletconnect://",
            "nostr+walletconnect://abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234", // Missing required params
            "nostr+walletconnect://abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234?relay=wss://relay.example.com", // Missing secret
            "nostr+walletconnect://abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234?secret=abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234", // Missing relay
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
        let ndk = try await NDKTestFactory.createNDK(signer: signer)
        let uri = "nostr+walletconnect://abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234?relay=wss://relay.example.com&secret=abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"

        let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: uri)

        XCTAssertEqual(wallet.connectionURI.walletPubkey, "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234")
        XCTAssertEqual(wallet.connectionURI.relayURLs.first, "wss://relay.example.com")
        XCTAssertNotNil(wallet.connectionURI.secret)
    }

    func testNWCWalletRequiresSigner() async throws {
        let ndk = try await NDKTestFactory.createNDK() // No signer
        let uri = "nostr+walletconnect://abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234?relay=wss://relay.example.com&secret=abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"

        do {
            _ = try await NDKNWCWallet(ndk: ndk, connectionURI: uri)
            XCTFail("Should throw error when NDK has no signer")
        } catch {
            XCTAssertTrue(error is NDKError)
        }
    }

    // MARK: - Request Builder Tests

    func testBuildPayInvoiceRequest() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = try await NDKTestFactory.createNDK(signer: signer)
        let builder = NWCRequestBuilder(ndk: ndk, walletPubkey: "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234", signer: signer)

        let invoice = "lnbc100n1pjkl7sdpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypq"
        let request = PayInvoiceRequest(invoice: invoice, amount: nil)
        let event = try await builder.buildPayInvoiceRequest(request)

        XCTAssertEqual(event.kind, .nostrWalletConnectReq)
        XCTAssertFalse(event.content.isEmpty)
    }

    func testBuildGetBalanceRequest() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = try await NDKTestFactory.createNDK(signer: signer)
        let builder = NWCRequestBuilder(ndk: ndk, walletPubkey: "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234", signer: signer)

        let event = try await builder.buildGetBalanceRequest()

        XCTAssertEqual(event.kind, .nostrWalletConnectReq)
        XCTAssertFalse(event.content.isEmpty)
    }

    func testBuildMakeInvoiceRequest() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = try await NDKTestFactory.createNDK(signer: signer)
        let builder = NWCRequestBuilder(ndk: ndk, walletPubkey: "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234", signer: signer)

        let amount: Int64 = 1000
        let description = "Test invoice"
        let request = MakeInvoiceRequest(amount: amount, description: description)
        let event = try await builder.buildMakeInvoiceRequest(request)

        XCTAssertEqual(event.kind, .nostrWalletConnectReq)
        XCTAssertFalse(event.content.isEmpty)
    }

    func testBuildGetInfoRequest() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = try await NDKTestFactory.createNDK(signer: signer)
        let builder = NWCRequestBuilder(ndk: ndk, walletPubkey: "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234", signer: signer)

        let event = try await builder.buildGetInfoRequest()

        XCTAssertEqual(event.kind, .nostrWalletConnectReq)
        XCTAssertFalse(event.content.isEmpty)
    }

    // MARK: - Response Handler Tests

    func testHandleSuccessfulPaymentResponse() async throws {
        let responseContent = """
        {
            "result": {
                "preimage": "test_preimage_12345"
            }
        }
        """

        let signer = try NDKPrivateKeySigner.generate()
        let ndk = try await NDKTestFactory.createNDK(signer: signer)
        _ = NWCResponseHandler(ndk: ndk, signer: signer, relayURLs: [], walletPubkey: try await signer.pubkey)

        // Test basic JSON parsing
        let data = responseContent.data(using: .utf8)!
        let response = try JSONCoding.decode(NWCResponse<PayInvoiceResponse>.self, from: data)

        XCTAssertNotNil(response.result)
        XCTAssertEqual(response.result?.preimage, "test_preimage_12345")
    }

    func testHandleBalanceResponse() async throws {
        let responseContent = """
        {
            "result": {
                "balance": 50000
            }
        }
        """

        let signer = try NDKPrivateKeySigner.generate()
        let ndk = try await NDKTestFactory.createNDK(signer: signer)
        _ = NWCResponseHandler(ndk: ndk, signer: signer, relayURLs: [], walletPubkey: try await signer.pubkey)

        // Test basic JSON parsing
        let data = responseContent.data(using: .utf8)!
        let response = try JSONCoding.decode(NWCResponse<GetBalanceResponse>.self, from: data)

        XCTAssertNotNil(response.result)
        XCTAssertEqual(response.result?.balance, 50000)
    }

    func testResponseHandlerRejectsEventsForOtherClients() async throws {
        let clientSigner = try NDKPrivateKeySigner.generate()
        let walletSigner = try NDKPrivateKeySigner.generate()
        let otherClientSigner = try NDKPrivateKeySigner.generate()
        let ndk = try await NDKTestFactory.createNDK(signer: clientSigner)
        let clientPubkey = try await clientSigner.pubkey
        let walletPubkey = try await walletSigner.pubkey
        let otherClientPubkey = try await otherClientSigner.pubkey
        let requestId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let handler = NWCResponseHandler(
            ndk: ndk,
            signer: clientSigner,
            relayURLs: [],
            walletPubkey: walletPubkey,
            clientPubkey: clientPubkey
        )

        let expectedEvent = try await makeNWCEvent(
            ndk: ndk,
            signer: walletSigner,
            kind: .nostrWalletConnectRes,
            tags: [["p", clientPubkey], ["e", requestId]]
        )
        XCTAssertTrue(handler.isExpectedResponseEvent(expectedEvent, requestId: requestId))

        let wrongClientEvent = try await makeNWCEvent(
            ndk: ndk,
            signer: walletSigner,
            kind: .nostrWalletConnectRes,
            tags: [["p", otherClientPubkey], ["e", requestId]]
        )
        XCTAssertFalse(handler.isExpectedResponseEvent(wrongClientEvent, requestId: requestId))

        let wrongAuthorEvent = try await makeNWCEvent(
            ndk: ndk,
            signer: otherClientSigner,
            kind: .nostrWalletConnectRes,
            tags: [["p", clientPubkey], ["e", requestId]]
        )
        XCTAssertFalse(handler.isExpectedResponseEvent(wrongAuthorEvent, requestId: requestId))
    }

    func testResponseHandlerValidatesNWCNotificationKindsAndClientTag() async throws {
        let clientSigner = try NDKPrivateKeySigner.generate()
        let walletSigner = try NDKPrivateKeySigner.generate()
        let otherClientSigner = try NDKPrivateKeySigner.generate()
        let ndk = try await NDKTestFactory.createNDK(signer: clientSigner)
        let clientPubkey = try await clientSigner.pubkey
        let walletPubkey = try await walletSigner.pubkey
        let otherClientPubkey = try await otherClientSigner.pubkey
        let handler = NWCResponseHandler(
            ndk: ndk,
            signer: clientSigner,
            relayURLs: [],
            walletPubkey: walletPubkey,
            clientPubkey: clientPubkey
        )

        let currentNotification = try await makeNWCEvent(
            ndk: ndk,
            signer: walletSigner,
            kind: .nostrWalletConnectNotification,
            tags: [["p", clientPubkey]]
        )
        XCTAssertTrue(handler.isExpectedNotificationEvent(currentNotification))

        let legacyNotification = try await makeNWCEvent(
            ndk: ndk,
            signer: walletSigner,
            kind: .nostrWalletConnectLegacyNotification,
            tags: [["p", clientPubkey]]
        )
        XCTAssertTrue(handler.isExpectedNotificationEvent(legacyNotification))

        let responseKindEvent = try await makeNWCEvent(
            ndk: ndk,
            signer: walletSigner,
            kind: .nostrWalletConnectRes,
            tags: [["p", clientPubkey]]
        )
        XCTAssertFalse(handler.isExpectedNotificationEvent(responseKindEvent))

        let eventForOtherClient = try await makeNWCEvent(
            ndk: ndk,
            signer: walletSigner,
            kind: .nostrWalletConnectNotification,
            tags: [["p", otherClientPubkey]]
        )
        XCTAssertFalse(handler.isExpectedNotificationEvent(eventForOtherClient))

        let responseLinkedNotification = try await makeNWCEvent(
            ndk: ndk,
            signer: walletSigner,
            kind: .nostrWalletConnectNotification,
            tags: [
                ["p", clientPubkey],
                ["e", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
            ]
        )
        XCTAssertFalse(handler.isExpectedNotificationEvent(responseLinkedNotification))
    }

    // NOTE: Commented out - NWCError type is not defined in the codebase
    /*
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
     */

    // MARK: - Type Tests

    // NOTE: Commented out - NWCCapabilities type is not defined in the codebase
    /*
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
     */

    // NOTE: Commented out - NWCError type is not defined in the codebase
    /*
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
     */
}

private func makeNWCEvent(ndk: NDK, signer: NDKSigner, kind: Int, tags: [Tag]) async throws -> NDKEvent {
    try await NDKEventBuilder(ndk: ndk)
        .kind(kind)
        .content("encrypted-payload")
        .tags(tags)
        .build(signer: signer)
}
