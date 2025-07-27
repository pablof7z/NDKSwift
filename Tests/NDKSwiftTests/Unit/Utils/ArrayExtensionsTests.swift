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
    
    // MARK: - Safe Subscript Tests
    
    func testSafeSubscript_validIndex() {
        let array = ["a", "b", "c", "d"]
        
        XCTAssertEqual(array[safe: 0], "a")
        XCTAssertEqual(array[safe: 2], "c")
        XCTAssertEqual(array[safe: 3], "d")
    }
    
    func testSafeSubscript_invalidIndex() {
        let array = [1, 2, 3]
        
        XCTAssertNil(array[safe: -1])
        XCTAssertNil(array[safe: 3])
        XCTAssertNil(array[safe: 100])
    }
    
    func testSafeSubscript_emptyArray() {
        let array: [String] = []
        
        XCTAssertNil(array[safe: 0])
        XCTAssertNil(array[safe: -1])
    }
    
    // MARK: - Async Filter Tests
    
    func testAsyncFilter() async {
        let numbers = [1, 2, 3, 4, 5, 6]
        
        let evenNumbers = await numbers.asyncFilter { number in
            // Simulate async work
            try? await Task.sleep(nanoseconds: 1_000)
            return number % 2 == 0
        }
        
        XCTAssertEqual(evenNumbers, [2, 4, 6])
    }
    
    func testAsyncFilter_emptyArray() async {
        let empty: [Int] = []
        
        let filtered = await empty.asyncFilter { _ in true }
        
        XCTAssertTrue(filtered.isEmpty)
    }
    
    func testAsyncFilter_noneMatch() async {
        let numbers = [1, 3, 5, 7]
        
        let evenNumbers = await numbers.asyncFilter { $0 % 2 == 0 }
        
        XCTAssertTrue(evenNumbers.isEmpty)
    }
    
    // MARK: - NDKEvent Array Extension Tests
    
    func testMostRecent_withEvents() {
        let event1 = NDKEvent(
            pubkey: "test",
            createdAt: 1000,
            kind: .textNote,
            tags: [],
            content: "oldest"
        )
        let event2 = NDKEvent(
            pubkey: "test",
            createdAt: 2000,
            kind: .textNote,
            tags: [],
            content: "middle"
        )
        let event3 = NDKEvent(
            pubkey: "test",
            createdAt: 3000,
            kind: .textNote,
            tags: [],
            content: "newest"
        )
        
        let events = [event1, event3, event2]
        let mostRecent = events.mostRecent
        
        XCTAssertEqual(mostRecent?.createdAt, 3000)
        XCTAssertEqual(mostRecent?.content, "newest")
    }
    
    func testMostRecent_emptyArray() {
        let events: [NDKEvent] = []
        XCTAssertNil(events.mostRecent)
    }
    
    func testOldest_withEvents() {
        let event1 = NDKEvent(
            pubkey: "test",
            createdAt: 1000,
            kind: .textNote,
            tags: [],
            content: "oldest"
        )
        let event2 = NDKEvent(
            pubkey: "test",
            createdAt: 2000,
            kind: .textNote,
            tags: [],
            content: "newest"
        )
        
        let events = [event2, event1]
        let oldest = events.oldest
        
        XCTAssertEqual(oldest?.createdAt, 1000)
        XCTAssertEqual(oldest?.content, "oldest")
    }
    
    func testSortedByRecency() {
        let event1 = NDKEvent(
            pubkey: "test",
            createdAt: 1000,
            kind: .textNote,
            tags: [],
            content: "1"
        )
        let event2 = NDKEvent(
            pubkey: "test",
            createdAt: 3000,
            kind: .textNote,
            tags: [],
            content: "3"
        )
        let event3 = NDKEvent(
            pubkey: "test",
            createdAt: 2000,
            kind: .textNote,
            tags: [],
            content: "2"
        )
        
        let events = [event1, event2, event3]
        let sorted = events.sortedByRecency()
        
        XCTAssertEqual(sorted[0].createdAt, 3000)
        XCTAssertEqual(sorted[1].createdAt, 2000)
        XCTAssertEqual(sorted[2].createdAt, 1000)
    }
    
    func testSortedByAge() {
        let event1 = NDKEvent(
            pubkey: "test",
            createdAt: 1000,
            kind: .textNote,
            tags: [],
            content: "1"
        )
        let event2 = NDKEvent(
            pubkey: "test",
            createdAt: 3000,
            kind: .textNote,
            tags: [],
            content: "3"
        )
        
        let events = [event2, event1]
        let sorted = events.sortedByAge()
        
        XCTAssertEqual(sorted[0].createdAt, 1000)
        XCTAssertEqual(sorted[1].createdAt, 3000)
    }
    
    // MARK: - Mutation Extension Tests
    
    func testRemoveAllWhere() {
        var numbers = [1, 2, 3, 4, 5, 6]
        let removed = numbers.removeAll { $0 % 2 == 0 }
        
        XCTAssertEqual(numbers, [1, 3, 5])
        XCTAssertEqual(removed, [2, 4, 6])
    }
    
    func testRemoveAllWhere_noneMatch() {
        var numbers = [1, 3, 5]
        let removed = numbers.removeAll { $0 % 2 == 0 }
        
        XCTAssertEqual(numbers, [1, 3, 5])
        XCTAssertTrue(removed.isEmpty)
    }
    
    func testRemoveAllValue() {
        var letters = ["a", "b", "c", "b", "d", "b"]
        letters.removeAll(value: "b")
        
        XCTAssertEqual(letters, ["a", "c", "d"])
    }
    
    func testRemoveAllValue_notFound() {
        var numbers = [1, 2, 3]
        numbers.removeAll(value: 4)
        
        XCTAssertEqual(numbers, [1, 2, 3])
    }
}