import Foundation
import NDKSwift

// Test the Negentropy protocol implementation directly

@main
struct TestNegentropyProtocol {
    static func main() async {
        print("🔬 Testing Negentropy Protocol Implementation")
        print("==========================================\n")
        
        do {
            // Test 1: Empty set encoding
            print("Test 1: Empty Set Encoding")
            await testEmptySet()
            
            print("\n" + String(repeating: "-", count: 40) + "\n")
            
            // Test 2: Small set encoding (IdList mode)
            print("Test 2: Small Set Encoding (IdList mode)")
            await testSmallSet()
            
            print("\n" + String(repeating: "-", count: 40) + "\n")
            
            // Test 3: Protocol handshake flow
            print("Test 3: Protocol Handshake Flow")
            await testProtocolHandshake()
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    static func testEmptySet() async {
        do {
            let cache = MemoryCache()
            let storage = NDKCacheNegentropyStorage(cache: cache)
            let reconciler = NegentropyReconciler(storage: storage)
            
            // Initialize
            let initialMessage = try await reconciler.initiate()
            print("Initial message: \(initialMessage.hexString)")
            print("Expected: 61 (protocol version)")
            
            // Simulate protocol ack
            let ackData = Data([0x61])
            let response = try await reconciler.processMessage(ackData)
            
            switch response {
            case .continuing(let data, _, _):
                print("\nResponse after ack: \(data.hexString)")
                print("Decoded:")
                decodeMessage(data)
            case .terminated:
                print("Unexpected termination")
            }
            
        } catch {
            print("Error: \(error)")
        }
    }
    
    static func testSmallSet() async {
        do {
            let cache = MemoryCache()
            let storage = NDKCacheNegentropyStorage(cache: cache)
            
            // Add some test events
            for i in 0..<5 {
                let eventId = String(format: "%064x", i)
                let event = NDKEvent(
                    id: eventId,
                    pubkey: "4242424242424242424242424242424242424242424242424242424242424242",
                    createdAt: Timestamp(1000000 + i * 100),
                    kind: 1,
                    tags: [],
                    content: "Test event \(i)",
                    sig: String(repeating: "42", count: 64)
                )
                try await cache.saveEvent(event)
            }
            
            let reconciler = NegentropyReconciler(storage: storage)
            
            // Initialize
            let initialMessage = try await reconciler.initiate()
            print("Initial message: \(initialMessage.hexString)")
            
            // Simulate protocol ack
            let ackData = Data([0x61])
            let response = try await reconciler.processMessage(ackData)
            
            switch response {
            case .continuing(let data, _, _):
                print("\nResponse after ack: \(data.hexString)")
                print("Decoded:")
                decodeMessage(data)
            case .terminated:
                print("Unexpected termination")
            }
            
        } catch {
            print("Error: \(error)")
        }
    }
    
    static func testProtocolHandshake() async {
        do {
            let cache = MemoryCache()
            let storage = NDKCacheNegentropyStorage(cache: cache)
            let reconciler = NegentropyReconciler(storage: storage)
            
            print("1. Client initiates with protocol version")
            let initialMessage = try await reconciler.initiate()
            print("   Sent: \(initialMessage.hexString)")
            
            print("\n2. Server acknowledges with protocol version")
            let ackData = Data([0x61])
            print("   Received: \(ackData.hexString)")
            
            print("\n3. Client sends actual data")
            let response = try await reconciler.processMessage(ackData)
            
            switch response {
            case .continuing(let data, _, _):
                print("   Sent: \(data.hexString)")
                
                // Try to decode what we're sending
                print("\n   Analysis of sent data:")
                var index = 0
                while index < data.count {
                    // Read timestamp (varint)
                    let (timestamp, newIndex) = decodeVarint(data, from: index)
                    index = newIndex
                    
                    if timestamp == UInt64.max {
                        print("   - Upper bound: infinity")
                    } else {
                        print("   - Upper bound timestamp: \(timestamp)")
                    }
                    
                    // Read mode
                    if index < data.count {
                        let mode = data[index]
                        index += 1
                        
                        switch mode {
                        case 0x00:
                            print("   - Mode: Skip (0x00)")
                        case 0x01:
                            print("   - Mode: Fingerprint (0x01)")
                            if index + 16 <= data.count {
                                let fingerprint = data[index..<index+16]
                                print("   - Fingerprint: \(fingerprint.hexString)")
                                index += 16
                            }
                        case 0x02:
                            print("   - Mode: IdList (0x02)")
                            // Read count
                            let (count, nextIndex) = decodeVarint(data, from: index)
                            index = nextIndex
                            print("   - Count: \(count)")
                            
                            for i in 0..<Int(count) {
                                // Read timestamp
                                let (itemTimestamp, nextIdx) = decodeVarint(data, from: index)
                                index = nextIdx
                                print("   - Item \(i) timestamp: \(itemTimestamp)")
                                
                                // Read ID (32 bytes)
                                if index + 32 <= data.count {
                                    let id = data[index..<index+32]
                                    print("   - Item \(i) ID: \(id.hexString)")
                                    index += 32
                                }
                            }
                        default:
                            print("   - Unknown mode: 0x\(String(format: "%02x", mode))")
                        }
                    }
                    
                    if index >= data.count { break }
                }
                
            case .terminated:
                print("   Protocol terminated")
            }
            
        } catch {
            print("Error: \(error)")
        }
    }
    
    static func decodeMessage(_ data: Data) {
        var index = 0
        var rangeCount = 0
        
        while index < data.count {
            rangeCount += 1
            print("  Range \(rangeCount):")
            
            // Try to decode timestamp
            let (timestamp, newIndex) = decodeVarint(data, from: index)
            index = newIndex
            print("    Timestamp: \(timestamp) (0x\(String(format: "%llx", timestamp)))")
            
            if index >= data.count { break }
            
            // Read mode byte
            let mode = data[index]
            index += 1
            print("    Mode: 0x\(String(format: "%02x", mode))")
            
            // Handle different modes
            switch mode {
            case 0x00:
                print("    Type: Skip")
            case 0x01:
                print("    Type: Fingerprint")
                if index + 16 <= data.count {
                    let fingerprint = data[index..<index+16]
                    print("    Fingerprint: \(fingerprint.hexString)")
                    index += 16
                }
            case 0x02:
                print("    Type: IdList")
                // Decode count
                let (count, nextIndex) = decodeVarint(data, from: index)
                index = nextIndex
                print("    Count: \(count)")
            default:
                print("    Type: Unknown")
            }
            
            if index >= data.count { break }
        }
    }
    
    static func decodeVarint(_ data: Data, from startIndex: Int) -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift = 0
        var index = startIndex
        
        while index < data.count {
            let byte = data[index]
            index += 1
            
            result |= UInt64(byte & 0x7F) << shift
            
            if byte & 0x80 == 0 {
                return (result, index)
            }
            
            shift += 7
            if shift > 63 {
                return (0, index)
            }
        }
        
        return (0, index)
    }
}

// Extension for hex encoding
// Using hex conversion from NDKSwift's DataExtensions

