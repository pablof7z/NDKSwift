# NIP-44 Encryption Guide

NIP-44 is the modern encryption standard for Nostr, providing secure end-to-end encryption for direct messages and other private content. This guide explains how to use NIP-44 encryption in NDKSwift.

## Overview

NIP-44 improves upon the older NIP-04 standard with:
- **ChaCha20** encryption (faster and more secure than AES)
- **HMAC-SHA256** for message authentication
- **HKDF** for key derivation
- **Powers-of-two padding** to obfuscate message length
- **Constant-time operations** to prevent timing attacks

## Basic Usage

### Encrypting a Message

```swift
// Create or load a signer
let signer = try NDKPrivateKeySigner.generate()

// Create recipient user
let recipient = NDKUser(pubkey: "recipient_public_key_hex")

// Encrypt a message
let encrypted = try await signer.encrypt(
    recipient: recipient,
    value: "Hello, this is a secret message!",
    scheme: .nip44
)
```

### Decrypting a Message

```swift
// Create sender user
let sender = NDKUser(pubkey: "sender_public_key_hex")

// Decrypt the message
let decrypted = try await signer.decrypt(
    sender: sender,
    value: encrypted,
    scheme: .nip44
)
```

## Creating Encrypted Events

For direct messages, you'll typically use event kind 14 (proposed for NIP-44 DMs):

```swift
// Initialize NDK with a signer
let ndk = NDK()
ndk.signer = signer

// Encrypt content
let encryptedContent = try await signer.encrypt(
    recipient: recipient,
    value: "Private message content",
    scheme: .nip44
)

// Create encrypted event
let dmEvent = NDKEvent(
    pubkey: try await signer.pubkey,
    createdAt: Timestamp(Date().timeIntervalSince1970),
    kind: 14, // NIP-44 encrypted direct message
    tags: [
        ["p", recipient.pubkey] // Tag the recipient
    ],
    content: encryptedContent
)

// Sign and publish
try await dmEvent.sign(using: signer)
try await ndk.publish(dmEvent)
```

## Low-Level Crypto Functions

For advanced use cases, you can use the low-level crypto functions directly:

### Conversation Key Derivation

```swift
// Derive a shared conversation key between two parties
let conversationKey = try Crypto.nip44GetConversationKey(
    privateKey: alicePrivateKey,
    publicKey: bobPublicKey
)
// Note: Same key is derived by both parties (Alice->Bob = Bob->Alice)
```

### Direct Encryption/Decryption

```swift
// Generate a random nonce
let nonce = Crypto.randomBytes(count: 32)

// Encrypt with conversation key
let encrypted = try Crypto.nip44Encrypt(
    plaintext: "Secret message",
    conversationKey: conversationKey,
    nonce: nonce
)

// Decrypt
let decrypted = try Crypto.nip44Decrypt(
    payload: encrypted,
    conversationKey: conversationKey
)
```

## Security Considerations

1. **Key Management**: Private keys should be stored securely and never exposed
2. **Nonce Generation**: Always use cryptographically secure random nonces
3. **Message Authentication**: NIP-44 includes HMAC authentication - always verify before decrypting
4. **Forward Secrecy**: NIP-44 does not provide forward secrecy - consider this for sensitive communications
5. **Metadata**: Event metadata (timestamps, recipient pubkey) is not encrypted

## Migration from NIP-04

If you're migrating from NIP-04, here are the key differences:

```swift
// Check supported encryption schemes
let schemes = await signer.encryptionEnabled()
// Returns: [.nip04, .nip44]

// NIP-04 (deprecated)
let nip04Encrypted = try await signer.encrypt(
    recipient: recipient,
    value: message,
    scheme: .nip04
)

// NIP-44 (recommended)
let nip44Encrypted = try await signer.encrypt(
    recipient: recipient,
    value: message,
    scheme: .nip44
)
```

Key improvements in NIP-44:
- More secure encryption algorithm (ChaCha20 vs AES)
- Message authentication (HMAC)
- Better padding scheme
- Standardized key derivation

## Error Handling

NIP-44 operations can throw various errors:

```swift
do {
    let encrypted = try await signer.encrypt(
        recipient: recipient,
        value: message,
        scheme: .nip44
    )
} catch Crypto.NIP44Error.unsupportedVersion {
    // Handle unsupported encryption version
} catch Crypto.NIP44Error.invalidMAC {
    // Handle authentication failure
} catch Crypto.NIP44Error.invalidPadding {
    // Handle padding errors
} catch {
    // Handle other errors
}
```

## Example: Encrypted Chat Application

Here's a simple example of using NIP-44 in a chat application:

```swift
class SecureChat {
    let ndk: NDK
    let signer: NDKSigner
    
    init() async throws {
        ndk = NDK()
        signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
    }
    
    func sendMessage(to recipient: NDKUser, message: String) async throws {
        // Encrypt the message
        let encrypted = try await signer.encrypt(
            recipient: recipient,
            value: message,
            scheme: .nip44
        )
        
        // Create and publish encrypted event
        let event = NDKEvent(
            pubkey: try await signer.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 14,
            tags: [["p", recipient.pubkey]],
            content: encrypted
        )
        
        try await event.sign(using: signer)
        try await ndk.publish(event)
    }
    
    func decryptMessage(_ event: NDKEvent) async throws -> String? {
        // Verify it's for us
        guard event.tags(withName: "p").contains(where: { 
            $0.count > 1 && $0[1] == try await signer.pubkey 
        }) else {
            return nil
        }
        
        // Decrypt the content
        let sender = NDKUser(pubkey: event.pubkey)
        return try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
    }
}
```

## Testing

NDKSwift includes comprehensive tests for NIP-44 using the official test vectors:

```bash
swift test --filter NIP44Tests
```

## Resources

- [NIP-44 Specification](https://github.com/nostr-protocol/nips/blob/master/44.md)
- [Test Vectors](https://github.com/paulmillr/nip44)
- [Example Code](../Examples/NIP44Demo.swift)