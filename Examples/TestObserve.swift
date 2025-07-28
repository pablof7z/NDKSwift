import Foundation
@testable import NDKSwift

// Minimal test to check if observe() works

NDKLogger.logLevel = .trace

let ndk = NDK(relayUrls: ["wss://relay.primal.net"])

// Check if dataRequirementManager exists
if ndk.dataRequirementManager == nil {
    print("❌ PROBLEM: dataRequirementManager is nil!")
} else {
    print("✓ dataRequirementManager exists")
}

// Create data source
let filter = NDKFilter(kinds: [1])
let dataSource = ndk.observe(filter: filter, cachePolicy: .networkOnly)

print("DataSource created, checking if it registers with manager...")

// Give it a moment
try await Task.sleep(nanoseconds: 1_000_000_000)

print("Done")