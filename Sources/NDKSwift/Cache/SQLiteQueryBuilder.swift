import GRDB

/// Helper to build SQL queries for NDKSQLiteCache, eliminating duplicate query building logic
struct SQLiteQueryBuilder {

    /// Build WHERE clauses and arguments from an NDKFilter
    static func buildFilterClauses(
        from filter: NDKFilter,
        arguments: inout StatementArguments,
        whereClauses: inout [String],
        joins: inout [String],
        tagIndex: inout Int,
        includeTimeRange: (from: Timestamp, to: Timestamp)? = nil
    ) {
        // Time range (if provided)
        if let timeRange = includeTimeRange {
            whereClauses.append("e.created_at >= ? AND e.created_at < ?")
            arguments += [timeRange.from, timeRange.to]
        }

        // IDs filter
        if let ids = filter.ids, !ids.isEmpty {
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            whereClauses.append("e.id IN (\(placeholders))")
            for id in ids {
                arguments += [id]
            }
        }

        // Authors filter
        if let authors = filter.authors, !authors.isEmpty {
            let placeholders = authors.map { _ in "?" }.joined(separator: ", ")
            whereClauses.append("e.pubkey IN (\(placeholders))")
            for author in authors {
                arguments += [author]
            }
        }

        // Kinds filter
        if let kinds = filter.kinds, !kinds.isEmpty {
            let placeholders = kinds.map { _ in "?" }.joined(separator: ", ")
            whereClauses.append("e.kind IN (\(placeholders))")
            for kind in kinds {
                arguments += [kind]
            }
        }

        // Since filter
        if let since = filter.since {
            whereClauses.append("e.created_at >= ?")
            arguments += [since]
        }

        // Until filter
        if let until = filter.until {
            whereClauses.append("e.created_at <= ?")
            arguments += [until]
        }

        // Tags filter
        if let tags = filter.tags {
            for (tagName, values) in tags {
                if !values.isEmpty {
                    let tableAlias = "t\(tagIndex)"
                    tagIndex += 1

                    joins.append("INNER JOIN tags \(tableAlias) ON \(tableAlias).event_id = e.id")

                    var tagConditions: [String] = []
                    tagConditions.append("\(tableAlias).tag_name = ?")
                    arguments += [tagName]

                    if values.count == 1 {
                        tagConditions.append("\(tableAlias).tag_value = ?")
                        arguments += [values.first!]
                    } else {
                        let placeholders = values.map { _ in "?" }.joined(separator: ", ")
                        tagConditions.append("\(tableAlias).tag_value IN (\(placeholders))")
                        for value in values {
                            arguments += [value]
                        }
                    }

                    whereClauses.append("(" + tagConditions.joined(separator: " AND ") + ")")
                }
            }
        }
    }

    /// Build a complete SELECT query
    static func buildSelectQuery(
        baseSQL: String = "SELECT DISTINCT e.json FROM events e",
        joins: [String],
        whereClauses: [String],
        limit: Int? = nil,
        orderBy: String? = nil
    ) -> String {
        var sql = baseSQL

        // Add joins
        if !joins.isEmpty {
            sql += " " + joins.joined(separator: " ")
        }

        // Add WHERE clause
        if !whereClauses.isEmpty {
            sql += " WHERE " + whereClauses.joined(separator: " AND ")
        }

        // Add ORDER BY
        if let orderBy = orderBy {
            sql += " ORDER BY \(orderBy)"
        }

        // Add LIMIT
        if let limit = limit {
            sql += " LIMIT \(limit)"
        }

        return sql
    }

    /// Build a SELECT query for event IDs only
    static func buildSelectIdsQuery(
        joins: [String],
        whereClauses: [String],
        orderBy: String? = nil
    ) -> String {
        return buildSelectQuery(
            baseSQL: "SELECT DISTINCT e.id, e.created_at FROM events e",
            joins: joins,
            whereClauses: whereClauses,
            orderBy: orderBy
        )
    }
}