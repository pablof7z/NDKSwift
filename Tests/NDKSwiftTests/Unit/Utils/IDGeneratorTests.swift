@testable import NDKSwiftCore
import XCTest

final class IDGeneratorTests: XCTestCase {
    // MARK: - Subscription ID Tests

    func testSubscriptionIdGeneration() async {
        let generator = IDGenerator()

        let id1 = await generator.nextSubscriptionId()
        let id2 = await generator.nextSubscriptionId()
        let id3 = await generator.nextSubscriptionId()

        XCTAssertEqual(id1, "sub1")
        XCTAssertEqual(id2, "sub2")
        XCTAssertEqual(id3, "sub3")
    }

    func testSubscriptionIdUniqueness() async {
        let generator = IDGenerator()
        var ids = Set<String>()

        // Generate many IDs
        for _ in 0 ..< 1000 {
            let id = await generator.nextSubscriptionId()
            XCTAssertFalse(ids.contains(id), "Duplicate ID generated: \(id)")
            ids.insert(id)
        }

        XCTAssertEqual(ids.count, 1000)
    }

    // MARK: - Request ID Tests

    func testRequestIdGeneration() async {
        let generator = IDGenerator()

        let id1 = await generator.nextRequestId()
        let id2 = await generator.nextRequestId()
        let id3 = await generator.nextRequestId()

        XCTAssertEqual(id1, "req1")
        XCTAssertEqual(id2, "req2")
        XCTAssertEqual(id3, "req3")
    }

    func testRequestIdUniqueness() async {
        let generator = IDGenerator()
        var ids = Set<String>()

        // Generate many IDs
        for _ in 0 ..< 1000 {
            let id = await generator.nextRequestId()
            XCTAssertFalse(ids.contains(id), "Duplicate ID generated: \(id)")
            ids.insert(id)
        }

        XCTAssertEqual(ids.count, 1000)
    }

    // MARK: - Mixed ID Generation Tests

    func testMixedIdGeneration() async {
        let generator = IDGenerator()

        let sub1 = await generator.nextSubscriptionId()
        let req1 = await generator.nextRequestId()
        let sub2 = await generator.nextSubscriptionId()
        let req2 = await generator.nextRequestId()

        XCTAssertEqual(sub1, "sub1")
        XCTAssertEqual(req1, "req1")
        XCTAssertEqual(sub2, "sub2")
        XCTAssertEqual(req2, "req2")
    }

    // MARK: - Random ID Tests

    func testRandomIdDefault() {
        let id = IDGenerator.randomId()
        XCTAssertEqual(id.count, 8)
        XCTAssertTrue(id.allSatisfy { $0.isLetter || $0.isNumber })
    }

    func testRandomIdWithPrefix() {
        let id = IDGenerator.randomId(prefix: "test")
        XCTAssertTrue(id.hasPrefix("test_"))
        XCTAssertEqual(id.count, 13) // "test_" (5) + 8 random chars
    }

    func testRandomIdWithCustomLength() {
        let id = IDGenerator.randomId(length: 16)
        XCTAssertEqual(id.count, 16)
        XCTAssertTrue(id.allSatisfy { $0.isLetter || $0.isNumber })
    }

    func testRandomIdWithPrefixAndLength() {
        let id = IDGenerator.randomId(prefix: "auth", length: 12)
        XCTAssertTrue(id.hasPrefix("auth_"))
        XCTAssertEqual(id.count, 17) // "auth_" (5) + 12 random chars
    }

    func testRandomIdUniqueness() {
        var ids = Set<String>()

        // Generate many random IDs
        for _ in 0 ..< 1000 {
            let id = IDGenerator.randomId()
            ids.insert(id)
        }

        // Should be highly unlikely to have duplicates
        XCTAssertEqual(ids.count, 1000)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentSubscriptionIdGeneration() async {
        let generator = IDGenerator()
        let taskCount = 100

        // Launch many concurrent tasks
        let ids = await withTaskGroup(of: String.self) { group in
            for _ in 0 ..< taskCount {
                group.addTask {
                    await generator.nextSubscriptionId()
                }
            }

            var results = [String]()
            for await id in group {
                results.append(id)
            }
            return results
        }

        // All IDs should be unique
        let uniqueIds = Set(ids)
        XCTAssertEqual(uniqueIds.count, taskCount)

        // IDs should be in the format sub1, sub2, ..., sub100
        for i in 1 ... taskCount {
            XCTAssertTrue(uniqueIds.contains("sub\(i)"))
        }
    }

    func testConcurrentMixedIdGeneration() async {
        let generator = IDGenerator()
        let taskCount = 50

        // Launch concurrent tasks for both subscription and request IDs
        let (subIds, reqIds) = await withTaskGroup(of: (String, String).self) { group in
            for _ in 0 ..< taskCount {
                group.addTask {
                    let subId = await generator.nextSubscriptionId()
                    let reqId = await generator.nextRequestId()
                    return (subId, reqId)
                }
            }

            var subs = [String]()
            var reqs = [String]()
            for await(subId, reqId) in group {
                subs.append(subId)
                reqs.append(reqId)
            }
            return (subs, reqs)
        }

        // All IDs should be unique within their type
        XCTAssertEqual(Set(subIds).count, taskCount)
        XCTAssertEqual(Set(reqIds).count, taskCount)
    }

    // MARK: - Shared Instance Tests

    func testSharedGeneratorInstance() async {
        // Reset any previous state by using a local generator
        let localGenerator = IDGenerator()

        // Test that shared instance works
        let id1 = await sharedIDGenerator.nextSubscriptionId()
        let id2 = await sharedIDGenerator.nextRequestId()

        XCTAssertTrue(id1.hasPrefix("sub"))
        XCTAssertTrue(id2.hasPrefix("req"))

        // Local generator should have independent counters
        let localId1 = await localGenerator.nextSubscriptionId()
        let localId2 = await localGenerator.nextRequestId()

        XCTAssertEqual(localId1, "sub1")
        XCTAssertEqual(localId2, "req1")
    }
}
