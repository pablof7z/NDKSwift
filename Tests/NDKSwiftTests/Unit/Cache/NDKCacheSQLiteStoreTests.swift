@testable import NDKSwiftCore
import Foundation
import XCTest

final class NDKCacheSQLiteStoreTests: XCTestCase {
    func testClearDecryptedContentLeavesOtherAuxiliaryTables() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ndkswift-aux-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")

        defer {
            try? FileManager.default.removeItem(at: dbURL)
            try? FileManager.default.removeItem(atPath: dbURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: dbURL.path + "-shm")
        }

        let store = try NDKCacheSQLiteStore(path: dbURL.path)
        let kvValue = Data([0x01, 0x02, 0x03])
        let nip05Entry = NIP05CacheEntry(
            identifier: "alice@example.com",
            pubkey: String(repeating: "a", count: 64),
            status: .verified,
            claimedAt: Date(timeIntervalSince1970: 1_700_000_000),
            verifiedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let fetchDate = Date(timeIntervalSince1970: 1_700_000_200)

        try await store.setKV(namespace: "namespace", key: "key", value: kvValue)
        try await store.addDeletedEvent("deleted-event")
        try await store.setDecrypted(key: "event:viewer", content: "plaintext")
        try await store.saveNIP05(identifier: nip05Entry.identifier, entryJSON: JSONEncoder().encode(nip05Entry))
        try await store.setFetchTime(fingerprint: "filter-fingerprint", at: fetchDate)

        try await store.clearDecryptedContent()

        let decryptedContent = try await store.getDecrypted(key: "event:viewer")
        let persistedKV = try await store.getKV(namespace: "namespace", key: "key")
        let deletedEvents = try await store.loadDeletedEvents()

        XCTAssertNil(decryptedContent)
        XCTAssertEqual(persistedKV, kvValue)
        XCTAssertEqual(deletedEvents, Set(["deleted-event"]))

        let nip05Rows = try await store.loadAllNIP05()
        XCTAssertEqual(nip05Rows.count, 1)
        XCTAssertEqual(nip05Rows.first?.identifier, nip05Entry.identifier)
        let decodedNIP05 = try JSONDecoder().decode(
            NIP05CacheEntry.self,
            from: try XCTUnwrap(nip05Rows.first?.entryJSON)
        )
        XCTAssertEqual(decodedNIP05, nip05Entry)

        let fetchRows = try await store.loadAllFetchTimes()
        XCTAssertEqual(fetchRows.count, 1)
        XCTAssertEqual(fetchRows.first?.fingerprint, "filter-fingerprint")
        let persistedFetchDate = try XCTUnwrap(fetchRows.first?.date)
        XCTAssertEqual(persistedFetchDate.timeIntervalSince1970, fetchDate.timeIntervalSince1970, accuracy: 1)
    }
}
