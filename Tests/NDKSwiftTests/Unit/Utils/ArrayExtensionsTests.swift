import XCTest
@testable import NDKSwift

final class ArrayExtensionsTests: XCTestCase {
    
    func testChunkedWithValidSize() {
        let array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let chunks = array.chunked(size: 3)
        
        XCTAssertEqual(chunks.count, 4)
        XCTAssertEqual(chunks[0], [1, 2, 3])
        XCTAssertEqual(chunks[1], [4, 5, 6])
        XCTAssertEqual(chunks[2], [7, 8, 9])
        XCTAssertEqual(chunks[3], [10])
    }
    
    func testChunkedWithSizeOne() {
        let array = ["a", "b", "c"]
        let chunks = array.chunked(size: 1)
        
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], ["a"])
        XCTAssertEqual(chunks[1], ["b"])
        XCTAssertEqual(chunks[2], ["c"])
    }
    
    func testChunkedWithSizeLargerThanArray() {
        let array = [1, 2, 3]
        let chunks = array.chunked(size: 5)
        
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], [1, 2, 3])
    }
    
    func testChunkedWithEmptyArray() {
        let array: [Int] = []
        let chunks = array.chunked(size: 3)
        
        XCTAssertTrue(chunks.isEmpty)
    }
    
    func testChunkedWithZeroSize() {
        let array = [1, 2, 3]
        let chunks = array.chunked(size: 0)
        
        XCTAssertTrue(chunks.isEmpty)
    }
    
    func testUniquePreservesOrder() {
        let array = [1, 2, 3, 2, 4, 3, 5]
        let unique = array.unique()
        
        XCTAssertEqual(unique, [1, 2, 3, 4, 5])
    }
    
    func testUniqueWithStrings() {
        let array = ["apple", "banana", "apple", "cherry", "banana", "date"]
        let unique = array.unique()
        
        XCTAssertEqual(unique, ["apple", "banana", "cherry", "date"])
    }
    
    func testUniqueWithEmptyArray() {
        let array: [Int] = []
        let unique = array.unique()
        
        XCTAssertTrue(unique.isEmpty)
    }
    
    func testUniqueWithAllDuplicates() {
        let array = [1, 1, 1, 1, 1]
        let unique = array.unique()
        
        XCTAssertEqual(unique, [1])
    }
    
    func testUniqueWithNoDuplicates() {
        let array = [1, 2, 3, 4, 5]
        let unique = array.unique()
        
        XCTAssertEqual(unique, array)
    }
}