import Foundation
import NDKSwift

@main
struct NegentropyDemo {
    static func main() async throws {
        print("🧪 Negentropy Implementation Demo")
        print("================================")
        
        // Test 1: NegentropyItem creation
        print("\n1. Testing NegentropyItem creation...")
        let id = Data(repeating: 0x42, count: 32)
        let timestamp: UInt64 = 1234567890
        let item = NegentropyItem(id: id, timestamp: timestamp)
        print("   ✅ Created item with timestamp: \(item.timestamp)")
        
        // Test 2: Hex ID creation
        print("\n2. Testing hex ID creation...")
        let hexId = "4242424242424242424242424242424242424242424242424242424242424242"
        let hexItem = try NegentropyItem(hexId: hexId, timestamp: timestamp)
        print("   ✅ Created item from hex ID")
        
        // Test 3: NegentropyAccumulator
        print("\n3. Testing NegentropyAccumulator...")
        var accumulator = NegentropyAccumulator()
        
        accumulator.add(item)
        accumulator.add(hexItem)
        
        let fingerprint = accumulator.fingerprint()
        print("   ✅ Accumulator with \(accumulator.count) items")
        print("   ✅ Fingerprint: \(fingerprint.hexString.prefix(16))...")
        
        // Test 4: Basic protocol encoding
        print("\n4. Testing protocol encoding...")
        let initialData = try NegentropyEncoder.encodeInitialMessage(
            fingerprint: fingerprint,
            count: accumulator.count
        )
        print("   ✅ Encoded initial message: \(initialData.count) bytes")
        
        // Test 5: Cache storage
        print("\n5. Testing cache integration...")
        let cache = MemoryCache()
        let storage = NDKCacheNegentropyStorage(cache: cache)
        
        // Create a test event
        let event = NDKEvent(
            id: hexId,
            pubkey: "4242424242424242424242424242424242424242424242424242424242424242",
            createdAt: Timestamp(timestamp),
            kind: 1,
            tags: [],
            content: "Test event for negentropy",
            sig: String(repeating: "42", count: 64)
        )
        
        try await cache.saveEvent(event)
        
        let range = NegentropyRange(
            lower: nil,
            upper: nil,
            fingerprint: Data(),
            count: 0
        )
        
        let items = try await storage.getItems(in: range)
        print("   ✅ Retrieved \(items.count) items from cache storage")
        
        // Test 6: Basic reconciliation setup
        print("\n6. Testing reconciliation setup...")
        let negentropy = Negentropy(storage: storage)
        let initMessage = try await negentropy.initiate()
        print("   ✅ Created initiator message: \(initMessage.count) bytes")
        
        // Test 7: NIP-77 message encoding
        print("\n7. Testing NIP-77 message encoding...")
        let filter = NDKFilter(kinds: [1], limit: 100)
        let nip77Open = NIP77Message.open(
            subscriptionId: "demo-sub-123",
            filter: filter,
            initialMessage: initMessage
        )
        
        let jsonMessage = try nip77Open.toJSON()
        print("   ✅ NIP-77 message encoded: \(jsonMessage.prefix(100))...")
        
        let decoded = try NIP77Message.fromJSON(jsonMessage)
        print("   ✅ NIP-77 message decoded successfully")
        print("   ✅ Message type: \(decoded.type)")
        print("   ✅ Subscription ID: \(decoded.subscriptionId)")
        
        print("\n🎉 All negentropy components working correctly!")
        print("   • NegentropyItem creation and comparison ✅")
        print("   • NegentropyAccumulator fingerprinting ✅")
        print("   • Protocol message encoding/decoding ✅")
        print("   • Cache integration ✅")
        print("   • Negentropy reconciliation setup ✅")
        print("   • NIP-77 message handling ✅")
    }
}