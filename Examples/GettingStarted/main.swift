import Foundation

@main
struct GettingStarted {
    static func main() async throws {
        let args = CommandLine.arguments
        
        guard args.count > 1 else {
            printUsage()
            return
        }
        
        let example = args[1]
        
        switch example {
        case "1", "01", "connect":
            try await Example01_ConnectToRelay.run()
        case "2", "02", "publish":
            try await Example02_PublishEvent.run()
        case "3", "03", "subscribe":
            try await Example03_Subscribe.run()
        case "3.1", "observer":
            try await Example03_1_SimpleObserver.run()
        case "3.2", "grouped":
            try await Example03_2_GroupedSubscriptions.run()
        case "4", "04", "profile":
            try await Example04_UserProfile.run()
        case "5", "05", "encrypted":
            try await Example05_EncryptedMessages.run()
        case "6", "06", "outbox":
            try await runOutboxExample()
        case "7", "07", "multiple":
            try await Example07_MultipleObservers.run()
        case "8", "08", "nip46", "bunker":
            try await Example08_PublishWithNIP46.run()
        default:
            print("❌ Unknown example: \(example)")
            printUsage()
        }
    }
    
    static func printUsage() {
        print("""
        NDKSwift Getting Started Examples
        =================================
        
        Usage: swift run GettingStarted <example>
        
        Examples:
          1 or connect    - Connect to a relay
          2 or publish    - Publish an event
          3 or subscribe  - Subscribe to events
          3.1 or observer - Simple observer (single relay, limit 3)
          3.2 or grouped  - Test grouped subscriptions isolation
          4 or profile    - Work with user profiles
          5 or encrypted  - Send encrypted messages
          6 or outbox     - Demonstrate NIP-65 outbox model
          7 or multiple   - Test multiple observers on same filter
          8 or nip46      - Publish with NIP-46 remote signer (bunker/nostrconnect)
        
        Example: swift run GettingStarted 1
        """)
    }
}