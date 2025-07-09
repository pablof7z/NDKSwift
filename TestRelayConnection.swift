import Foundation

// Test basic relay WebSocket connection

struct TestRelayConnection {
    static func main() async {
        print("🔌 Testing Relay Connections")
        print("============================\n")
        
        let relays = [
            "wss://relay.primal.net",
            "wss://relay.damus.io",
            "wss://relay.8333.space/",
            "wss://nos.lol"
        ]
        
        for relay in relays {
            print("Testing \(relay)...")
            
            let session = URLSession(configuration: .default)
            let request = URLRequest(url: URL(string: relay)!)
            
            do {
                let webSocketTask = session.webSocketTask(with: request)
                webSocketTask.resume()
                
                // Send a simple REQ message to test connection
                let testMessage = URLSessionWebSocketTask.Message.string(
                    "[\"REQ\", \"test\", {\"kinds\": [0], \"limit\": 1}]"
                )
                
                try await webSocketTask.send(testMessage)
                
                // Wait for response with timeout
                let receiveTask = Task {
                    return try await webSocketTask.receive()
                }
                
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    throw URLError(.timedOut)
                }
                
                // Race between receive and timeout
                do {
                    _ = try await receiveTask.value
                    print("✅ \(relay) - Connected!")
                    timeoutTask.cancel()
                    
                    // Close connection
                    webSocketTask.cancel(with: .normalClosure, reason: nil)
                } catch {
                    print("❌ \(relay) - Failed: \(error)")
                    receiveTask.cancel()
                }
                
            } catch {
                print("❌ \(relay) - Error: \(error)")
            }
            
            print("")
        }
        
        print("✅ Connection test completed")
    }
}

// Run the test
await TestRelayConnection.main()