import XCTest
@testable import NDKSwift

final class NostrIdentifierTests: XCTestCase {
    
    // MARK: - Valid Identifier Test Cases
    
    func testValidIdentifiers() throws {
        struct ValidTestCase {
            let name: String
            let identifier: String
            let setupIdentifier: () throws -> String
            let expectedFilter: (NDKFilter) -> Bool
        }
        
        let eventId = "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36"
        let author = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        
        let testCases = [
            ValidTestCase(
                name: "Hex Event ID",
                identifier: eventId,
                setupIdentifier: { eventId },
                expectedFilter: { filter in
                    filter.ids?.count == 1 &&
                    filter.ids?.first == eventId &&
                    filter.authors == nil &&
                    filter.kinds == nil
                }
            ),
            ValidTestCase(
                name: "Note Bech32",
                identifier: "",
                setupIdentifier: { try Bech32.note(from: eventId) },
                expectedFilter: { filter in
                    filter.ids?.count == 1 &&
                    filter.ids?.first == eventId &&
                    filter.authors == nil &&
                    filter.kinds == nil
                }
            ),
            ValidTestCase(
                name: "Nevent Bech32",
                identifier: "",
                setupIdentifier: {
                    try Bech32.nevent(
                        eventId: eventId,
                        relays: ["wss://relay.damus.io"],
                        author: author,
                        kind: 1
                    )
                },
                expectedFilter: { filter in
                    filter.ids?.count == 1 &&
                    filter.ids?.first == eventId &&
                    filter.authors == nil &&
                    filter.kinds == nil
                }
            ),
            ValidTestCase(
                name: "Naddr Bech32",
                identifier: "",
                setupIdentifier: {
                    try Bech32.naddr(
                        identifier: "1234",
                        kind: 30023,
                        author: author,
                        relays: ["wss://relay.damus.io"]
                    )
                },
                expectedFilter: { filter in
                    filter.ids == nil &&
                    filter.authors?.count == 1 &&
                    filter.authors?.first == author &&
                    filter.kinds?.count == 1 &&
                    filter.kinds?.first == 30023 &&
                    filter.tagFilter("d") == ["1234"]
                }
            ),
            ValidTestCase(
                name: "Naddr with empty identifier",
                identifier: "",
                setupIdentifier: {
                    try Bech32.naddr(
                        identifier: "",
                        kind: 30023,
                        author: author
                    )
                },
                expectedFilter: { filter in
                    filter.ids == nil &&
                    filter.authors?.count == 1 &&
                    filter.authors?.first == author &&
                    filter.kinds?.count == 1 &&
                    filter.kinds?.first == 30023 &&
                    filter.tagFilter("d") == [""]
                }
            )
        ]
        
        for testCase in testCases {
            let identifier = try testCase.setupIdentifier()
            let filter = try NostrIdentifier.createFilter(from: identifier)
            
            XCTAssertTrue(
                testCase.expectedFilter(filter),
                "Test case '\(testCase.name)' failed: filter does not match expected properties"
            )
        }
    }
    
    // MARK: - Invalid Identifier Test Cases
    
    func testInvalidIdentifiers() {
        let invalidIdentifierTestCases: [TestCase<String, NDKError>] = [
            TestCase(
                "Empty string",
                input: "",
                expected: NDKError.invalidInput("Identifier cannot be empty")
            ),
            TestCase(
                "Whitespace only",
                input: "   ",
                expected: NDKError.invalidInput("Identifier cannot be empty")
            ),
            TestCase(
                "Hex too short",
                input: "5c83da77",
                expected: NDKError.invalidInput("Invalid hex event ID: must be 64 characters")
            ),
            TestCase(
                "Hex too long",
                input: "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f3600",
                expected: NDKError.invalidInput("Invalid hex event ID: must be 64 characters")
            )
        ]
        
        runParameterizedErrorTest(testCases: invalidIdentifierTestCases) { identifier in
            _ = try NostrIdentifier.createFilter(from: identifier)
        }
    }
    
    // MARK: - Unsupported Bech32 Types
    
    func testUnsupportedBech32Types() throws {
        struct UnsupportedTestCase {
            let name: String
            let createBech32: () throws -> String
        }
        
        let pubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        
        let testCases = [
            UnsupportedTestCase(
                name: "npub",
                createBech32: { try Bech32.npub(from: pubkey) }
            ),
            UnsupportedTestCase(
                name: "nsec",
                createBech32: { try Bech32.nsec(from: pubkey) }
            )
        ]
        
        for testCase in testCases {
            let bech32 = try testCase.createBech32()
            
            XCTAssertThrowsError(
                try NostrIdentifier.createFilter(from: bech32),
                "Test case '\(testCase.name)' should throw error"
            ) { error in
                guard case NDKError.invalidInput(let message) = error else {
                    XCTFail("Expected invalidInput error for \(testCase.name)")
                    return
                }
                XCTAssertTrue(
                    message.contains("Unsupported bech32 type"),
                    "Error message should mention unsupported bech32 type for \(testCase.name)"
                )
            }
        }
    }
    
    // MARK: - Invalid Bech32 Strings
    
    func testInvalidBech32Strings() {
        let invalidBech32TestCases = [
            "invalid1bech32",
            "note1invalid",
            "nevent1toolong" + String(repeating: "a", count: 1000),
            "naddr1!@#$%^&*()",
            "1234567890"
        ]
        
        for invalidString in invalidBech32TestCases {
            XCTAssertThrowsError(
                try NostrIdentifier.createFilter(from: invalidString),
                "Should throw error for invalid bech32: \(invalidString)"
            ) { error in
                XCTAssertNotNil(error, "Error should not be nil for: \(invalidString)")
            }
        }
    }
}