import Foundation
import CashuSwift
@testable import NDKSwift

/// A wrapper around NDKCashuWallet that provides testing utilities
/// Since actors don't support inheritance, we use composition
class TestableWalletWrapper {
    let wallet: NDKCashuWallet
    let ndk: NDK
    
    init(ndk: NDK) {
        self.ndk = ndk
        self.wallet = NDKCashuWallet(ndk: ndk)
    }
    
    /// Add a test mint without network calls
    func addTestMint(url: URL) async throws {
        // Create keyset data
        let keysetData = """
        {
            "id": "\(url.host ?? "test")_keyset",
            "unit": "sat",
            "active": true,
            "input_fee_ppk": 0,
            "keys": {
                "1": "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2",
                "2": "0324653eac434488002cc06bbfb7f10fe18991e35f9fe4302dbea6d2353dc0ab1c",
                "4": "027f31ebc5462c1fdce1b737ecff52d37d75dea43ce11c74d25aa297165faa2007",
                "8": "031b84c5567b126440995d3ed5aaba0565d71e1834604819ff9c17f5e9d5dd078f"
            }
        }
        """.data(using: .utf8)!
        
        let testKeyset = try JSONDecoder().decode(CashuSwift.Keyset.self, from: keysetData)
        let mint = CashuSwift.Mint(url: url, keysets: [testKeyset])
        
        // Access wallet's internal properties for testing
        await wallet.setTestMint(mint, for: url)
        await wallet.setTestKeyset(testKeyset)
    }
    
    /// Add test proofs without network operations
    func addTestProofs(_ proofs: [CashuSwift.Proof], mintURL: String) async throws {
        // Ensure we have the mint
        if await wallet.getMint(for: URL(string: mintURL)!) == nil {
            try await addTestMint(url: URL(string: mintURL)!)
        }
        
        // Add proofs using the receive method
        try await wallet.receive(proofs: proofs)
    }
}

/// Extension to NDKCashuWallet for test access
/// This uses @testable import to access internal properties
extension NDKCashuWallet {
    /// Test helper to directly set a mint
    func setTestMint(_ mint: CashuSwift.Mint, for url: URL) async {
        mints[url.absoluteString] = mint
    }
    
    /// Test helper to directly set a keyset
    func setTestKeyset(_ keyset: CashuSwift.Keyset) async {
        keysets[keyset.keysetID] = keyset
    }
    
    /// Test helper to get a mint
    func getMint(for url: URL) async -> CashuSwift.Mint? {
        return mints[url.absoluteString]
    }
}

/// Test helpers for creating mock Cashu data
struct CashuTestHelpers {
    
    /// Create a test proof with reasonable defaults
    static func createProof(
        amount: Int,
        keysetID: String? = nil,
        mint: String = "https://test.mint"
    ) -> CashuSwift.Proof {
        // Use the mint's host to generate a consistent keyset ID
        let mintURL = URL(string: mint)!
        let defaultKeysetID = "\(mintURL.host ?? "test")_keyset"
        
        return CashuSwift.Proof(
            keysetID: keysetID ?? defaultKeysetID,
            amount: amount,
            secret: "secret_\(UUID().uuidString)",
            C: "C_\(UUID().uuidString)"
        )
    }
    
    /// Create multiple test proofs with a distribution
    static func createProofs(
        amounts: [Int],
        keysetID: String? = nil,
        mint: String = "https://test.mint"
    ) -> [CashuSwift.Proof] {
        return amounts.map { amount in
            createProof(amount: amount, keysetID: keysetID, mint: mint)
        }
    }
    
    /// Create a test token
    static func createToken(
        proofs: [CashuSwift.Proof],
        mint: String = "https://test.mint"
    ) -> CashuSwift.Token {
        return CashuSwift.Token(
            proofs: [mint: proofs],
            unit: "sat"
        )
    }
}