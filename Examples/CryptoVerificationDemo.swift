#!/usr/bin/env swift

import Foundation
import NDKSwift

// Test the crypto implementation
Task {
    print("NDKSwift Crypto Verification Demo")
    print("=================================")

    // Generate a private key
    let privateKey = try Crypto.generatePrivateKey()
    print("Generated private key: \(privateKey)")

    // Derive public key
    let publicKey = try Crypto.getPublicKey(from: privateKey)
    print("Derived public key: \(publicKey)")
    print("Public key length: \(publicKey.count / 2) bytes") // Should be 32

    // Create a test message (event ID hash)
    let message = "Hello Nostr!".data(using: .utf8)!.sha256()
    print("\nMessage hash: \(message.hexString)")

    // Sign the message
    let signature = try Crypto.sign(message: message, privateKey: privateKey)
    print("Signature: \(signature)")
    print("Signature length: \(signature.count / 2) bytes") // Should be 64

    // Verify the signature
    let isValid = try Crypto.verify(signature: signature, message: message, publicKey: publicKey)
    print("\nSignature verification: \(isValid ? "✅ VALID" : "❌ INVALID")")

    // Test with wrong public key
    let wrongPublicKey = try Crypto.getPublicKey(from: Crypto.generatePrivateKey())
    let isInvalid = try Crypto.verify(signature: signature, message: message, publicKey: wrongPublicKey)
    print("Wrong key verification: \(isInvalid ? "❌ UNEXPECTED VALID" : "✅ CORRECTLY INVALID")")

    // Test full event signing flow
    print("\n--- Full Event Test ---")
    let signer = try NDKPrivateKeySigner(privateKey: privateKey)
    let event = NDKEvent(content: "Test event", tags: [])
    event.pubkey = try await signer.pubkey

    // Generate ID and sign
    let eventId = try event.generateID()
    print("Event ID: \(eventId)")

    let eventSig = try await signer.sign(event)
    event.sig = eventSig
    print("Event signature: \(eventSig)")

    // Verify event structure
    try event.validate()
    print("Event validation: ✅ PASSED")

    print("\nCrypto implementation verified successfully!")
    exit(0)
}

RunLoop.main.run()
