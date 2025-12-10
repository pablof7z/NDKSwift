import XCTest
import GRDB
@testable import NDKSwiftCore
@testable import NDKSwiftSQLite

final class SQLiteQueryBuilderTests: XCTestCase {
    
    // MARK: - Basic Filter Tests
    
    func testBuildFilterWithIds() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter(ids: ["id1", "id2", "id3"])
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(whereClauses.count, 1)
        XCTAssertEqual(whereClauses[0], "e.id IN (?, ?, ?)")
        // Note: Cannot access arguments.values as it's internal to GRDB
        // The test verifies the SQL structure is correct
    }
    
    func testBuildFilterWithAuthors() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter(authors: ["pubkey1", "pubkey2"])
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(whereClauses.count, 1)
        XCTAssertEqual(whereClauses[0], "e.pubkey IN (?, ?)")
        // Note: Cannot access arguments.values as it's internal to GRDB
    }
    
    func testBuildFilterWithKinds() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter(kinds: [1, 3, 7])
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(whereClauses.count, 1)
        XCTAssertEqual(whereClauses[0], "e.kind IN (?, ?, ?)")
        // Note: Cannot access arguments.values as it's internal to GRDB
    }
    
    func testBuildFilterWithTimeRange() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter()
        let fromTime = Timestamp(1000)
        let toTime = Timestamp(2000)
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex,
            includeTimeRange: (from: fromTime, to: toTime)
        )
        
        XCTAssertEqual(whereClauses.count, 1)
        XCTAssertEqual(whereClauses[0], "e.created_at >= ? AND e.created_at < ?")
        // Note: Cannot access arguments.values as it's internal to GRDB
    }
    
    func testBuildFilterWithSinceAndUntil() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter(since: Timestamp(1000), until: Timestamp(2000))
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(whereClauses.count, 2)
        XCTAssertTrue(whereClauses.contains("e.created_at >= ?"))
        XCTAssertTrue(whereClauses.contains("e.created_at <= ?"))
        // Note: Cannot access arguments.values as it's internal to GRDB
    }
    
    // MARK: - Tag Filter Tests
    
    func testBuildFilterWithSingleTag() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter(tags: ["e": Set(["event1"])])
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(joins.count, 1)
        XCTAssertEqual(joins[0], "INNER JOIN tags t0 ON t0.event_id = e.id")
        XCTAssertEqual(whereClauses.count, 1)
        XCTAssertEqual(whereClauses[0], "(t0.tag_name = ? AND t0.tag_value = ?)")
        // Note: Cannot access arguments.values as it's internal to GRDB
    }
    
    func testBuildFilterWithMultipleTagValues() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter(tags: ["p": Set(["pubkey1", "pubkey2", "pubkey3"])])
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(joins.count, 1)
        XCTAssertEqual(joins[0], "INNER JOIN tags t0 ON t0.event_id = e.id")
        XCTAssertEqual(whereClauses.count, 1)
        XCTAssertEqual(whereClauses[0], "(t0.tag_name = ? AND t0.tag_value IN (?, ?, ?))")
        // Note: Cannot access arguments.values as it's internal to GRDB
    }
    
    func testBuildFilterWithMultipleTags() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter(tags: [
            "e": Set(["event1"]),
            "p": Set(["pubkey1", "pubkey2"])
        ])
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(joins.count, 2)
        XCTAssertTrue(joins.contains("INNER JOIN tags t0 ON t0.event_id = e.id"))
        XCTAssertTrue(joins.contains("INNER JOIN tags t1 ON t1.event_id = e.id"))
        XCTAssertEqual(whereClauses.count, 2)
        XCTAssertEqual(tagIndex, 2)
    }
    
    // MARK: - Complex Filter Tests
    
    func testBuildComplexFilter() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter(
            ids: ["id1"],
            authors: ["author1", "author2"],
            kinds: [1, 3],
            since: Timestamp(1000),
            tags: ["e": Set(["event1"])]
        )
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(whereClauses.count, 5) // ids, authors, kinds, since, tags
        XCTAssertEqual(joins.count, 1) // One tag join
        // Note: Cannot access arguments.values as it's internal to GRDB
    }
    
    // MARK: - Query Building Tests
    
    func testBuildSelectQuery() throws {
        let joins = ["INNER JOIN tags t0 ON t0.event_id = e.id"]
        let whereClauses = ["e.kind = ?", "e.created_at >= ?"]
        
        let query = SQLiteQueryBuilder.buildSelectQuery(
            joins: joins,
            whereClauses: whereClauses,
            limit: 10,
            orderBy: "e.created_at DESC"
        )
        
        let expectedQuery = "SELECT DISTINCT e.json FROM events e INNER JOIN tags t0 ON t0.event_id = e.id WHERE e.kind = ? AND e.created_at >= ? ORDER BY e.created_at DESC LIMIT 10"
        XCTAssertEqual(query, expectedQuery)
    }
    
    func testBuildSelectIdsQuery() throws {
        let joins = ["INNER JOIN tags t0 ON t0.event_id = e.id"]
        let whereClauses = ["e.kind = ?"]
        
        let query = SQLiteQueryBuilder.buildSelectIdsQuery(
            joins: joins,
            whereClauses: whereClauses,
            orderBy: "e.created_at DESC"
        )
        
        let expectedQuery = "SELECT DISTINCT e.id, e.created_at FROM events e INNER JOIN tags t0 ON t0.event_id = e.id WHERE e.kind = ? ORDER BY e.created_at DESC"
        XCTAssertEqual(query, expectedQuery)
    }
    
    func testBuildQueryWithNoFilters() throws {
        let query = SQLiteQueryBuilder.buildSelectQuery(
            joins: [],
            whereClauses: [],
            limit: nil,
            orderBy: nil
        )
        
        XCTAssertEqual(query, "SELECT DISTINCT e.json FROM events e")
    }
    
    // MARK: - SQL Injection Prevention Tests
    
    func testSQLInjectionPrevention() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        // Attempt SQL injection in various fields
        let filter = NDKFilter(
            ids: ["'; DROP TABLE events; --"],
            authors: ["author'; DELETE FROM events WHERE '1'='1"],
            tags: ["e": Set(["event'; UPDATE events SET json='hacked' WHERE '1'='1"])]
        )
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        // Verify that the SQL structure is unchanged and injection attempts are parameterized
        XCTAssertEqual(whereClauses[0], "e.id IN (?)")
        XCTAssertEqual(whereClauses[1], "e.pubkey IN (?)")
        XCTAssertTrue(whereClauses[2].contains("tag_value = ?"))
        
        // Note: Cannot access arguments.values as it's internal to GRDB
        // The SQL injection attempts are properly parameterized
    }
    
    func testEmptyFilter() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter()
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(whereClauses.count, 0)
        XCTAssertEqual(joins.count, 0)
        // Note: Cannot access arguments.values as it's internal to GRDB
    }
}