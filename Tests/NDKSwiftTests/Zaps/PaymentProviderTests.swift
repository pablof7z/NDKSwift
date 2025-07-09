import XCTest
@testable import NDKSwift

final class PaymentProviderTests: XCTestCase {
    
    // MARK: - NWC Payment Provider Tests
    
    func testNWCProviderCanFulfillLightningInvoices() async throws {
        let nwcWallet = try NDKNWCWallet(connectionURI: "nostr+walletconnect://...")
        let provider = NWCPaymentProvider(nwcWallet: nwcWallet)
        
        let invoiceRequest = LightningInvoiceRequest(
            bolt11: "lnbc1000n1...",
            amountSats: 1000,
            callbackURL: "https://wallet.com/callback"
        )
        
        let canFulfill = await provider.canFulfill(invoiceRequest)
        XCTAssertTrue(canFulfill)
    }
    
    func testNWCProviderCannotFulfillCashuRequests() async throws {
        let nwcWallet = try NDKNWCWallet(connectionURI: "nostr+walletconnect://...")
        let provider = NWCPaymentProvider(nwcWallet: nwcWallet)
        
        let cashuRequest = CashuProofRequest(
            amount: 1000,
            mint: "https://mint.com",
            unit: "sat",
            p2pkPubkey: "pubkey"
        )
        
        let canFulfill = await provider.canFulfill(cashuRequest)
        XCTAssertFalse(canFulfill)
    }
    
    // MARK: - QR Code Payment Provider Tests
    
    func testQRCodeProviderCanFulfillAnyRequest() async throws {
        let provider = QRCodePaymentProvider()
        
        // Test Lightning
        let invoiceRequest = LightningInvoiceRequest(
            bolt11: "lnbc1000n1...",
            amountSats: 1000,
            callbackURL: "https://wallet.com/callback"
        )
        XCTAssertTrue(await provider.canFulfill(invoiceRequest))
        
        // Test Cashu
        let cashuRequest = CashuProofRequest(
            amount: 1000,
            mint: "https://mint.com",
            unit: "sat",
            p2pkPubkey: "pubkey"
        )
        XCTAssertTrue(await provider.canFulfill(cashuRequest))
    }
    
    func testQRCodeProviderUsesCustomHandlers() async throws {
        var displayCalled = false
        var confirmCalled = false
        var displayedData: String?
        
        let provider = QRCodePaymentProvider(
            displayQRCode: { data in
                displayCalled = true
                displayedData = data
            },
            confirmPayment: {
                confirmCalled = true
                return true
            }
        )
        
        let request = LightningInvoiceRequest(
            bolt11: "lnbc1000n1...",
            amountSats: 1000,
            callbackURL: ""
        )
        
        let confirmation = try await provider.fulfill(request)
        
        XCTAssertTrue(displayCalled)
        XCTAssertTrue(confirmCalled)
        XCTAssertEqual(displayedData, "lnbc1000n1...")
        XCTAssertTrue(confirmation is ManualPaymentConfirmation)
    }
    
    func testQRCodeProviderHandlesRejection() async throws {
        let provider = QRCodePaymentProvider(
            displayQRCode: { _ in },
            confirmPayment: { false } // User rejects
        )
        
        let request = LightningInvoiceRequest(
            bolt11: "lnbc1000n1...",
            amountSats: 1000,
            callbackURL: ""
        )
        
        do {
            _ = try await provider.fulfill(request)
            XCTFail("Expected error")
        } catch {
            guard case NDKError.userCancelled = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
        }
    }
    
    // MARK: - Wallet Adapter Provider Tests
    
    func testWalletAdapterBridgesLegacyWallet() async throws {
        let mockWallet = MockWallet()
        let provider = WalletAdapterPaymentProvider(wallet: mockWallet)
        
        // Should fulfill Lightning requests
        let invoiceRequest = LightningInvoiceRequest(
            bolt11: "lnbc1000n1...",
            amountSats: 1000,
            callbackURL: ""
        )
        
        let canFulfill = await provider.canFulfill(invoiceRequest)
        XCTAssertTrue(canFulfill)
        
        let confirmation = try await provider.fulfill(invoiceRequest)
        guard let lightningConfirmation = confirmation as? LightningPaymentConfirmation else {
            XCTFail("Expected LightningPaymentConfirmation")
            return
        }
        
        XCTAssertEqual(lightningConfirmation.preimage, "mock-preimage")
    }
    
    func testWalletAdapterHandlesCashuWallets() async throws {
        let mockWallet = MockCashuWallet()
        let provider = WalletAdapterPaymentProvider(wallet: mockWallet)
        
        // Should fulfill Cashu requests if wallet supports it
        let cashuRequest = CashuProofRequest(
            amount: 1000,
            mint: "https://mint.com",
            unit: "sat",
            p2pkPubkey: "pubkey"
        )
        
        let canFulfill = await provider.canFulfill(cashuRequest)
        XCTAssertTrue(canFulfill)
        
        let confirmation = try await provider.fulfill(cashuRequest)
        guard let cashuConfirmation = confirmation as? CashuPaymentConfirmation else {
            XCTFail("Expected CashuPaymentConfirmation")
            return
        }
        
        XCTAssertEqual(cashuConfirmation.proofs.count, 1)
        XCTAssertEqual(cashuConfirmation.proofs.first?.amount, 1000)
    }
}

// MARK: - Mock Cashu Wallet

class MockCashuWallet: NDKWallet, @unchecked Sendable {
    var pubkey: String? = "mock-cashu-wallet"
    
    func balance() async throws -> Int64 {
        5000
    }
    
    func pay(invoice: String) async throws -> String? {
        nil // Can't pay Lightning invoices
    }
    
    func createInvoice(amountSats: Int64, description: String?, expirySeconds: Int?) async throws -> String {
        throw NDKError.notImplemented
    }
    
    func checkInvoice(_ invoice: String) async throws -> InvoiceStatus {
        throw NDKError.notImplemented
    }
    
    func cashuTokens() async throws -> [CashuToken] {
        [CashuToken(token: [], unit: "sat")]
    }
    
    func createCashuToken(amount: Int64, unit: String, mint: String) async throws -> CashuToken {
        // Create P2PK-locked token
        return CashuToken(token: [], unit: unit)
    }
    
    func redeemCashuToken(_ token: CashuToken) async throws -> Int64 {
        1000
    }
}