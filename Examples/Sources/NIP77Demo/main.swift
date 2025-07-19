import Foundation
import NDKSwift

// Real NIP-77 Negentropy Sync Test with customizable parameters
print("🔄 NIP-77 Negentropy Sync Demo")
print("==============================\n")

// Parse command line arguments
let args = CommandLine.arguments
var relayURL = "wss://nostr.oxtr.dev"
var filterKinds: [Int] = [1]
var filterAuthors: [String] = []
var filterLimit: Int? = nil
var filterSince: Timestamp? = Timestamp.now - 3600 // Default to last hour
var showProgress = false
var debugMode = false

// Simple argument parsing
var i = 1
while i < args.count {
    switch args[i] {
    case "--relay", "-r":
        if i + 1 < args.count {
            relayURL = args[i + 1]
            i += 1
        }
    case "--kinds", "-k":
        if i + 1 < args.count {
            filterKinds = args[i + 1].split(separator: ",").compactMap { Int($0) }
            i += 1
        }
    case "--authors", "-a":
        if i + 1 < args.count {
            filterAuthors = args[i + 1].split(separator: ",").map { String($0) }
            i += 1
        }
    case "--limit", "-l":
        if i + 1 < args.count {
            filterLimit = Int(args[i + 1])
            i += 1
        }
    case "--since", "-s":
        if i + 1 < args.count {
            if let hours = Int(args[i + 1]) {
                filterSince = Timestamp.now - Timestamp(hours * 3600)
            }
            i += 1
        }
    case "--progress", "-p":
        showProgress = true
    case "--debug", "-d":
        debugMode = true
    case "--help", "-h":
        printHelp()
        exit(0)
    default:
        break
    }
    i += 1
}

func printHelp() {
    print("""
    Usage: NIP77Demo [options]
    
    Options:
      --relay, -r <url>      Relay URL to sync with (default: wss://relay.damus.io)
      --kinds, -k <list>     Comma-separated list of event kinds (default: 1)
      --authors, -a <list>   Comma-separated list of author pubkeys
      --limit, -l <number>   Maximum number of events to sync
      --since, -s <hours>    Sync events from last N hours
      --progress, -p         Show real-time progress during sync
      --debug, -d            Show all messages sent/received to/from relay
      --help, -h             Show this help message
    
    Examples:
      # Sync text notes from the last 24 hours
      NIP77Demo --relay wss://relay.damus.io --kinds 1 --since 24
      
      # Sync specific author's events
      NIP77Demo --authors 82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2 --kinds 1,30023
      
      # Sync with custom relay
      NIP77Demo --relay wss://nos.lol --kinds 1 --limit 100
    """)
}

// Main function to allow early return
func runDemo() async throws {
    // Create test signer (for testing local events)
    let privateKey = Crypto.generatePrivateKey()
    let signer = try NDKPrivateKeySigner(privateKey: privateKey)
    
    // Setup NDK with SQLite cache for persistence
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("nip77_demo_cache.db")
    let cache = try await NDKSQLiteCache(path: cacheURL.path, debugMode: true)
    
    let ndk = NDK(
        relayUrls: [relayURL],
        signer: signer,
        cache: cache
    )
    
    // Enable debug mode if requested
    if debugMode {
        ndk.debugMode = true
        print("🐛 Debug mode enabled - will show all relay messages")
    }
    
    print("📡 Target relay: \(relayURL)")
    
    // Build filter
    var filter = NDKFilter(kinds: filterKinds)
    if !filterAuthors.isEmpty {
        filter.authors = filterAuthors
    }
    if let limit = filterLimit {
        filter.limit = limit
    }
    if let since = filterSince {
        filter.since = since
    }
    
    print("\n📋 Filter configuration:")
    print("  - Kinds: \(filterKinds)")
    if !filterAuthors.isEmpty {
        print("  - Authors: \(filterAuthors.map { String($0.prefix(8)) + "..." }.joined(separator: ", "))")
    }
    if let limit = filterLimit {
        print("  - Limit: \(limit)")
    }
    if let since = filterSince {
        let hours = Int((Double(Timestamp.now - since)) / 3600)
        print("  - Since: \(hours) hours ago")
    }
    
    // Check current cache state
    let cachedEvents = try await cache.queryEvents(filter)
    print("\n💾 Local cache has \(cachedEvents.count) matching events")
    
    print("\n🌐 Connecting to relay...")
    await ndk.connect()
    
    // Wait for connection
    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
    
    // Test if relay supports NIP-77
    print("\n🔍 Checking NIP-77 support...")
    let supportsNegentropy = await ndk.relaySupportsNegentropy(relayURL)
    print("Relay supports NIP-77: \(supportsNegentropy)")
    
    if !supportsNegentropy {
        print("\n❌ Relay doesn't support NIP-77 (Negentropy)")
        print("This relay does not advertise support for NIP-77 in its NIP-11 information.")
        print("Trying to send NEG-OPEN anyway...")
    }
    
    // Perform actual NIP-77 sync
    print("\n🔄 Starting NIP-77 Negentropy sync...")
    let startTime = Date()
    
    let syncResult = try await ndk.syncEvents(
        filter: filter,
        relay: relayURL,
        direction: .both  // Use .receive for download-only, .send for upload-only
    )
    
    let syncDuration = Date().timeIntervalSince(startTime)
    
    // Display results
    print("\n📊 NIP-77 Sync Results:")
    print("====================")
    print("✅ Events we already had: \(syncResult.localEventCount)")
    print("📥 New events downloaded: \(syncResult.downloadedEvents.count)")
    print("📤 Events uploaded to relay: \(syncResult.uploadedEvents.count)")
    print("💬 Protocol messages exchanged: \(syncResult.messageRounds)")
    print("📏 Total bytes transferred: \(formatBytes(syncResult.bytesTransferred))")
    print("⏱️  Sync duration: \(String(format: "%.2f", syncDuration))s")
    print("🚀 Bandwidth efficiency: \(syncResult.efficiencyRatio)% vs naive sync")
    
    // Show sample of new events
    if syncResult.downloadedEvents.count > 0 {
        print("\n📥 Sample of new events (showing first 5):")
        for event in syncResult.downloadedEvents.prefix(5) {
            let author = event.pubkey.prefix(8)
            let content = event.content.prefix(100)
            print("  - [\(event.createdAt)] \(author)...: \(content)\(event.content.count > 100 ? "..." : "")")
        }
        
        if syncResult.downloadedEvents.count > 5 {
            print("  ... and \(syncResult.downloadedEvents.count - 5) more events")
        }
    }
    
    // Final cache state
    let finalCachedEvents = try await cache.queryEvents(filter)
    print("\n💾 Final cache state: \(finalCachedEvents.count) events")
    
    // Calculate what regular sync would have done
    let naiveBytes = (syncResult.localEventCount + syncResult.downloadedEvents.count) * 500 // ~500 bytes per event
    let savings = max(0, naiveBytes - syncResult.bytesTransferred)
    print("\n💡 Bandwidth saved: \(formatBytes(savings)) (\(syncResult.efficiencyRatio)% reduction)")
}

// Run the demo
do {
    try await runDemo()
} catch {
    print("❌ Error: \(error)")
}

func formatBytes(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    return formatter.string(fromByteCount: Int64(bytes))
}