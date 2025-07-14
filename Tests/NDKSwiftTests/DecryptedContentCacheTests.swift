import XCTest
@testable import NDKSwift

final class DecryptedContentCacheTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var recipientSigner: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create signers
        signer = try NDKPrivateKeySigner(privateKey: TestKeys.alicePrivateKey)
        recipientSigner = try NDKPrivateKeySigner(privateKey: TestKeys.bobPrivateKey)
        
        // Create NDK with memory cache
        ndk = NDK(relayUrls: [], signer: signer)
        ndk.cache = SimpleMemoryCache()
    }
    
    override func tearDown() async throws {
        ndk = nil
        signer = nil
        recipientSigner = nil
        try await super.tearDown()
    }
    
    // MARK: - SimpleMemoryCache Tests
    
    func testDecryptedContentCaching() async throws {
        // Create an encrypted message
        let originalContent = "This is a secret message!"
        let event = try await NDKEvent.encryptedDirectMessage(
            content: originalContent,
            recipientPubkey: try await recipientSigner.pubkey,
            signer: signer
        )
        
        // First decryption - should decrypt and cache
        let decrypted1 = try await event.decryptedContent(
            signer: recipientSigner,
            senderPubkey: try await signer.pubkey,
            ndk: ndk
        )
        XCTAssertEqual(decrypted1, originalContent)
        
        // Verify content was cached
        let viewerPubkey = try await recipientSigner.pubkey
        let cachedContent = await ndk.cache?.getDecryptedContent(for: event.id, viewerPubkey: viewerPubkey)
        XCTAssertEqual(cachedContent, originalContent)
        
        // Second decryption - should use cache
        let decrypted2 = try await event.decryptedContent(
            signer: recipientSigner,
            senderPubkey: try await signer.pubkey,
            ndk: ndk
        )
        XCTAssertEqual(decrypted2, originalContent)
    }
    
    func testClearDecryptedContent() async throws {
        // Create and decrypt a message
        let originalContent = "This is another secret!"
        let event = try await NDKEvent.encryptedDirectMessage(
            content: originalContent,
            recipientPubkey: try await recipientSigner.pubkey,
            signer: signer
        )
        
        // Decrypt to cache it
        _ = try await event.decryptedContent(
            signer: recipientSigner,
            senderPubkey: try await signer.pubkey,
            ndk: ndk
        )
        
        // Verify it's cached
        let viewerPubkey = try await recipientSigner.pubkey
        let cachedBefore = await ndk.cache?.getDecryptedContent(for: event.id, viewerPubkey: viewerPubkey)
        XCTAssertNotNil(cachedBefore)
        
        // Clear decrypted content
        await ndk.cache?.clearDecryptedContent()
        
        // Verify it's no longer cached
        let cachedAfter = await ndk.cache?.getDecryptedContent(for: event.id, viewerPubkey: viewerPubkey)
        XCTAssertNil(cachedAfter)
    }
    
    func testClearAllCacheData() async throws {
        // Create and decrypt a message
        let event = try await NDKEvent.encryptedDirectMessage(
            content: "Secret to be cleared",
            recipientPubkey: try await recipientSigner.pubkey,
            signer: signer
        )
        
        // Save event and decrypt to cache both
        try await ndk.cache?.saveEvent(event)
        _ = try await event.decryptedContent(
            signer: recipientSigner,
            senderPubkey: try await signer.pubkey,
            ndk: ndk
        )
        
        // Verify both are cached
        let viewerPubkey = try await recipientSigner.pubkey
        let savedEvent = await ndk.cache?.getEvent(id: event.id)
        let cachedContent = await ndk.cache?.getDecryptedContent(for: event.id, viewerPubkey: viewerPubkey)
        XCTAssertNotNil(savedEvent)
        XCTAssertNotNil(cachedContent)
        
        // Clear all cache data
        try await ndk.cache?.clear()
        
        // Verify everything is cleared
        let eventAfter = await ndk.cache?.getEvent(id: event.id)
        let contentAfter = await ndk.cache?.getDecryptedContent(for: event.id, viewerPubkey: viewerPubkey)
        XCTAssertNil(eventAfter)
        XCTAssertNil(contentAfter)
    }
    
    func testNoCacheScenario() async throws {
        // Create NDK without cache
        let ndkNoCache = NDK(relayUrls: [], signer: signer)
        
        // Create an encrypted message
        let originalContent = "Message without cache"
        let event = try await NDKEvent.encryptedDirectMessage(
            content: originalContent,
            recipientPubkey: try await recipientSigner.pubkey,
            signer: signer
        )
        
        // Decryption should still work without cache
        let decrypted = try await event.decryptedContent(
            signer: recipientSigner,
            senderPubkey: try await signer.pubkey,
            ndk: ndkNoCache
        )
        XCTAssertEqual(decrypted, originalContent)
    }
    
    // MARK: - SQLiteCache Tests
    
    func testSQLiteCacheDecryptedContent() async throws {
        // Create NDK with SQLite cache
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_decrypt_\(UUID().uuidString).db").path
        let sqliteCache = try await NDKSQLiteCache(path: dbPath)
        ndk.cache = sqliteCache
        
        // Create and decrypt a message
        let originalContent = "SQLite cached secret"
        let event = try await NDKEvent.encryptedDirectMessage(
            content: originalContent,
            recipientPubkey: try await recipientSigner.pubkey,
            signer: signer
        )
        
        // First decryption
        let decrypted1 = try await event.decryptedContent(
            signer: recipientSigner,
            senderPubkey: try await signer.pubkey,
            ndk: ndk
        )
        XCTAssertEqual(decrypted1, originalContent)
        
        // Verify persisted in SQLite
        let viewerPubkey = try await recipientSigner.pubkey
        let cached = await sqliteCache.getDecryptedContent(for: event.id, viewerPubkey: viewerPubkey)
        XCTAssertEqual(cached, originalContent)
        
        // Create new cache instance with same DB to test persistence
        let sqliteCache2 = try await NDKSQLiteCache(path: dbPath)
        let persistedContent = await sqliteCache2.getDecryptedContent(for: event.id, viewerPubkey: viewerPubkey)
        XCTAssertEqual(persistedContent, originalContent)
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    func testSQLiteCacheClearDecryptedContent() async throws {
        // Create NDK with SQLite cache
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_clear_\(UUID().uuidString).db").path
        let sqliteCache = try await NDKSQLiteCache(path: dbPath)
        ndk.cache = sqliteCache
        
        // Create multiple encrypted messages
        let messages = ["Secret 1", "Secret 2", "Secret 3"]
        var events: [NDKEvent] = []
        
        for content in messages {
            let event = try await NDKEvent.encryptedDirectMessage(
                content: content,
                recipientPubkey: try await recipientSigner.pubkey,
                signer: signer
            )
            events.append(event)
            
            // Decrypt to cache
            _ = try await event.decryptedContent(
                signer: recipientSigner,
                senderPubkey: try await signer.pubkey,
                ndk: ndk
            )
        }
        
        // Verify all are cached
        let viewerPubkey = try await recipientSigner.pubkey
        for (index, event) in events.enumerated() {
            let cached = await sqliteCache.getDecryptedContent(for: event.id, viewerPubkey: viewerPubkey)
            XCTAssertEqual(cached, messages[index])
        }
        
        // Clear decrypted content
        await sqliteCache.clearDecryptedContent()
        
        // Verify all are cleared
        for event in events {
            let cached = await sqliteCache.getDecryptedContent(for: event.id, viewerPubkey: viewerPubkey)
            XCTAssertNil(cached)
        }
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    func testClearDecryptedContentForSpecificViewer() async throws {
        // Create two different viewers
        let viewer1Signer = try NDKPrivateKeySigner(privateKey: TestKeys.alicePrivateKey)
        let viewer2Signer = try NDKPrivateKeySigner(privateKey: TestKeys.bobPrivateKey)
        let senderSigner = try NDKPrivateKeySigner(privateKey: TestKeys.charliePrivateKey)
        
        // Create NDK with memory cache
        ndk = NDK(relayUrls: [], signer: senderSigner)
        ndk.cache = SimpleMemoryCache()
        
        // Create encrypted messages for both viewers
        let message = "Secret message"
        let viewer1Pubkey = try await viewer1Signer.pubkey
        let viewer2Pubkey = try await viewer2Signer.pubkey
        
        let eventForViewer1 = try await NDKEvent.encryptedDirectMessage(
            content: message,
            recipientPubkey: viewer1Pubkey,
            signer: senderSigner
        )
        
        let eventForViewer2 = try await NDKEvent.encryptedDirectMessage(
            content: message,
            recipientPubkey: viewer2Pubkey,
            signer: senderSigner
        )
        
        // Decrypt with both viewers
        _ = try await eventForViewer1.decryptedContent(
            signer: viewer1Signer,
            senderPubkey: try await senderSigner.pubkey,
            ndk: ndk
        )
        
        _ = try await eventForViewer2.decryptedContent(
            signer: viewer2Signer,
            senderPubkey: try await senderSigner.pubkey,
            ndk: ndk
        )
        
        // Verify both are cached
        let cached1Before = await ndk.cache?.getDecryptedContent(for: eventForViewer1.id, viewerPubkey: viewer1Pubkey)
        let cached2Before = await ndk.cache?.getDecryptedContent(for: eventForViewer2.id, viewerPubkey: viewer2Pubkey)
        XCTAssertNotNil(cached1Before)
        XCTAssertNotNil(cached2Before)
        
        // Clear only viewer1's content
        await ndk.cache?.clearDecryptedContent(for: viewer1Pubkey)
        
        // Verify viewer1's content is cleared but viewer2's remains
        let cached1After = await ndk.cache?.getDecryptedContent(for: eventForViewer1.id, viewerPubkey: viewer1Pubkey)
        let cached2After = await ndk.cache?.getDecryptedContent(for: eventForViewer2.id, viewerPubkey: viewer2Pubkey)
        XCTAssertNil(cached1After)
        XCTAssertNotNil(cached2After)
    }
}