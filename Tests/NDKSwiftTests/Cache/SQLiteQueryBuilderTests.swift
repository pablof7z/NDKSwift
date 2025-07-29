import XCTest
import GRDB
@testable import NDKSwift

final class SQLiteQueryBuilderTests: XCTestCase {
    
    // MARK: - Basic Filter Tests
    
    func testBuildFilterWithIds() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter()
        filter.ids = ["id1", "id2", "id3"]
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(whereClauses.count, 1)
        XCTAssertEqual(whereClauses[0], "e.id IN (?, ?, ?)")
        XCTAssertEqual(arguments.values.count, 3)
        XCTAssertEqual(arguments.values[0] as? String, "id1")
        XCTAssertEqual(arguments.values[1] as? String, "id2")
        XCTAssertEqual(arguments.values[2] as? String, "id3")
    }
    
    func testBuildFilterWithAuthors() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter()
        filter.authors = ["pubkey1", "pubkey2"]
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(whereClauses.count, 1)
        XCTAssertEqual(whereClauses[0], "e.pubkey IN (?, ?)")
        XCTAssertEqual(arguments.values.count, 2)
        XCTAssertEqual(arguments.values[0] as? String, "pubkey1")
        XCTAssertEqual(arguments.values[1] as? String, "pubkey2")
    }
    
    func testBuildFilterWithKinds() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter()
        filter.kinds = [1, 3, 7]
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(whereClauses.count, 1)
        XCTAssertEqual(whereClauses[0], "e.kind IN (?, ?, ?)")
        XCTAssertEqual(arguments.values.count, 3)
        XCTAssertEqual(arguments.values[0] as? Int, 1)
        XCTAssertEqual(arguments.values[1] as? Int, 3)
        XCTAssertEqual(arguments.values[2] as? Int, 7)
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
        XCTAssertEqual(arguments.values.count, 2)
        XCTAssertEqual(arguments.values[0] as? Timestamp, fromTime)
        XCTAssertEqual(arguments.values[1] as? Timestamp, toTime)
    }
    
    func testBuildFilterWithSinceAndUntil() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter()
        filter.since = Timestamp(1000)
        filter.until = Timestamp(2000)
        
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
        XCTAssertEqual(arguments.values.count, 2)
    }
    
    // MARK: - Tag Filter Tests
    
    func testBuildFilterWithSingleTag() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter()
        filter.tags = ["e": ["event1"]]
        
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
        XCTAssertEqual(arguments.values.count, 2)
        XCTAssertEqual(arguments.values[0] as? String, "e")
        XCTAssertEqual(arguments.values[1] as? String, "event1")
    }
    
    func testBuildFilterWithMultipleTagValues() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter()
        filter.tags = ["p": ["pubkey1", "pubkey2", "pubkey3"]]
        
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
        XCTAssertEqual(arguments.values.count, 4)
        XCTAssertEqual(arguments.values[0] as? String, "p")
        XCTAssertEqual(arguments.values[1] as? String, "pubkey1")
        XCTAssertEqual(arguments.values[2] as? String, "pubkey2")
        XCTAssertEqual(arguments.values[3] as? String, "pubkey3")
    }
    
    func testBuildFilterWithMultipleTags() throws {
        var arguments = StatementArguments()
        var whereClauses: [String] = []
        var joins: [String] = []
        var tagIndex = 0
        
        let filter = NDKFilter()
        filter.tags = [
            "e": ["event1"],
            "p": ["pubkey1", "pubkey2"]
        ]
        
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
        
        let filter = NDKFilter()
        filter.ids = ["id1"]
        filter.authors = ["author1", "author2"]
        filter.kinds = [1, 3]
        filter.since = Timestamp(1000)
        filter.tags = ["e": ["event1"]]
        
        SQLiteQueryBuilder.buildFilterClauses(
            from: filter,
            arguments: &arguments,
            whereClauses: &whereClauses,
            joins: &joins,
            tagIndex: &tagIndex
        )
        
        XCTAssertEqual(whereClauses.count, 5) // ids, authors, kinds, since, tags
        XCTAssertEqual(joins.count, 1) // One tag join
        XCTAssertGreaterThan(arguments.values.count, 6) // All the parameter values
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
        
        let filter = NDKFilter()
        // Attempt SQL injection in various fields
        filter.ids = ["'; DROP TABLE events; --"]
        filter.authors = ["author'; DELETE FROM events WHERE '1'='1"]
        filter.tags = ["e": ["event'; UPDATE events SET json='hacked' WHERE '1'='1"]]
        
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
        
        // Verify that injection attempts are stored as parameters, not in the SQL
        XCTAssertEqual(arguments.values[0] as? String, "'; DROP TABLE events; --")
        XCTAssertEqual(arguments.values[1] as? String, "author'; DELETE FROM events WHERE '1'='1")
        XCTAssertTrue((arguments.values.last as? String)?.contains("UPDATE events SET") ?? false)
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
        XCTAssertEqual(arguments.values.count, 0)
    }
}