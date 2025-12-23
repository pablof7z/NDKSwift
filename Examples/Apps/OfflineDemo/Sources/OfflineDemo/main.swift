import Foundation
import NDKSwiftCore
import NDKSwiftNostrDB

// MARK: - ANSI Colors & Terminal

enum Color: String {
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
    case dim = "\u{001B}[2m"

    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
    case white = "\u{001B}[37m"

    case brightRed = "\u{001B}[91m"
    case brightGreen = "\u{001B}[92m"
    case brightYellow = "\u{001B}[93m"
    case brightBlue = "\u{001B}[94m"
    case brightMagenta = "\u{001B}[95m"
    case brightCyan = "\u{001B}[96m"
}

func c(_ text: String, _ color: Color, bold: Bool = false) -> String {
    let boldCode = bold ? Color.bold.rawValue : ""
    return "\(boldCode)\(color.rawValue)\(text)\(Color.reset.rawValue)"
}

// Terminal control sequences
struct Term {
    static let clearScreen = "\u{001B}[2J"
    static let home = "\u{001B}[H"
    static let clearLine = "\u{001B}[2K"
    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"

    static func moveTo(_ row: Int, _ col: Int) -> String {
        "\u{001B}[\(row);\(col)H"
    }
}

// MARK: - TUI State

/// Represents the publish state of a relay for an unpublished event
enum RelayPublishState: Sendable {
    case pending
    case published
    case failed(reason: String)
}

/// Record of an unpublished event with per-relay status for TUI display
struct UnpublishedEventDisplay: Sendable {
    let eventId: String
    let kind: Int
    var relayStates: [String: RelayPublishState]  // relay URL -> state
}

actor TUIState {
    var isOnline = false
    var relayStates: [String: NDKRelayConnectionState] = [:]
    // Track active subscriptions: subId -> (kinds, authorCount)
    var subscriptions: [String: (kinds: [Int], authorCount: Int)] = [:]
    // Track subscriptions per relay: (relay, subId) -> (kinds, authorCount)
    var relaySubscriptions: [(relay: String, subId: String, kinds: [Int], authorCount: Int)] = []
    var recentEvents: [(timestamp: Date, kind: Int, author: String, preview: String)] = []
    var unpublishedEvents: [String: UnpublishedEventDisplay] = [:]  // eventId -> display record
    var logs: [(timestamp: Date, message: String)] = []
    var eventCount = 0
    var totalEvents = 0
    var total10002Events = 0  // Debug: total kind-10002 events in NostrDB
    var authorRelays: [String: Set<String>] = [:] // pubkey -> Set of relay URLs from outbox

    let maxEvents = 10
    let maxLogs = 8

    func setOnline(_ online: Bool) {
        isOnline = online
    }

    func setRelayState(_ url: String, _ state: NDKRelayConnectionState) {
        relayStates[url] = state
    }

    func addSubscription(subId: String, kinds: [Int], authorCount: Int) {
        subscriptions[subId] = (kinds: kinds, authorCount: authorCount)
    }

    func addRelaySubscription(relay: String, subId: String, kinds: [Int], authorCount: Int) {
        relaySubscriptions.append((relay: relay, subId: subId, kinds: kinds, authorCount: authorCount))
    }

    func addEvent(kind: Int, author: String, preview: String) {
        eventCount += 1
        recentEvents.insert((Date(), kind, author, preview), at: 0)
        if recentEvents.count > maxEvents {
            recentEvents.removeLast()
        }
    }

    func setUnpublishedEvents(_ events: [String: UnpublishedEventDisplay]) {
        unpublishedEvents = events
    }

    func addUnpublishedEvent(eventId: String, kind: Int, targetRelays: [String]) {
        var relayStates: [String: RelayPublishState] = [:]
        for relay in targetRelays {
            relayStates[relay] = .pending
        }
        unpublishedEvents[eventId] = UnpublishedEventDisplay(
            eventId: eventId,
            kind: kind,
            relayStates: relayStates
        )
    }

    func markRelayPublished(eventId: String, relay: String) {
        unpublishedEvents[eventId]?.relayStates[relay] = .published
    }

    func markRelayFailed(eventId: String, relay: String, reason: String) {
        unpublishedEvents[eventId]?.relayStates[relay] = .failed(reason: reason)
    }

    func removeUnpublishedEvent(eventId: String) {
        unpublishedEvents.removeValue(forKey: eventId)
    }

    func setAuthorRelays(_ pubkey: String, relays: Set<String>) {
        authorRelays[pubkey] = relays
    }

    func setTotalEvents(_ count: Int) {
        totalEvents = count
    }

    func setTotal10002Events(_ count: Int) {
        total10002Events = count
    }

    func log(_ message: String) {
        logs.insert((Date(), message), at: 0)
        if logs.count > maxLogs {
            logs.removeLast()
        }
    }

    func getSnapshot() -> TUISnapshot {
        TUISnapshot(
            isOnline: isOnline,
            relayStates: relayStates,
            subscriptions: subscriptions,
            relaySubscriptions: relaySubscriptions,
            recentEvents: recentEvents,
            unpublishedEvents: Array(unpublishedEvents.values),
            logs: logs,
            eventCount: eventCount,
            totalEvents: totalEvents,
            total10002Events: total10002Events,
            authorRelays: authorRelays
        )
    }
}

struct TUISnapshot {
    let isOnline: Bool
    let relayStates: [String: NDKRelayConnectionState]
    let subscriptions: [String: (kinds: [Int], authorCount: Int)]
    let relaySubscriptions: [(relay: String, subId: String, kinds: [Int], authorCount: Int)]
    let recentEvents: [(timestamp: Date, kind: Int, author: String, preview: String)]
    let unpublishedEvents: [UnpublishedEventDisplay]
    let logs: [(timestamp: Date, message: String)]
    let eventCount: Int
    let totalEvents: Int
    let total10002Events: Int  // Debug: total kind-10002 events in NostrDB
    let authorRelays: [String: Set<String>]
}

// MARK: - TUI Renderer

class TUIRenderer {
    private var lastRender = ""
    private let width = 80

    func render(_ state: TUISnapshot, userNpub: String, followCount: Int) {
        var lines: [String] = []

        // Header
        lines.append(c("╔" + String(repeating: "═", count: width - 2) + "╗", .cyan))
        lines.append(c("║", .cyan) + centerText("NDKSwift Offline-First Demo", width - 2) + c("║", .cyan))
        lines.append(c("╠" + String(repeating: "═", count: width - 2) + "╣", .cyan))

        // Status bar
        let modeText = state.isOnline ? c("● ONLINE", .brightGreen, bold: true) : c("○ OFFLINE", .brightYellow, bold: true)
        let connectedCount = state.relayStates.values.filter { state in
            state == .connected || state == .authenticated
        }.count
        let relayCountColor: Color = connectedCount > 0 ? .brightGreen : .yellow
        let relayText = "Relays: \(c("\(connectedCount)", relayCountColor))/\(state.relayStates.count)"
        let allEventsText = "All: \(c("\(state.totalEvents)", .brightGreen))"
        let eventsText = "Session: \(c("\(state.eventCount)", .green))"
        let unpubCount = state.unpublishedEvents.count
        let unpubColor: Color = unpubCount > 0 ? .brightYellow : .green
        let unpubText = "Unpub: \(c("\(unpubCount)", unpubColor))"

        let statusLine = "  \(modeText)  │  \(relayText)  │  \(allEventsText)  │  \(eventsText)  │  \(unpubText)"
        lines.append(c("║", .cyan) + padRight(statusLine, width - 2) + c("║", .cyan))

        // Debug: Show total kind-10002 events in NostrDB
        let k10002Text = "10002 in DB: \(c("\(state.total10002Events)", .brightMagenta))"
        let debugLine = "  \(k10002Text)"
        lines.append(c("║", .cyan) + padRight(debugLine, width - 2) + c("║", .cyan))

        lines.append(c("╠" + String(repeating: "═", count: width - 2) + "╣", .cyan))

        // Relays section
        let relayLimit = 8
        let totalRelays = state.relayStates.count
        lines.append(c("║", .cyan) + c(" RELAYS (\(totalRelays))", .brightCyan, bold: true) + padRight("", width - 13 - String(totalRelays).count) + c("║", .cyan))
        lines.append(c("║", .cyan) + padRight(String(repeating: "─", count: width - 4), width - 2) + c("║", .cyan))

        let sortedRelays = state.relayStates.sorted(by: { $0.key < $1.key })
        for (url, connState) in sortedRelays.prefix(relayLimit) {
            let (icon, color) = relayIcon(connState)
            let shortUrl = url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "/", with: "")

            // Count unique pubkeys covered by this relay
            let pubkeysCovered = state.authorRelays.filter { _, relays in
                relays.contains(url)
            }.count

            let subsOnRelay = state.relaySubscriptions.filter { $0.relay == url }
            let subCount = subsOnRelay.count

            var info = ""
            if subCount > 0 || pubkeysCovered > 0 {
                var parts: [String] = []
                if subCount > 0 {
                    parts.append("\(subCount) sub\(subCount == 1 ? "" : "s")")
                }
                if pubkeysCovered > 0 {
                    parts.append("\(pubkeysCovered) pubkey\(pubkeysCovered == 1 ? "" : "s")")
                }
                info = c(" [\(parts.joined(separator: ", "))]", .dim)
            }
            lines.append(c("║", .cyan) + padRight("  \(c(icon, color)) \(shortUrl)\(info)", width - 2) + c("║", .cyan))
        }

        if totalRelays > relayLimit {
            let remaining = totalRelays - relayLimit
            lines.append(c("║", .cyan) + padRight(c("  ... and \(remaining) more relay\(remaining == 1 ? "" : "s")", .dim), width - 2) + c("║", .cyan))
        }

        lines.append(c("╠" + String(repeating: "═", count: width - 2) + "╣", .cyan))

        // Outbox section - Author relay distribution
        lines.append(c("║", .cyan) + c(" OUTBOX (author→relays)", .brightYellow, bold: true) + padRight("", width - 26) + c("║", .cyan))
        lines.append(c("║", .cyan) + padRight(String(repeating: "─", count: width - 4), width - 2) + c("║", .cyan))

        if state.authorRelays.isEmpty {
            lines.append(c("║", .cyan) + padRight(c("  (no outbox data yet)", .dim), width - 2) + c("║", .cyan))
        } else {
            // Compute top relays across all authors
            var relayCount: [String: Int] = [:]
            for (_, relays) in state.authorRelays {
                for relay in relays {
                    relayCount[relay, default: 0] += 1
                }
            }
            let topRelays = relayCount.sorted { $0.value > $1.value }.prefix(4)

            // Show top relays with author count
            if !topRelays.isEmpty {
                let topLine = topRelays.map { relay, count in
                    let short = relay.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "/", with: "")
                    return "\(String(short.prefix(15)))(\(count))"
                }.joined(separator: " ")
                lines.append(c("║", .cyan) + padRight("  \(c("Top:", .dim)) \(topLine)", width - 2) + c("║", .cyan))
            }

            // Show each author's status
            let knownCount = state.authorRelays.filter { !$0.value.isEmpty }.count
            let unknownCount = state.authorRelays.count - knownCount
            let statusText = "Authors: \(c("\(knownCount) known", .green)), \(c("\(unknownCount) unknown", unknownCount > 0 ? .yellow : .dim))"
            lines.append(c("║", .cyan) + padRight("  \(statusText)", width - 2) + c("║", .cyan))

            // Show individual authors (limited)
            for (pubkey, relays) in state.authorRelays.sorted(by: { $0.key < $1.key }).prefix(4) {
                let shortPubkey = String(pubkey.prefix(8))
                if relays.isEmpty {
                    lines.append(c("║", .cyan) + padRight("  \(c(shortPubkey, .yellow)) → \(c("(no relay info)", .dim))", width - 2) + c("║", .cyan))
                } else {
                    let relayList = relays.map { $0.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "/", with: "") }.sorted().prefix(2).joined(separator: ", ")
                    lines.append(c("║", .cyan) + padRight("  \(c(shortPubkey, .green)) → \(relayList)\(relays.count > 2 ? "..." : "")", width - 2) + c("║", .cyan))
                }
            }
        }

        lines.append(c("╠" + String(repeating: "═", count: width - 2) + "╣", .cyan))

        // Subscriptions section
        let subLimit = 10
        let totalSubs = state.subscriptions.count
        lines.append(c("║", .cyan) + c(" SUBSCRIPTIONS (\(totalSubs))", .brightBlue, bold: true) + padRight("", width - 20 - String(totalSubs).count) + c("║", .cyan))
        lines.append(c("║", .cyan) + padRight(String(repeating: "─", count: width - 4), width - 2) + c("║", .cyan))

        if state.subscriptions.isEmpty {
            lines.append(c("║", .cyan) + padRight(c("  (none)", .dim), width - 2) + c("║", .cyan))
        } else {
            // Display subscriptions with per-relay breakdown
            let relayLimit = 4  // Max relays to show per subscription
            for (subId, sub) in state.subscriptions.sorted(by: { $0.key < $1.key }).prefix(subLimit) {
                let shortSubId = String(subId.prefix(8))
                let kindsStr = "kinds: [\(sub.kinds.map { String($0) }.joined(separator: ","))]"

                // Header line: subscription ID and kinds
                lines.append(c("║", .cyan) + padRight("  \(c(shortSubId, .brightBlue)) \(c(kindsStr, .dim))", width - 2) + c("║", .cyan))

                // Get relay subscriptions for this subscription, sorted by author count descending
                let relaysForSub = state.relaySubscriptions
                    .filter { $0.subId == subId }
                    .sorted { $0.authorCount > $1.authorCount }

                if relaysForSub.isEmpty {
                    lines.append(c("║", .cyan) + padRight(c("     (pending)", .yellow), width - 2) + c("║", .cyan))
                } else {
                    // Show per-relay author counts
                    for relaySub in relaysForSub.prefix(relayLimit) {
                        let shortRelay = relaySub.relay
                            .replacingOccurrences(of: "wss://", with: "")
                            .replacingOccurrences(of: "/", with: "")
                        let authorText = c("#\(relaySub.authorCount)", .green)
                        lines.append(c("║", .cyan) + padRight("     \(authorText) \(shortRelay)", width - 2) + c("║", .cyan))
                    }

                    // Show overflow indicator if more relays
                    if relaysForSub.count > relayLimit {
                        let remaining = relaysForSub.count - relayLimit
                        lines.append(c("║", .cyan) + padRight(c("     ... +\(remaining) more relay\(remaining == 1 ? "" : "s")", .dim), width - 2) + c("║", .cyan))
                    }
                }
            }

            if totalSubs > subLimit {
                let remaining = totalSubs - subLimit
                lines.append(c("║", .cyan) + padRight(c("  ... and \(remaining) more subscription\(remaining == 1 ? "" : "s")", .dim), width - 2) + c("║", .cyan))
            }
        }

        lines.append(c("╠" + String(repeating: "═", count: width - 2) + "╣", .cyan))

        // Events section
        lines.append(c("║", .cyan) + c(" RECENT EVENTS", .brightGreen, bold: true) + padRight("", width - 16) + c("║", .cyan))
        lines.append(c("║", .cyan) + padRight(String(repeating: "─", count: width - 4), width - 2) + c("║", .cyan))

        if state.recentEvents.isEmpty {
            lines.append(c("║", .cyan) + padRight(c("  (waiting for events...)", .dim), width - 2) + c("║", .cyan))
        } else {
            for event in state.recentEvents.prefix(6) {
                let timeStr = formatTime(event.timestamp)
                let preview = String(event.preview.prefix(40))
                let line = "  \(c(timeStr, .dim)) k:\(c("\(event.kind)", .cyan)) \(c(String(event.author.prefix(8)), .yellow)) \"\(preview)\""
                lines.append(c("║", .cyan) + padRight(line, width - 2) + c("║", .cyan))
            }
        }

        lines.append(c("╠" + String(repeating: "═", count: width - 2) + "╣", .cyan))

        // Unpublished events section
        lines.append(c("║", .cyan) + c(" UNPUBLISHED EVENTS", .brightYellow, bold: true) + padRight("", width - 21) + c("║", .cyan))
        lines.append(c("║", .cyan) + padRight(String(repeating: "─", count: width - 4), width - 2) + c("║", .cyan))

        if state.unpublishedEvents.isEmpty {
            lines.append(c("║", .cyan) + padRight(c("  (all events published)", .dim), width - 2) + c("║", .cyan))
        } else {
            for event in state.unpublishedEvents.prefix(3) {
                let shortId = String(event.eventId.prefix(8))
                lines.append(c("║", .cyan) + padRight("  \(c(shortId, .brightYellow)) k:\(event.kind)", width - 2) + c("║", .cyan))

                // Show each relay with its status
                for (relay, publishState) in event.relayStates.sorted(by: { $0.key < $1.key }).prefix(4) {
                    let shortRelay = relay.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "/", with: "")
                    let (icon, color, suffix): (String, Color, String) = {
                        switch publishState {
                        case .published:
                            return ("✓", .green, "")
                        case .pending:
                            return ("⏳", .yellow, "")
                        case .failed(let reason):
                            let shortReason = String(reason.prefix(20))
                            return ("✗", .red, " (\(shortReason))")
                        }
                    }()
                    lines.append(c("║", .cyan) + padRight("    \(c(icon, color)) \(shortRelay)\(c(suffix, .dim))", width - 2) + c("║", .cyan))
                }

                // Show overflow indicator if more relays
                if event.relayStates.count > 4 {
                    let remaining = event.relayStates.count - 4
                    lines.append(c("║", .cyan) + padRight(c("    ... +\(remaining) more relay\(remaining == 1 ? "" : "s")", .dim), width - 2) + c("║", .cyan))
                }
            }

            // Show overflow indicator if more events
            if state.unpublishedEvents.count > 3 {
                let remaining = state.unpublishedEvents.count - 3
                lines.append(c("║", .cyan) + padRight(c("  ... +\(remaining) more event\(remaining == 1 ? "" : "s")", .dim), width - 2) + c("║", .cyan))
            }
        }

        lines.append(c("╠" + String(repeating: "═", count: width - 2) + "╣", .cyan))

        // Activity log
        lines.append(c("║", .cyan) + c(" ACTIVITY LOG", .brightMagenta, bold: true) + padRight("", width - 15) + c("║", .cyan))
        lines.append(c("║", .cyan) + padRight(String(repeating: "─", count: width - 4), width - 2) + c("║", .cyan))

        if state.logs.isEmpty {
            lines.append(c("║", .cyan) + padRight(c("  (no activity yet)", .dim), width - 2) + c("║", .cyan))
        } else {
            for log in state.logs.prefix(6) {
                let timeStr = formatTime(log.timestamp)
                let msg = String(log.message.prefix(60))
                lines.append(c("║", .cyan) + padRight("  \(c(timeStr, .dim)) \(msg)", width - 2) + c("║", .cyan))
            }
        }

        lines.append(c("╠" + String(repeating: "═", count: width - 2) + "╣", .cyan))

        // Footer with controls
        lines.append(c("║", .cyan) + padRight("  \(c("O", .brightYellow))=online  \(c("S", .brightYellow))=sub  \(c("E", .brightYellow))=event  \(c("Q", .brightYellow))=quit", width - 2) + c("║", .cyan))
        lines.append(c("╚" + String(repeating: "═", count: width - 2) + "╝", .cyan))

        // Output
        let output = Term.home + lines.joined(separator: "\n")
        print(output)
    }

    private func centerText(_ text: String, _ width: Int) -> String {
        let padding = (width - text.count) / 2
        return String(repeating: " ", count: max(0, padding)) + text + String(repeating: " ", count: max(0, width - padding - text.count))
    }

    private func padRight(_ text: String, _ width: Int) -> String {
        // Strip ANSI codes to get actual length
        let stripped = text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
        let padding = width - stripped.count
        return text + String(repeating: " ", count: max(0, padding))
    }

    private func relayIcon(_ state: NDKRelayConnectionState) -> (String, Color) {
        switch state {
        case .connected, .authenticated: return ("●", .brightGreen)
        case .connecting, .authenticating: return ("◐", .yellow)
        case .authRequired: return ("🔐", .yellow)
        case .disconnected, .disconnecting: return ("○", .red)
        case .failed: return ("✗", .brightRed)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Terminal Input

func enableRawMode() -> termios {
    var raw = termios()
    tcgetattr(STDIN_FILENO, &raw)
    let original = raw
    raw.c_lflag &= ~UInt(ECHO | ICANON)
    raw.c_cc.16 = 1 // VMIN
    raw.c_cc.17 = 0 // VTIME
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    return original
}

func restoreTerminalMode(_ original: termios) {
    var orig = original
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)
}

// MARK: - Main App

@main
struct OfflineDemo {
    // App relay for fallback queries
    static let defaultRelays: [String] = ["wss://pyramid.fiatjaf.com"]

    nonisolated(unsafe) static var ndk: NDK!
    nonisolated(unsafe) static var cache: NDKNostrDBCache!
    nonisolated(unsafe) static var tuiState = TUIState()
    nonisolated(unsafe) static var renderer = TUIRenderer()
    nonisolated(unsafe) static var followedPubkeys: [String] = []
    nonisolated(unsafe) static var userNpub = ""
    nonisolated(unsafe) static var shouldExit = false
    nonisolated(unsafe) static var debugMode = false

    static func debug(_ message: String) {
        guard debugMode else { return }
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        FileHandle.standardError.write("[\(timestamp)] DEBUG: \(message)\n".data(using: .utf8)!)
    }

    static func main() async throws {
        // Parse arguments
        let args = CommandLine.arguments
        let isOfflineMode = args.contains("--offline")
        let resetCache = args.contains("--reset")
        let autoOnline = args.contains("--auto-online")
        debugMode = args.contains("--debug")
        let testMode = args.contains("--test")

        // Test mode - bypass TUI and just run through the flow
        if testMode {
            await runTestMode(resetCache: resetCache)
            return
        }

        // Debug mode - bypass TUI and print diagnostic info directly
        if debugMode {
            await runDebugMode(resetCache: resetCache)
            return
        }

        // Determine command
        var command: String?
        var kinds: [Int] = []
        var content: String?

        var i = 1
        while i < args.count {
            let arg = args[i]
            if arg == "req" {
                command = "req"
            } else if arg == "event" {
                command = "event"
            } else if arg == "-k", i + 1 < args.count {
                if let kind = Int(args[i + 1]) {
                    kinds.append(kind)
                }
                i += 1
            } else if arg == "-c", i + 1 < args.count {
                content = args[i + 1]
                i += 1
            }
            i += 1
        }

        // Show usage if no command
        if command == nil {
            printUsage()
            exit(0)
        }

        // Initialize
        print(Term.clearScreen + Term.home + Term.hideCursor)
        print("Initializing...")

        // Initialize cache
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OfflineDemo")

        if resetCache {
            try? FileManager.default.removeItem(at: cacheDir)
        }

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        cache = try await NDKNostrDBCache(path: cacheDir.path)

        // Initialize or load private key
        let signer = try await loadOrCreateSigner()
        userNpub = try signer.npub

        // Initialize NDK with Jaeger telemetry
        ndk = NDK(
            relayURLs: defaultRelays,
            signer: signer,
            cache: cache,
            debugMode: debugMode,
            outboxEnabled: true,
            outboxConfig: NDKOutboxConfig(
                blacklistedRelays: [],
                outboxRelays: ["wss://relay.damus.io"]
            ),
            telemetryConfig: .jaeger(
                endpoint: URL(string: "http://localhost:4318/v1/traces")!,
                serviceName: "offline-demo"
            )
        )

        // Initialize relay states
        for relay in defaultRelays {
            await tuiState.setRelayState(relay + "/", .disconnected)
        }

        // Set initial mode
        await tuiState.setOnline(!isOfflineMode)

        // Start relay monitoring (before connect so we catch all events)
        Task {
            for await change in await ndk.pool.relayChanges {
                switch change {
                case .relayAdded(let relay):
                    await tuiState.setRelayState(relay.url, .disconnected)

                    // Get relay origin to understand why it was added
                    let origin = await relay.origin
                    var reason = ""
                    switch origin {
                    case .explicit:
                        reason = "explicit"
                    case .outbox(let authorPubkey):
                        reason = "outbox(\(String(authorPubkey.prefix(8))))"
                    case .outboxConfig:
                        reason = "outbox config"
                    case .fallback:
                        reason = "fallback"
                    }

                    await tuiState.log("Relay added [\(reason)]: \(relay.url.replacingOccurrences(of: "wss://", with: ""))")
                case .relayConnected(let relay):
                    await tuiState.setRelayState(relay.url, .connected)
                    await tuiState.log("✓ Connected: \(relay.url.replacingOccurrences(of: "wss://", with: ""))")
                case .relayDisconnected(let relay):
                    await tuiState.setRelayState(relay.url, .disconnected)
                    await tuiState.log("✗ Disconnected: \(relay.url.replacingOccurrences(of: "wss://", with: ""))")
                case .relayRemoved(let url):
                    await tuiState.log("Relay removed: \(url)")
                }
                await refreshUI()
            }
        }

        // Load initial unpublished events and start monitoring changes
        Task {
            // Load initial state from cache
            let records = await cache.getAllUnpublishedRecords()
            var initialEvents: [String: UnpublishedEventDisplay] = [:]
            for (eventId, record) in records {
                var relayStates: [String: RelayPublishState] = [:]
                for relay in record.publishedRelays {
                    relayStates[relay] = .published
                }
                for (relay, reason) in record.pendingRelays {
                    relayStates[relay] = reason.isEmpty ? .pending : .failed(reason: reason)
                }
                if let kind = record.kind {
                    initialEvents[eventId] = UnpublishedEventDisplay(
                        eventId: eventId,
                        kind: kind,
                        relayStates: relayStates
                    )
                }
            }
            await tuiState.setUnpublishedEvents(initialEvents)
            await refreshUI()

            // Monitor changes reactively
            guard let changes = await cache.unpublishedChanges else { return }
            for await change in changes {
                switch change {
                case .eventAdded(let eventId, let kind, let targetRelays):
                    await tuiState.addUnpublishedEvent(eventId: eventId, kind: kind, targetRelays: targetRelays)
                case .relayPublished(let eventId, let relay):
                    await tuiState.markRelayPublished(eventId: eventId, relay: relay)
                case .relayFailed(let eventId, let relay, let reason):
                    await tuiState.markRelayFailed(eventId: eventId, relay: relay, reason: reason)
                case .eventRemoved(let eventId):
                    await tuiState.removeUnpublishedEvent(eventId: eventId)
                }
                await refreshUI()
            }
        }

        // Monitor per-relay publish events for activity log
        Task {
            for await publishEvent in await ndk.pool.publishEvents {
                let shortId = String(publishEvent.eventId.prefix(8))
                let shortRelay = publishEvent.relayUrl
                    .replacingOccurrences(of: "wss://", with: "")
                    .replacingOccurrences(of: "/", with: "")
                if publishEvent.success {
                    await tuiState.log("Event \(shortId) → \(shortRelay) ✓")
                } else {
                    let reason = publishEvent.message ?? "failed"
                    await tuiState.log("Event \(shortId) → \(shortRelay) ✗ (\(reason))")
                }
                await refreshUI()
            }
        }

        // Connect first if online mode (needed before fetching contact list)
        if !isOfflineMode {
            debug("Calling ndk.connect()...")
            await ndk.connect()
            debug("ndk.connect() complete")

            // Wait a moment for connections to establish
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let relays = await ndk.pool.relays
            debug("Connected relays: \(relays.count)")
            for relay in relays {
                let state = await relay.connectionState
                debug("  \(relay.url): \(state)")
            }
        }

        // Load hardcoded follows (1047 pubkeys from pablof7z's kind:3)
        await loadFollows()
        debug("Loaded \(followedPubkeys.count) follows")

        await tuiState.log("Initialized in \(isOfflineMode ? "OFFLINE" : "ONLINE") mode")

        // Execute command
        switch command {
        case "req":
            if kinds.isEmpty {
                kinds = [1] // Default to kind 1
            }
            await executeSubscription(kinds: kinds)

        case "event":
            guard let kind = kinds.first else {
                print("No kind specified")
                exit(1)
            }
            guard let eventContent = content else {
                print("No content specified")
                exit(1)
            }
            await executePublish(kind: kind, content: eventContent)

        default:
            break
        }

        // Initial render
        await refreshUI()

        // Enter interactive mode
        let originalTermios = enableRawMode()
        defer {
            restoreTerminalMode(originalTermios)
            print(Term.showCursor)
        }

        // Auto-online feature: go online automatically after 2 seconds
        var autoOnlineTask: Task<Void, Never>?
        if autoOnline && isOfflineMode {
            autoOnlineTask = Task {
                try? await Task.sleep(for: .seconds(2))
                await tuiState.log("Auto-going online...")
                await toggleOnlineOffline()
                // Wait for events and then exit
                try? await Task.sleep(for: .seconds(8))
                shouldExit = true
            }
        }
        defer { autoOnlineTask?.cancel() }

        while !shouldExit {
            var char: CChar = 0
            let bytesRead = read(STDIN_FILENO, &char, 1)

            if bytesRead > 0 {
                let key = Character(UnicodeScalar(UInt8(bitPattern: char)))

                if key == "o" || key == "O" {
                    await toggleOnlineOffline()
                } else if key == "s" || key == "S" {
                    await createRandomSubscription()
                } else if key == "e" || key == "E" {
                    await publishRandomEvent()
                } else if key == "q" || key == "Q" {
                    shouldExit = true
                }
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        print(Term.clearScreen + Term.home)
        print("Goodbye!")
    }

    static func refreshUI() async {
        // Update outbox data for all followed pubkeys
        await refreshOutboxData()

        // Update total events count from cache stats
        if let stats = await cache.getStats() {
            await tuiState.setTotalEvents(stats.totalEvents)
        }

        // Debug: Count total kind-10002 events in NostrDB
        let filter10002 = NDKFilter(kinds: [10002])
        if let events = try? await cache.queryEvents(filter10002) {
            await tuiState.setTotal10002Events(events.count)
        }

        let state = await tuiState.getSnapshot()
        renderer.render(state, userNpub: userNpub, followCount: followedPubkeys.count)
    }

    static func refreshOutboxData() async {
        var knownCount = 0
        var unknownCount = 0
        var nilCount = 0
        var emptyCount = 0

        for pubkey in followedPubkeys {
            // Get cached relay info (non-blocking)
            if let item = await ndk.outbox.getRelaysSyncFor(pubkey: pubkey, type: .read) {
                let relays = Set(item.readRelays.map { $0.url })
                await tuiState.setAuthorRelays(pubkey, relays: relays)
                if !relays.isEmpty {
                    knownCount += 1
                } else {
                    emptyCount += 1
                    unknownCount += 1
                }
            } else {
                // Mark as unknown (empty set)
                await tuiState.setAuthorRelays(pubkey, relays: [])
                nilCount += 1
                unknownCount += 1
            }
        }

        // Log on first few calls and periodically
        if debugMode {
            debug("refreshOutboxData: \(knownCount) known, \(unknownCount) unknown (nil=\(nilCount), empty=\(emptyCount)) out of \(followedPubkeys.count)")
        }
    }

    // MARK: - Key Management

    static func loadOrCreateSigner() async throws -> NDKPrivateKeySigner {
        let keyNamespace = "offline_demo"
        let keyName = "private_key"

        if let keyData = await cache.getValue(forKey: keyName, namespace: keyNamespace),
           let keyHex = String(data: keyData, encoding: .utf8) {
            return try NDKPrivateKeySigner(privateKey: keyHex)
        }

        let signer = try NDKPrivateKeySigner.generate()
        let keyHex = signer.privateKeyValue
        if let keyData = keyHex.data(using: .utf8) {
            try await cache.setValue(keyData, forKey: keyName, namespace: keyNamespace)
        }

        return signer
    }

    // MARK: - Contact List

    /// The seed pubkey whose contact list we use (fa984bd7... = pablof7z)
    static let seedPubkey = "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"

    static func loadFollows() async {
        // Use hardcoded follows list (1047 pubkeys from pablof7z's kind:3)
        followedPubkeys = HardcodedFollows.pubkeys
        await tuiState.log("\(followedPubkeys.count) follows (hardcoded)")
    }

    // MARK: - Commands

    static func executeSubscription(kinds: [Int]) async {
        await tuiState.log("Creating subscription for kinds: \(kinds)")
        debug("executeSubscription called with kinds: \(kinds)")

        guard !followedPubkeys.isEmpty else {
            await tuiState.log("No followed pubkeys!")
            debug("ERROR: No followed pubkeys!")
            return
        }

        debug("Creating filter with \(followedPubkeys.count) authors")
        let filter = NDKFilter(authors: followedPubkeys, kinds: kinds)

        // Generate a tracking ID for display
        let subId = String(UUID().uuidString.prefix(8))

        debug("Creating NDKSubscription with subId: \(subId)")
        let subscription = NDKSubscription<NDKEvent>(
            ndk: ndk,
            filter: filter,
            maxAge: 0,
            subscriptionId: subId,
            includeRelayUpdates: true
        )
        debug("NDKSubscription created")

        // Add subscription to UI immediately
        await tuiState.addSubscription(subId: subId, kinds: kinds, authorCount: followedPubkeys.count)
        await tuiState.log("Sub \(subId) created for kinds \(kinds)")
        await refreshUI()

        // Monitor incoming events
        Task {
            for await batch in subscription.events {
                for event in batch {
                    let preview = event.content.replacingOccurrences(of: "\n", with: " ")
                    await tuiState.addEvent(
                        kind: event.kind,
                        author: event.pubkey,
                        preview: preview
                    )
                }
                await refreshUI()
            }
        }

        // Monitor relay updates (including subscription activations)
        Task {
            guard let relayUpdates = subscription.relayUpdates else {
                debug("WARNING: relayUpdates is nil for subscription \(subId)")
                await tuiState.log("ERROR: relayUpdates is nil for sub \(subId)")
                return
            }
            debug("Starting relay updates monitoring for subscription \(subId)")
            for await update in relayUpdates {
                debug("Received relay update: \(update)")
                switch update {
                case let .subscriptionActivated(relay, kinds, authorCount):
                    debug("Subscription activated on relay \(relay) with \(authorCount) authors")
                    await tuiState.addRelaySubscription(relay: relay, subId: subId, kinds: kinds, authorCount: authorCount)
                    await tuiState.log("Sub \(String(subId.prefix(8))) → \(relay.replacingOccurrences(of: "wss://", with: "")) (\(authorCount) authors)")
                    await refreshUI()
                default:
                    debug("Ignoring relay update type: \(update)")
                    break
                }
            }
            debug("Relay updates stream ended for subscription \(subId)")
        }

        // Track relay connection states
        Task {
            while !shouldExit {
                let relays = await ndk.pool.relays
                for relay in relays {
                    let state = await relay.connectionState
                    await tuiState.setRelayState(relay.url, state)
                }
                await refreshUI()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    static func executePublish(kind: Int, content: String) async {
        await tuiState.log("Publishing kind:\(kind) event...")

        do {
            let (event, relays) = try await ndk.publish { builder in
                builder.kind(kind).content(content)
            }

            if relays.isEmpty {
                await tuiState.log("Event \(String(event.id.prefix(8))) queued (offline)")
            } else {
                let relayList = relays.map { $0.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "/", with: "") }.prefix(3).joined(separator: ", ")
                await tuiState.log("Event \(String(event.id.prefix(8))) → \(relayList)\(relays.count > 3 ? "..." : "")")
            }
        } catch {
            await tuiState.log("Publish error: \(error)")
        }

        await refreshUI()
    }

    // MARK: - Interactive Commands

    static func createRandomSubscription() async {
        guard !followedPubkeys.isEmpty else {
            await tuiState.log("No follows loaded!")
            return
        }

        let randomKind = randomNostrKind()
        await tuiState.log("Creating sub for kind \(randomKind) with \(followedPubkeys.count) authors")
        await executeSubscription(kinds: [randomKind])
    }

    static func publishRandomEvent() async {
        guard !followedPubkeys.isEmpty else {
            await tuiState.log("No follows loaded!")
            return
        }

        let randomPubkeys = selectRandomPubkeys(count: 5)
        let content = "Test event p-tagging \(randomPubkeys.count) random users"

        await tuiState.log("Publishing event with \(randomPubkeys.count) p-tags...")

        do {
            let (event, relays) = try await ndk.publish { builder in
                var b = builder.kind(1).content(content)
                for pubkey in randomPubkeys {
                    b = b.tag(["p", pubkey])
                }
                return b
            }

            if relays.isEmpty {
                await tuiState.log("Event \(String(event.id.prefix(8))) queued (offline)")
            } else {
                let relayList = relays.map { $0.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "/", with: "") }.joined(separator: ", ")
                await tuiState.log("Event \(String(event.id.prefix(8))) published to:")
                await tuiState.log("  → \(relayList)")
            }
        } catch {
            await tuiState.log("Publish error: \(error)")
        }

        await refreshUI()
    }

    // MARK: - Helper Functions

    static func randomNostrKind() -> Int {
        let commonKinds = [1, 3, 4, 5, 6, 7, 10002, 30023, 1111]
        return commonKinds.randomElement() ?? 1
    }

    static func selectRandomPubkeys(count: Int) -> [String] {
        let actualCount = min(count, followedPubkeys.count)
        return Array(followedPubkeys.shuffled().prefix(actualCount))
    }

    // MARK: - Online/Offline Toggle

    static func toggleOnlineOffline() async {
        let currentlyOnline = await tuiState.getSnapshot().isOnline

        if currentlyOnline {
            await tuiState.log("Going OFFLINE...")
            debug("toggleOnlineOffline: Going OFFLINE")
            await ndk.pool.disconnectAll()
            await tuiState.setOnline(false)
        } else {
            await tuiState.log("Going ONLINE...")
            debug("toggleOnlineOffline: Going ONLINE")
            await tuiState.setOnline(true)

            debug("toggleOnlineOffline: Calling ndk.connect()")
            await ndk.connect()
            debug("toggleOnlineOffline: ndk.connect() complete")

            debug("toggleOnlineOffline: Calling pool.connectAll()")
            await ndk.pool.connectAll()
            debug("toggleOnlineOffline: pool.connectAll() complete")

            // Check relay states after connect
            let relays = await ndk.pool.relays
            debug("toggleOnlineOffline: Pool has \(relays.count) relays")
            for relay in relays {
                let state = await relay.connectionState
                debug("  \(relay.url): \(state)")
            }

            // Check pending authors
            let pendingBefore = await ndk.outbox.getPendingAuthorsForTesting()
            debug("toggleOnlineOffline: Pending authors before discovery: \(pendingBefore.count)")

            // Wait a bit and check again
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let pendingAfter = await ndk.outbox.getPendingAuthorsForTesting()
            debug("toggleOnlineOffline: Pending authors after 3s: \(pendingAfter.count)")
        }

        await refreshUI()
    }

    // MARK: - Debug Mode (No TUI)

    /// Actor for thread-safe event counting in debug mode
    actor EventCounter {
        private(set) var count = 0

        func add(_ amount: Int) {
            count += amount
        }
    }

    static func runDebugMode(resetCache: Bool) async {
        print("╔══════════════════════════════════════════════════════════════════╗")
        print("║           NDKSwift Outbox Discovery Debug Mode                   ║")
        print("╚══════════════════════════════════════════════════════════════════╝")
        print("")

        // Initialize cache
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OfflineDemo")

        if resetCache {
            try? FileManager.default.removeItem(at: cacheDir)
            print("✓ Cache RESET")
        } else {
            print("✓ Using existing cache")
        }

        try! FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        cache = try! await NDKNostrDBCache(path: cacheDir.path)

        // Count existing 10002 events
        let filter10002 = NDKFilter(kinds: [10002])
        let existing10002 = (try? await cache.queryEvents(filter10002)) ?? []
        print("✓ Existing kind:10002 events in cache: \(existing10002.count)")

        // Initialize signer
        let signer = try! await loadOrCreateSigner()
        print("✓ Signer: \(try! signer.npub.prefix(20))...")

        // Initialize NDK with outbox relay
        ndk = NDK(
            relayURLs: ["wss://pyramid.fiatjaf.com"],
            signer: signer,
            cache: cache,
            debugMode: true,  // Enable library debug logging
            outboxEnabled: true,
            outboxConfig: NDKOutboxConfig(
                blacklistedRelays: [],
                outboxRelays: ["wss://relay.damus.io"]
            )
        )
        print("✓ NDK initialized")
        print("  - App relay: wss://pyramid.fiatjaf.com")
        print("  - Outbox relay: wss://relay.damus.io")

        // Load follows
        followedPubkeys = HardcodedFollows.pubkeys
        print("✓ Loaded \(followedPubkeys.count) followed pubkeys")
        print("")

        // ==================== STEP 1: Connect ====================
        print("═══════════════════════════════════════════════════════════════════")
        print("STEP 1: Connecting to relays...")
        print("═══════════════════════════════════════════════════════════════════")
        await ndk.connect()

        // Wait for connection
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Check relay states
        let relays = await ndk.pool.relays
        print("Pool has \(relays.count) relays:")
        for relay in relays {
            let state = await relay.connectionState
            print("  - \(relay.url): \(state)")
        }
        print("")

        // ==================== STEP 2: Check Initial State ====================
        print("═══════════════════════════════════════════════════════════════════")
        print("STEP 2: Checking initial outbox state...")
        print("═══════════════════════════════════════════════════════════════════")

        var knownBefore = 0
        for pubkey in followedPubkeys {
            if let item = await ndk.outbox.getRelaysSyncFor(pubkey: pubkey, type: .read) {
                if !item.readRelays.isEmpty {
                    knownBefore += 1
                }
            }
        }
        print("Known authors before subscription: \(knownBefore) / \(followedPubkeys.count)")
        print("")

        // ==================== STEP 3: Create Subscription ====================
        print("═══════════════════════════════════════════════════════════════════")
        print("STEP 3: Creating subscription with \(followedPubkeys.count) authors for kind:1...")
        print("═══════════════════════════════════════════════════════════════════")

        let filter = NDKFilter(authors: followedPubkeys, kinds: [1])
        let subscription = NDKSubscription<NDKEvent>(
            ndk: ndk,
            filter: filter,
            maxAge: 0,
            subscriptionId: "debug-sub",
            includeRelayUpdates: true
        )

        // Start monitoring events in background
        let eventCounter = EventCounter()
        Task {
            for await batch in subscription.events {
                await eventCounter.add(batch.count)
                let total = await eventCounter.count
                // Only log occasionally to avoid spam
                if total % 100 == 0 || total <= 10 {
                    print("[kind:1] Received batch of \(batch.count) events (total: \(total))")
                }
            }
        }
        print("Subscription created, waiting for discovery to trigger...")
        print("")

        // ==================== STEP 4: Monitor Discovery ====================
        print("═══════════════════════════════════════════════════════════════════")
        print("STEP 4: Monitoring relay discovery for 30 seconds...")
        print("═══════════════════════════════════════════════════════════════════")

        for i in 1...30 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            // Count known authors
            var currentKnown = 0
            for pubkey in followedPubkeys {
                if let item = await ndk.outbox.getRelaysSyncFor(pubkey: pubkey, type: .read) {
                    if !item.readRelays.isEmpty {
                        currentKnown += 1
                    }
                }
            }

            // Count 10002 events in cache
            let current10002 = (try? await cache.queryEvents(filter10002)) ?? []

            // Get pending count
            let pending = await ndk.outbox.getPendingAuthorsForTesting()
            let kind1Count = await eventCounter.count

            print("[\(String(format: "%2d", i))s] kind:10002 in DB: \(String(format: "%4d", current10002.count)) | Known authors: \(String(format: "%4d", currentKnown))/\(followedPubkeys.count) | Pending: \(pending.count) | kind:1 events: \(kind1Count)")

            // If we have enough, break early
            if current10002.count >= 400 {
                print("✓ SUCCESS! Got \(current10002.count) kind:10002 events!")
                break
            }
        }

        print("")
        print("═══════════════════════════════════════════════════════════════════")
        print("FINAL STATUS")
        print("═══════════════════════════════════════════════════════════════════")

        // Final count
        let final10002 = (try? await cache.queryEvents(filter10002)) ?? []
        print("kind:10002 events in cache: \(final10002.count)")

        var finalKnown = 0
        for pubkey in followedPubkeys {
            if let item = await ndk.outbox.getRelaysSyncFor(pubkey: pubkey, type: .read) {
                if !item.readRelays.isEmpty {
                    finalKnown += 1
                }
            }
        }
        print("Known authors: \(finalKnown) / \(followedPubkeys.count)")
        print("kind:1 events received: \(await eventCounter.count)")

        // Show top relays by author count
        var relayAuthorCounts: [String: Int] = [:]
        for pubkey in followedPubkeys {
            if let item = await ndk.outbox.getRelaysSyncFor(pubkey: pubkey, type: .read) {
                for relay in item.readRelays {
                    relayAuthorCounts[relay.url, default: 0] += 1
                }
            }
        }
        let topRelays = relayAuthorCounts.sorted { $0.value > $1.value }.prefix(10)
        if !topRelays.isEmpty {
            print("\nTop relays by author count:")
            for (relay, count) in topRelays {
                let shortRelay = relay.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "/", with: "")
                print("  \(shortRelay): \(count) authors")
            }
        }

        print("\n=== Debug Complete ===")
    }

    // MARK: - Test Mode

    static func runTestMode(resetCache: Bool) async {
        print("=== NDKSwift Outbox Discovery Test Mode ===")

        // Initialize cache
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OfflineDemo")

        if resetCache {
            try? FileManager.default.removeItem(at: cacheDir)
            print("[1/7] Cache reset")
        } else {
            print("[1/7] Using existing cache")
        }

        try! FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        cache = try! await NDKNostrDBCache(path: cacheDir.path)

        // Initialize signer
        let signer = try! await loadOrCreateSigner()
        print("[2/7] Signer initialized: \(try! signer.npub.prefix(16))...")

        // Initialize NDK with outbox relay
        ndk = NDK(
            relayURLs: [],  // No app relays
            signer: signer,
            cache: cache,
            debugMode: true,  // Enable library debug logging
            outboxEnabled: true,
            outboxConfig: NDKOutboxConfig(
                blacklistedRelays: [],
                outboxRelays: ["wss://relay.damus.io"]
            )
        )
        print("[3/7] NDK initialized with outbox relay: wss://relay.damus.io")

        // Load follows
        followedPubkeys = HardcodedFollows.pubkeys
        print("[4/7] Loaded \(followedPubkeys.count) followed pubkeys")

        // Check pending authors BEFORE subscription
        let pendingBefore = await ndk.outbox.getPendingAuthorsForTesting()
        print("[5/7] Pending authors BEFORE subscription: \(pendingBefore.count)")

        // Create subscription (OFFLINE - no relays connected yet)
        print("[5/7] Creating subscription with \(followedPubkeys.count) authors (OFFLINE)...")
        let filter = NDKFilter(authors: followedPubkeys, kinds: [1])
        let subscription = NDKSubscription<NDKEvent>(
            ndk: ndk,
            filter: filter,
            maxAge: 0,
            subscriptionId: "test-sub",
            includeRelayUpdates: true
        )

        // Start monitoring events in background
        var eventCount = 0
        Task {
            for await batch in subscription.events {
                eventCount += batch.count
                print("       📨 Received \(batch.count) events (total: \(eventCount))")
            }
        }

        // Wait for async tasks to complete
        print("[5/7] Waiting 2s for async discovery tasks...")
        try! await Task.sleep(nanoseconds: 2_000_000_000)

        // Check pending authors AFTER subscription
        let pendingAfterSub = await ndk.outbox.getPendingAuthorsForTesting()
        print("[5/7] Pending authors AFTER subscription: \(pendingAfterSub.count)")

        // Check known authors in cache
        var knownCount = 0
        for pubkey in followedPubkeys {
            if let item = await ndk.outbox.getRelaysSyncFor(pubkey: pubkey, type: .read) {
                if !item.readRelays.isEmpty {
                    knownCount += 1
                }
            }
        }
        print("[5/7] Known authors in cache: \(knownCount) / \(followedPubkeys.count)")

        // NOW GO ONLINE
        print("[6/7] Connecting to relays...")
        await ndk.connect()

        // Wait for connection
        try! await Task.sleep(nanoseconds: 2_000_000_000)

        // Check relay states
        let relays = await ndk.pool.relays
        print("[6/7] Pool has \(relays.count) relays")
        for relay in relays {
            let state = await relay.connectionState
            print("       - \(relay.url): \(state)")
        }

        // Check pending authors after connect
        let pendingAfterConnect = await ndk.outbox.getPendingAuthorsForTesting()
        print("[6/7] Pending authors AFTER connect: \(pendingAfterConnect.count)")

        // Wait for discovery to complete
        print("[7/7] Waiting 10s for relay discovery...")
        for i in 1...10 {
            try! await Task.sleep(nanoseconds: 1_000_000_000)

            var currentKnown = 0
            for pubkey in followedPubkeys {
                if let item = await ndk.outbox.getRelaysSyncFor(pubkey: pubkey, type: .read) {
                    if !item.readRelays.isEmpty {
                        currentKnown += 1
                    }
                }
            }

            let currentPending = await ndk.outbox.getPendingAuthorsForTesting()
            print("       [\(i)s] Known: \(currentKnown), Pending: \(currentPending.count)")

            if currentKnown > 0 {
                print("       SUCCESS! Discovery is working!")
            }
        }

        print("\n=== Test Complete ===")
    }

    // MARK: - Usage

    static func printUsage() {
        print(c("NDKSwift Offline-First Demo", .brightCyan, bold: true))
        print("")
        print(c("Usage:", .yellow, bold: true))
        print("  OfflineDemo [--offline] [--reset] req [-k <kind>...]")
        print("  OfflineDemo [--offline] [--reset] event -k <kind> -c <content>")
        print("")
        print(c("Options:", .yellow, bold: true))
        print("  --offline    Start in offline mode (no relay connections)")
        print("  --reset      Reset cache before starting")
        print("  --debug      Output debug info to stderr")
        print("")
        print(c("Examples:", .yellow, bold: true))
        print(c("  OfflineDemo --offline req -k 1 -k 20", .dim))
        print(c("  OfflineDemo --offline event -k 1 -c \"hello world\"", .dim))
        print(c("  OfflineDemo req -k 1   # Start online", .dim))
    }
}
