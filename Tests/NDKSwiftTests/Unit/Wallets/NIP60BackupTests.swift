import XCTest
@testable import NDKSwift
@testable import CashuSwift

final class NIP60BackupTests: XCTestCase {
    
    var ndk: NDK!
    var wallet: NIP60Wallet!
    var signer: NDKPrivateKeySigner!
    var mockRelay: MockRelay!
    var mockCache: MemoryCache!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create mock components
        mockRelay = MockRelay(url: "wss://test.relay")
        mockCache = MemoryCache()
        
        // Create signer
        let privateKey = "test_private_key_for_backup_tests"
        signer = NDKPrivateKeySigner(privateKey: privateKey)!
        
        // Create NDK instance
        ndk = NDK(relayURLs: ["wss://test.relay"], signer: signer, cache: mockCache)
        
        // Replace relay pool with mock
        await ndk.pool.setMockRelay(mockRelay)
        
        // Create wallet
        wallet = NIP60Wallet(ndk: ndk, signer: signer)
    }
    
    override func tearDown() async throws {
        wallet = nil
        ndk = nil
        signer = nil
        mockRelay = nil
        mockCache = nil
        try await super.tearDown()
    }
    
    // MARK: - Backup Tests
    
    func testCreateBackup() async throws {
        // Configure wallet with test data
        let testMints = ["https://mint1.example.com", "https://mint2.example.com"]
        let testRelays = ["wss://relay1.example.com", "wss://relay2.example.com"]
        
        try await wallet.configureWithNewMints(testMints, relays: testRelays)
        
        // Setup mock to capture published events
        var publishedEvents: [NDKEvent] = []
        await mockRelay.setHandler { relayMessage in
            if case .event(let eventMessage) = relayMessage {
                publishedEvents.append(eventMessage.event)
            }
            return .ok(eventID: "test-id", accepted: true, message: "")
        }
        
        // Create backup
        let backupEvent = try await wallet.createBackup()
        
        // Verify backup event properties
        XCTAssertEqual(backupEvent.event.kind, EventKind.cashuWalletBackup)
        XCTAssertFalse(backupEvent.event.content.isEmpty, "Backup should have encrypted content")
        
        // Verify public key tag
        let pTags = backupEvent.event.tags.filter { $0.count >= 2 && $0[0] == "p" }
        XCTAssertEqual(pTags.count, 1, "Should have exactly one p tag")
        XCTAssertEqual(pTags.first?[1], try await signer.pubkey, "P tag should contain user's public key")
        
        // Verify relay tags
        let relayTags = backupEvent.event.tags.filter { $0.count >= 2 && $0[0] == "relay" }
        XCTAssertEqual(relayTags.count, testRelays.count, "Should have relay tags for each configured relay")
        
        // Verify decrypted content
        let mints = try await backupEvent.mints(signer: signer)
        XCTAssertEqual(Set(mints), Set(testMints), "Backup should contain all configured mints")
        
        let p2pkPrivateKey = try await backupEvent.p2pkPrivateKey(signer: signer)
        XCTAssertNotNil(p2pkPrivateKey, "Backup should include P2PK private key")
        
        // Verify event was published
        XCTAssertEqual(publishedEvents.count, 2, "Should publish wallet config and backup events")
        XCTAssertTrue(publishedEvents.contains { $0.kind == EventKind.cashuWalletBackup }, "Should publish backup event")
    }
    
    // MARK: - Restore Tests
    
    func testRestoreFromBackup() async throws {
        // Create a backup event manually
        let testMints = ["https://restored-mint1.com", "https://restored-mint2.com"]
        let testRelays = ["wss://restored-relay1.com", "wss://restored-relay2.com"]
        let testP2pkPrivateKey = "test_p2pk_private_key"
        
        // Create backup event
        let backupEvent = try await NDKCashuWalletBackupEvent.create(
            ndk: ndk,
            mints: testMints,
            relays: testRelays,
            p2pkPrivateKey: testP2pkPrivateKey,
            signer: signer
        )
        
        // Store backup event in cache
        await mockCache.store(events: [backupEvent.event])
        
        // Setup mock to return backup event
        await mockRelay.setHandler { relayMessage in
            if case .request = relayMessage {
                return .eose(subscriptionID: "test-sub")
            }
            return .ok(eventID: "test-id", accepted: true, message: "")
        }
        
        // Restore from backup
        let restored = try await wallet.restoreFromBackup()
        
        XCTAssertTrue(restored, "Restoration should succeed")
        
        // Verify restored configuration
        let restoredMints = await wallet.mints.getAllMints().map { $0.url }
        XCTAssertEqual(Set(restoredMints), Set(testMints), "Mints should be restored")
        
        XCTAssertEqual(wallet.walletConfigRelays, testRelays, "Relays should be restored")
        
        // Verify P2PK key was restored
        let (restoredP2pkPrivateKey, _) = try await wallet.p2pkManager.getOrCreateKeypair()
        XCTAssertEqual(restoredP2pkPrivateKey, testP2pkPrivateKey, "P2PK private key should be restored")
    }
    
    func testRestoreFromBackupNoBackupExists() async throws {
        // Setup mock to return no events
        await mockRelay.setHandler { relayMessage in
            if case .request = relayMessage {
                return .eose(subscriptionID: "test-sub")
            }
            return .ok(eventID: "test-id", accepted: true, message: "")
        }
        
        // Try to restore when no backup exists
        let restored = try await wallet.restoreFromBackup()
        
        XCTAssertFalse(restored, "Restoration should fail when no backup exists")
    }
    
    // MARK: - Has Backup Tests
    
    func testHasBackup() async throws {
        // Create a backup event
        let backupEvent = try await NDKCashuWalletBackupEvent.create(
            ndk: ndk,
            mints: ["https://test-mint.com"],
            signer: signer
        )
        
        // Store backup event in cache
        await mockCache.store(events: [backupEvent.event])
        
        // Setup mock to return backup event
        await mockRelay.setHandler { relayMessage in
            if case .request = relayMessage {
                return .eose(subscriptionID: "test-sub")
            }
            return .ok(eventID: "test-id", accepted: true, message: "")
        }
        
        // Check if backup exists
        let hasBackup = try await wallet.hasBackup()
        
        XCTAssertTrue(hasBackup, "Should detect existing backup")
    }
    
    func testHasBackupNoBackupExists() async throws {
        // Setup mock to return no events
        await mockRelay.setHandler { relayMessage in
            if case .request = relayMessage {
                return .eose(subscriptionID: "test-sub")
            }
            return .ok(eventID: "test-id", accepted: true, message: "")
        }
        
        // Check if backup exists
        let hasBackup = try await wallet.hasBackup()
        
        XCTAssertFalse(hasBackup, "Should return false when no backup exists")
    }
    
    // MARK: - Integration Tests
    
    func testBackupAndRestoreRoundTrip() async throws {
        // Configure wallet with test data
        let testMints = ["https://roundtrip-mint1.com", "https://roundtrip-mint2.com"]
        let testRelays = ["wss://roundtrip-relay1.com", "wss://roundtrip-relay2.com"]
        
        try await wallet.configureWithNewMints(testMints, relays: testRelays)
        
        // Setup mock to capture and return events
        var storedEvents: [NDKEvent] = []
        await mockRelay.setHandler { relayMessage in
            if case .event(let eventMessage) = relayMessage {
                storedEvents.append(eventMessage.event)
            } else if case .request(let _, let filters) = relayMessage {
                // Return stored backup events when requested
                let backupEvents = storedEvents.filter { event in
                    filters.contains { filter in
                        filter.kinds?.contains(Int32(EventKind.cashuWalletBackup)) ?? false
                    }
                }
                for event in backupEvents {
                    _ = RelayMessage.event(EventMessage(subscriptionID: "test-sub", event: event))
                }
                return .eose(subscriptionID: "test-sub")
            }
            return .ok(eventID: "test-id", accepted: true, message: "")
        }
        
        // Create backup
        let backupEvent = try await wallet.createBackup()
        storedEvents.append(backupEvent.event)
        
        // Create new wallet instance
        let newWallet = NIP60Wallet(ndk: ndk, signer: signer)
        
        // Restore from backup
        let restored = try await newWallet.restoreFromBackup()
        
        XCTAssertTrue(restored, "Restoration should succeed")
        
        // Verify complete restoration
        let restoredMints = await newWallet.mints.getAllMints().map { $0.url }
        XCTAssertEqual(Set(restoredMints), Set(testMints), "All mints should be restored")
        
        XCTAssertEqual(newWallet.walletConfigRelays, testRelays, "All relays should be restored")
        
        // Verify P2PK keys match
        let (originalP2pk, _) = try await wallet.p2pkManager.getOrCreateKeypair()
        let (restoredP2pk, _) = try await newWallet.p2pkManager.getOrCreateKeypair()
        XCTAssertEqual(originalP2pk, restoredP2pk, "P2PK keys should match after restoration")
    }
}