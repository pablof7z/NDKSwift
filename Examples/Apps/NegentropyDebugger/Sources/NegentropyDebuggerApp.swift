import NDKSwiftCore
import NDKSwiftNostrDB
import SwiftUI

@main
struct NegentropyDebuggerApp: App {
    @StateObject private var viewModel = DebuggerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Models

struct SyncSessionInfo: Identifiable {
    let id: String
    let relayURL: String
    let filter: NDKFilter
    let startTime: Date
    var messageRounds: Int
    var bytesTransferred: Int
    var downloadedCount: Int
    var uploadedCount: Int
    var isActive: Bool
    var actualDownloaded: [NDKEvent]
    var actualUploaded: [NDKEvent]
    var efficiencyRatio: Int
    var duration: TimeInterval
}

struct ProtocolMessage: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let direction: MessageDirection
    let type: MessageType
    let subscriptionId: String
    let dataPreview: String
    let fullData: String
    let byteCount: Int

    enum MessageDirection: String, Hashable {
        case outgoing = "OUT"
        case incoming = "IN"
    }

    enum MessageType: String, CaseIterable, Hashable {
        case negOpen = "NEG-OPEN"
        case negMsg = "NEG-MSG"
        case negClose = "NEG-CLOSE"
        case negErr = "NEG-ERR"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ProtocolMessage, rhs: ProtocolMessage) -> Bool {
        lhs.id == rhs.id
    }
}

struct DatabaseStats {
    var totalEvents: Int = 0
    var totalStorageSize: Int64 = 0
    var inMemoryCount: Int = 0
    var databasePath: String = ""
    var databases: [(name: String, count: Int, size: Int)] = []
    var kinds: [(kind: UInt64, count: Int, size: Int)] = []
}

// MARK: - View Model

@MainActor
class DebuggerViewModel: ObservableObject {
    @Published var ndk: NDK?
    @Published var cache: NDKNostrDBCache?
    @Published var isInitialized = false
    @Published var initError: String?
    @Published var logs: [LogEntry] = []
    @Published var isLoading = false

    // NostrDB Stats
    @Published var dbStats = DatabaseStats()

    // Event Browser
    @Published var queriedEvents: [NDKEvent] = []
    @Published var selectedEvent: NDKEvent?
    @Published var searchQuery = ""
    @Published var filterKind: Int? = nil

    // Negentropy
    @Published var syncSessions: [SyncSessionInfo] = []
    @Published var protocolMessages: [ProtocolMessage] = []
    @Published var selectedRelayURL = "wss://relay.damus.io"
    @Published var syncFilterKinds = "1"
    @Published var syncFilterLimit = "100"
    @Published var syncDirection: SyncDirection = .both

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let message: String

        enum LogLevel: String {
            case info = "INFO"
            case debug = "DEBUG"
            case warning = "WARN"
            case error = "ERROR"
        }
    }

    private let relayUrls = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band",
        "wss://purplepag.es",
        "wss://relay.primal.net",
    ]

    func initialize() async {
        isLoading = true
        log("Initializing NegentropyDebugger...", level: .info)

        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dbPath = documentsPath.appendingPathComponent("nostrdb-debug").path

            log("Database path: \(dbPath)", level: .debug)

            try FileManager.default.createDirectory(atPath: dbPath, withIntermediateDirectories: true)

            #if targetEnvironment(simulator)
                log("Running on Simulator - NostrDB may have limitations", level: .warning)
            #endif

            let nostrDBCache = try await NDKNostrDBCache(path: dbPath)
            cache = nostrDBCache
            log("NostrDB cache initialized successfully", level: .info)

            ndk = NDK(
                relayURLs: relayUrls,
                cache: nostrDBCache
            )
            log("NDK initialized with \(relayUrls.count) relays", level: .info)

            isInitialized = true
            await refreshStats()

        } catch {
            initError = error.localizedDescription
            log("Initialization failed: \(error.localizedDescription)", level: .error)
        }

        isLoading = false
    }

    // MARK: - Database Operations

    func refreshStats() async {
        guard let cache = cache else { return }

        log("Refreshing database stats...", level: .debug)

        if let stats = await cache.getStats() {
            var newStats = DatabaseStats()
            newStats.totalEvents = stats.totalEvents
            newStats.totalStorageSize = await cache.getDatabaseSize()
            newStats.inMemoryCount = await cache.inMemoryEventCount
            newStats.databasePath = await cache.getCachePath() ?? "Unknown"

            // Convert database stats
            newStats.databases = stats.databases.map { (key, value) in
                (name: key.name, count: value.count, size: value.totalSize)
            }.sorted { $0.count > $1.count }

            // Convert kind stats (now includes ALL kinds, not just common ones)
            newStats.kinds = stats.kinds.map { (key, value) in
                (kind: key, count: value.count, size: value.totalSize)
            }.sorted { $0.count > $1.count }

            dbStats = newStats
            log("Stats refreshed: \(stats.totalEvents) events, \(formatBytes(Int(newStats.totalStorageSize)))", level: .info)
        } else {
            log("Failed to get database stats", level: .warning)
        }
    }

    func clearInMemoryCache() async {
        guard let cache = cache else { return }

        log("Clearing in-memory cache...", level: .info)
        do {
            try await cache.clear()
            await refreshStats()
            log("In-memory cache cleared", level: .info)
        } catch {
            log("Failed to clear cache: \(error.localizedDescription)", level: .error)
        }
    }

    func resetDatabase() async {
        guard let cache = cache else { return }

        log("Resetting database (this will delete all data)...", level: .warning)
        do {
            try await cache.clearPersisted()
            await refreshStats()
            queriedEvents = []
            log("Database reset complete", level: .info)
        } catch {
            log("Failed to reset database: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: - Event Browser

    func queryEvents() async {
        guard let cache = cache else { return }

        isLoading = true
        log("Querying events with kind filter: \(filterKind?.description ?? "all")", level: .debug)

        do {
            var filter = NDKFilter()
            if let kind = filterKind {
                filter.kinds = [kind]
            }
            filter.limit = 100

            let events = try await cache.queryEvents(filter)
            queriedEvents = events.sorted { $0.createdAt > $1.createdAt }
            log("Query returned \(events.count) events", level: .info)
        } catch {
            log("Query failed: \(error.localizedDescription)", level: .error)
        }

        isLoading = false
    }

    func textSearch(_ query: String) async {
        guard let cache = cache, !query.isEmpty else { return }

        isLoading = true
        log("Text search for: '\(query)'", level: .debug)

        let results = await cache.textSearch(query, limit: 50)
        queriedEvents = results.sorted { $0.createdAt > $1.createdAt }
        log("Search found \(results.count) events", level: .info)

        isLoading = false
    }

    func fetchFromRelays() async {
        guard let ndk = ndk else { return }

        isLoading = true
        log("Fetching events from relays...", level: .info)

        await ndk.connect()
        log("Connected to relays", level: .debug)

        let filter = NDKFilter(
            kinds: filterKind.map { [$0] },
            limit: 50
        )

        let subscription = ndk.subscribe(
            filter: filter,
            cachePolicy: .networkOnly,
            closeOnEose: true
        )

        var fetchedEvents: [NDKEvent] = []

        let collectTask = Task {
            for await event in subscription.eventsUntilEOSE {
                fetchedEvents.append(event)
                if fetchedEvents.count >= 50 { break }
            }
        }

        try? await Task.sleep(for: .seconds(5))
        collectTask.cancel()

        queriedEvents = fetchedEvents.sorted { $0.createdAt > $1.createdAt }
        log("Fetched \(fetchedEvents.count) events from relays", level: .info)

        await refreshStats()
        isLoading = false
    }

    // MARK: - Negentropy Sync

    func startSync() async {
        guard let ndk = ndk else {
            log("NDK not initialized", level: .error)
            return
        }

        isLoading = true
        let startTime = Date()

        log("Starting negentropy sync with \(selectedRelayURL)", level: .info)
        log("Filter: kinds=[\(syncFilterKinds)], limit=\(syncFilterLimit), direction=\(syncDirection)", level: .debug)

        // Parse kinds
        let kinds = syncFilterKinds.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        // Create filter
        var filter = NDKFilter()
        if !kinds.isEmpty {
            filter.kinds = kinds
        }
        if let limit = Int(syncFilterLimit) {
            filter.limit = limit
        }

        // Record NEG-OPEN message
        let negOpenPreview = "NEG-OPEN: filter=\(kinds.isEmpty ? "all" : kinds.map(String.init).joined(separator: ","))"
        addProtocolMessage(
            direction: .outgoing,
            type: .negOpen,
            subscriptionId: "pending",
            dataPreview: negOpenPreview,
            fullData: negOpenPreview,
            byteCount: negOpenPreview.count
        )

        await ndk.connect()
        log("Connected to relays", level: .debug)

        do {
            let result = try await ndk.syncEvents(filter: filter, relay: selectedRelayURL, direction: syncDirection)

            // Create session info from result
            let session = SyncSessionInfo(
                id: UUID().uuidString,
                relayURL: selectedRelayURL,
                filter: filter,
                startTime: startTime,
                messageRounds: result.messageRounds,
                bytesTransferred: result.bytesTransferred,
                downloadedCount: result.downloadedEvents.count,
                uploadedCount: result.uploadedEvents.count,
                isActive: false,
                actualDownloaded: result.downloadedEvents,
                actualUploaded: result.uploadedEvents,
                efficiencyRatio: result.efficiencyRatio,
                duration: result.duration
            )

            syncSessions.insert(session, at: 0)

            // Record completion message
            addProtocolMessage(
                direction: .incoming,
                type: .negClose,
                subscriptionId: session.id,
                dataPreview: "Sync complete: \(result.downloadedEvents.count) down, \(result.uploadedEvents.count) up",
                fullData: """
                    Sync Complete
                    Downloaded: \(result.downloadedEvents.count) events
                    Uploaded: \(result.uploadedEvents.count) events
                    Rounds: \(result.messageRounds)
                    Bytes: \(formatBytes(result.bytesTransferred))
                    Duration: \(String(format: "%.2f", result.duration))s
                    Efficiency: \(result.efficiencyRatio)%
                    """,
                byteCount: result.bytesTransferred
            )

            log("Sync complete: \(result.downloadedEvents.count) downloaded, \(result.uploadedEvents.count) uploaded, \(result.messageRounds) rounds, \(formatBytes(result.bytesTransferred))", level: .info)

            await refreshStats()

        } catch {
            log("Sync failed: \(error.localizedDescription)", level: .error)

            addProtocolMessage(
                direction: .incoming,
                type: .negErr,
                subscriptionId: "error",
                dataPreview: "Error: \(error.localizedDescription)",
                fullData: error.localizedDescription,
                byteCount: 0
            )
        }

        isLoading = false
    }

    private func addProtocolMessage(direction: ProtocolMessage.MessageDirection, type: ProtocolMessage.MessageType, subscriptionId: String, dataPreview: String, fullData: String, byteCount: Int) {
        let message = ProtocolMessage(
            timestamp: Date(),
            direction: direction,
            type: type,
            subscriptionId: subscriptionId,
            dataPreview: dataPreview,
            fullData: fullData,
            byteCount: byteCount
        )
        protocolMessages.insert(message, at: 0)

        // Keep only last 100 messages
        if protocolMessages.count > 100 {
            protocolMessages.removeLast()
        }
    }

    // MARK: - Logging

    func log(_ message: String, level: LogEntry.LogLevel) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        logs.insert(entry, at: 0)

        // Keep only last 500 logs
        if logs.count > 500 {
            logs.removeLast()
        }

        print("[\(level.rawValue)] \(message)")
    }

    func clearLogs() {
        logs.removeAll()
    }

    // MARK: - Helpers

    func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }

    func kindName(_ kind: UInt64) -> String {
        "Kind \(kind)"
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var viewModel: DebuggerViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if !viewModel.isInitialized {
                InitializingView()
            } else {
                TabView {
                    DatabaseDashboardView()
                        .tabItem {
                            Label("Database", systemImage: "cylinder.split.1x2")
                        }

                    EventBrowserView()
                        .tabItem {
                            Label("Events", systemImage: "list.bullet.rectangle")
                        }

                    NegentropySyncView()
                        .tabItem {
                            Label("Negentropy", systemImage: "arrow.triangle.2.circlepath")
                        }

                    ProtocolInspectorView()
                        .tabItem {
                            Label("Protocol", systemImage: "network")
                        }

                    LogsView()
                        .tabItem {
                            Label("Logs", systemImage: "terminal")
                        }
                }
            }
        }
        .task {
            if !viewModel.isInitialized {
                await viewModel.initialize()
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var viewModel: DebuggerViewModel

    var body: some View {
        List {
            Section("Status") {
                HStack {
                    Circle()
                        .fill(viewModel.isInitialized ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(viewModel.isInitialized ? "Ready" : "Initializing...")
                }

                if viewModel.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Working...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.isInitialized {
                Section("Quick Stats") {
                    LabeledContent("Total Events", value: "\(viewModel.dbStats.totalEvents)")
                    LabeledContent("Storage", value: viewModel.formatBytes(Int(viewModel.dbStats.totalStorageSize)))
                    LabeledContent("In Memory", value: "\(viewModel.dbStats.inMemoryCount)")
                }

                Section("Sync Sessions") {
                    if viewModel.syncSessions.isEmpty {
                        Text("No sync sessions")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.syncSessions.prefix(5)) { session in
                            VStack(alignment: .leading) {
                                Text(session.relayURL)
                                    .font(.caption)
                                    .lineLimit(1)
                                HStack {
                                    Image(systemName: "arrow.down")
                                    Text("\(session.downloadedCount)")
                                    Image(systemName: "arrow.up")
                                    Text("\(session.uploadedCount)")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Debugger")
    }
}

// MARK: - Initializing View

struct InitializingView: View {
    @EnvironmentObject var viewModel: DebuggerViewModel

    var body: some View {
        VStack(spacing: 20) {
            if let error = viewModel.initError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                Text("Initialization Failed")
                    .font(.title)
                Text(error)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task {
                        await viewModel.initialize()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Initializing NostrDB...")
                    .font(.title2)
                Text("Setting up database and connecting to relays")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Database Dashboard

struct DatabaseDashboardView: View {
    @EnvironmentObject var viewModel: DebuggerViewModel
    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overview Cards
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                    StatCard(
                        title: "Total Events",
                        value: "\(viewModel.dbStats.totalEvents)",
                        icon: "doc.text",
                        color: .blue
                    )

                    StatCard(
                        title: "Storage Size",
                        value: viewModel.formatBytes(Int(viewModel.dbStats.totalStorageSize)),
                        icon: "internaldrive",
                        color: .orange
                    )

                    StatCard(
                        title: "In Memory",
                        value: "\(viewModel.dbStats.inMemoryCount)",
                        icon: "memorychip",
                        color: .green
                    )

                    StatCard(
                        title: "Databases",
                        value: "\(viewModel.dbStats.databases.count)",
                        icon: "cylinder.split.1x2",
                        color: .purple
                    )
                }
                .padding(.horizontal)

                // Database Path
                GroupBox("Database Location") {
                    HStack {
                        Text(viewModel.dbStats.databasePath)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = viewModel.dbStats.databasePath
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
                .padding(.horizontal)

                // Database Breakdown
                GroupBox("Database Breakdown") {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.dbStats.databases, id: \.name) { db in
                            HStack {
                                Text(db.name)
                                    .frame(width: 150, alignment: .leading)
                                Spacer()
                                Text("\(db.count)")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                                Text(viewModel.formatBytes(db.size))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .font(.system(.caption, design: .monospaced))
                            Divider()
                        }
                    }
                }
                .padding(.horizontal)

                // Event Kinds Breakdown (ALL kinds)
                GroupBox("Event Kinds") {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.dbStats.kinds.filter { $0.count > 0 }, id: \.kind) { kindStat in
                            HStack {
                                Text(viewModel.kindName(kindStat.kind))
                                    .frame(width: 120, alignment: .leading)
                                Spacer()
                                Text("\(kindStat.count)")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                                Text(viewModel.formatBytes(kindStat.size))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .font(.system(.caption, design: .monospaced))
                            Divider()
                        }
                    }
                }
                .padding(.horizontal)

                // Actions
                GroupBox("Actions") {
                    HStack(spacing: 16) {
                        Button {
                            Task { await viewModel.refreshStats() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await viewModel.clearInMemoryCache() }
                        } label: {
                            Label("Clear Memory", systemImage: "memorychip")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            Label("Reset Database", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Database Dashboard")
        .confirmationDialog(
            "Reset Database?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task { await viewModel.resetDatabase() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all events from the database. This action cannot be undone.")
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Event Browser

struct EventBrowserView: View {
    @EnvironmentObject var viewModel: DebuggerViewModel
    @State private var kindFilterText: String = ""

    var body: some View {
        HStack(spacing: 0) {
            // Event List
            VStack(spacing: 0) {
                // Search and Filters
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search content...", text: $viewModel.searchQuery)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                Task { await viewModel.textSearch(viewModel.searchQuery) }
                            }
                        if !viewModel.searchQuery.isEmpty {
                            Button {
                                viewModel.searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)

                    HStack {
                        Text("Kind:")
                            .foregroundStyle(.secondary)
                        TextField("All", text: $kindFilterText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: kindFilterText) { _, newValue in
                                viewModel.filterKind = Int(newValue)
                            }

                        Spacer()

                        Button {
                            Task { await viewModel.queryEvents() }
                        } label: {
                            Label("Query", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await viewModel.fetchFromRelays() }
                        } label: {
                            Label("Fetch", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()

                Divider()

                // Events List
                if viewModel.queriedEvents.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "doc.text",
                        description: Text("Query the database or fetch from relays")
                    )
                } else {
                    List(viewModel.queriedEvents, id: \.id) { event in
                        EventRowView(event: event)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedEvent = event
                            }
                            .listRowBackground(viewModel.selectedEvent?.id == event.id ? Color.blue.opacity(0.2) : Color.clear)
                    }
                }
            }
            .frame(minWidth: 400)

            Divider()

            // Event Detail
            if let event = viewModel.selectedEvent {
                EventDetailView(event: event)
                    .frame(minWidth: 400)
            } else {
                ContentUnavailableView(
                    "Select an Event",
                    systemImage: "hand.tap",
                    description: Text("Choose an event from the list to view details")
                )
                .frame(minWidth: 400)
            }
        }
        .navigationTitle("Event Browser (\(viewModel.queriedEvents.count))")
    }
}

struct EventRowView: View {
    let event: NDKEvent
    @EnvironmentObject var viewModel: DebuggerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(viewModel.kindName(UInt64(event.kind)))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)

                Spacer()

                Text(formatDate(event.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(event.content.prefix(150) + (event.content.count > 150 ? "..." : ""))
                .font(.caption)
                .lineLimit(3)

            Text(event.pubkey.prefix(16) + "...")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct EventDetailView: View {
    let event: NDKEvent
    @EnvironmentObject var viewModel: DebuggerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Event ID") {
                    HStack {
                        Text(event.id)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = event.id
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }

                GroupBox("Pubkey") {
                    HStack {
                        Text(event.pubkey)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = event.pubkey
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }

                GroupBox("Metadata") {
                    LabeledContent("Kind", value: "\(event.kind) (\(viewModel.kindName(UInt64(event.kind))))")
                    LabeledContent("Created At", value: formatFullDate(event.createdAt))
                }

                GroupBox("Content") {
                    Text(event.content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                if !event.tags.isEmpty {
                    GroupBox("Tags (\(event.tags.count))") {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(event.tags.enumerated()), id: \.offset) { _, tag in
                                HStack {
                                    Text("[\(tag.joined(separator: ", "))]")
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                Divider()
                            }
                        }
                    }
                }

                GroupBox("Signature") {
                    Text(event.sig)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }

                GroupBox("Raw JSON") {
                    if let json = try? event.toJSON() {
                        Text(json)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("Failed to serialize")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }

    private func formatFullDate(_ timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .long
        return formatter.string(from: date)
    }
}

// MARK: - Negentropy Sync View

struct NegentropySyncView: View {
    @EnvironmentObject var viewModel: DebuggerViewModel
    @State private var selectedSession: SyncSessionInfo?

    let relayOptions = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band",
        "wss://purplepag.es",
        "wss://relay.primal.net",
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Sync Configuration
            VStack(spacing: 0) {
                GroupBox("Sync Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Relay") {
                            Picker("", selection: $viewModel.selectedRelayURL) {
                                ForEach(relayOptions, id: \.self) { relay in
                                    Text(relay.replacingOccurrences(of: "wss://", with: ""))
                                        .tag(relay)
                                }
                            }
                        }

                        LabeledContent("Kinds") {
                            TextField("e.g., 1,6,7", text: $viewModel.syncFilterKinds)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                        }

                        LabeledContent("Limit") {
                            TextField("100", text: $viewModel.syncFilterLimit)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }

                        LabeledContent("Direction") {
                            Picker("", selection: $viewModel.syncDirection) {
                                Text("Both").tag(SyncDirection.both)
                                Text("Receive Only").tag(SyncDirection.receive)
                                Text("Send Only").tag(SyncDirection.send)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                .padding()

                Button {
                    Task { await viewModel.startSync() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Start Sync")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
                .padding(.horizontal)

                Divider()
                    .padding(.vertical)

                // Session List
                Text("Sync Sessions")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                if viewModel.syncSessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Start a sync to see session details")
                    )
                } else {
                    List(viewModel.syncSessions) { session in
                        SyncSessionRowView(session: session)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSession = session
                            }
                            .listRowBackground(selectedSession?.id == session.id ? Color.blue.opacity(0.2) : Color.clear)
                    }
                }
            }
            .frame(minWidth: 350)

            Divider()

            // Session Detail
            if let session = selectedSession ?? viewModel.syncSessions.first {
                SyncSessionDetailView(session: session)
                    .frame(minWidth: 400)
            } else {
                ContentUnavailableView(
                    "No Session Selected",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Complete a sync to see details")
                )
                .frame(minWidth: 400)
            }
        }
        .navigationTitle("Negentropy Sync")
    }
}

struct SyncSessionRowView: View {
    let session: SyncSessionInfo
    @EnvironmentObject var viewModel: DebuggerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(session.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(session.relayURL.replacingOccurrences(of: "wss://", with: ""))
                    .font(.caption)
                    .lineLimit(1)
            }

            HStack(spacing: 16) {
                Label("\(session.downloadedCount)", systemImage: "arrow.down")
                Label("\(session.uploadedCount)", systemImage: "arrow.up")
                Label("\(session.messageRounds)", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(viewModel.formatBytes(session.bytesTransferred))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct SyncSessionDetailView: View {
    let session: SyncSessionInfo
    @EnvironmentObject var viewModel: DebuggerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Session Overview") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                        MetricView(title: "Rounds", value: "\(session.messageRounds)", icon: "arrow.triangle.2.circlepath")
                        MetricView(title: "Downloaded", value: "\(session.downloadedCount)", icon: "arrow.down.circle")
                        MetricView(title: "Uploaded", value: "\(session.uploadedCount)", icon: "arrow.up.circle")
                        MetricView(title: "Total Bytes", value: viewModel.formatBytes(session.bytesTransferred), icon: "network")
                        MetricView(title: "Efficiency", value: "\(session.efficiencyRatio)%", icon: "bolt")
                        MetricView(title: "Duration", value: String(format: "%.2fs", session.duration), icon: "clock")
                    }
                }

                if !session.actualDownloaded.isEmpty {
                    GroupBox("Downloaded Events (\(session.actualDownloaded.count))") {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(session.actualDownloaded.prefix(20), id: \.id) { event in
                                HStack {
                                    Text(viewModel.kindName(UInt64(event.kind)))
                                        .font(.caption)
                                        .padding(.horizontal, 4)
                                        .background(Color.green.opacity(0.2))
                                        .cornerRadius(4)
                                    Text(event.content.prefix(50) + "...")
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                            if session.actualDownloaded.count > 20 {
                                Text("... and \(session.actualDownloaded.count - 20) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !session.actualUploaded.isEmpty {
                    GroupBox("Uploaded Events (\(session.actualUploaded.count))") {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(session.actualUploaded.prefix(20), id: \.id) { event in
                                HStack {
                                    Text(viewModel.kindName(UInt64(event.kind)))
                                        .font(.caption)
                                        .padding(.horizontal, 4)
                                        .background(Color.orange.opacity(0.2))
                                        .cornerRadius(4)
                                    Text(event.content.prefix(50) + "...")
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                            if session.actualUploaded.count > 20 {
                                Text("... and \(session.actualUploaded.count - 20) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GroupBox("Timing") {
                    LabeledContent("Started", value: formatTime(session.startTime))
                }
            }
            .padding()
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct MetricView: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Protocol Inspector

struct ProtocolInspectorView: View {
    @EnvironmentObject var viewModel: DebuggerViewModel
    @State private var selectedMessage: ProtocolMessage?
    @State private var filterType: ProtocolMessage.MessageType?

    var filteredMessages: [ProtocolMessage] {
        guard let filterType = filterType else {
            return viewModel.protocolMessages
        }
        return viewModel.protocolMessages.filter { $0.type == filterType }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Filters
                HStack {
                    Text("Filter:")
                        .foregroundStyle(.secondary)

                    Button {
                        filterType = nil
                    } label: {
                        Text("All")
                    }
                    .buttonStyle(.bordered)
                    .tint(filterType == nil ? .blue : .gray)

                    ForEach(ProtocolMessage.MessageType.allCases, id: \.self) { type in
                        Button {
                            filterType = type
                        } label: {
                            Text(type.rawValue)
                        }
                        .buttonStyle(.bordered)
                        .tint(filterType == type ? .blue : .gray)
                    }

                    Spacer()

                    Button {
                        viewModel.protocolMessages.removeAll()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                Divider()

                // Message List
                if filteredMessages.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "network",
                        description: Text("Protocol messages will appear here during sync")
                    )
                } else {
                    List(filteredMessages) { message in
                        ProtocolMessageRowView(message: message)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMessage = message
                            }
                            .listRowBackground(selectedMessage?.id == message.id ? Color.blue.opacity(0.2) : Color.clear)
                    }
                }
            }
            .frame(minWidth: 400)

            Divider()

            // Message Detail
            if let message = selectedMessage {
                ProtocolMessageDetailView(message: message)
                    .frame(minWidth: 400)
            } else {
                ContentUnavailableView(
                    "Select a Message",
                    systemImage: "hand.tap",
                    description: Text("Choose a message to view details")
                )
                .frame(minWidth: 400)
            }
        }
        .navigationTitle("Protocol Inspector (\(filteredMessages.count))")
    }
}

struct ProtocolMessageRowView: View {
    let message: ProtocolMessage
    @EnvironmentObject var viewModel: DebuggerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: message.direction == .outgoing ? "arrow.up.circle" : "arrow.down.circle")
                    .foregroundStyle(message.direction == .outgoing ? .blue : .green)

                Text(message.type.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(messageTypeColor(message.type).opacity(0.2))
                    .cornerRadius(4)

                Spacer()

                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(message.dataPreview)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.secondary)

            Text("\(viewModel.formatBytes(message.byteCount))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func messageTypeColor(_ type: ProtocolMessage.MessageType) -> Color {
        switch type {
        case .negOpen: return .blue
        case .negMsg: return .purple
        case .negClose: return .green
        case .negErr: return .red
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

struct ProtocolMessageDetailView: View {
    let message: ProtocolMessage
    @EnvironmentObject var viewModel: DebuggerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Message Info") {
                    LabeledContent("Type", value: message.type.rawValue)
                    LabeledContent("Direction", value: message.direction == .outgoing ? "Outgoing" : "Incoming")
                    LabeledContent("Subscription ID", value: message.subscriptionId)
                    LabeledContent("Size", value: viewModel.formatBytes(message.byteCount))
                    LabeledContent("Timestamp", value: formatFullTime(message.timestamp))
                }

                GroupBox("Data") {
                    Text(message.fullData)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
    }

    private func formatFullTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .long
        return formatter.string(from: date)
    }
}

// MARK: - Logs View

struct LogsView: View {
    @EnvironmentObject var viewModel: DebuggerViewModel
    @State private var filterLevel: DebuggerViewModel.LogEntry.LogLevel?

    var filteredLogs: [DebuggerViewModel.LogEntry] {
        guard let level = filterLevel else {
            return viewModel.logs
        }
        return viewModel.logs.filter { $0.level == level }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack {
                Text("Filter:")
                    .foregroundStyle(.secondary)

                Button { filterLevel = nil } label: { Text("All") }
                    .buttonStyle(.bordered)
                    .tint(filterLevel == nil ? .blue : .gray)

                Button { filterLevel = .info } label: { Text("Info") }
                    .buttonStyle(.bordered)
                    .tint(filterLevel == .info ? .blue : .gray)

                Button { filterLevel = .debug } label: { Text("Debug") }
                    .buttonStyle(.bordered)
                    .tint(filterLevel == .debug ? .blue : .gray)

                Button { filterLevel = .warning } label: { Text("Warn") }
                    .buttonStyle(.bordered)
                    .tint(filterLevel == .warning ? .orange : .gray)

                Button { filterLevel = .error } label: { Text("Error") }
                    .buttonStyle(.bordered)
                    .tint(filterLevel == .error ? .red : .gray)

                Spacer()

                Text("\(filteredLogs.count) entries")
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.clearLogs()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Log List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredLogs) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(formatTime(entry.timestamp))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 80, alignment: .leading)

                                Text(entry.level.rawValue)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(logLevelColor(entry.level))
                                    .frame(width: 50, alignment: .leading)

                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: viewModel.logs.count) { _, _ in
                    if let first = filteredLogs.first {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
        .navigationTitle("Logs")
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func logLevelColor(_ level: DebuggerViewModel.LogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .debug: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
