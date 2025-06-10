@testable import NDKSwift
import XCTest

final class NDKRelayListTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var relayList: NDKRelayList!

    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        relayList = NDKRelayList(ndk: ndk)
    }

    override func tearDown() async throws {
        ndk = nil
        signer = nil
        relayList = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testRelayListInitialization() {
        XCTAssertEqual(relayList.kind, 10002)
        XCTAssertNotNil(relayList.ndk)
        XCTAssertTrue(relayList.relayEntries.isEmpty)
    }

    func testFromEvent() {
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 10002,
            tags: [
                ["r", "wss://relay1.example.com", "read"],
                ["r", "wss://relay2.example.com", "write"],
                ["r", "wss://relay3.example.com", "read", "write"],
            ]
        )

        let relayList = NDKRelayList.fromEvent(event)

        XCTAssertEqual(relayList.kind, 10002)
        XCTAssertEqual(relayList.relayEntries.count, 3)
    }

    // MARK: - Relay Management Tests

    func testAddRelay() {
        relayList.addRelay("wss://relay.example.com")

        XCTAssertEqual(relayList.relayEntries.count, 1)
        XCTAssertTrue(relayList.hasRelay("wss://relay.example.com/"))

        let entry = relayList.relayEntries.first!
        XCTAssertTrue(entry.canRead)
        XCTAssertTrue(entry.canWrite)
    }

    func testAddRelayWithAccess() {
        relayList.addRelay("wss://read.example.com", access: [.read])
        relayList.addRelay("wss://write.example.com", access: [.write])

        XCTAssertEqual(relayList.relayEntries.count, 2)

        let readEntry = relayList.relayEntries.first { $0.relay.url.contains("read") }!
        XCTAssertTrue(readEntry.canRead)
        XCTAssertFalse(readEntry.canWrite)

        let writeEntry = relayList.relayEntries.first { $0.relay.url.contains("write") }!
        XCTAssertFalse(writeEntry.canRead)
        XCTAssertTrue(writeEntry.canWrite)
    }

    func testAddReadOnlyRelay() {
        relayList.addReadRelay("wss://read.example.com")

        let entry = relayList.relayEntries.first!
        XCTAssertTrue(entry.canRead)
        XCTAssertFalse(entry.canWrite)
        XCTAssertEqual(entry.access, [.read])
    }

    func testAddWriteOnlyRelay() {
        relayList.addWriteRelay("wss://write.example.com")

        let entry = relayList.relayEntries.first!
        XCTAssertFalse(entry.canRead)
        XCTAssertTrue(entry.canWrite)
        XCTAssertEqual(entry.access, [.write])
    }

    func testRemoveRelay() {
        relayList.addRelay("wss://relay.example.com")
        XCTAssertTrue(relayList.hasRelay("wss://relay.example.com"))

        relayList.removeRelay("wss://relay.example.com")
        XCTAssertFalse(relayList.hasRelay("wss://relay.example.com"))
        XCTAssertTrue(relayList.relayEntries.isEmpty)
    }

    func testUpdateRelayAccess() {
        relayList.addRelay("wss://relay.example.com", access: [.read])

        var entry = relayList.relayEntries.first!
        XCTAssertEqual(entry.access, [.read])

        relayList.updateRelayAccess("wss://relay.example.com/", access: [.read, .write])

        entry = relayList.relayEntries.first!
        XCTAssertEqual(entry.access, [.read, .write])
    }

    func testDuplicateRelayPrevention() {
        relayList.addRelay("wss://relay.example.com")
        relayList.addRelay("wss://relay.example.com") // Should not add duplicate

        XCTAssertEqual(relayList.relayEntries.count, 1)
    }

    // MARK: - URL Normalization Tests

    func testURLNormalization() {
        relayList.addRelay("relay.example.com")

        XCTAssertTrue(relayList.hasRelay("wss://relay.example.com/"))

        let entry = relayList.relayEntries.first!
        XCTAssertEqual(entry.relay.url, "wss://relay.example.com/")
    }

    // MARK: - Access Filtering Tests

    func testReadRelays() {
        relayList.addRelay("wss://both.example.com", access: [.read, .write])
        relayList.addRelay("wss://read.example.com", access: [.read])
        relayList.addRelay("wss://write.example.com", access: [.write])

        let readRelays = relayList.readRelays
        XCTAssertEqual(readRelays.count, 2)
        XCTAssertTrue(readRelays.contains { $0.url.contains("both") })
        XCTAssertTrue(readRelays.contains { $0.url.contains("read") })
        XCTAssertFalse(readRelays.contains { $0.url.contains("write") })
    }

    func testWriteRelays() {
        relayList.addRelay("wss://both.example.com", access: [.read, .write])
        relayList.addRelay("wss://read.example.com", access: [.read])
        relayList.addRelay("wss://write.example.com", access: [.write])

        let writeRelays = relayList.writeRelays
        XCTAssertEqual(writeRelays.count, 2)
        XCTAssertTrue(writeRelays.contains { $0.url.contains("both") })
        XCTAssertTrue(writeRelays.contains { $0.url.contains("write") })
        XCTAssertFalse(writeRelays.contains { $0.url.contains("read") })
    }

    // MARK: - Relay Set Creation Tests

    func testToRelaySet() {
        relayList.addRelay("wss://relay1.example.com")
        relayList.addRelay("wss://relay2.example.com")

        let relaySet = relayList.toRelaySet()
        XCTAssertEqual(relaySet.count, 2)
    }

    func testReadRelaySet() {
        relayList.addRelay("wss://both.example.com", access: [.read, .write])
        relayList.addRelay("wss://read.example.com", access: [.read])
        relayList.addRelay("wss://write.example.com", access: [.write])

        let readSet = relayList.readRelaySet()
        XCTAssertEqual(readSet.count, 2)
    }

    func testWriteRelaySet() {
        relayList.addRelay("wss://both.example.com", access: [.read, .write])
        relayList.addRelay("wss://read.example.com", access: [.read])
        relayList.addRelay("wss://write.example.com", access: [.write])

        let writeSet = relayList.writeRelaySet()
        XCTAssertEqual(writeSet.count, 2)
    }

    // MARK: - Relay Entry Tests

    func testRelayEntryCreation() {
        let relay = NDKRelay(url: "wss://relay.example.com")
        let entry = NDKRelayListEntry(relay: relay, access: [.read])

        XCTAssertEqual(entry.relay.url, "wss://relay.example.com")
        XCTAssertTrue(entry.canRead)
        XCTAssertFalse(entry.canWrite)
    }

    func testRelayEntryFromURL() {
        let entry = NDKRelayListEntry(url: "wss://relay.example.com", access: [.write])

        XCTAssertEqual(entry.relay.url, "wss://relay.example.com")
        XCTAssertFalse(entry.canRead)
        XCTAssertTrue(entry.canWrite)
    }

    func testRelayEntryToTag() {
        let entry = NDKRelayListEntry(url: "wss://relay.example.com", access: [.read, .write])
        let tag = entry.toTag()

        XCTAssertEqual(tag[0], "r")
        XCTAssertEqual(tag[1], "wss://relay.example.com")
        XCTAssertTrue(tag.contains("read"))
        XCTAssertTrue(tag.contains("write"))
    }

    // MARK: - Bulk Operations Tests

    func testSetRelays() {
        let entries = [
            NDKRelayListEntry(url: "wss://relay1.example.com", access: [.read]),
            NDKRelayListEntry(url: "wss://relay2.example.com", access: [.write]),
            NDKRelayListEntry(url: "wss://relay3.example.com", access: [.read, .write]),
        ]

        relayList.setRelays(entries)

        XCTAssertEqual(relayList.relayEntries.count, 3)
        XCTAssertEqual(relayList.readRelays.count, 2)
        XCTAssertEqual(relayList.writeRelays.count, 2)
    }

    func testMergeRelayLists() {
        relayList.addRelay("wss://relay1.example.com")

        let other = NDKRelayList(ndk: ndk)
        other.addRelay("wss://relay2.example.com")
        other.addRelay("wss://relay1.example.com") // Duplicate

        relayList.merge(with: other)

        XCTAssertEqual(relayList.relayEntries.count, 2)
        XCTAssertTrue(relayList.hasRelay("wss://relay1.example.com"))
        XCTAssertTrue(relayList.hasRelay("wss://relay2.example.com"))
    }

    // MARK: - Factory Methods Tests

    func testFromPubkeys() {
        let urls = ["wss://relay1.example.com", "wss://relay2.example.com"]
        let relayList = NDKRelayList.from(relays: urls, ndk: ndk)

        XCTAssertEqual(relayList.relayEntries.count, 2)
        XCTAssertNotNil(relayList.ndk)
    }

    func testFromSeparateReadWrite() {
        let readURLs = ["wss://read1.example.com", "wss://read2.example.com"]
        let writeURLs = ["wss://write1.example.com", "wss://write2.example.com"]

        let relayList = NDKRelayList.from(readRelays: readURLs, writeRelays: writeURLs, ndk: ndk)

        XCTAssertEqual(relayList.relayEntries.count, 4)
        XCTAssertEqual(relayList.readRelays.count, 2)
        XCTAssertEqual(relayList.writeRelays.count, 2)
    }

    // MARK: - Access Query Tests

    func testAccessForRelay() {
        relayList.addRelay("wss://relay.example.com", access: [.read])

        let access = relayList.accessFor(relay: "wss://relay.example.com")
        XCTAssertEqual(access, [.read])

        let unknownAccess = relayList.accessFor(relay: "wss://unknown.example.com")
        XCTAssertNil(unknownAccess)
    }

    // MARK: - Tag Parsing Tests

    func testParsingExistingTags() {
        // Test parsing relay list with existing tags
        let event = NDKEvent()
        event.kind = 10002
        event.tags = [
            ["r", "wss://relay1.example.com"],
            ["r", "wss://relay2.example.com", "read"],
            ["r", "wss://relay3.example.com", "write"],
            ["r", "wss://relay4.example.com", "read", "write"],
        ]

        let relayList = NDKRelayList.fromEvent(event)

        XCTAssertEqual(relayList.relayEntries.count, 4)

        // First relay should have both read and write (default)
        let entry1 = relayList.relayEntries.first { $0.relay.url.contains("relay1") }!
        XCTAssertTrue(entry1.canRead)
        XCTAssertTrue(entry1.canWrite)

        // Second relay should be read-only
        let entry2 = relayList.relayEntries.first { $0.relay.url.contains("relay2") }!
        XCTAssertTrue(entry2.canRead)
        XCTAssertFalse(entry2.canWrite)

        // Third relay should be write-only
        let entry3 = relayList.relayEntries.first { $0.relay.url.contains("relay3") }!
        XCTAssertFalse(entry3.canRead)
        XCTAssertTrue(entry3.canWrite)

        // Fourth relay should have both
        let entry4 = relayList.relayEntries.first { $0.relay.url.contains("relay4") }!
        XCTAssertTrue(entry4.canRead)
        XCTAssertTrue(entry4.canWrite)
    }
}
