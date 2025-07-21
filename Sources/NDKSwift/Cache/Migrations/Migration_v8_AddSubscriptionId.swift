import Foundation
import GRDB

extension NDKSQLiteCache {
    static func registerV8AddSubscriptionIdMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v8-add-subscription-id") { db in
            // Check if subscription_id column already exists
            let columns = try db.columns(in: "relay_sources")
            let hasSubscriptionId = columns.contains { $0.name == "subscription_id" }
            
            if !hasSubscriptionId {
                // Add subscription_id column to relay_sources table
                try db.alter(table: "relay_sources") { t in
                    t.add(column: "subscription_id", .text)
                }
                
                // Add index for subscription_id
                try db.create(index: "idx_relay_sources_subscription", 
                             on: "relay_sources", 
                             columns: ["subscription_id"], 
                             ifNotExists: true)
            }
        }
    }
}