#!/usr/bin/env swift sh

import Foundation
import NDKSwift

// Simple test script for NIP-17
@main
struct TestNIP17 {
    static func main() async throws {
        print("Testing NIP-17 implementation...")
        
        // Create signers
        let alice = try NDKPrivateKeySigner.generate()
        let bob = try NDKPrivateKeySigner.generate()
        
        let alicePubkey = try await alice.pubkey
        let bobPubkey = try await bob.pubkey
        
        print("Alice: \(alicePubkey)")
        print("Bob: \(bobPubkey)")
        
        // Test basic message
        let message = "Hello Bob, this is a private message!"
        let recipient = NIP17Recipient(pubkey: bobPubkey)
        
        print("\nSending message from Alice to Bob...")
        let wrapped = try await NIP17.sendMessage(
            message,
            to: recipient,
            signer: alice,
            subject: "Test Subject"
        )
        
        print("Wrapped event:")
        print("- Kind: \(wrapped.kind)")
        print("- ID: \(wrapped.id)")
        print("- Author: \(wrapped.pubkey)")
        
        print("\nBob unwrapping message...")
        let unwrapped = try await NIP17.unwrapEvent(wrapped, recipientSigner: bob)
        
        print("Unwrapped event:")
        print("- Kind: \(unwrapped.kind)")
        print("- Author: \(unwrapped.pubkey)")
        print("- Content: \(unwrapped.content)")
        
        let subjectTag = unwrapped.tags.first { $0[0] == "subject" }
        print("- Subject: \(subjectTag?[1] ?? "none")")
        
        print("\n✅ NIP-17 test passed!")
    }
}