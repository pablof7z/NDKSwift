import XCTest
@testable import NDKSwift

final class RawLoggingIntegrationTest: XCTestCase {
    
    func testRawLoggingOutput() async throws {
        // Enable network traffic logging
        NDKLogger.logNetworkTraffic = true
        
        // Create NDK instance
        let ndk = NDK(relayUrls: ["wss://relay.nostr.band"])
        
        // Connect to relay
        await ndk.connect()
        
        // Create a filter with large arrays to test truncation
        var largeAuthors: [String] = []
        for i in 0..<150 {
            largeAuthors.append("a\(String(format: "%063d", i))") // 64-char pubkeys
        }
        
        let filter = NDKFilter(
            authors: largeAuthors,
            kinds: [1, 30023],
            limit: 10
        )
        
        print("\n=== Raw Logging Test Output ===")
        print("Creating subscription with \(largeAuthors.count) authors...")
        
        // Subscribe to trigger the logging
        let subscription = ndk.subscribe(filter: filter)
        
        // Give it a moment to send the REQ
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // The raw log output should appear in the console
        print("\n(Check the console output above for the raw REQ message)")
        print("Expected format: RAW: [\"REQ\",\"<sub-id>\",{\"authors\":\"<150-authors>\",\"kinds\":[1,30023],\"limit\":10}]")
        print("=== End of Raw Logging Test ===\n")
        
        // Cancel subscription
        subscription.cancel()
        
        // Disconnect
        await ndk.disconnect()
    }
}