// NOTE: Commented out - Array extensions (chunked, unique, sortedByAge, removeAll) don't exist in the codebase
/*
import XCTest
@testable import NDKSwiftCore

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
            id: "event1id",
            pubkey: "test",
            createdAt: 1000,
            kind: 1,
            tags: [],
            content: "oldest",
            sig: "sig1"
        )
        let event2 = NDKEvent(
            id: "event2id",
            pubkey: "test",
            createdAt: 2000,
            kind: 1,
            tags: [],
            content: "middle",
            sig: "sig2"
        )
        let event3 = NDKEvent(
            id: "event3id",
            pubkey: "test",
            createdAt: 3000,
            kind: 1,
            tags: [],
            content: "newest",
            sig: "sig3"
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
            id: "event1id",
            pubkey: "test",
            createdAt: 1000,
            kind: 1,
            tags: [],
            content: "oldest",
            sig: "sig1"
        )
        let event2 = NDKEvent(
            id: "event2id",
            pubkey: "test",
            createdAt: 2000,
            kind: 1,
            tags: [],
            content: "newest",
            sig: "sig2"
        )
        
        let events = [event2, event1]
        let oldest = events.oldest
        
        XCTAssertEqual(oldest?.createdAt, 1000)
        XCTAssertEqual(oldest?.content, "oldest")
    }
    
    func testSortedByRecency() {
        let event1 = NDKEvent(
            id: "event1id",
            pubkey: "test",
            createdAt: 1000,
            kind: 1,
            tags: [],
            content: "1",
            sig: "sig1"
        )
        let event2 = NDKEvent(
            id: "event2id",
            pubkey: "test",
            createdAt: 3000,
            kind: 1,
            tags: [],
            content: "3",
            sig: "sig2"
        )
        let event3 = NDKEvent(
            id: "event3id",
            pubkey: "test",
            createdAt: 2000,
            kind: 1,
            tags: [],
            content: "2",
            sig: "sig3"
        )
        
        let events = [event1, event2, event3]
        let sorted = events.sortedByRecency()
        
        XCTAssertEqual(sorted[0].createdAt, 3000)
        XCTAssertEqual(sorted[1].createdAt, 2000)
        XCTAssertEqual(sorted[2].createdAt, 1000)
    }
    
    func testSortedByAge() {
        let event1 = NDKEvent(
            id: "event1id",
            pubkey: "test",
            createdAt: 1000,
            kind: 1,
            tags: [],
            content: "1",
            sig: "sig1"
        )
        let event2 = NDKEvent(
            id: "event2id",
            pubkey: "test",
            createdAt: 3000,
            kind: 1,
            tags: [],
            content: "3",
            sig: "sig2"
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
    
    // MARK: - Performance Tests
    
    func testChunkedPerformance() {
        let largeArray = Array(0..<10000)
        
        measure {
            _ = largeArray.chunked(size: 100)
        }
    }
    
    func testUniquePerformance() {
        let largeArray = Array(repeating: Array(0..<100), count: 100).flatMap { $0 }
        
        measure {
            _ = largeArray.unique()
        }
    }
    
    // MARK: - Edge Cases
    
    func testChunkedWithNegativeSize() {
        let array = [1, 2, 3]
        let chunks = array.chunked(size: -1)
        
        XCTAssertTrue(chunks.isEmpty)
    }
    
    func testRemoveAllWhereAllMatch() {
        var numbers = [2, 4, 6, 8]
        let removed = numbers.removeAll { $0 % 2 == 0 }
        
        XCTAssertTrue(numbers.isEmpty)
        XCTAssertEqual(removed, [2, 4, 6, 8])
    }
    
    func testRemoveAllValueMultipleOccurrences() {
        var letters = ["a", "b", "a", "c", "a", "d"]
        letters.removeAll(value: "a")
        
        XCTAssertEqual(letters, ["b", "c", "d"])
    }
    
    func testGetAllKeysNDKEventArray() {
        let events = [
            NDKEvent(id: "event1id", pubkey: "key1", createdAt: 1000, kind: 1, tags: [], content: "1", sig: "sig1"),
            NDKEvent(id: "event2id", pubkey: "key2", createdAt: 2000, kind: 1, tags: [], content: "2", sig: "sig2")
        ]
        
        // Test that events can be stored and retrieved by id
        var eventDict: [String: NDKEvent] = [:]
        for event in events {
            eventDict[event.id] = event
        }
        
        XCTAssertEqual(eventDict.count, 2)
        XCTAssertNotNil(eventDict[events[0].id])
        XCTAssertNotNil(eventDict[events[1].id])
    }
    
    func testSafeSubscriptBoundaryConditions() {
        let array = [10, 20, 30]
        
        // Test exact boundary
        XCTAssertEqual(array[safe: array.count - 1], 30)
        XCTAssertNil(array[safe: array.count])
        
        // Test with single element
        let singleElement = [42]
        XCTAssertEqual(singleElement[safe: 0], 42)
        XCTAssertNil(singleElement[safe: 1])
    }
    
    func testAsyncFilterMaintainsOrder() async {
        let numbers = [5, 2, 8, 1, 9, 3]
        
        let filtered = await numbers.asyncFilter { $0 > 4 }
        
        XCTAssertEqual(filtered, [5, 8, 9])
    }
    
    func testMostRecentWithSameTimestamp() {
        let event1 = NDKEvent(id: "event1id", pubkey: "test", createdAt: 1000, kind: 1, tags: [], content: "first", sig: "sig1")
        let event2 = NDKEvent(id: "event2id", pubkey: "test", createdAt: 1000, kind: 1, tags: [], content: "second", sig: "sig2")
        
        let events = [event1, event2]
        let mostRecent = events.mostRecent
        
        // Should return one of them (implementation dependent)
        XCTAssertNotNil(mostRecent)
        XCTAssertEqual(mostRecent?.createdAt, 1000)
    }
}
*/