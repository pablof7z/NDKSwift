import Foundation
import GRDB
import NDKSwiftCore

extension NDKSQLiteCache {
    static func registerV11ProfileAdditionalFieldsMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v11-profile-additional-fields") { db in
            // Add additional_fields column to store dynamic profile fields
            // Using BLOB to store property list encoded data for efficiency
            try db.alter(table: "profiles") { t in
                t.add(column: "additional_fields", .blob)
            }

            // Add display_name column since it's separate from name
            try db.alter(table: "profiles") { t in
                t.add(column: "display_name", .text)
            }

            // Migrate existing profiles to populate display_name and additional_fields from JSON
            let cursor = try Row.fetchCursor(db, sql: "SELECT pubkey, json FROM profiles WHERE json IS NOT NULL")
            while let row = try cursor.next() {
                if let jsonString = row["json"] as? String,
                   let jsonData = jsonString.data(using: .utf8),
                   let profileDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                {
                    // Update display_name if present
                    if let displayName = profileDict["display_name"] as? String {
                        try db.execute(
                            sql: "UPDATE profiles SET display_name = ? WHERE pubkey = ?",
                            arguments: [displayName, row["pubkey"]]
                        )
                    }

                    // Extract additional fields (fields not in the standard set)
                    let knownKeys = ["name", "display_name", "about", "picture", "banner", "nip05", "lud16", "lud06", "website"]
                    var additionalFields: [String: String] = [:]

                    for (key, value) in profileDict {
                        if !knownKeys.contains(key), let stringValue = value as? String {
                            additionalFields[key] = stringValue
                        }
                    }

                    // Store additional fields as property list data if any exist
                    if !additionalFields.isEmpty {
                        if let plistData = try? PropertyListSerialization.data(fromPropertyList: additionalFields, format: .binary, options: 0) {
                            try db.execute(
                                sql: "UPDATE profiles SET additional_fields = ? WHERE pubkey = ?",
                                arguments: [plistData, row["pubkey"]]
                            )
                        }
                    }
                }
            }
        }
    }
}
