@testable import NDKSwiftCore
import XCTest

final class NIP05Tests: XCTestCase {
    var ndk: NDK!
    var cache: NDKNostrDBCache!

    override func setUp() async throws {
        try await super.setUp()
        cache = try await NDKTestFactory.createTestCache()
        ndk = NDK(cache: cache)
    }

    func testNIP05CacheOperations() async throws {
        // Test saving a NIP-05 entry
        let entry = NIP05CacheEntry(
            identifier: "alice@example.com",
            pubkey: "pubkey123",
            status: .verified,
            nip46Relays: ["wss://relay.example.com"],
            claimedAt: Date(),
            verifiedAt: Date(),
            lastCheckAt: Date(),
            errorMessage: nil,
            httpStatusCode: 200
        )

        try await cache.saveNIP05Entry(entry)

        // Test retrieving the entry
        let retrieved = await cache.getNIP05Entry("alice@example.com")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.pubkey, "pubkey123")
        XCTAssertEqual(retrieved?.status, .verified)

        // Test getting by pubkey
        let byPubkey = await cache.getNIP05ForPubkey("pubkey123")
        XCTAssertEqual(byPubkey, "alice@example.com")
    }

    func testNIP05SearchFunctionality() async throws {
        // Save multiple entries
        let entries = [
            NIP05CacheEntry(
                identifier: "alice@example.com",
                pubkey: "pubkey1",
                status: .verified,
                nip46Relays: nil,
                claimedAt: Date()
            ),
            NIP05CacheEntry(
                identifier: "bob@example.com",
                pubkey: "pubkey2",
                status: .verified,
                nip46Relays: nil,
                claimedAt: Date()
            ),
            NIP05CacheEntry(
                identifier: "alice@nostr.com",
                pubkey: "pubkey3",
                status: .unverified,
                nip46Relays: nil,
                claimedAt: Date()
            ),
        ]

        for entry in entries {
            try await cache.saveNIP05Entry(entry)
        }

        // Test search
        let aliceResults = await cache.searchNIP05("alice", limit: 10)
        XCTAssertEqual(aliceResults.count, 2)
        XCTAssertTrue(aliceResults.contains(where: { $0.identifier == "alice@example.com" }))
        XCTAssertTrue(aliceResults.contains(where: { $0.identifier == "alice@nostr.com" }))

        let exampleResults = await cache.searchNIP05("@example", limit: 10)
        XCTAssertEqual(exampleResults.count, 2)
        XCTAssertTrue(exampleResults.contains(where: { $0.identifier == "alice@example.com" }))
        XCTAssertTrue(exampleResults.contains(where: { $0.identifier == "bob@example.com" }))
    }

    func testNIP05VerificationStates() async throws {
        let identifier = "test@example.com"
        let pubkey = "testpubkey"

        // Test unverified state
        let unverified = NIP05CacheEntry(
            identifier: identifier,
            pubkey: pubkey,
            status: .unverified,
            nip46Relays: nil,
            claimedAt: Date()
        )
        try await cache.saveNIP05Entry(unverified)

        let needsVerification = await cache.needsNIP05Verification(identifier, maxAge: 86400)
        XCTAssertTrue(needsVerification, "Unverified entries should need verification")

        // Update to verified
        var verified = unverified
        verified.status = .verified
        verified.verifiedAt = Date()
        verified.lastCheckAt = Date()
        try await cache.saveNIP05Entry(verified)

        let needsVerificationAfter = await cache.needsNIP05Verification(identifier, maxAge: 86400)
        XCTAssertFalse(needsVerificationAfter, "Recently verified entries should not need verification")

        // Test invalidation
        try await cache.invalidateNIP05(identifier, actualPubkey: "differentpubkey")
        let invalidated = await cache.getNIP05Entry(identifier)
        XCTAssertEqual(invalidated?.status, .invalid)

        // The correct pubkey should now be saved
        let correctPubkey = await cache.getNIP05ForPubkey("differentpubkey")
        XCTAssertEqual(correctPubkey, identifier)
    }

    func testRateLimiting() async throws {
        let domain = "example.com"

        // First check should be allowed
        let canCheck1 = await cache.canCheckNIP05Domain(domain)
        XCTAssertTrue(canCheck1)

        // Record the check
        try await cache.recordNIP05DomainCheck(domain)

        // Immediate second check should be rate limited
        let canCheck2 = await cache.canCheckNIP05Domain(domain)
        XCTAssertFalse(canCheck2)
    }
}
