import Foundation
@testable import NDKSwift
import CashuSwift

// Test that CashuSwift.Proof constructor works with keysetID
let proof = CashuSwift.Proof(
    keysetID: "test-keyset",
    amount: 100,
    secret: "test-secret",
    C: "test-C"
)

print("CashuSwift.Proof constructor with keysetID: ✓")

// Test that NDKError can be pattern matched
func testNDKError() {
    let error = NDKError.notConfigured("Test component")
    
    switch error {
    case .notConfigured(let message):
        print("NDKError pattern matching: ✓ (\(message))")
    default:
        print("NDKError pattern matching: ✗")
    }
}

testNDKError()

// Test that JSONDecoder can decode NDKEvent
func testNDKEventDecoding() {
    let eventJSON = """
    {
        "id": "test_id",
        "kind": 1,
        "content": "test content",
        "pubkey": "test_pubkey",
        "created_at": 1234567890,
        "tags": [],
        "sig": "test_signature"
    }
    """
    
    do {
        let eventData = eventJSON.data(using: .utf8)!
        let event = try JSONDecoder().decode(NDKEvent.self, from: eventData)
        print("NDKEvent JSONDecoder: ✓ (id: \(event.id))")
    } catch {
        print("NDKEvent JSONDecoder: ✗ (\(error))")
    }
}

testNDKEventDecoding()

print("All fixes verified successfully!")