import XCTest
@testable import NDKSwift

final class NDKRelayListTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        signer = try NDKPrivateKeySigner(privateKey: "test-private-key")
        ndk.signer = signer
    }
    
    override func tearDown() async throws {
        ndk = nil
        signer = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        let relayList = NDKRelayList(ndk: ndk)
        XCTAssertEqual(relayList.kind, EventKind.relayList)
        XCTAssertTrue(relayList.relayEntries.isEmpty)
        XCTAssertTrue(relayList.relayURLs.isEmpty)
    }
    
    func testFromEvent() {
        let event = NDKEvent(
            id: "test-id",
            pubkey: "test-pubkey",
            createdAt: Timestamp.now,
            kind: EventKind.relayList,
            tags: [
                ["r", "wss://relay1.com", "read"],
                ["r", "wss://relay2.com", "write"],
                ["r", "wss://relay3.com", "read", "write"],
                ["r", "wss://relay4.com"] // No access markers - should default to read+write
            ],
            content: "",
            sig: "test-sig"
        )
        
        let relayList = NDKRelayList.fromEvent(event, ndk: ndk)
        XCTAssertEqual(relayList.id, "test-id")
        XCTAssertEqual(relayList.pubkey, "test-pubkey")
        XCTAssertEqual(relayList.kind, EventKind.relayList)
        XCTAssertEqual(relayList.relayEntries.count, 4)
    }
    
    // MARK: - Relay Management Tests
    
    func testAddRelay() {
        let relayList = NDKRelayList(ndk: ndk)
        
        // Add relay with default access (read+write)
        relayList.addRelay("wss://relay1.com")
        XCTAssertEqual(relayList.relayEntries.count, 1)
        XCTAssertTrue(relayList.hasRelay("wss://relay1.com"))
        
        let entry1 = relayList.relayEntries.first
        XCTAssertNotNil(entry1)
        XCTAssertTrue(entry1!.canRead)
        XCTAssertTrue(entry1!.canWrite)
        
        // Add same relay again - should not duplicate
        relayList.addRelay("wss://relay1.com")
        XCTAssertEqual(relayList.relayEntries.count, 1)
        
        // Add relay with specific access
        relayList.addRelay("wss://relay2.com", access: [.read])
        XCTAssertEqual(relayList.relayEntries.count, 2)
        
        let entry2 = relayList.relayEntries.first { $0.relay.url == "wss://relay2.com" }
        XCTAssertNotNil(entry2)
        XCTAssertTrue(entry2!.canRead)
        XCTAssertFalse(entry2!.canWrite)
    }
    
    func testAddReadWriteRelays() {
        let relayList = NDKRelayList(ndk: ndk)
        
        // Add read-only relay
        relayList.addReadRelay("wss://read.com")
        let readEntry = relayList.relayEntries.first { $0.relay.url == "wss://read.com" }
        XCTAssertNotNil(readEntry)
        XCTAssertTrue(readEntry!.canRead)
        XCTAssertFalse(readEntry!.canWrite)
        
        // Add write-only relay
        relayList.addWriteRelay("wss://write.com")
        let writeEntry = relayList.relayEntries.first { $0.relay.url == "wss://write.com" }
        XCTAssertNotNil(writeEntry)
        XCTAssertFalse(writeEntry!.canRead)
        XCTAssertTrue(writeEntry!.canWrite)
    }
    
    func testRemoveRelay() {
        let relayList = NDKRelayList(ndk: ndk)
        
        // Add relays
        relayList.addRelay("wss://relay1.com")
        relayList.addRelay("wss://relay2.com")
        relayList.addRelay("wss://relay3.com")
        XCTAssertEqual(relayList.relayEntries.count, 3)
        
        // Remove relay
        relayList.removeRelay("wss://relay2.com")
        XCTAssertEqual(relayList.relayEntries.count, 2)
        XCTAssertFalse(relayList.hasRelay("wss://relay2.com"))
        XCTAssertTrue(relayList.hasRelay("wss://relay1.com"))
        XCTAssertTrue(relayList.hasRelay("wss://relay3.com"))
    }
    
    // MARK: - Access Permission Tests
    
    func testUpdateRelayAccess() {
        let relayList = NDKRelayList(ndk: ndk)
        
        // Add relay with read+write
        relayList.addRelay("wss://relay1.com")
        var access = relayList.accessFor(relay: "wss://relay1.com")
        XCTAssertEqual(access, [.read, .write])
        
        // Update to read-only
        relayList.updateRelayAccess("wss://relay1.com", access: [.read])
        access = relayList.accessFor(relay: "wss://relay1.com")
        XCTAssertEqual(access, [.read])
        
        // Update to write-only
        relayList.updateRelayAccess("wss://relay1.com", access: [.write])
        access = relayList.accessFor(relay: "wss://relay1.com")
        XCTAssertEqual(access, [.write])
    }
    
    func testReadWriteRelayQueries() {
        let relayList = NDKRelayList(ndk: ndk)
        
        // Add various relays
        relayList.addRelay("wss://both1.com", access: [.read, .write])
        relayList.addRelay("wss://both2.com", access: [.read, .write])
        relayList.addReadRelay("wss://read1.com")
        relayList.addReadRelay("wss://read2.com")
        relayList.addWriteRelay("wss://write1.com")
        relayList.addWriteRelay("wss://write2.com")
        
        // Test read relays
        let readRelays = relayList.readRelays
        XCTAssertEqual(readRelays.count, 4)
        XCTAssertTrue(readRelays.contains { $0.url == "wss://both1.com" })
        XCTAssertTrue(readRelays.contains { $0.url == "wss://both2.com" })
        XCTAssertTrue(readRelays.contains { $0.url == "wss://read1.com" })
        XCTAssertTrue(readRelays.contains { $0.url == "wss://read2.com" })
        
        // Test write relays
        let writeRelays = relayList.writeRelays
        XCTAssertEqual(writeRelays.count, 4)
        XCTAssertTrue(writeRelays.contains { $0.url == "wss://both1.com" })
        XCTAssertTrue(writeRelays.contains { $0.url == "wss://both2.com" })
        XCTAssertTrue(writeRelays.contains { $0.url == "wss://write1.com" })
        XCTAssertTrue(writeRelays.contains { $0.url == "wss://write2.com" })
    }
    
    // MARK: - URL Normalization Tests
    
    func testURLNormalization() {
        let relayList = NDKRelayList(ndk: ndk)
        
        // Add relay with non-normalized URL
        relayList.addRelay("wss://relay.com")
        
        // Should normalize and recognize as same relay
        XCTAssertTrue(relayList.hasRelay("wss://relay.com/"))
        XCTAssertTrue(relayList.hasRelay("WSS://RELAY.COM"))
        
        // Try to add same relay with different normalization - should not duplicate
        relayList.addRelay("wss://relay.com/")
        relayList.addRelay("WSS://RELAY.COM")
        XCTAssertEqual(relayList.relayEntries.count, 1)
    }
    
    // MARK: - Relay Set Conversion Tests
    
    func testRelaySetConversion() {
        let relayList = NDKRelayList(ndk: ndk)
        
        relayList.addRelay("wss://relay1.com")
        relayList.addRelay("wss://relay2.com")
        relayList.addReadRelay("wss://read.com")
        relayList.addWriteRelay("wss://write.com")
        
        // Test full relay set
        let fullSet = relayList.toRelaySet()
        XCTAssertEqual(fullSet.count, 4)
        
        // Test read relay set
        let readSet = relayList.readRelaySet()
        XCTAssertEqual(readSet.count, 3) // relay1, relay2, read
        
        // Test write relay set
        let writeSet = relayList.writeRelaySet()
        XCTAssertEqual(writeSet.count, 3) // relay1, relay2, write
    }
    
    // MARK: - Merge Tests
    
    func testMergeRelayLists() {
        let list1 = NDKRelayList(ndk: ndk)
        list1.addRelay("wss://relay1.com")
        list1.addRelay("wss://relay2.com")
        
        let list2 = NDKRelayList(ndk: ndk)
        list2.addRelay("wss://relay2.com") // Duplicate
        list2.addRelay("wss://relay3.com")
        list2.addRelay("wss://relay4.com")
        
        list1.merge(with: list2)
        
        XCTAssertEqual(list1.relayEntries.count, 4)
        XCTAssertTrue(list1.hasRelay("wss://relay1.com"))
        XCTAssertTrue(list1.hasRelay("wss://relay2.com"))
        XCTAssertTrue(list1.hasRelay("wss://relay3.com"))
        XCTAssertTrue(list1.hasRelay("wss://relay4.com"))
    }
    
    // MARK: - Factory Method Tests
    
    func testCreateFromRelayURLs() {
        let urls = ["wss://relay1.com", "wss://relay2.com", "wss://relay3.com"]
        let relayList = NDKRelayList.from(relays: urls, ndk: ndk)
        
        XCTAssertEqual(relayList.relayEntries.count, 3)
        XCTAssertEqual(relayList.relayURLs.sorted(), urls.sorted())
        
        // All should have read+write access
        for entry in relayList.relayEntries {
            XCTAssertTrue(entry.canRead)
            XCTAssertTrue(entry.canWrite)
        }
    }
    
    func testCreateFromSeparateReadWriteRelays() {
        let readURLs = ["wss://read1.com", "wss://read2.com"]
        let writeURLs = ["wss://write1.com", "wss://write2.com"]
        
        let relayList = NDKRelayList.from(
            readRelays: readURLs,
            writeRelays: writeURLs,
            ndk: ndk
        )
        
        XCTAssertEqual(relayList.relayEntries.count, 4)
        XCTAssertEqual(relayList.readRelays.count, 2)
        XCTAssertEqual(relayList.writeRelays.count, 2)
    }
    
    // MARK: - Tag Format Tests
    
    func testRelayEntryTagFormat() {
        // Test read+write relay
        let entry1 = NDKRelayListEntry(url: "wss://relay1.com", access: [.read, .write])
        let tag1 = entry1.toTag()
        XCTAssertEqual(tag1[0], "r")
        XCTAssertEqual(tag1[1], "wss://relay1.com")
        XCTAssertTrue(tag1.contains("read"))
        XCTAssertTrue(tag1.contains("write"))
        
        // Test read-only relay
        let entry2 = NDKRelayListEntry(url: "wss://relay2.com", access: [.read])
        let tag2 = entry2.toTag()
        XCTAssertEqual(tag2, ["r", "wss://relay2.com", "read"])
        
        // Test write-only relay
        let entry3 = NDKRelayListEntry(url: "wss://relay3.com", access: [.write])
        let tag3 = entry3.toTag()
        XCTAssertEqual(tag3, ["r", "wss://relay3.com", "write"])
    }
    
    // MARK: - Timestamp Update Tests
    
    func testTimestampUpdates() {
        let relayList = NDKRelayList(ndk: ndk)
        let initialTimestamp = relayList.createdAt
        
        // Wait a tiny bit to ensure timestamp changes
        Thread.sleep(forTimeInterval: 0.001)
        
        // Adding relay should update timestamp
        relayList.addRelay("wss://relay1.com")
        XCTAssertGreaterThan(relayList.createdAt, initialTimestamp)
        
        let timestamp2 = relayList.createdAt
        Thread.sleep(forTimeInterval: 0.001)
        
        // Removing relay should update timestamp
        relayList.removeRelay("wss://relay1.com")
        XCTAssertGreaterThan(relayList.createdAt, timestamp2)
    }
    
    // MARK: - Access Enum Tests
    
    func testRelayAccessEnum() {
        XCTAssertEqual(NDKRelayAccess.read.rawValue, "read")
        XCTAssertEqual(NDKRelayAccess.write.rawValue, "write")
        XCTAssertEqual(NDKRelayAccess.read.marker, "read")
        XCTAssertEqual(NDKRelayAccess.write.marker, "write")
        
        // Test all cases
        XCTAssertEqual(NDKRelayAccess.allCases.count, 2)
        XCTAssertTrue(NDKRelayAccess.allCases.contains(.read))
        XCTAssertTrue(NDKRelayAccess.allCases.contains(.write))
    }
}