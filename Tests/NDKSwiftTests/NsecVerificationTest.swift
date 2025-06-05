@testable import NDKSwift
import XCTest

final class NsecVerificationTest: XCTestCase {
    func testNsecToPubkeyConversion() {
        let nsecInput = "nsec1pnfm84sp6ed974zj7qsqqcn692hgnf9s48jk8x0psagucv6yy3ys5qqx7c"
        let expectedPubkey = "2bfe63136e95ef81b137bd814405dfcaeeabd4bab04388f2167318001fb71473"

        do {
            let signer = try NDKPrivateKeySigner(nsec: nsecInput)
            let actualPubkey = try signer.pubkey
            let npub = try signer.npub

            print("✅ Input nsec: \(nsecInput)")
            print("✅ Expected pubkey: \(expectedPubkey)")
            print("✅ Actual pubkey: \(actualPubkey)")
            print("✅ Npub: \(npub)")
            print("✅ Match: \(actualPubkey == expectedPubkey)")

            XCTAssertEqual(actualPubkey, expectedPubkey, "Pubkey should match expected value")
        } catch {
            print("❌ Error in nsec conversion: \(error)")
            XCTFail("Should not fail nsec conversion: \(error)")
        }
    }
}
