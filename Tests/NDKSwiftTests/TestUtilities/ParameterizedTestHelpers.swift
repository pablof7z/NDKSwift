import XCTest
@testable import NDKSwift

// MARK: - Parameterized Test Support

/// A test case with input and expected output
struct TestCase<Input, Expected> {
    let name: String
    let input: Input
    let expected: Expected
    let file: StaticString
    let line: UInt
    
    init(
        _ name: String,
        input: Input,
        expected: Expected,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        self.name = name
        self.input = input
        self.expected = expected
        self.file = file
        self.line = line
    }
}

/// Extension to run parameterized tests
extension XCTestCase {
    
    /// Runs a parameterized test with multiple test cases
    func runParameterizedTest<Input, Expected>(
        testCases: [TestCase<Input, Expected>],
        test: (Input) throws -> Expected
    ) where Expected: Equatable {
        for testCase in testCases {
            do {
                let result = try test(testCase.input)
                XCTAssertEqual(
                    result,
                    testCase.expected,
                    "Test case '\(testCase.name)' failed",
                    file: testCase.file,
                    line: testCase.line
                )
            } catch {
                XCTFail(
                    "Test case '\(testCase.name)' threw error: \(error)",
                    file: testCase.file,
                    line: testCase.line
                )
            }
        }
    }
    
    /// Runs a parameterized async test with multiple test cases
    func runParameterizedAsyncTest<Input, Expected>(
        testCases: [TestCase<Input, Expected>],
        test: (Input) async throws -> Expected
    ) async where Expected: Equatable {
        for testCase in testCases {
            do {
                let result = try await test(testCase.input)
                XCTAssertEqual(
                    result,
                    testCase.expected,
                    "Test case '\(testCase.name)' failed",
                    file: testCase.file,
                    line: testCase.line
                )
            } catch {
                XCTFail(
                    "Test case '\(testCase.name)' threw error: \(error)",
                    file: testCase.file,
                    line: testCase.line
                )
            }
        }
    }
    
    /// Runs a parameterized test that should throw an error
    func runParameterizedErrorTest<Input, ErrorType: Error & Equatable>(
        testCases: [TestCase<Input, ErrorType>],
        test: (Input) throws -> Void
    ) {
        for testCase in testCases {
            XCTAssertThrowsError(
                try test(testCase.input),
                "Test case '\(testCase.name)' should throw error",
                file: testCase.file,
                line: testCase.line
            ) { error in
                XCTAssertEqual(
                    error as? ErrorType,
                    testCase.expected,
                    "Test case '\(testCase.name)' threw wrong error",
                    file: testCase.file,
                    line: testCase.line
                )
            }
        }
    }
    
    /// Runs a parameterized test with custom assertions
    func runParameterizedCustomTest<Input>(
        testCases: [TestCase<Input, Void>],
        test: (Input, _ testCase: TestCase<Input, Void>) throws -> Void
    ) {
        for testCase in testCases {
            do {
                try test(testCase.input, testCase)
            } catch {
                XCTFail(
                    "Test case '\(testCase.name)' threw error: \(error)",
                    file: testCase.file,
                    line: testCase.line
                )
            }
        }
    }
}

// MARK: - Common Test Data Types

/// Test case for Nostr identifier parsing
struct NostrIdentifierTestCase {
    let identifier: String
    let expectedType: NostrIdentifierType?
    let expectedData: NostrIdentifierData?
    
    enum NostrIdentifierType {
        case npub
        case nsec
        case note
        case nevent
        case naddr
        case nprofile
        case invalid
    }
    
    struct NostrIdentifierData {
        let hex: String?
        let relays: [String]?
        let author: String?
        let kind: Int?
        let identifier: String?
    }
}

/// Test case for URL normalization
struct URLNormalizationTestCase {
    let input: String
    let expected: String
}

/// Test case for filter matching
struct FilterMatchTestCase {
    let filter: NDKFilter
    let event: NDKEvent
    let shouldMatch: Bool
}

// MARK: - Test Data Builders

/// Builder for creating parameterized test data
struct TestDataBuilder {
    
    /// Creates test cases for Bech32 encoding/decoding
    static func bech32TestCases() -> [TestCase<(hrp: String, data: Data), String>] {
        return [
            TestCase(
                "npub encoding",
                input: ("npub", Data(repeating: 0x00, count: 32)),
                expected: "npub1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqsajtdv6"
            ),
            TestCase(
                "nsec encoding",
                input: ("nsec", Data(repeating: 0xFF, count: 32)),
                expected: "nsec1llllllllllllllllllllllllllllllllllllllllllllllllllllwj5xj8"
            ),
            TestCase(
                "note encoding",
                input: ("note", Data(repeating: 0xAB, count: 32)),
                expected: "note12k4k4jd4ftftftftftftftftftftftftftftftftftftftftfttfqj7x"
            )
        ]
    }
    
    /// Creates test cases for content tagging
    static func contentTaggingTestCases() -> [TestCase<String, [[String]]>] {
        return [
            TestCase(
                "simple hashtag",
                input: "Hello #nostr world",
                expected: [["t", "nostr"]]
            ),
            TestCase(
                "multiple hashtags",
                input: "#bitcoin and #lightning are cool",
                expected: [["t", "bitcoin"], ["t", "lightning"]]
            ),
            TestCase(
                "mention",
                input: "Hey @npub1234567890abcdef",
                expected: [["p", "1234567890abcdef"]]
            ),
            TestCase(
                "mixed tags",
                input: "Check out #nostr and talk to @npub1234567890abcdef",
                expected: [["t", "nostr"], ["p", "1234567890abcdef"]]
            ),
            TestCase(
                "no tags",
                input: "Just plain text",
                expected: []
            )
        ]
    }
    
    /// Creates test cases for event validation
    static func eventValidationTestCases() -> [TestCase<NDKEvent, Bool>] {
        return [
            TestCase(
                "valid event",
                input: EventTestHelpers.createTestEvent(),
                expected: true
            ),
            TestCase(
                "missing id",
                input: EventTestHelpers.createInvalidEvent(reason: .missingId),
                expected: false
            ),
            TestCase(
                "missing pubkey",
                input: EventTestHelpers.createInvalidEvent(reason: .missingPubkey),
                expected: false
            ),
            TestCase(
                "future date too far",
                input: EventTestHelpers.createInvalidEvent(reason: .futureDateTooFar),
                expected: false
            )
        ]
    }
}

// MARK: - XCTest Assertions Extensions

extension XCTestCase {
    
    /// Asserts that two arrays contain the same elements, regardless of order
    func assertArraysEqualUnordered<T: Equatable>(
        _ array1: [T],
        _ array2: [T],
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            array1.count,
            array2.count,
            "Arrays have different counts. \(message)",
            file: file,
            line: line
        )
        
        for element in array1 {
            XCTAssertTrue(
                array2.contains(element),
                "Element \(element) not found in second array. \(message)",
                file: file,
                line: line
            )
        }
    }
    
    /// Asserts that an async operation completes within a timeout
    func assertAsyncCompletes<T>(
        timeout: TimeInterval = 5.0,
        _ operation: () async throws -> T,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        let expectation = XCTestExpectation(description: "Async operation completes")
        
        Task {
            do {
                _ = try await operation()
                expectation.fulfill()
            } catch {
                XCTFail("Async operation failed: \(error)", file: file, line: line)
            }
        }
        
        await fulfillment(of: [expectation], timeout: timeout)
    }
}