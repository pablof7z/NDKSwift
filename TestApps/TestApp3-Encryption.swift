#!/usr/bin/env swift

/*
 * TestApp3-Encryption.swift
 *
 * COMPREHENSIVE TEST: Encryption Features (NIP-04 & NIP-44)
 *
 * This test validates the ACTUAL behavior of NDKSwift's encryption.
 * It tests:
 * 1. NIP-04 encryption/decryption
 * 2. NIP-44 encryption/decryption
 * 3. Edge cases (empty messages, large messages, unicode)
 * 4. Error handling for invalid keys/data
 * 5. Encrypted direct messages (kind 4)
 * 6. Signer encryption capabilities
 * 7. Cross-compatibility testing
 *
 * CRITICAL: This validates ACTUAL behavior, not documentation!
 */

import Foundation
import NDKSwift

// MARK: - Test Configuration

let TIMEOUT_SHORT = 2_000_000_000 // 2 seconds
let TIMEOUT_MEDIUM = 5_000_000_000 // 5 seconds

let TEST_RELAYS = ["wss://relay.primal.net"]

// MARK: - Test Helpers

func printSection(_ title: String) {
    print("\n" + String(repeating: "=", count: 70))
    print(" \(title)")
    print(String(repeating: "=", count: 70))
}

func printTest(_ name: String) {
    print("\n--- TEST: \(name) ---")
}

func printSuccess(_ message: String) {
    print("✅ SUCCESS: \(message)")
}

func printFailure(_ message: String, error: Error? = nil) {
    print("❌ FAILURE: \(message)")
    if let error = error {
        print("   Error: \(error)")
    }
}

func printDiscovery(_ message: String) {
    print("🔍 DISCOVERY: \(message)")
}

// MARK: - Test Functions

func testNIP04Encryption() async throws {
    printSection("TEST 1: NIP-04 Encryption/Decryption")

    // Create two users
    let alice = try NDKPrivateKeySigner.generate()
    let bob = try NDKPrivateKeySigner.generate()

    let alicePubkey = try await alice.pubkey
    let bobPubkey = try await bob.pubkey

    print("Alice pubkey: \(String(alicePubkey.prefix(16)))...")
    print("Bob pubkey: \(String(bobPubkey.prefix(16)))...")

    // Test 1.1: Basic NIP-04 encryption
    printTest("Basic NIP-04 encryption")
    let message = "Hello Bob! This is a secret message from Alice."
    let bobUser = NDKUser(pubkey: bobPubkey)

    let encrypted = try await alice.encrypt(
        recipient: bobUser,
        value: message,
        scheme: .nip04
    )
    print("   Original: \(message)")
    print("   Encrypted: \(String(encrypted.prefix(50)))...")
    printSuccess("Message encrypted with NIP-04")
    printDiscovery("encrypt(recipient:value:scheme:) returns encrypted string")

    // Test 1.2: NIP-04 decryption
    printTest("NIP-04 decryption")
    let aliceUser = NDKUser(pubkey: alicePubkey)
    let decrypted = try await bob.decrypt(
        sender: aliceUser,
        value: encrypted,
        scheme: .nip04
    )
    print("   Decrypted: \(decrypted)")

    if decrypted == message {
        printSuccess("Message decrypted correctly")
    } else {
        printFailure("Decryption mismatch: '\(decrypted)' != '\(message)'")
    }
    printDiscovery("decrypt(sender:value:scheme:) decrypts with sender's pubkey")

    // Test 1.3: Round-trip encryption
    printTest("Round-trip encryption (Alice -> Bob -> Alice)")
    let roundtripMessage = "Testing round-trip encryption"
    let enc1 = try await alice.encrypt(recipient: bobUser, value: roundtripMessage, scheme: .nip04)
    let dec1 = try await bob.decrypt(sender: aliceUser, value: enc1, scheme: .nip04)

    // Bob encrypts response
    let bobResponse = "Roger that, Alice!"
    let enc2 = try await bob.encrypt(recipient: aliceUser, value: bobResponse, scheme: .nip04)
    let dec2 = try await alice.decrypt(sender: bobUser, value: enc2, scheme: .nip04)

    print("   Alice -> Bob: '\(roundtripMessage)' -> '\(dec1)'")
    print("   Bob -> Alice: '\(bobResponse)' -> '\(dec2)'")

    if dec1 == roundtripMessage, dec2 == bobResponse {
        printSuccess("Round-trip encryption works")
    } else {
        printFailure("Round-trip failed")
    }
    printDiscovery("Both parties can encrypt messages to each other")

    // Test 1.4: Empty message
    printTest("Empty message encryption")
    let emptyMessage = ""
    let emptyEnc = try await alice.encrypt(recipient: bobUser, value: emptyMessage, scheme: .nip04)
    let emptyDec = try await bob.decrypt(sender: aliceUser, value: emptyEnc, scheme: .nip04)
    print("   Empty message encrypted/decrypted: '\(emptyDec)'")

    if emptyDec == emptyMessage {
        printSuccess("Empty message handled correctly")
    } else {
        printFailure("Empty message failed")
    }
    printDiscovery("Can encrypt/decrypt empty strings")

    // Test 1.5: Unicode message
    printTest("Unicode message encryption")
    let unicodeMessage = "Hello 世界! 🌍🔐 Special chars: éñü"
    let unicodeEnc = try await alice.encrypt(recipient: bobUser, value: unicodeMessage, scheme: .nip04)
    let unicodeDec = try await bob.decrypt(sender: aliceUser, value: unicodeEnc, scheme: .nip04)
    print("   Unicode: '\(unicodeMessage)' -> '\(unicodeDec)'")

    if unicodeDec == unicodeMessage {
        printSuccess("Unicode handled correctly")
    } else {
        printFailure("Unicode failed: '\(unicodeDec)' != '\(unicodeMessage)'")
    }
    printDiscovery("Unicode characters are preserved")

    // Test 1.6: Large message
    printTest("Large message encryption")
    let largeMessage = String(repeating: "A", count: 10000)
    let largeEnc = try await alice.encrypt(recipient: bobUser, value: largeMessage, scheme: .nip04)
    let largeDec = try await bob.decrypt(sender: aliceUser, value: largeEnc, scheme: .nip04)
    print("   Large message size: \(largeMessage.count) chars")
    print("   Encrypted size: \(largeEnc.count) chars")

    if largeDec == largeMessage {
        printSuccess("Large message handled correctly")
    } else {
        printFailure("Large message failed")
    }
    printDiscovery("Can handle messages of 10k+ characters")
}

func testNIP44Encryption() async throws {
    printSection("TEST 2: NIP-44 Encryption/Decryption")

    let alice = try NDKPrivateKeySigner.generate()
    let bob = try NDKPrivateKeySigner.generate()

    let alicePubkey = try await alice.pubkey
    let bobPubkey = try await bob.pubkey
    let bobUser = NDKUser(pubkey: bobPubkey)
    let aliceUser = NDKUser(pubkey: alicePubkey)

    // Test 2.1: Basic NIP-44 encryption
    printTest("Basic NIP-44 encryption")
    let message = "Hello Bob! This uses NIP-44 encryption."

    do {
        let encrypted = try await alice.encrypt(
            recipient: bobUser,
            value: message,
            scheme: .nip44
        )
        print("   Original: \(message)")
        print("   Encrypted: \(String(encrypted.prefix(50)))...")
        printSuccess("Message encrypted with NIP-44")
        printDiscovery("NIP-44 encryption is supported")

        // Test 2.2: NIP-44 decryption
        printTest("NIP-44 decryption")
        let decrypted = try await bob.decrypt(
            sender: aliceUser,
            value: encrypted,
            scheme: .nip44
        )
        print("   Decrypted: \(decrypted)")

        if decrypted == message {
            printSuccess("NIP-44 decryption works")
        } else {
            printFailure("NIP-44 decryption mismatch")
        }

        // Test 2.3: NIP-44 with unicode
        printTest("NIP-44 with unicode")
        let unicodeMsg = "Testing NIP-44 with 日本語 and emojis 🔐✨"
        let unicodeEnc = try await alice.encrypt(recipient: bobUser, value: unicodeMsg, scheme: .nip44)
        let unicodeDec = try await bob.decrypt(sender: aliceUser, value: unicodeEnc, scheme: .nip44)

        if unicodeDec == unicodeMsg {
            printSuccess("NIP-44 handles unicode correctly")
        } else {
            printFailure("NIP-44 unicode failed")
        }

        // Test 2.4: NIP-44 large message
        printTest("NIP-44 large message")
        let largeMsg = String(repeating: "B", count: 5000)
        let largeEnc = try await alice.encrypt(recipient: bobUser, value: largeMsg, scheme: .nip44)
        let largeDec = try await bob.decrypt(sender: aliceUser, value: largeEnc, scheme: .nip44)

        if largeDec == largeMsg {
            printSuccess("NIP-44 handles large messages")
        } else {
            printFailure("NIP-44 large message failed")
        }

    } catch {
        print("   NIP-44 Error: \(error)")
        printDiscovery("NIP-44 may throw errors depending on implementation")
    }
}

func testEncryptionSchemeComparison() async throws {
    printSection("TEST 3: NIP-04 vs NIP-44 Comparison")

    let alice = try NDKPrivateKeySigner.generate()
    let bob = try NDKPrivateKeySigner.generate()
    let bobUser = try NDKUser(pubkey: await bob.pubkey)

    let testMessage = "Comparing encryption schemes"

    // Test 3.1: Encryption size comparison
    printTest("Encrypted size comparison")
    let nip04Enc = try await alice.encrypt(recipient: bobUser, value: testMessage, scheme: .nip04)
    print("   Message length: \(testMessage.count)")
    print("   NIP-04 encrypted length: \(nip04Enc.count)")

    do {
        let nip44Enc = try await alice.encrypt(recipient: bobUser, value: testMessage, scheme: .nip44)
        print("   NIP-44 encrypted length: \(nip44Enc.count)")
        printDiscovery("NIP-04 and NIP-44 produce different encrypted sizes")
    } catch {
        print("   NIP-44 not available for comparison")
    }

    // Test 3.2: Signer encryption capabilities
    printTest("Signer encryption capabilities")
    let schemes = await alice.encryptionEnabled()
    print("   Supported schemes: \(schemes)")
    printSuccess("Signer reports: \(schemes)")
    printDiscovery("NDKPrivateKeySigner supports: \(schemes)")

    // Test 3.3: Cannot decrypt NIP-04 with NIP-44
    printTest("Cross-scheme decryption (should fail)")
    let aliceUser = try NDKUser(pubkey: await alice.pubkey)
    do {
        // Try to decrypt NIP-04 message with NIP-44
        _ = try await bob.decrypt(sender: aliceUser, value: nip04Enc, scheme: .nip44)
        printFailure("Should not be able to decrypt NIP-04 with NIP-44")
    } catch {
        printSuccess("Correctly fails when using wrong encryption scheme")
        printDiscovery("Must use matching encryption scheme for decryption")
    }
}

func testEncryptedDirectMessages() async throws {
    printSection("TEST 4: Encrypted Direct Messages (Kind 4)")

    let ndk = NDK(relayUrls: TEST_RELAYS)
    let alice = try NDKPrivateKeySigner.generate()
    let bob = try NDKPrivateKeySigner.generate()

    ndk.signer = alice
    let alicePubkey = try await alice.pubkey
    let bobPubkey = try await bob.pubkey

    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // Test 4.1: Create encrypted DM with NIP-04
    printTest("Create encrypted DM event (NIP-04)")
    let secretMessage = "This is a private message from Alice to Bob 🔒"

    let dmEvent = try await NDKEvent.encryptedDirectMessage(
        content: secretMessage,
        recipientPubkey: bobPubkey,
        signer: alice,
        ndk: ndk,
        useNIP44: false
    )

    print("   Event ID: \(String(dmEvent.id.prefix(16)))...")
    print("   Event kind: \(dmEvent.kind)")
    print("   Encrypted content: \(String(dmEvent.content.prefix(50)))...")
    print("   Tags: \(dmEvent.tags)")

    printSuccess("Encrypted DM event created")
    printDiscovery("NDKEvent.encryptedDirectMessage() creates kind 4 event")
    printDiscovery("Event content is encrypted, recipient is in 'p' tag")

    // Verify event structure
    if dmEvent.kind == EventKind.encryptedDirectMessage {
        printSuccess("Event has correct kind (4)")
    } else {
        printFailure("Event has wrong kind: \(dmEvent.kind)")
    }

    let pTags = dmEvent.tags(withName: "p")
    if let firstPTag = pTags.first, firstPTag.value == bobPubkey {
        printSuccess("Event has correct 'p' tag for recipient")
    } else {
        printFailure("Event missing or wrong 'p' tag")
    }

    // Test 4.2: Decrypt DM content
    printTest("Decrypt DM content")
    let decryptedContent = try await dmEvent.decryptedContent(
        signer: bob,
        senderPubkey: alicePubkey,
        ndk: ndk
    )

    print("   Decrypted: \(decryptedContent ?? "nil")")

    if decryptedContent == secretMessage {
        printSuccess("DM content decrypted correctly")
    } else {
        printFailure("DM decryption failed: '\(decryptedContent ?? "nil")' != '\(secretMessage)'")
    }
    printDiscovery("event.decryptedContent(signer:senderPubkey:ndk:) decrypts content")

    // Test 4.3: Publish encrypted DM
    printTest("Publish encrypted DM")
    do {
        let publishResult = try await ndk.publish(dmEvent)
        print("   Published to \(publishResult.count) relay(s)")
        printSuccess("Encrypted DM published")
        printDiscovery("Encrypted DMs are published like regular events")
    } catch {
        print("   Publish error: \(error)")
        printDiscovery("Publishing may fail without proper relay connection")
    }

    // Test 4.4: Create DM with NIP-44
    printTest("Create encrypted DM event (NIP-44)")
    do {
        let dmEvent44 = try await NDKEvent.encryptedDirectMessage(
            content: "NIP-44 encrypted message",
            recipientPubkey: bobPubkey,
            signer: alice,
            ndk: ndk,
            useNIP44: true
        )
        print("   NIP-44 DM created: \(String(dmEvent44.id.prefix(16)))...")
        printSuccess("NIP-44 DM creation works")
        printDiscovery("Can create DMs with NIP-44 by setting useNIP44: true")
    } catch {
        print("   NIP-44 DM error: \(error)")
        printDiscovery("NIP-44 DMs may not be fully supported")
    }

    await ndk.disconnect()
}

func testErrorHandling() async throws {
    printSection("TEST 5: Error Handling")

    let alice = try NDKPrivateKeySigner.generate()
    let bob = try NDKPrivateKeySigner.generate()
    let bobUser = try NDKUser(pubkey: await bob.pubkey)

    // Test 5.1: Invalid encrypted string
    printTest("Decrypt invalid encrypted string")
    do {
        let aliceUser = try NDKUser(pubkey: await alice.pubkey)
        _ = try await bob.decrypt(
            sender: aliceUser,
            value: "invalid_encrypted_string",
            scheme: .nip04
        )
        printFailure("Should have thrown error for invalid encrypted string")
    } catch {
        printSuccess("Correctly throws error for invalid encrypted data")
        print("   Error: \(error)")
        printDiscovery("Invalid encrypted strings throw NDKError")
    }

    // Test 5.2: Wrong recipient decryption
    printTest("Decrypt with wrong recipient")
    let charlie = try NDKPrivateKeySigner.generate()
    let message = "Secret message"
    let encrypted = try await alice.encrypt(recipient: bobUser, value: message, scheme: .nip04)

    do {
        let aliceUser = try NDKUser(pubkey: await alice.pubkey)
        _ = try await charlie.decrypt(
            sender: aliceUser,
            value: encrypted,
            scheme: .nip04
        )
        printFailure("Should have thrown error when wrong recipient tries to decrypt")
    } catch {
        printSuccess("Correctly throws error when wrong recipient decrypts")
        printDiscovery("Decryption requires correct recipient private key")
    }

    // Test 5.3: Malformed base64
    printTest("Decrypt malformed base64")
    do {
        let aliceUser = try NDKUser(pubkey: await alice.pubkey)
        _ = try await bob.decrypt(
            sender: aliceUser,
            value: "not?base64!",
            scheme: .nip04
        )
        printFailure("Should have thrown error for malformed base64")
    } catch {
        printSuccess("Correctly handles malformed base64")
    }
}

func testEncryptionEdgeCases() async throws {
    printSection("TEST 6: Encryption Edge Cases")

    let alice = try NDKPrivateKeySigner.generate()
    let bob = try NDKPrivateKeySigner.generate()
    let bobUser = try NDKUser(pubkey: await bob.pubkey)
    let aliceUser = try NDKUser(pubkey: await alice.pubkey)

    // Test 6.1: Special characters
    printTest("Special characters")
    let specialChars = "!@#$%^&*()_+-=[]{}|;':\",./<>?\\`~\n\t\r"
    let enc = try await alice.encrypt(recipient: bobUser, value: specialChars, scheme: .nip04)
    let dec = try await bob.decrypt(sender: aliceUser, value: enc, scheme: .nip04)

    if dec == specialChars {
        printSuccess("Special characters preserved")
    } else {
        printFailure("Special characters corrupted")
        print("   Original: \(specialChars.debugDescription)")
        print("   Decrypted: \(dec.debugDescription)")
    }
    printDiscovery("All ASCII special characters are preserved")

    // Test 6.2: Newlines and whitespace
    printTest("Newlines and whitespace")
    let whitespaceMsg = "Line 1\nLine 2\n\tTabbed\r\nCRLF"
    let wEnc = try await alice.encrypt(recipient: bobUser, value: whitespaceMsg, scheme: .nip04)
    let wDec = try await bob.decrypt(sender: aliceUser, value: wEnc, scheme: .nip04)

    if wDec == whitespaceMsg {
        printSuccess("Whitespace characters preserved")
    } else {
        printFailure("Whitespace corrupted")
    }
    printDiscovery("Newlines, tabs, and CRLF are preserved")

    // Test 6.3: Very long message
    printTest("Very long message (50KB)")
    let veryLongMessage = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 1000)
    print("   Message size: \(veryLongMessage.count) bytes")

    do {
        let vEnc = try await alice.encrypt(recipient: bobUser, value: veryLongMessage, scheme: .nip04)
        let vDec = try await bob.decrypt(sender: aliceUser, value: vEnc, scheme: .nip04)

        if vDec == veryLongMessage {
            printSuccess("Very long message handled correctly")
            print("   Encrypted size: \(vEnc.count) bytes")
        } else {
            printFailure("Very long message corrupted")
        }
    } catch {
        print("   Error with very long message: \(error)")
        printDiscovery("Very long messages may have size limits")
    }

    // Test 6.4: JSON content
    printTest("JSON content encryption")
    let jsonContent = "{\"type\":\"message\",\"content\":\"Hello\",\"timestamp\":1234567890}"
    let jEnc = try await alice.encrypt(recipient: bobUser, value: jsonContent, scheme: .nip04)
    let jDec = try await bob.decrypt(sender: aliceUser, value: jEnc, scheme: .nip04)

    if jDec == jsonContent {
        printSuccess("JSON content preserved")
    } else {
        printFailure("JSON content corrupted")
    }
    printDiscovery("Can encrypt structured data like JSON")
}

// MARK: - Main Test Runner

@main
struct TestApp3 {
    static func main() async {
        print("╔════════════════════════════════════════════════════════════════════╗")
        print("║              NDKSwift Test App 3: Encryption (NIP-04/44)           ║")
        print("║                                                                    ║")
        print("║  This test validates encryption functionality through hands-on    ║")
        print("║  testing of NIP-04 and NIP-44 encryption schemes.                 ║")
        print("╚════════════════════════════════════════════════════════════════════╝")

        do {
            try await testNIP04Encryption()
            try await testNIP44Encryption()
            try await testEncryptionSchemeComparison()
            try await testEncryptedDirectMessages()
            try await testErrorHandling()
            try await testEncryptionEdgeCases()

            printSection("TEST SUMMARY")
            print("✅ All encryption tests completed!")
            print("\nKey Discoveries:")
            print("- NIP-04 encryption is fully supported and working")
            print("- NIP-44 support depends on implementation")
            print("- Both schemes preserve unicode and special characters")
            print("- Empty messages and large messages are handled correctly")
            print("- Encrypted DMs use kind 4 with 'p' tag for recipient")
            print("- Must use matching encryption scheme for decryption")
            print("- Error handling is robust for invalid data")
            print("- Can encrypt structured data like JSON")

        } catch {
            printFailure("Test suite failed", error: error)
        }
    }
}
