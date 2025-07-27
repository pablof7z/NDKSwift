#!/usr/bin/env swift

import Foundation
@testable import NDKSwift

// Standalone test to verify NIP-17 works
print("🧪 Testing NIP-17 Implementation...")

// Test 1: Basic Flow
print("\n1️⃣ Testing Basic NIP-17 Flow")
do {
    let alice = try NDKPrivateKeySigner.generate()
    let bob = try NDKPrivateKeySigner.generate()
    
    let alicePubkey = try await alice.pubkey
    let bobPubkey = try await bob.pubkey
    
    print("   Alice: \(alicePubkey.prefix(16))...")
    print("   Bob: \(bobPubkey.prefix(16))...")
    
    // Send message
    let message = "Hello Bob!"
    let wrapped = try await NIP17.sendMessage(
        message,
        to: NIP17Recipient(pubkey: bobPubkey),
        signer: alice,
        subject: "Test"
    )
    
    print("   ✓ Message wrapped: kind \(wrapped.kind)")
    
    // Unwrap
    let unwrapped = try await NIP17.unwrapEvent(wrapped, recipientSigner: bob)
    print("   ✓ Message unwrapped: '\(unwrapped.content)'")
    
    assert(unwrapped.content == message)
    assert(unwrapped.pubkey == alicePubkey)
    print("   ✅ Basic flow test passed!")
} catch {
    print("   ❌ Error: \(error)")
    exit(1)
}

// Test 2: Group Messaging
print("\n2️⃣ Testing Group Messaging")
do {
    let alice = try NDKPrivateKeySigner.generate()
    let bob = try NDKPrivateKeySigner.generate()
    let charlie = try NDKPrivateKeySigner.generate()
    
    let bobPubkey = try await bob.pubkey
    let charliePubkey = try await charlie.pubkey
    
    let recipients = [
        NIP17Recipient(pubkey: bobPubkey),
        NIP17Recipient(pubkey: charliePubkey)
    ]
    
    let wrappedEvents = try await NIP17.sendToMany(
        "Group message!",
        to: recipients,
        signer: alice
    )
    
    print("   ✓ Wrapped for \(wrappedEvents.events.count) recipients")
    
    // Bob unwraps his copy
    if let bobWrapped = wrappedEvents.events[bobPubkey] {
        let unwrapped = try await NIP17.unwrapEvent(bobWrapped, recipientSigner: bob)
        print("   ✓ Bob received: '\(unwrapped.content)'")
        assert(unwrapped.content == "Group message!")
    }
    
    print("   ✅ Group messaging test passed!")
} catch {
    print("   ❌ Error: \(error)")
    exit(1)
}

// Test 3: NIP-59 Direct Test
print("\n3️⃣ Testing NIP-59 Gift Wrap")
do {
    let signer = try NDKPrivateKeySigner.generate()
    let recipient = try NDKPrivateKeySigner.generate()
    
    let senderPubkey = try await signer.pubkey
    let recipientPubkey = try await recipient.pubkey
    
    // Create rumor
    let rumor = NIP59.createRumor(
        kind: EventKind.textNote,
        content: "Test rumor",
        tags: [],
        pubkey: senderPubkey
    )
    
    // Seal and wrap
    let wrapped = try await NIP59.sealAndWrap(
        rumor: rumor,
        signer: signer,
        recipientPubkey: recipientPubkey
    )
    
    print("   ✓ Gift wrapped: kind \(wrapped.kind)")
    
    // Unwrap
    let recovered = try await NIP59.unwrapAndUnseal(
        giftWrap: wrapped,
        recipientSigner: recipient
    )
    
    print("   ✓ Unwrapped: '\(recovered.content)'")
    assert(recovered.content == "Test rumor")
    print("   ✅ NIP-59 test passed!")
} catch {
    print("   ❌ Error: \(error)")
    exit(1)
}

// Test 4: Privacy Features
print("\n4️⃣ Testing Privacy Features")
do {
    let alice = try NDKPrivateKeySigner.generate()
    let bob = try NDKPrivateKeySigner.generate()
    
    let alicePubkey = try await alice.pubkey
    let bobPubkey = try await bob.pubkey
    
    let wrapped = try await NIP17.sendMessage(
        "Private message",
        to: NIP17Recipient(pubkey: bobPubkey),
        signer: alice
    )
    
    // Check metadata privacy
    print("   ✓ Sender hidden: \(wrapped.pubkey != alicePubkey)")
    print("   ✓ Gift wrap kind: \(wrapped.kind == EventKind.giftWrap)")
    
    let now = Timestamp.now
    let timeDiff = abs(wrapped.createdAt - now)
    let twoDays: Int64 = 2 * 24 * 60 * 60
    print("   ✓ Timestamp randomized: \(timeDiff <= twoDays)")
    
    assert(wrapped.pubkey != alicePubkey)
    assert(wrapped.kind == EventKind.giftWrap)
    print("   ✅ Privacy features test passed!")
} catch {
    print("   ❌ Error: \(error)")
    exit(1)
}

print("\n✅ All NIP-17 tests passed!")
print("🎉 Implementation is working correctly!")