import XCTest

/// A test case with an input and expected output
struct TestCase<Input, Output> {
    let name: String
    let input: Input
    let expected: Output
    
    init(_ name: String, input: Input, expected: Output) {
        self.name = name
        self.input = input
        self.expected = expected
    }
}

/// Run a parameterized test with multiple test cases
func runParameterizedTest<Input, Output: Equatable>(
    testCases: [TestCase<Input, Output>],
    test: (Input) throws -> Output,
    file: StaticString = #file,
    line: UInt = #line
) {
    for testCase in testCases {
        let result: Output
        do {
            result = try test(testCase.input)
        } catch {
            XCTFail("Test '\(testCase.name)' threw error: \(error)", file: file, line: line)
            continue
        }
        
        XCTAssertEqual(
            result,
            testCase.expected,
            "Test '\(testCase.name)' failed",
            file: file,
            line: line
        )
    }
}

/// Run a parameterized test that expects errors
func runParameterizedErrorTest<Input, ErrorType: Error & Equatable>(
    testCases: [TestCase<Input, ErrorType>],
    test: (Input) throws -> Void,
    file: StaticString = #file,
    line: UInt = #line
) {
    for testCase in testCases {
        do {
            try test(testCase.input)
            XCTFail("Test '\(testCase.name)' should have thrown error but didn't", file: file, line: line)
        } catch let error as ErrorType {
            XCTAssertEqual(
                error,
                testCase.expected,
                "Test '\(testCase.name)' threw wrong error",
                file: file,
                line: line
            )
        } catch {
            XCTFail("Test '\(testCase.name)' threw unexpected error type: \(error)", file: file, line: line)
        }
    }
}

/// Run an async parameterized test
func runParameterizedAsyncTest<Input, Output: Equatable>(
    testCases: [TestCase<Input, Output>],
    test: (Input) async throws -> Output,
    file: StaticString = #file,
    line: UInt = #line
) async {
    for testCase in testCases {
        let result: Output
        do {
            result = try await test(testCase.input)
        } catch {
            XCTFail("Test '\(testCase.name)' threw error: \(error)", file: file, line: line)
            continue
        }
        
        XCTAssertEqual(
            result,
            testCase.expected,
            "Test '\(testCase.name)' failed",
            file: file,
            line: line
        )
    }
}