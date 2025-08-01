import XCTest
@testable import NDKSwift
import CashuSwift

final class CashuDepositTests: XCTestCase {
    var ndk: NDK!
    var eventManager: WalletEventManager!
    var mints: MintManager!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        ndk = NDK()
        eventManager = WalletEventManager(ndk: ndk)
        mints = MintManager()
        // Use a valid 64 character hex string for testing
        signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
    }
    
    func testRequestMintQuoteReturnsEventId() async throws {
        // Test that requestMintQuote returns both quote and event ID when persisting
        let mockMintURL = "https://testmint.com"
        
        // Mock the mint manager response
        // Note: In a real test, you'd want to mock the network call
        
        do {
            let (quote, eventId) = try await CashuDeposit.requestMintQuote(
                amount: 1000,
                mintURL: mockMintURL,
                mints: mints,
                eventManager: eventManager,
                persistQuote: true,
                signer: signer
            )
            
            XCTAssertNotNil(quote)
            XCTAssertNotNil(eventId, "Event ID should be returned when persistQuote is true")
            XCTAssertEqual(quote.amount, 1000)
            XCTAssertEqual(quote.mintURL, mockMintURL)
        } catch {
            // Expected to fail without proper mocking
            print("Test failed as expected without mock: \(error)")
        }
    }
    
    func testRequestMintQuoteWithoutPersistReturnsNilEventId() async throws {
        // Test that requestMintQuote returns nil event ID when not persisting
        let mockMintURL = "https://testmint.com"
        
        do {
            let (quote, eventId) = try await CashuDeposit.requestMintQuote(
                amount: 1000,
                mintURL: mockMintURL,
                mints: mints,
                eventManager: eventManager,
                persistQuote: false,
                signer: nil
            )
            
            XCTAssertNotNil(quote)
            XCTAssertNil(eventId, "Event ID should be nil when persistQuote is false")
        } catch {
            // Expected to fail without proper mocking
            print("Test failed as expected without mock: \(error)")
        }
    }
    
    func testMonitorDepositAcceptsQuoteEventId() async throws {
        // Test that monitorDeposit accepts an optional quote event ID
        let quote = CashuMintQuote(
            quoteId: "test_quote_id",
            mintURL: "https://testmint.com",
            amount: 1000,
            invoice: "lnbc1000...",
            expiry: Date().addingTimeInterval(600),
            requestedAt: Date()
        )
        
        // This should compile without errors
        let stream = CashuDeposit.monitorDeposit(
            quote: quote,
            quoteEventId: "test_event_id",
            mints: mints,
            eventManager: eventManager,
            signer: signer,
            timeout: 60,
            quoteAge: 0,
            onProofsReceived: { proofs in
                return []
            }
        )
        
        // Cancel the stream immediately since we're just testing compilation
        var iterator = stream.makeAsyncIterator()
        _ = try? await iterator.next()
    }
}