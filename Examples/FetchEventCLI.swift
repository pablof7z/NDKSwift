import Foundation
import NDKSwift

// Enable debug logging
#if DEBUG
let debugLogging = true
#else
let debugLogging = false
#endif

func debugLog(_ message: String) {
    if debugLogging {
        print("🐛 DEBUG: \(message)")
    }
}

// CLI app to fetch and display Nostr events using bech32 identifiers

@main
struct FetchEventCLI {
    static func main() async {
        // Get command line arguments
        let args = CommandLine.arguments
        
        guard args.count > 1 else {
            print("Usage: \(args[0]) <bech32-event-id>")
            print("Example: \(args[0]) note1...")
            print("         \(args[0]) nevent1...")
            print("         \(args[0]) naddr1...")
            exit(1)
        }
        
        let eventIdentifier = args[1]
        
        print("🔍 Fetching event: \(eventIdentifier)")
        print("─────────────────────────────────────────")
        
        debugLog("Starting FetchEventCLI")
        
        // Initialize NDK with some common relays
        let relayUrls = [
            "wss://relay.damus.io",
            "wss://relay.nostr.band",
            "wss://nos.lol",
            "wss://relay.primal.net"
        ]
        
        debugLog("Initializing NDK with relays: \(relayUrls)")
        let ndk = NDK(relayUrls: relayUrls)
        ndk.debugMode = true // Enable NDK's built-in debug mode
        
        // Connect to relays
        print("📡 Connecting to relays...")
        debugLog("Calling ndk.connect()")
        
        // Add timeout to the entire operation
        let mainTask = Task {
            await ndk.connect()
            debugLog("NDK connect completed")
            print("📡 Connected")
            
            // Wait a moment for connections to establish
            debugLog("Waiting 2 seconds for connections to establish")
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            debugLog("Wait completed")
            
            return await performFetch(ndk: ndk, eventIdentifier: eventIdentifier)
        }
        
        // Add overall timeout
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds
            debugLog("Overall operation timed out after 8 seconds")
            return false
        }
        
        let result = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await mainTask.value }
            group.addTask { await timeoutTask.value }
            
            for await result in group {
                group.cancelAll()
                return result
            }
            return false
        }
        
        if !result {
            print("❌ Operation timed out or failed")
        }
        
        // Disconnect
        debugLog("Disconnecting from relays")
        await ndk.disconnect()
        debugLog("Disconnected")
    }
    
    static func performFetch(ndk: NDK, eventIdentifier: String) async -> Bool {
        do {
            debugLog("Starting performFetch")
            
            // First, let's see what filter will be created
            debugLog("Creating filter from identifier: \(eventIdentifier)")
            let filter = try NostrIdentifier.createFilter(from: eventIdentifier)
            debugLog("Filter created successfully")
            
            print("\n🔎 Filter details:")
            print("─────────────────────────────────────────")
            if let ids = filter.ids, !ids.isEmpty {
                print("📌 Event IDs: \(ids)")
                debugLog("Filter has \(ids.count) event IDs")
            }
            if let authors = filter.authors, !authors.isEmpty {
                print("👤 Authors: \(authors)")
                debugLog("Filter has \(authors.count) authors")
            }
            if let kinds = filter.kinds, !kinds.isEmpty {
                print("🏷️  Kinds: \(kinds)")
                debugLog("Filter has \(kinds.count) kinds")
            }
            if let dTag = filter.tagFilter("d") {
                print("🏷️  d-tag: \(dTag)")
                debugLog("Filter has d-tag: \(dTag)")
            }
            print("─────────────────────────────────────────\n")
            
            print("🔍 Starting to fetch event...")
            debugLog("About to call ndk.fetchEvent")
            
            // Use the actual fetchEvent method we implemented
            let fetchTask = Task {
                debugLog("Calling ndk.fetchEvent with identifier")
                let event = try await ndk.fetchEvent(eventIdentifier)
                debugLog("fetchEvent completed")
                return event
            }
            
            let timeoutTask = Task<NDKEvent?, Never> {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                debugLog("Fetch operation timed out")
                return nil
            }
            
            debugLog("Racing fetch vs timeout")
            let event = await withTaskGroup(of: NDKEvent?.self) { group in
                group.addTask { try? await fetchTask.value }
                group.addTask { await timeoutTask.value }
                
                for await result in group {
                    group.cancelAll()
                    return result
                }
                return nil
            }
            
            debugLog("Fetch completed")
            
            if let event = event {
                debugLog("Event found!")
                displayEvent(event)
                return true
            } else {
                print("❌ Event not found or fetch timed out")
                debugLog("No event found")
                return false
            }
        } catch {
            print("❌ Error fetching event: \(error)")
            debugLog("Error in performFetch: \(error)")
            return false
        }
    }
    
    static func displayEvent(_ event: NDKEvent) {
        print("\n📄 Event Details:")
        print("─────────────────────────────────────────")
        
        // Event ID
        if let eventId = event.id {
            print("🆔 Event ID: \(eventId)")
            if let noteId = try? Bech32.note(from: eventId) {
                print("   Bech32: \(noteId)")
            }
        }
        
        // Author
        print("\n👤 Author:")
        print("   Public Key: \(event.pubkey)")
        if let npub = try? Bech32.npub(from: event.pubkey) {
            print("   npub: \(npub)")
        }
        
        // Timestamp
        let date = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        print("\n📅 Created: \(formatter.string(from: date))")
        
        // Kind
        print("\n🏷️  Kind: \(event.kind) \(kindDescription(event.kind))")
        
        // Tags
        if !event.tags.isEmpty {
            print("\n🏷️  Tags:")
            for tag in event.tags {
                if tag.count > 0 {
                    let tagName = tag[0]
                    let tagValue = tag.count > 1 ? tag[1] : ""
                    let extra = tag.count > 2 ? " +" : ""
                    print("   [\(tagName)] \(tagValue)\(extra)")
                }
            }
        }
        
        // Content
        print("\n📝 Content:")
        print("─────────────────────────────────────────")
        
        // Handle different content types
        switch event.kind {
        case 0: // Metadata
            if let data = event.content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let name = json["name"] as? String {
                    print("Name: \(name)")
                }
                if let about = json["about"] as? String {
                    print("About: \(about)")
                }
                if let picture = json["picture"] as? String {
                    print("Picture: \(picture)")
                }
                if let nip05 = json["nip05"] as? String {
                    print("NIP-05: \(nip05)")
                }
                if let lud16 = json["lud16"] as? String {
                    print("Lightning: \(lud16)")
                }
            } else {
                print(event.content)
            }
            
        case 30023: // Long-form content
            // First few lines as preview
            let lines = event.content.components(separatedBy: .newlines)
            let preview = lines.prefix(10).joined(separator: "\n")
            print(preview)
            if lines.count > 10 {
                print("\n... (truncated, \(lines.count - 10) more lines)")
            }
            
        default:
            // Default: show raw content
            if event.content.count > 500 {
                print(String(event.content.prefix(500)))
                print("\n... (truncated, \(event.content.count - 500) more characters)")
            } else {
                print(event.content)
            }
        }
        
        print("─────────────────────────────────────────")
        
        // Show relays where this event was found
        if !event.seenOnRelays.isEmpty {
            print("\n🌐 Seen on relays:")
            for relay in event.seenOnRelays {
                print("   - \(relay)")
            }
        }
    }
    
    static func kindDescription(_ kind: Int) -> String {
        switch kind {
        case 0: return "(Metadata)"
        case 1: return "(Text Note)"
        case 3: return "(Contact List)"
        case 4: return "(Encrypted Direct Message)"
        case 5: return "(Event Deletion)"
        case 6: return "(Repost)"
        case 7: return "(Reaction)"
        case 10002: return "(Relay List)"
        case 30023: return "(Long-form Content)"
        case 30024: return "(Draft Long-form Content)"
        case 30078: return "(Application Data)"
        default: return ""
        }
    }
}