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

            // Migrate existing JSON data to structured columns
            let cursor = try Row.fetchCursor(db, sql: "SELECT url, json FROM mint_info")
            while let row = try cursor.next() {
                if let url = row["url"] as? String,
                   let jsonString = row["json"] as? String,
                   let info = JSONCoding.safeDecode(NDKMintInfo.self, from: jsonString) {

                    let unitsJson = (try? JSONCoding.encode(info.nuts?.nut04?.methods?.map { $0.unit } ?? [])) ?? Data()
                    let unitsString = String(data: unitsJson, encoding: .utf8)

                    try db.execute(
                        sql: """
                        UPDATE mint_info
                        SET name = ?, pubkey = ?, version = ?, units = ?
                        WHERE url = ?
                        """,
                        arguments: [info.name, info.pubkey, info.version, unitsString, url]
                    )
                }
            }
        }
    }
}