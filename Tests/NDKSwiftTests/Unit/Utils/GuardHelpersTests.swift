@testable import NDKSwiftCore
import XCTest

final class GuardHelpersTests: XCTestCase {
    // MARK: - Test Errors

    enum TestError: Error, Equatable {
        case testError
        case customError(String)
    }

    // MARK: - unwrap Tests

    func testUnwrapWithValue() throws {
        // Given
        let optionalValue: String? = "test"

        // When
        let result = try GuardHelpers.unwrap(optionalValue, error: TestError.testError)

        // Then
        XCTAssertEqual(result, "test")
    }

    func testUnwrapWithNilThrows() {
        // Given
        let optionalValue: String? = nil

        // When/Then
        XCTAssertThrowsError(try GuardHelpers.unwrap(optionalValue, error: TestError.testError)) { error in
            XCTAssertEqual(error as? TestError, TestError.testError)
        }
    }

    func testUnwrapWithDifferentTypes() throws {
        // Test with Int
        let intValue: Int? = 42
        let intResult = try GuardHelpers.unwrap(intValue, error: TestError.testError)
        XCTAssertEqual(intResult, 42)

        // Test with custom type
        struct CustomType: Equatable {
            let value: String
        }
        let customValue: CustomType? = CustomType(value: "test")
        let customResult = try GuardHelpers.unwrap(customValue, error: TestError.testError)
        XCTAssertEqual(customResult, CustomType(value: "test"))
    }

    // MARK: - requireNotEmpty String Tests

    func testRequireNotEmptyStringWithContent() throws {
        // Given
        let string = "test content"

        // When
        let result = try GuardHelpers.requireNotEmpty(string, error: TestError.testError)

        // Then
        XCTAssertEqual(result, "test content")
    }

    func testRequireNotEmptyStringWithEmptyStringThrows() {
        // Given
        let string = ""

        // When/Then
        XCTAssertThrowsError(try GuardHelpers.requireNotEmpty(string, error: TestError.testError)) { error in
            XCTAssertEqual(error as? TestError, TestError.testError)
        }
    }

    func testRequireNotEmptyStringWithWhitespace() throws {
        // Given - whitespace is not considered empty
        let string = "   "

        // When
        let result = try GuardHelpers.requireNotEmpty(string, error: TestError.testError)

        // Then
        XCTAssertEqual(result, "   ")
    }

    // MARK: - requireNotEmpty Array Tests

    func testRequireNotEmptyArrayWithElements() throws {
        // Given
        let array = [1, 2, 3]

        // When
        let result = try GuardHelpers.requireNotEmpty(array, error: TestError.testError)

        // Then
        XCTAssertEqual(result, [1, 2, 3])
    }

    func testRequireNotEmptyArrayWithEmptyArrayThrows() {
        // Given
        let array: [Int] = []

        // When/Then
        XCTAssertThrowsError(try GuardHelpers.requireNotEmpty(array, error: TestError.testError)) { error in
            XCTAssertEqual(error as? TestError, TestError.testError)
        }
    }

    func testRequireNotEmptyArrayWithDifferentTypes() throws {
        // Test with String array
        let stringArray = ["a", "b", "c"]
        let stringResult = try GuardHelpers.requireNotEmpty(stringArray, error: TestError.testError)
        XCTAssertEqual(stringResult, ["a", "b", "c"])

        // Test with custom type array
        struct CustomType: Equatable {
            let value: Int
        }
        let customArray = [CustomType(value: 1), CustomType(value: 2)]
        let customResult = try GuardHelpers.requireNotEmpty(customArray, error: TestError.testError)
        XCTAssertEqual(customResult.count, 2)
    }

    // MARK: - require Tests

    func testRequireWithPassingCondition() throws {
        // Given
        let value = 10

        // When
        let result = try GuardHelpers.require(value, condition: { $0 > 0 }, error: TestError.testError)

        // Then
        XCTAssertEqual(result, 10)
    }

    func testRequireWithFailingCondition() {
        // Given
        let value = -5

        // When/Then
        XCTAssertThrowsError(try GuardHelpers.require(value, condition: { $0 > 0 }, error: TestError.testError)) { error in
            XCTAssertEqual(error as? TestError, TestError.testError)
        }
    }

    func testRequireWithComplexConditions() throws {
        // Test string length condition
        let string = "hello"
        let stringResult = try GuardHelpers.require(string, condition: { $0.count >= 5 }, error: TestError.testError)
        XCTAssertEqual(stringResult, "hello")

        // Test array condition
        let array = [1, 2, 3, 4, 5]
        let arrayResult = try GuardHelpers.require(array, condition: { $0.count == 5 }, error: TestError.testError)
        XCTAssertEqual(arrayResult, [1, 2, 3, 4, 5])

        // Test custom type condition
        struct Person {
            let name: String
            let age: Int
        }
        let person = Person(name: "John", age: 25)
        let personResult = try GuardHelpers.require(person, condition: { $0.age >= 18 }, error: TestError.testError)
        XCTAssertEqual(personResult.name, "John")
    }

    // MARK: - requireContent Tests

    func testRequireContentWithValidContent() throws {
        // Given
        let content: String? = "valid content"

        // When
        let result = try GuardHelpers.requireContent(content, error: TestError.testError)

        // Then
        XCTAssertEqual(result, "valid content")
    }

    func testRequireContentWithNilThrows() {
        // Given
        let content: String? = nil

        // When/Then
        XCTAssertThrowsError(try GuardHelpers.requireContent(content, error: TestError.testError)) { error in
            XCTAssertEqual(error as? TestError, TestError.testError)
        }
    }

    func testRequireContentWithEmptyStringThrows() {
        // Given
        let content: String? = ""

        // When/Then
        XCTAssertThrowsError(try GuardHelpers.requireContent(content, error: TestError.testError)) { error in
            XCTAssertEqual(error as? TestError, TestError.testError)
        }
    }

    func testRequireContentWithWhitespace() throws {
        // Given - whitespace is considered valid content
        let content: String? = "   "

        // When
        let result = try GuardHelpers.requireContent(content, error: TestError.testError)

        // Then
        XCTAssertEqual(result, "   ")
    }

    // MARK: - Custom Error Tests

    func testCustomErrorPropagation() {
        // Test that custom errors are properly propagated
        let customError = TestError.customError("Custom message")

        // Test with unwrap
        let nilValue: String? = nil
        XCTAssertThrowsError(try GuardHelpers.unwrap(nilValue, error: customError)) { error in
            XCTAssertEqual(error as? TestError, TestError.customError("Custom message"))
        }

        // Test with requireNotEmpty
        XCTAssertThrowsError(try GuardHelpers.requireNotEmpty("", error: customError)) { error in
            XCTAssertEqual(error as? TestError, TestError.customError("Custom message"))
        }
    }

    // MARK: - Discardable Result Tests

    func testDiscardableResults() throws {
        // These methods have @discardableResult, so we can call them without using the result
        try GuardHelpers.requireNotEmpty("test", error: TestError.testError)
        try GuardHelpers.requireNotEmpty([1, 2, 3], error: TestError.testError)
        try GuardHelpers.require(5, condition: { $0 > 0 }, error: TestError.testError)

        // No assertions needed - just verifying compilation
    }
}
