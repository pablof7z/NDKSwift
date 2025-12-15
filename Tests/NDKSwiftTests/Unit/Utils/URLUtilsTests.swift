@testable import NDKSwiftCore
import XCTest

final class URLUtilsTests: XCTestCase {
    func testValidateURL_ValidURL_ReturnsURL() throws {
        let urlString = "https://example.com"
        let url = try URLUtils.validateURL(urlString)
        XCTAssertEqual(url.absoluteString, urlString)
    }

    func testValidateURL_ValidURLWithPath_ReturnsURL() throws {
        let urlString = "https://example.com/path/to/resource"
        let url = try URLUtils.validateURL(urlString)
        XCTAssertEqual(url.absoluteString, urlString)
    }

    func testValidateURL_ValidURLWithQuery_ReturnsURL() throws {
        let urlString = "https://example.com?param=value&other=test"
        let url = try URLUtils.validateURL(urlString)
        XCTAssertEqual(url.absoluteString, urlString)
    }

    func testValidateURL_InvalidURL_ThrowsError() {
        let invalidURLs = [
            "",
            " ",
            "not a url",
            "://invalid",
            "http://",
            "https://",
            "ftp://[invalid",
        ]

        for urlString in invalidURLs {
            XCTAssertThrowsError(try URLUtils.validateURL(urlString)) { error in
                guard case let NDKError.invalidURL(invalidString) = error else {
                    XCTFail("Expected NDKError.invalidURL but got \(error)")
                    return
                }
                XCTAssertEqual(invalidString, urlString)
            }
        }
    }

    func testSafeURL_ValidURL_ReturnsURL() {
        let urlString = "https://example.com"
        let url = URLUtils.safeURL(urlString)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, urlString)
    }

    func testSafeURL_InvalidURL_ReturnsNil() {
        let invalidURLs = [
            "",
            " ",
            "not a url",
            "://invalid",
            "http://",
            "https://",
            "ftp://[invalid",
        ]

        for urlString in invalidURLs {
            let url = URLUtils.safeURL(urlString)
            XCTAssertNil(url, "Expected nil for invalid URL: '\(urlString)'")
        }
    }

    func testSafeURL_SpecialCharacters_HandlesCorrectly() {
        let specialURLs = [
            "https://example.com/path%20with%20spaces",
            "https://example.com/unicode/测试",
            "https://example.com:8080/port",
            "ws://websocket.example.com",
            "wss://secure.websocket.example.com",
        ]

        for urlString in specialURLs {
            let url = URLUtils.safeURL(urlString)
            XCTAssertNotNil(url, "Expected valid URL for: '\(urlString)'")
        }
    }
}
