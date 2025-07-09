import Foundation
import NDKSwift
import CashuSwift

// Minimal test of Cashu functionality
@main
struct SimpleCashuTest {
    static func main() async {
        print("🏃 Starting Simple Cashu Test...")
        
        do {
            // Create components directly
            let proofManager = CashuProofManager()
            let p2pkManager = P2PKManager()
            
            // Test proof management
            let testProof = CashuProof(
                id: "009a1f293253e41e",
                amount: 64,
                secret: "test-secret-123",
                C: "02c020067db727d586bc3183aecf97fcb800c3f4cc4759f69c626c9db5d8f5b5d4"
            )
            
            await proofManager.addProofs([testProof], mint: "https://testnut.cashu.space")
            
            let available = await proofManager.getAvailableProofs()
            print("✅ Added proof, available count: \(available.count)")
            
            // Test P2PK
            let (privKey, pubKey) = try await p2pkManager.getOrCreateKeypair()
            print("✅ Generated P2PK keypair, pubkey: \(pubKey)")
            
            // Test CashuSwift mint connection
            guard let mintURL = URL(string: "https://testnut.cashu.space") else {
                throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            let mint = CashuSwift.Mint(url: mintURL)
            print("✅ Created CashuSwift mint: \(mint.url)")
            
            // Try to get mint info
            do {
                let info = try await mint.info()
                print("✅ Got mint info: \(info.name)")
            } catch {
                print("⚠️ Could not fetch mint info: \(error)")
            }
            
            print("\n🎉 Simple Cashu test completed successfully!")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}