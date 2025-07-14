import Foundation

struct TestKeys {
    // Alice's keys
    static let alicePrivateKey = "5dab4439106cf3d98a77b18835a5c830dfa1cb2d08c6a7ea7a3b0de0e35b47f7"
    static let alicePublicKey = "8ffdc77eda1e6483816d199b5f7937693c9bfed98f1389eade9d332423a77b0e"
    
    // Bob's keys
    static let bobPrivateKey = "7d4c4d5f4a94da4898d7b6ab2d7cb0be6e74e374cd2fd9fde8bc506b41c61a3e"
    static let bobPublicKey = "477318cfb5427b9cfc66a9fa376150c1ddbc62115ae27cef72417eb959691396"
    
    // Charlie's keys
    static let charliePrivateKey = "8e4d3c5b2a1f6d8e7c9b0a5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d"
    static let charliePublicKey = "ee11a5dff40c19a555f41fe42b48f00e618c91225622ae37b6c2bb67b76c4e49"
    
    // Invalid keys for testing error cases
    static let invalidPrivateKey = "invalid_key"
    static let invalidPublicKey = "zzz"
    static let tooShortKey = "abc123"
    static let tooLongKey = String(repeating: "a", count: 128)
    
    // Key in different formats - these will be computed dynamically in tests
    // static let nsecKey = "nsec1..."  // Alice's private key in nsec format
    // static let npubKey = "npub1..."  // Alice's public key in npub format
}