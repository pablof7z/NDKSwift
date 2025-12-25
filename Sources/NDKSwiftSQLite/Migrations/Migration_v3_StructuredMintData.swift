import Foundation
import GRDB

extension NDKSQLiteCache {
    static func registerV3StructuredMintDataMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3-structured-mint-data") { db in
            // Add structured columns to mint_info
            try db.alter(table: "mint_info") { t in
                t.add(column: "name", .text)
                t.add(column: "pubkey", .text)
                t.add(column: "version", .text)
                t.add(column: "units", .text) // JSON array of supported units
            }

            // Create index for mint name searches
            try db.create(index: "idx_mint_info_name", on: "mint_info", columns: ["name"])

            // Migrate existing JSON data to structured columns using raw JSON parsing
            let cursor = try Row.fetchCursor(db, sql: "SELECT url, json FROM mint_info")
            while let row = try cursor.next() {
                if let url = row["url"] as? String,
                   let jsonString = row["json"] as? String,
                   let jsonData = jsonString.data(using: .utf8),
                   let info = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    let name = info["name"] as? String
                    let pubkey = info["pubkey"] as? String
                    let version = info["version"] as? String

                    // Extract units from nuts.nut04.methods[].unit
                    var units: [String] = []
                    if let nuts = info["nuts"] as? [String: Any],
                       let nut04 = nuts["4"] as? [String: Any],
                       let methods = nut04["methods"] as? [[String: Any]] {
                        units = methods.compactMap { $0["unit"] as? String }
                    }
                    let unitsJson = try? JSONSerialization.data(withJSONObject: units)
                    let unitsString = unitsJson.flatMap { String(data: $0, encoding: .utf8) }

                    try db.execute(
                        sql: """
                        UPDATE mint_info
                        SET name = ?, pubkey = ?, version = ?, units = ?
                        WHERE url = ?
                        """,
                        arguments: [name, pubkey, version, unitsString, url]
                    )
                }
            }
        }
    }
}
