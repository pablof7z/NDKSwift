import Foundation
import NDKSwift

class CommandProcessor {
    private let ndk: NDK
    private let signer: NDKPrivateKeySigner
    private var publishResults: [String: [String: (accepted: Bool, message: String?)]] = [:] // eventId -> [relayUrl -> result]
    private weak var renderer: TerminalRenderer?
    
    init(ndk: NDK, signer: NDKPrivateKeySigner) {
        self.ndk = ndk
        self.signer = signer
    }
    
    func setRenderer(_ renderer: TerminalRenderer) {
        self.renderer = renderer
    }
    
    // Called by OutboxDebugger when OK messages are received
    func trackPublishResult(eventId: String, relay: String, accepted: Bool, message: String?) async {
        await MainActor.run {
            if publishResults[eventId] == nil {
                publishResults[eventId] = [:]
            }
            publishResults[eventId]?[relay] = (accepted, message)
        }
    }
    
    func processOutbox(npubs: [String]) async -> String {
        guard !npubs.isEmpty else {
            return "Usage: outbox [npub1...] [npub2...]"
        }
        
        var output = ""
        
        for npub in npubs {
            guard let pubkey = try? String.fromNpub(npub) else {
                output += "Invalid npub: \(npub)\n"
                continue
            }
            
            output += Terminal.bold("Outbox for \(npub):\n")
            
            // Get outbox info from NDK
            let outboxInfo = await ndk.outbox.getCachedOutbox(for: pubkey)
            
            if let outboxInfo = outboxInfo {
                output += "  Read relays:\n"
                if outboxInfo.readRelays.isEmpty {
                    output += "    (none)\n"
                } else {
                    for relayInfo in outboxInfo.readRelays {
                        output += "    • \(relayInfo.url)\n"
                    }
                }
                
                output += "  Write relays:\n"
                if outboxInfo.writeRelays.isEmpty {
                    output += "    (none)\n"
                } else {
                    for relayInfo in outboxInfo.writeRelays {
                        output += "    • \(relayInfo.url)\n"
                    }
                }
            } else {
                output += "  No outbox information cached\n"
            }
            
            output += "\n"
        }
        
        return output.trimmingCharacters(in: .newlines)
    }
    
    func processPublish(npubs: [String], relayStats: [RelayMonitor.RelayStats]) async -> String {
        var output = ""
        
        // Parse npubs
        var taggedPubkeys: [String] = []
        for npub in npubs {
            guard let pubkey = try? String.fromNpub(npub) else {
                output += "Warning: Invalid npub '\(npub)', skipping\n"
                continue
            }
            taggedPubkeys.append(pubkey)
        }
        
        // Create event
        let content = "Hello world from Outbox Debugger!"
        var tags: [[String]] = []
        
        for pubkey in taggedPubkeys {
            tags.append(["p", pubkey])
        }
        
        // Create and sign event
        let event = try! await NDKEventBuilder(ndk: ndk)
            .content(content)
            .kind(EventKind.textNote)
            .tags(tags)
            .build(signer: signer)
        
        output += Terminal.bold("Publishing event:\n")
        output += "  ID: \(event.id)\n"
        output += "  Content: \(content)\n"
        output += "  Tagged users: \(taggedPubkeys.count)\n\n"
        
        // Clear previous results for this event
        publishResults[event.id] = [:]
        
        // Publish
        let publishedRelays = try! await ndk.publish(event)
        
        // Wait a bit for OK responses
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        output += Terminal.bold("Publish results:\n")
        
        let eventResults = publishResults[event.id] ?? [:]
        
        for relay in publishedRelays {
            let relayUrl = relay.url
            let url = relayUrl.replacingOccurrences(of: "wss://", with: "")
                             .replacingOccurrences(of: "ws://", with: "")
            
            if let result = eventResults[relayUrl] {
                if result.accepted {
                    output += "  ✅ \(url) - Event accepted\n"
                } else {
                    output += "  ❌ \(url) - Event rejected: \(result.message ?? "unknown reason")\n"
                }
            } else {
                output += "  🟡 \(url) - Sent, no response yet\n"
            }
        }
        
        // Show which relays were selected
        output += "\n" + Terminal.bold("Relay selection logic:\n")
        let relayUrlList = publishedRelays.map { $0.url }.joined(separator: ", ")
        output += "  Used relays: \(relayUrlList)\n"
        
        return output
    }
    
    func processReq(npubs: [String]) async -> String {
        guard !npubs.isEmpty else {
            return "Usage: req npub1... npub2..."
        }
        
        var output = ""
        var debugProgress: [String] = []
        var lastDebugTime = Date()
        var liveOutput = "🔄 Starting request processing...\n"
        
        // Update display immediately
        if let renderer = renderer {
            await renderer.render(inputBuffer: "", output: liveOutput)
        }
        
        // Set up debug hook to capture internal progress
        NDKDebugHooks.setDebugHook { [weak self] event in
            let elapsed = Date().timeIntervalSince(lastDebugTime)
            lastDebugTime = Date()
            let timing = elapsed > 0.01 ? " (+\(String(format: "%.2f", elapsed))s)" : ""
            
            switch event {
            case .flowStep(let description):
                debugProgress.append("⚙️  \(description)\(timing)")
                liveOutput += "⚙️  \(description)\(timing)\n"
            case .outboxStrategyRequested(let filter):
                let authorCount = filter.authors?.count ?? 0
                let msg = "🔍 Requesting outbox strategy for \(authorCount) author(s)\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
            case .outboxLookupStarted(let pubkey):
                let npub = (try? String.toNpub(pubkey)) ?? pubkey.prefix(8) + "..."
                let msg = "  → Looking up outbox for \(npub)\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
            case .outboxLookupCompleted(let pubkey, let found):
                let npub = (try? String.toNpub(pubkey)) ?? pubkey.prefix(8) + "..."
                let status = found ? "found" : "not found"
                let msg = "  ✓ Outbox for \(npub): \(status)\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
            case .outboxStrategyComputed(let relayToAuthors):
                let msg = "📊 Outbox strategy computed: \(relayToAuthors.count) relays\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
                for (relay, authors) in relayToAuthors.prefix(5) {
                    let relayMsg = "  → \(relay): \(authors.count) author(s)"
                    debugProgress.append(relayMsg)
                    liveOutput += relayMsg + "\n"
                }
                if relayToAuthors.count > 5 {
                    let moreMsg = "  → ... and \(relayToAuthors.count - 5) more relays"
                    debugProgress.append(moreMsg)
                    liveOutput += moreMsg + "\n"
                }
            case .dataSourceCreated(let filter, let relays):
                let msg = "📝 DataSource created with filter:\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
                if let authors = filter.authors {
                    let authMsg = "  → Authors: \(authors.count)"
                    debugProgress.append(authMsg)
                    liveOutput += authMsg + "\n"
                }
                if let relays = relays {
                    let relayMsg = "  → Specific relays: \(relays.count)"
                    debugProgress.append(relayMsg)
                    liveOutput += relayMsg + "\n"
                }
            case .subscriptionCreated(let id, let filter):
                let msg = "🆕 Subscription created: \(id.prefix(8))...\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
                if let kinds = filter.kinds {
                    let kindMsg = "  → Kinds: \(kinds)"
                    debugProgress.append(kindMsg)
                    liveOutput += kindMsg + "\n"
                }
            case .subscriptionStarting(let id, let relays):
                let msg = "🚀 Starting subscription \(id.prefix(8))... on \(relays.count) relay(s)\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
            case .subscriptionReceived(let id, let relay, let event):
                let msg = "📨 Event received from \(relay) for sub \(id.prefix(8))...\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
                let detailMsg = "  → Kind: \(event.kind), Author: \(event.pubkey.prefix(8))..."
                debugProgress.append(detailMsg)
                liveOutput += detailMsg + "\n"
            case .subscriptionEose(let id, let relay):
                let msg = "📦 EOSE from \(relay) for sub \(id.prefix(8))...\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
            case .poolConnecting(let relay):
                let msg = "🔌 Connecting to \(relay)...\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
            case .poolConnected(let relay):
                let msg = "✅ Connected to \(relay)\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
            case .poolDisconnected(let relay, let error):
                let errorMsg = error != nil ? " (error)" : ""
                let msg = "❌ Disconnected from \(relay)\(errorMsg)\(timing)"
                debugProgress.append(msg)
                liveOutput += msg + "\n"
            default:
                break
            }
            
            // Update display in real-time
            if let renderer = self?.renderer {
                Task {
                    await renderer.render(inputBuffer: "", output: liveOutput)
                }
            }
        }
        
        // Parse npubs
        var pubkeys: [String] = []
        for npub in npubs {
            guard let pubkey = try? String.fromNpub(npub) else {
                output += "Invalid npub: \(npub)\n"
                continue
            }
            pubkeys.append(pubkey)
        }
        
        guard !pubkeys.isEmpty else {
            return output + "No valid npubs provided"
        }
        
        // Create filter for recent kind:1 events
        let filter = NDKFilter(
            authors: pubkeys,
            kinds: [EventKind.textNote],
            limit: 1
        )
        
        liveOutput += "\n" + Terminal.bold("Fetching recent kind:1 events for \(pubkeys.count) user(s):") + "\n\n"
        
        // Update display
        if let renderer = renderer {
            await renderer.render(inputBuffer: "", output: liveOutput)
        }
        
        // Clear debug progress and set start time
        debugProgress.removeAll()
        lastDebugTime = Date()
        
        // Track which relays are queried by using outbox strategy
        let outboxStrategy = await ndk.outbox.getOutboxStrategy(for: filter)
        
        var relayQueries: [String: [String]] = [:]
        for (relay, relayFilter) in outboxStrategy.filtersByRelay {
            relayQueries[relay] = relayFilter.authors ?? []
        }
        
        if relayQueries.isEmpty {
            debugProgress.append("⚠️  No relay information found. Using default pool.")
            // Use default pool - we'll just let NDK handle this
            // The data source will use all connected relays automatically
        }
        
        // Create data source to fetch events
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: 0, // Don't use cache for debugging
            cachePolicy: .networkOnly
        )
        
        // Collect events with timeout
        var events: [NDKEvent] = []
        var relayStatuses: [String: String] = [:]
        let startTime = Date()
        let timeout: TimeInterval = 10.0
        
        // Add relay query info to live output
        liveOutput += "\n" + Terminal.bold("Query Summary:") + "\n"
        liveOutput += "Will query \(relayQueries.count) relay(s)\n\n"
        liveOutput += Terminal.dim("Waiting for responses (timeout: \(Int(timeout))s)...") + "\n"
        
        // Update display
        if let renderer = renderer {
            await renderer.render(inputBuffer: "", output: liveOutput)
        }
        
        // Track progress
        for relay in relayQueries.keys {
            relayStatuses[relay] = "waiting"
        }
        
        let task = Task {
            for await update in dataSource.relayUpdates {
                switch update {
                case .event(let event, let relay):
                    events.append(event)
                    relayStatuses[relay] = "received event"
                    let msg = Terminal.color("  • \(relay): Got event from \(event.pubkey.prefix(8))...", .green)
                    liveOutput += msg + "\n"
                    if let renderer = self.renderer {
                        await renderer.render(inputBuffer: "", output: liveOutput)
                    }
                case .eose(let relay):
                    relayStatuses[relay] = "eose"
                    let msg = Terminal.color("  • \(relay): End of stored events", .blue)
                    liveOutput += msg + "\n"
                    if let renderer = self.renderer {
                        await renderer.render(inputBuffer: "", output: liveOutput)
                    }
                    // Check if all relays have sent EOSE
                    if relayStatuses.values.allSatisfy({ $0 == "eose" || $0.contains("error") }) {
                        break
                    }
                case .closed(let relay):
                    relayStatuses[relay] = "closed"
                    let msg = Terminal.color("  • \(relay): Connection closed", .red)
                    liveOutput += msg + "\n"
                    if let renderer = self.renderer {
                        await renderer.render(inputBuffer: "", output: liveOutput)
                    }
                    break
                }
                
                // Check timeout
                if Date().timeIntervalSince(startTime) > timeout {
                    let msg = Terminal.color("\n⏱️ Timeout reached!", .yellow)
                    liveOutput += msg + "\n"
                    if let renderer = self.renderer {
                        await renderer.render(inputBuffer: "", output: liveOutput)
                    }
                    break
                }
            }
        }
        
        // Wait for completion or timeout
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        task.cancel()
        
        // Clear debug hook
        NDKDebugHooks.setDebugHook(nil)
        
        // Now build the final output with all results
        output = liveOutput + "\n\n"
        
        // Show relay usage
        output += Terminal.bold("Relay queries:\n")
        if relayQueries.isEmpty {
            output += "  Used default relay pool\n"
        } else {
            for (relay, authors) in relayQueries {
                output += "  \(relay):\n"
                for author in authors {
                    if let npub = try? String.toNpub(author) {
                        output += "    • \(npub)\n"
                    } else {
                        output += "    • \(author)\n"
                    }
                }
            }
        }
        
        output += "\n" + Terminal.bold("Results:\n")
        
        // Group events by author
        var eventsByAuthor: [String: NDKEvent] = [:]
        for event in events {
            eventsByAuthor[event.pubkey] = event
        }
        
        for pubkey in pubkeys {
            let npub = (try? String.toNpub(pubkey)) ?? pubkey
            
            if let event = eventsByAuthor[pubkey] {
                output += "\n\(Terminal.color(npub, .brightBlue)):\n"
                output += "  Content: \(event.content.prefix(100))"
                if event.content.count > 100 {
                    output += "..."
                }
                output += "\n"
                output += "  Created: \(formatDate(Date(timeIntervalSince1970: TimeInterval(event.createdAt))))\n"
            } else {
                output += "\n\(Terminal.color(npub, .brightBlue)):\n"
                output += "  No recent events found\n"
            }
        }
        
        return output
    }
    
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}