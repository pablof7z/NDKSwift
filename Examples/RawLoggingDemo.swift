import Foundation
import NDKSwift

@main
struct RawLoggingDemo {
    static func main() async throws {
        // Simple demo to show the new raw logging format
        
        // Enable network traffic logging
        NDKLogger.logNetworkTraffic = true

        // Test 1: Small REQ message
        print("=== Test 1: Small REQ message ===")
        let smallFilter = NDKFilter(kinds: [1111])
        let smallMessage = NostrMessage.req(subscriptionId: "ds_3crnld2z", filters: [smallFilter])
        if let serialized = try? smallMessage.serialize() {
            print("Original: \(serialized)")
            print("Truncated: \(NDKLogFormatter.truncateMessage(serialized))")
        }

        // Test 2: Large authors array (>100 items)
        print("\n=== Test 2: Large authors array ===")
        var largeAuthors: [String] = []
        for i in 0..<150 {
            largeAuthors.append(String(repeating: "0", count: 64)) // Simulate real pubkeys
        }
        let largeFilter = NDKFilter(authors: largeAuthors, kinds: [1, 30023])
        let largeMessage = NostrMessage.req(subscriptionId: "large_authors", filters: [largeFilter])
        if let serialized = try? largeMessage.serialize() {
            print("Original length: \(serialized.count) chars")
            let truncated = NDKLogFormatter.truncateMessage(serialized)
            print("Truncated length: \(truncated.count) chars")
            print("Truncated: \(truncated)")
        }

        // Test 3: Multiple large arrays
        print("\n=== Test 3: Multiple large arrays ===")
        var hugeIds: [String] = []
        for i in 0..<200 {
            hugeIds.append(String(repeating: "1", count: 64)) // Simulate event IDs
        }
        let hugeFilter = NDKFilter(ids: hugeIds, authors: largeAuthors, kinds: [1])
        let hugeMessage = NostrMessage.req(subscriptionId: "huge_arrays", filters: [hugeFilter])
        if let serialized = try? hugeMessage.serialize() {
            print("Original length: \(serialized.count) chars")
            let truncated = NDKLogFormatter.truncateMessage(serialized)
            print("Truncated length: \(truncated.count) chars")
            print("Truncated: \(truncated)")
        }

        // Test 4: Actual logging output
        print("\n=== Test 4: Actual logging output ===")
        let testURL = URL(string: "wss://relay.nostr.band")!
        NDKNetworkLogger.logNetworkSend(to: testURL, message: try! largeMessage.serialize(), parsed: largeMessage)
    }
}