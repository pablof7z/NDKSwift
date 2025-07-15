import XCTest
@testable import NDKSwift

final class SignerSerializationTest: XCTestCase {
    
    func testPrivateKeySignerSerializationBug() async throws {
        print("\n=== Reproducing the Serialization Bug ===")
        
        // Step 1: Register the signers (should happen automatically)
        let registry = NDKSignerRegistry.shared
        print("Registered types: \(registry.getRegisteredSignerTypes())")
        
        // Step 2: Create and serialize a private key signer
        let privateKey = Crypto.generatePrivateKey()
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        
        print("\nSerializing signer...")
        let serializedData = try await signer.serialize()
        
        print("Serialized data length: \(serializedData.count)")
        if let json = String(data: serializedData, encoding: .utf8) {
            print("Serialized JSON: \(json)")
        }
        
        // Step 3: Try to deserialize (THIS IS WHERE IT FAILS)
        print("\nDeserializing signer...")
        
        do {
            let deserializedSigner = try registry.createSigner(from: serializedData)
            print("✅ Success! Deserialized signer")
            
            // Verify pubkeys match
            let originalPubkey = try await signer.pubkey
            let deserializedPubkey = try await deserializedSigner.pubkey
            XCTAssertEqual(originalPubkey, deserializedPubkey)
        } catch {
            print("❌ Failed to deserialize: \(error)")
            
            // Let's manually check what's wrong
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("Missing key: '\(key)'")
                    print("Context: \(context.debugDescription)")
                    
                    // Try to decode manually to see structure
                    if let jsonObject = try? JSONSerialization.jsonObject(with: serializedData) as? [String: Any] {
                        print("Actual JSON structure: \(jsonObject.keys)")
                    }
                default:
                    print("Other decoding error: \(decodingError)")
                }
            }
            
            throw error
        }
    }
}