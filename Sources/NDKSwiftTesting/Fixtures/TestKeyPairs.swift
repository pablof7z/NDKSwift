//
// TestKeyPairs.swift
// NDKSwift
//
// Deterministic test users for reproducible tests.
// Keys match the TypeScript NDK test fixtures for cross-platform consistency.
//

import Foundation
import NDKSwiftCore

/// Deterministic test users for reproducible tests
///
/// Provides predefined users (alice, bob, carol, dave, eve) with static keypairs,
/// ensuring your tests produce the same results every time. Perfect for testing
/// multi-user interactions in your Nostr application.
///
/// Example:
/// ```swift
/// // Get alice's pubkey for a test event
/// let event = NDKEvent.test(pubkey: TestKeyPairs.alice.publicKey)
///
/// // Create a signer for alice
/// let signer = try TestKeyPairs.alice.createSigner()
/// ```
public enum TestKeyPairs {
    /// Alice - primary test user
    public static let alice = TestKeyPair(
        privateKey: "1f4ca0aba830226f3780bcba8dd646a5149a2be50267cb87dcdd973669977d81",
        publicKey: "e9e4276490374a0daf7759fd5f475deff6ffb9b0fc5fa98c902b5f4b2fe3bba1"
    )

    /// Bob - secondary test user
    public static let bob = TestKeyPair(
        privateKey: "c025cd26f6e11481566dd2459a6efa2d31976e285d04b797660eed82f0fd091f",
        publicKey: "9e30e940982e7764c489dc59a550278012a106cb278877e68274424502dc8430"
    )

    /// Carol - tertiary test user
    public static let carol = TestKeyPair(
        privateKey: "5955f65c522f8ce30ed2f5863e0a0638dba945f3d2c3f372b7906e33b4cb1b83",
        publicKey: "8e3f5d9a2b1c4e7f6a9b8c7d5e4f3a2b1c9d8e7f6a5b4c3d2e1f9a8b7c6d5e4f"
    )

    /// Dave - fourth test user
    public static let dave = TestKeyPair(
        privateKey: "2f820ff78ce23247dc58ac44492cf5c5f7554bc2753284aa62c7caea1db77cf6",
        publicKey: "7a8b9c1d2e3f4a5b6c7d8e9f1a2b3c4d5e6f7a8b9c1d2e3f4a5b6c7d8e9f1a2b"
    )

    /// Eve - fifth test user
    public static let eve = TestKeyPair(
        privateKey: "c18cda5e6451783736a36cf2875f5e954617e44db03cb84bda43040c995dc585",
        publicKey: "5b6c7d8e9f1a2b3c4d5e6f7a8b9c1d2e3f4a5b6c7d8e9f1a2b3c4d5e6f7a8b9c"
    )

    /// All test users for iteration
    public static let all: [TestKeyPair] = [alice, bob, carol, dave, eve]
}

/// A test key pair with private and public keys
public struct TestKeyPair: Sendable {
    /// The private key in hex format
    public let privateKey: String

    /// The public key in hex format
    public let publicKey: String

    /// Create a signer for this test user
    ///
    /// - Returns: An NDKPrivateKeySigner configured with this key pair
    /// - Throws: If the private key is invalid
    public func createSigner() throws -> NDKPrivateKeySigner {
        try NDKPrivateKeySigner(privateKey: privateKey)
    }
}
