import XCTest
@testable import NDKSwiftCore

/// End-to-end tests for encrypted direct message exchange
/// Tests both NIP-04 and NIP-44 encryption standards
final class EncryptedDME2ETests: XCTestCase {
    let relayURLs = RelayConstants.testRelays
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Configure logging for debugging
        NDKLogger.logLevel = .debug
        NDKLogger.logNetworkTraffic = false
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
    }
    
    func testBasicEncryptedDMExchange() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting basic encrypted DM exchange E2E test")
        
        // Step 1: Create two users (Alice and Bob)
        print("[\(timestamp())] Creating Alice and Bob...")
        let aliceNDK = NDK(cache: MemoryCache())
        let bobNDK = NDK(cache: MemoryCache())
        
        let aliceSigner = try NDKPrivateKeySigner.generate()
        let bobSigner = try NDKPrivateKeySigner.generate()
        
        aliceNDK.signer = aliceSigner
        bobNDK.signer = bobSigner
        
        let alicePubkey = try await aliceSigner.pubkey
        let bobPubkey = try await bobSigner.pubkey
        
        print("[\(timestamp())] Alice pubkey: \(alicePubkey)")
        print("[\(timestamp())] Bob pubkey: \(bobPubkey)")
        
        // Step 2: Connect both users to relays
        print("[\(timestamp())] Connecting to relays...")
        for relayURL in relayURLs {
            await aliceNDK.addRelay(relayURL)
            await bobNDK.addRelay(relayURL)
        }
        
        await aliceNDK.connect()
        await bobNDK.connect()
        
        let aliceConnected = await aliceNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        let bobConnected = await bobNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        guard aliceConnected > 0 && bobConnected > 0 else {
            XCTFail("Failed to connect to relays")
            return
        }
        
        print("[\(timestamp())] Both users connected to relays")
        
        // Step 3: Set up Bob's subscription for encrypted DMs
        print("[\(timestamp())] Setting up Bob's DM subscription...")
        let bobFilter = NDKFilter(
            kinds: [EventKind.encryptedDirectMessage],
            limit: 10,
            tags: ["p": Set([bobPubkey])]
        )
        
        var bobReceivedEvents: [NDKEvent] = []
        let bobReceivedExpectation = XCTestExpectation(description: "Bob receives encrypted DM")
        
        let bobSubscription = bobNDK.subscribe(filter: bobFilter)
        
        Task {
            for await event in bobSubscription.events {
                print("[\(timestamp())] Bob received event: \(event.id)")
                bobReceivedEvents.append(event)
                
                // Check if this is from Alice
                if event.pubkey == alicePubkey {
                    bobReceivedExpectation.fulfill()
                    break
                }
            }
        }
        
        // Give subscription time to establish
        try await Task.sleep(nanoseconds: TimeConstants.nanosecondsPerSecond) // 1 second
        
        // Step 4: Alice sends encrypted DM to Bob (using NIP-44)
        print("[\(timestamp())] Alice sending encrypted DM to Bob (NIP-44)...")
        let aliceMessage = "Hello Bob! This is a secret message from Alice. 🔐"
        
        let encryptStart = Date()
        let aliceDM = try await NDKEvent.encryptedDirectMessage(
            content: aliceMessage,
            recipientPubkey: bobPubkey,
            signer: aliceSigner,
            ndk: aliceNDK,
            useNIP44: true
        )
        let encryptTime = Date()
        print("[\(timestamp())] Message encrypted in \(encryptTime.timeIntervalSince(encryptStart))s")
        
        // Verify event properties
        XCTAssertEqual(aliceDM.kind, EventKind.encryptedDirectMessage)
        XCTAssertEqual(aliceDM.pubkey, alicePubkey)
        XCTAssertTrue(aliceDM.tags.contains(["p", bobPubkey]))
        XCTAssertNotNil(aliceDM.sig)
        XCTAssertNotEqual(aliceDM.content, aliceMessage) // Content should be encrypted
        
        print("[\(timestamp())] Publishing Alice's encrypted DM...")
        let publishedRelays = try await aliceNDK.publish(aliceDM)
        XCTAssertGreaterThan(publishedRelays.count, 0, "Should publish to at least one relay")
        print("[\(timestamp())] Published to \(publishedRelays.count) relays")
        
        // Step 5: Wait for Bob to receive and decrypt the message
        print("[\(timestamp())] Waiting for Bob to receive the DM...")
        let receiveResult = await XCTWaiter.fulfillment(of: [bobReceivedExpectation], timeout: 10.0)
        
        if receiveResult == .completed {
            print("[\(timestamp())] Bob received the encrypted DM")
            
            // Find Alice's message
            let aliceDMReceived = bobReceivedEvents.first { $0.pubkey == alicePubkey }
            XCTAssertNotNil(aliceDMReceived)
            
            if let receivedDM = aliceDMReceived {
                // Decrypt the message
                print("[\(timestamp())] Bob decrypting the message...")
                let decryptStart = Date()
                let decryptedContent = try await receivedDM.decryptedContent(
                    signer: bobSigner,
                    senderPubkey: alicePubkey,
                    ndk: bobNDK
                )
                let decryptTime = Date()
                print("[\(timestamp())] Message decrypted in \(decryptTime.timeIntervalSince(decryptStart))s")
                
                XCTAssertEqual(decryptedContent, aliceMessage)
                print("[\(timestamp())] Decrypted message: \(decryptedContent)")
            }
        } else {
            XCTFail("Bob did not receive the encrypted DM within timeout")
        }
        
        // Step 6: Bob replies to Alice
        print("[\(timestamp())] Bob sending reply to Alice...")
        let bobMessage = "Hi Alice! I got your secret message. This is my encrypted reply! 🔒"
        
        let bobDM = try await NDKEvent.encryptedDirectMessage(
            content: bobMessage,
            recipientPubkey: alicePubkey,
            signer: bobSigner,
            ndk: bobNDK,
            useNIP44: true
        )
        
        // Set up Alice's subscription
        let aliceFilter = NDKFilter(
            kinds: [EventKind.encryptedDirectMessage],
            since: Timestamp.now - 60, // Last minute
            tags: ["p": Set([alicePubkey])]
        )
        
        let aliceReceivedExpectation = XCTestExpectation(description: "Alice receives Bob's reply")
        let aliceSubscription = aliceNDK.subscribe(filter: aliceFilter)
        
        Task {
            for await event in aliceSubscription.events {
                if event.pubkey == bobPubkey {
                    print("[\(timestamp())] Alice received Bob's reply")
                    
                    // Decrypt Bob's message
                    let decryptedReply = try await event.decryptedContent(
                        signer: aliceSigner,
                        senderPubkey: bobPubkey,
                        ndk: aliceNDK
                    )
                    
                    XCTAssertEqual(decryptedReply, bobMessage)
                    print("[\(timestamp())] Alice decrypted Bob's reply: \(decryptedReply)")
                    aliceReceivedExpectation.fulfill()
                    break
                }
            }
        }
        
        // Give subscription time to establish
        try await Task.sleep(nanoseconds: TimeConstants.nanosecondsPerMillisecond * 500) // 0.5 seconds
        
        // Publish Bob's reply
        _ = try await bobNDK.publish(bobDM)
        
        // Wait for Alice to receive
        let aliceResult = await XCTWaiter.fulfillment(of: [aliceReceivedExpectation], timeout: 10.0)
        XCTAssertEqual(aliceResult, .completed, "Alice should receive Bob's reply")
        
        // Cleanup
        await aliceNDK.disconnect()
        await bobNDK.disconnect()
        
        let totalTime = Date()
        print("[\(timestamp())] Basic encrypted DM exchange test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    func testNIP04vsNIP44Compatibility() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting NIP-04 vs NIP-44 compatibility E2E test")
        
        // Create two users
        let senderNDK = NDK(cache: MemoryCache())
        let receiverNDK = NDK(cache: MemoryCache())
        
        let senderSigner = try NDKPrivateKeySigner.generate()
        let receiverSigner = try NDKPrivateKeySigner.generate()
        
        senderNDK.signer = senderSigner
        receiverNDK.signer = receiverSigner
        
        let senderPubkey = try await senderSigner.pubkey
        let receiverPubkey = try await receiverSigner.pubkey
        
        // Connect to relays
        for relayURL in relayURLs {
            await senderNDK.addRelay(relayURL)
            await receiverNDK.addRelay(relayURL)
        }
        
        await senderNDK.connect()
        await receiverNDK.connect()
        
        await senderNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        await receiverNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        // Test messages
        let testMessages = [
            "Simple message",
            "Message with emojis 🚀🌟💫",
            "Message with special characters: @#$%^&*()",
            "Multi-line message\nLine 2\nLine 3",
            "Very long message: " + String(repeating: "Lorem ipsum ", count: 100)
        ]
        
        // Test both NIP-04 and NIP-44
        for useNIP44 in [false, true] {
            let scheme = useNIP44 ? "NIP-44" : "NIP-04"
            print("[\(timestamp())] Testing \(scheme) encryption...")
            
            for (index, message) in testMessages.enumerated() {
                print("[\(timestamp())] Testing message \(index + 1): \(message.prefix(50))...")
                
                // Create encrypted DM
                let dmEvent = try await NDKEvent.encryptedDirectMessage(
                    content: message,
                    recipientPubkey: receiverPubkey,
                    signer: senderSigner,
                    ndk: senderNDK,
                    useNIP44: useNIP44
                )
                
                // Verify encryption worked
                XCTAssertNotEqual(dmEvent.content, message, "\(scheme) should encrypt the content")
                
                // Decrypt using low-level API to test both directions
                if useNIP44 {
                    let decrypted = try Crypto.nip44Decrypt(
                        encrypted: dmEvent.content,
                        privateKey: receiverSigner.privateKeyValue,
                        pubkey: senderPubkey
                    )
                    XCTAssertEqual(decrypted, message, "\(scheme) decryption should recover original message")
                } else {
                    let decrypted = try Crypto.nip04Decrypt(
                        encrypted: dmEvent.content,
                        privateKey: receiverSigner.privateKeyValue,
                        pubkey: senderPubkey
                    )
                    XCTAssertEqual(decrypted, message, "\(scheme) decryption should recover original message")
                }
                
                // Also test high-level API
                let decryptedHighLevel = try await dmEvent.decryptedContent(
                    signer: receiverSigner,
                    senderPubkey: senderPubkey,
                    ndk: receiverNDK
                )
                XCTAssertEqual(decryptedHighLevel, message, "High-level API should decrypt correctly")
            }
        }
        
        // Test that NIP-44 encrypted messages can't be decrypted with NIP-04 and vice versa
        print("[\(timestamp())] Testing cross-scheme incompatibility...")
        
        let testMessage = "This should fail with wrong scheme"
        
        // Create NIP-44 encrypted message
        let nip44Event = try await NDKEvent.encryptedDirectMessage(
            content: testMessage,
            recipientPubkey: receiverPubkey,
            signer: senderSigner,
            ndk: senderNDK,
            useNIP44: true
        )
        
        // Try to decrypt with NIP-04 (should fail)
        do {
            _ = try Crypto.nip04Decrypt(
                encrypted: nip44Event.content,
                privateKey: receiverSigner.privateKeyValue,
                pubkey: senderPubkey
            )
            XCTFail("NIP-04 should not decrypt NIP-44 messages")
        } catch {
            print("[\(timestamp())] Expected failure: NIP-04 cannot decrypt NIP-44")
        }
        
        // Cleanup
        await senderNDK.disconnect()
        await receiverNDK.disconnect()
        
        let totalTime = Date()
        print("[\(timestamp())] NIP-04 vs NIP-44 compatibility test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    func testEncryptedDMWithMultipleRecipients() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting encrypted DM with multiple recipients E2E test")
        
        // Create sender and multiple recipients
        let senderNDK = NDK(cache: MemoryCache())
        let senderSigner = try NDKPrivateKeySigner.generate()
        senderNDK.signer = senderSigner
        let senderPubkey = try await senderSigner.pubkey
        
        // Create 3 recipients
        var recipients: [(ndk: NDK, signer: NDKPrivateKeySigner, pubkey: String)] = []
        
        for i in 1...3 {
            let ndk = NDK(cache: MemoryCache())
            let signer = try NDKPrivateKeySigner.generate()
            let pubkey = try await signer.pubkey
            ndk.signer = signer
            
            recipients.append((ndk, signer, pubkey))
            print("[\(timestamp())] Created recipient \(i) with pubkey: \(pubkey)")
        }
        
        // Connect all to relays
        print("[\(timestamp())] Connecting all users to relays...")
        for relayURL in relayURLs {
            await senderNDK.addRelay(relayURL)
            for (ndk, _, _) in recipients {
                await ndk.addRelay(relayURL)
            }
        }
        
        await senderNDK.connect()
        for (ndk, _, _) in recipients {
            await ndk.connect()
        }
        
        // Wait for connections
        await senderNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        for (ndk, _, _) in recipients {
            await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        }
        
        // Send individual encrypted messages to each recipient
        let baseMessage = "Secret message for recipient"
        
        for (index, (recipientNDK, recipientSigner, recipientPubkey)) in recipients.enumerated() {
            let message = "\(baseMessage) #\(index + 1)"
            
            print("[\(timestamp())] Sending encrypted DM to recipient \(index + 1)...")
            
            // Create and publish encrypted DM
            let dmEvent = try await NDKEvent.encryptedDirectMessage(
                content: message,
                recipientPubkey: recipientPubkey,
                signer: senderSigner,
                ndk: senderNDK,
                useNIP44: true
            )
            
            // Set up recipient's subscription
            let filter = NDKFilter(
                kinds: [EventKind.encryptedDirectMessage],
                since: Timestamp.now - 30,
                tags: ["p": Set([recipientPubkey])]
            )
            
            let expectation = XCTestExpectation(description: "Recipient \(index + 1) receives DM")
            let subscription = recipientNDK.subscribe(filter: filter)
            
            Task {
                for await event in subscription.events {
                    if event.pubkey == senderPubkey {
                        // Decrypt the message
                        let decrypted = try await event.decryptedContent(
                            signer: recipientSigner,
                            senderPubkey: senderPubkey,
                            ndk: recipientNDK
                        )
                        
                        XCTAssertEqual(decrypted, message)
                        print("[\(timestamp())] Recipient \(index + 1) decrypted: \(decrypted)")
                        expectation.fulfill()
                        break
                    }
                }
            }
            
            // Give subscription time to establish
            try await Task.sleep(nanoseconds: TimeConstants.nanosecondsPerMillisecond * 500)
            
            // Publish the DM
            _ = try await senderNDK.publish(dmEvent)
            
            // Wait for recipient to receive
            let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 10.0)
            XCTAssertEqual(result, .completed, "Recipient \(index + 1) should receive DM")
        }
        
        // Test that recipients can't decrypt each other's messages
        print("[\(timestamp())] Testing message isolation between recipients...")
        
        // Create a DM for recipient 1
        let isolationTestMessage = "This is only for recipient 1"
        let dmForRecipient1 = try await NDKEvent.encryptedDirectMessage(
            content: isolationTestMessage,
            recipientPubkey: recipients[0].pubkey,
            signer: senderSigner,
            ndk: senderNDK,
            useNIP44: true
        )
        
        // Try to decrypt with recipient 2's key (should fail)
        do {
            _ = try await dmForRecipient1.decryptedContent(
                signer: recipients[1].signer,
                senderPubkey: senderPubkey,
                ndk: recipients[1].ndk
            )
            XCTFail("Recipient 2 should not be able to decrypt recipient 1's message")
        } catch {
            print("[\(timestamp())] Expected: Recipient 2 cannot decrypt recipient 1's message")
        }
        
        // Cleanup
        await senderNDK.disconnect()
        for (ndk, _, _) in recipients {
            await ndk.disconnect()
        }
        
        let totalTime = Date()
        print("[\(timestamp())] Multiple recipients test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    func testEncryptedDMCaching() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting encrypted DM caching E2E test")
        
        // Create users with cache
        let cache = MemoryCache()
        let senderNDK = NDK(cache: cache)
        let receiverNDK = NDK(cache: cache)
        
        let senderSigner = try NDKPrivateKeySigner.generate()
        let receiverSigner = try NDKPrivateKeySigner.generate()
        
        senderNDK.signer = senderSigner
        receiverNDK.signer = receiverSigner
        
        let senderPubkey = try await senderSigner.pubkey
        let receiverPubkey = try await receiverSigner.pubkey
        
        // Create encrypted DM
        let message = "Test message for caching"
        let dmEvent = try await NDKEvent.encryptedDirectMessage(
            content: message,
            recipientPubkey: receiverPubkey,
            signer: senderSigner,
            ndk: senderNDK,
            useNIP44: true
        )
        
        // First decryption (should cache)
        print("[\(timestamp())] First decryption (should cache)...")
        let firstDecryptStart = Date()
        let firstDecrypted = try await dmEvent.decryptedContent(
            signer: receiverSigner,
            senderPubkey: senderPubkey,
            ndk: receiverNDK
        )
        let firstDecryptTime = Date().timeIntervalSince(firstDecryptStart)
        
        XCTAssertEqual(firstDecrypted, message)
        print("[\(timestamp())] First decryption took: \(firstDecryptTime)s")
        
        // Second decryption (should use cache and be faster)
        print("[\(timestamp())] Second decryption (should use cache)...")
        let secondDecryptStart = Date()
        let secondDecrypted = try await dmEvent.decryptedContent(
            signer: receiverSigner,
            senderPubkey: senderPubkey,
            ndk: receiverNDK
        )
        let secondDecryptTime = Date().timeIntervalSince(secondDecryptStart)
        
        XCTAssertEqual(secondDecrypted, message)
        print("[\(timestamp())] Second decryption took: \(secondDecryptTime)s")
        
        // Cache should make second decryption much faster
        // Note: This might not always be true for very small messages, but the behavior should be consistent
        print("[\(timestamp())] Cache speedup: \(firstDecryptTime / secondDecryptTime)x")
        
        // Test that cache is specific to sender/receiver pair
        let otherSigner = try NDKPrivateKeySigner.generate()
        let otherPubkey = try await otherSigner.pubkey
        
        // Try to decrypt with wrong sender pubkey (should fail, not use cache)
        do {
            _ = try await dmEvent.decryptedContent(
                signer: receiverSigner,
                senderPubkey: otherPubkey,
                ndk: receiverNDK
            )
            XCTFail("Should fail with wrong sender pubkey")
        } catch {
            print("[\(timestamp())] Expected: Cannot decrypt with wrong sender pubkey")
        }
        
        let totalTime = Date()
        print("[\(timestamp())] Caching test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    func testLargeEncryptedMessages() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting large encrypted messages E2E test")
        
        // Create users
        let ndk1 = NDK(cache: MemoryCache())
        let ndk2 = NDK(cache: MemoryCache())
        
        let signer1 = try NDKPrivateKeySigner.generate()
        let signer2 = try NDKPrivateKeySigner.generate()
        
        ndk1.signer = signer1
        ndk2.signer = signer2
        
        let pubkey1 = try await signer1.pubkey
        let pubkey2 = try await signer2.pubkey
        
        // Test various message sizes
        let messageSizes = [
            100,      // 100 bytes
            1_000,    // 1 KB
            10_000,   // 10 KB
            100_000   // 100 KB
        ]
        
        for size in messageSizes {
            print("[\(timestamp())] Testing \(size) byte message...")
            
            // Generate message of specified size
            let baseString = "0123456789ABCDEF"
            let repeats = size / baseString.count + 1
            let largeMessage = String(repeating: baseString, count: repeats).prefix(size)
            let message = String(largeMessage)
            
            // Test both NIP-04 and NIP-44
            for useNIP44 in [false, true] {
                let scheme = useNIP44 ? "NIP-44" : "NIP-04"
                print("[\(timestamp())] Encrypting with \(scheme)...")
                
                let encryptStart = Date()
                let dmEvent = try await NDKEvent.encryptedDirectMessage(
                    content: message,
                    recipientPubkey: pubkey2,
                    signer: signer1,
                    ndk: ndk1,
                    useNIP44: useNIP44
                )
                let encryptTime = Date().timeIntervalSince(encryptStart)
                
                print("[\(timestamp())] \(scheme) encryption of \(size) bytes took: \(encryptTime)s")
                print("[\(timestamp())] Encrypted size: \(dmEvent.content.count) bytes")
                
                // Decrypt
                let decryptStart = Date()
                let decrypted = try await dmEvent.decryptedContent(
                    signer: signer2,
                    senderPubkey: pubkey1,
                    ndk: ndk2
                )
                let decryptTime = Date().timeIntervalSince(decryptStart)
                
                print("[\(timestamp())] \(scheme) decryption took: \(decryptTime)s")
                
                XCTAssertEqual(decrypted.count, message.count)
                XCTAssertEqual(decrypted, message)
            }
        }
        
        let totalTime = Date()
        print("[\(timestamp())] Large messages test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    private func timestamp() -> String {
        return DateFormatters.custom(format: "HH:mm:ss.SSS").string(from: Date())
    }
}