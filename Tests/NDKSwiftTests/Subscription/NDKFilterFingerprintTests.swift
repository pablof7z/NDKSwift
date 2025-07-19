import XCTest
@testable import NDKSwift

final class NDKFilterFingerprintTests: XCTestCase {
    
    func testBasicFingerprint() {
        let filter = NDKFilter(
            authors: ["author1"],
            kinds: [1]
        )
        
        let fingerprint = NDKFilterFingerprint(filters: [filter], closeOnEose: false)
        XCTAssertEqual(fingerprint.value, "authors-kinds")
    }
    
    func testFingerprintWithCloseOnEose() {
        let filter = NDKFilter(
            authors: ["author1"],
            kinds: [1]
        )
        
        let fingerprint = NDKFilterFingerprint(filters: [filter], closeOnEose: true)
        XCTAssertEqual(fingerprint.value, "+authors-kinds")
    }
    
    func testFingerprintIgnoresValues() {
        // Two filters with different values but same keys should have same fingerprint
        let filter1 = NDKFilter(
            authors: ["author1"],
            kinds: [1]
        )
        
        let filter2 = NDKFilter(
            authors: ["author2", "author3"],
            kinds: [1, 3, 7]
        )
        
        let fingerprint1 = NDKFilterFingerprint(filters: [filter1], closeOnEose: false)
        let fingerprint2 = NDKFilterFingerprint(filters: [filter2], closeOnEose: false)
        
        XCTAssertEqual(fingerprint1.value, fingerprint2.value)
    }
    
    func testFingerprintWithTimeConstraints() {
        // Time constraints include values to prevent mixing different windows
        let filter1 = NDKFilter(
            kinds: [1],
            since: 1000,
            until: 2000
        )
        
        let filter2 = NDKFilter(
            kinds: [1],
            since: 3000,
            until: 4000
        )
        
        let fingerprint1 = NDKFilterFingerprint(filters: [filter1], closeOnEose: false)
        let fingerprint2 = NDKFilterFingerprint(filters: [filter2], closeOnEose: false)
        
        XCTAssertEqual(fingerprint1.value, "kinds-since:1000-until:2000")
        XCTAssertEqual(fingerprint2.value, "kinds-since:3000-until:4000")
        XCTAssertNotEqual(fingerprint1.value, fingerprint2.value)
    }
    
    func testFingerprintWithAllFields() {
        let filter = NDKFilter(
            ids: ["id1"],
            authors: ["author1"],
            kinds: [1],
            events: ["event1"],
            pubkeys: ["pubkey1"],
            since: 1000,
            until: 2000,
            limit: 100
        )
        
        let fingerprint = NDKFilterFingerprint(filters: [filter], closeOnEose: false)
        let expectedKeys = "#e-#p-authors-ids-kinds-limit-since:1000-until:2000"
        XCTAssertEqual(fingerprint.value, expectedKeys)
    }
    
    func testFingerprintWithTags() {
        let filter = NDKFilter(
            kinds: [1],
            tags: [
                "t": ["bitcoin"],
                "a": ["30023:author:identifier"]
            ]
        )
        
        let fingerprint = NDKFilterFingerprint(filters: [filter], closeOnEose: false)
        XCTAssertEqual(fingerprint.value, "#a-#t-kinds")
    }
    
    func testFingerprintWithMultipleFilters() {
        let filter1 = NDKFilter(kinds: [1])
        let filter2 = NDKFilter(authors: ["author1"])
        let filter3 = NDKFilter(ids: ["id1"])
        
        let fingerprint = NDKFilterFingerprint(
            filters: [filter1, filter2, filter3],
            closeOnEose: false
        )
        
        XCTAssertEqual(fingerprint.value, "kinds|authors|ids")
    }
    
    func testFingerprintEquality() {
        let filter = NDKFilter(
            authors: ["author1"],
            kinds: [1, 3]
        )
        
        let fingerprint1 = NDKFilterFingerprint(filters: [filter], closeOnEose: false)
        let fingerprint2 = NDKFilterFingerprint(filters: [filter], closeOnEose: false)
        
        XCTAssertEqual(fingerprint1, fingerprint2)
        XCTAssertEqual(fingerprint1.hashValue, fingerprint2.hashValue)
    }
    
    func testFingerprintInequality() {
        let filter1 = NDKFilter(kinds: [1])
        let filter2 = NDKFilter(authors: ["author1"])
        
        let fingerprint1 = NDKFilterFingerprint(filters: [filter1], closeOnEose: false)
        let fingerprint2 = NDKFilterFingerprint(filters: [filter2], closeOnEose: false)
        
        XCTAssertNotEqual(fingerprint1, fingerprint2)
    }
}