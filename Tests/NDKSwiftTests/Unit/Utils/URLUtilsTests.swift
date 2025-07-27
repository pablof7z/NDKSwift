import XCTest
@testable import NDKSwift

final class URLUtilsTests: XCTestCase {
    
    func testValidateURL_ValidHTTPURL() throws {
        let urlString = "https://example.com"
        let url = try URLUtils.validateURL(urlString)
        XCTAssertEqual(url.absoluteString, urlString)
    }
    
    func testValidateURL_ValidHTTPURLWithPath() throws {
        let urlString = "https://example.com/path/to/resource"
        let url = try URLUtils.validateURL(urlString)
        XCTAssertEqual(url.absoluteString, urlString)
    }
    
    func testValidateURL_ValidHTTPURLWithQuery() throws {
        let urlString = "https://example.com/search?q=test&page=1"
        let url = try URLUtils.validateURL(urlString)
        XCTAssertEqual(url.absoluteString, urlString)
    }
    
    func testValidateURL_ValidWebSocketURL() throws {
        let urlString = "wss://relay.example.com"
        let url = try URLUtils.validateURL(urlString)
        XCTAssertEqual(url.absoluteString, urlString)
    }
    
    func testValidateURL_ValidURLWithPort() throws {
        let urlString = "https://example.com:8080/api"
        let url = try URLUtils.validateURL(urlString)
        XCTAssertEqual(url.absoluteString, urlString)
    }
    
    func testValidateURL_ValidURLWithAuthentication() throws {
        let urlString = "https://user:pass@example.com"
        let url = try URLUtils.validateURL(urlString)
        XCTAssertEqual(url.absoluteString, urlString)
    }
    
    func testValidateURL_InvalidURL_EmptyString() {
        let urlString = ""
        XCTAssertThrowsError(try URLUtils.validateURL(urlString)) { error in
            XCTAssertTrue(error is NDKError)
            if case NDKError.invalidURL(let invalid) = error as! NDKError {
                XCTAssertEqual(invalid, urlString)
            } else {
                XCTFail("Expected NDKError.invalidURL")
            }
        }
    }
    
    func testValidateURL_InvalidURL_MalformedURL() {
        let urlString = "ht!tp://bad url with spaces"
        XCTAssertThrowsError(try URLUtils.validateURL(urlString)) { error in
            XCTAssertTrue(error is NDKError)
            if case NDKError.invalidURL(let invalid) = error as! NDKError {
                XCTAssertEqual(invalid, urlString)
            } else {
                XCTFail("Expected NDKError.invalidURL")
            }
        }
    }
    
    func testValidateURL_InvalidURL_NoScheme() throws {
        // URLs without scheme are actually valid in Foundation
        let urlString = "example.com"
        let url = try URLUtils.validateURL(urlString)
        XCTAssertEqual(url.absoluteString, urlString)
    }
    
    func testSafeURL_ValidURL() {
        let urlString = "https://example.com"
        let url = URLUtils.safeURL(urlString)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, urlString)
    }
    
    func testSafeURL_InvalidURL() {
        let urlString = "ht!tp://bad url with spaces"
        let url = URLUtils.safeURL(urlString)
        XCTAssertNil(url)
    }
    
    func testSafeURL_EmptyString() {
        let urlString = ""
        let url = URLUtils.safeURL(urlString)
        XCTAssertNil(url)
    }
    
    func testSafeURL_ValidComplexURL() {
        let urlString = "https://user:pass@example.com:8080/path?query=value#fragment"
        let url = URLUtils.safeURL(urlString)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, urlString)
    }
    
    func testSafeURL_URLWithSpecialCharacters() {
        let urlString = "https://example.com/path%20with%20spaces"
        let url = URLUtils.safeURL(urlString)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, urlString)
    }
    
    func testSafeURL_FileURL() {
        let urlString = "file:///Users/test/document.pdf"
        let url = URLUtils.safeURL(urlString)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, urlString)
    }
    
    func testSafeURL_DataURL() {
        let urlString = "data:text/plain;base64,SGVsbG8sIFdvcmxkIQ=="
        let url = URLUtils.safeURL(urlString)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, urlString)
    }
}