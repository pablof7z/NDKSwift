import SwiftUI
import NDKSwift

@main
struct NostrDBDemoApp: App {
    @StateObject private var viewModel = NostrDBViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Performance Metrics

struct PerformanceMetrics {
    var cacheInitTime: TimeInterval = 0
    var eventSaveTime: TimeInterval = 0
    var eventRetrieveTime: TimeInterval = 0
    var queryTime: TimeInterval = 0
    var textSearchTime: TimeInterval = 0
    var totalEventsStored: Int = 0
    var totalEventsRetrieved: Int = 0
    var totalQueries: Int = 0
    var averageSaveTime: TimeInterval = 0
    var averageRetrieveTime: TimeInterval = 0
}

// MARK: - View Model

@MainActor
class NostrDBViewModel: ObservableObject {
    @Published var ndk: NDK?
    @Published var cache: NDKCache?
    @Published var nostrDBCache: NDKNostrDBCache?
    @Published var isInitialized = false
    @Published var initError: String?
    @Published var events: [NDKEvent] = []
    @Published var metrics = PerformanceMetrics()
    @Published var logs: [String] = []
    @Published var isLoading = false
    @Published var cacheType: String = "Unknown"

    private var saveTimes: [TimeInterval] = []
    private var retrieveTimes: [TimeInterval] = []

    func initialize() async {
        isLoading = true
        log("Starting cache initialization...")

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            // Get documents directory for database
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dbPath = documentsPath.appendingPathComponent("nostrdb").path

            log("Database path: \(dbPath)")

            // Create directory if needed
            try FileManager.default.createDirectory(atPath: dbPath, withIntermediateDirectories: true)

            // NostrDB crashes on iOS Simulator due to LMDB mmap issues
            // Skip NostrDB on simulator and use SQLite directly
            var cacheToUse: NDKCache

            #if targetEnvironment(simulator)
            log("Running on Simulator - using SQLite cache (NostrDB not supported)")
            let sqliteCache = try await NDKSQLiteCache(path: documentsPath.appendingPathComponent("ndk_cache.sqlite").path)
            cacheToUse = sqliteCache
            cacheType = "SQLite"
            #else
            do {
                let nostrDB = try await NDKNostrDBCache(path: dbPath)
                nostrDBCache = nostrDB
                cacheToUse = nostrDB
                cacheType = "NostrDB"
                log("Using NostrDB cache backend")
            } catch {
                log("NostrDB unavailable (\(error.localizedDescription)), using SQLite fallback")
                let sqliteCache = try await NDKSQLiteCache(path: documentsPath.appendingPathComponent("ndk_cache.sqlite").path)
                cacheToUse = sqliteCache
                cacheType = "SQLite"
            }
            #endif

            cache = cacheToUse

            let initTime = CFAbsoluteTimeGetCurrent() - startTime
            metrics.cacheInitTime = initTime
            log("Cache initialized in \(String(format: "%.3f", initTime * 1000))ms")

            // Initialize NDK with cache
            ndk = NDK(
                relayUrls: [
                    "wss://relay.damus.io/",
                    "wss://nos.lol/",
                    "wss://relay.nostr.band/"
                ],
                cache: cacheToUse
            )

            log("NDK initialized with 3 relays")
            isInitialized = true

        } catch {
            initError = error.localizedDescription
            log("ERROR: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func fetchEvents() async {
        guard let ndk = ndk else {
            log("ERROR: NDK not initialized")
            return
        }

        isLoading = true
        log("Fetching events from relays...")

        let startTime = CFAbsoluteTimeGetCurrent()

        // Connect to relays
        await ndk.connect()
        log("Connected to relays")

        // Create filter for recent text notes
        let filter = NDKFilter(
            kinds: [1],
            limit: 50
        )

        // Subscribe and collect events with timeout
        let subscription = ndk.subscribe(
            filter: filter,
            cachePolicy: .networkOnly,
            closeOnEose: true
        )

        var fetchedEvents: [NDKEvent] = []

        // Collect events until timeout or EOSE
        let collectTask = Task {
            for await event in subscription.eventsUntilEOSE {
                fetchedEvents.append(event)
                if fetchedEvents.count >= 50 { break }
            }
        }

        // Timeout after 5 seconds
        try? await Task.sleep(for: .seconds(5))
        collectTask.cancel()

        let fetchTime = CFAbsoluteTimeGetCurrent() - startTime
        log("Fetched \(fetchedEvents.count) events in \(String(format: "%.3f", fetchTime * 1000))ms")

        events = fetchedEvents
        metrics.totalEventsRetrieved += fetchedEvents.count

        isLoading = false
    }

    func testSavePerformance() async {
        guard let cache = cache else {
            log("ERROR: Cache not initialized")
            return
        }

        isLoading = true
        log("Testing save performance with 100 events...")

        var totalTime: TimeInterval = 0
        let testEvents = createTestEvents(count: 100)

        for (index, event) in testEvents.enumerated() {
            let startTime = CFAbsoluteTimeGetCurrent()

            do {
                try await cache.saveEvent(event)
                let saveTime = CFAbsoluteTimeGetCurrent() - startTime
                totalTime += saveTime
                saveTimes.append(saveTime)

                if index % 20 == 0 {
                    log("Saved \(index + 1)/100 events...")
                }
            } catch {
                log("ERROR saving event: \(error.localizedDescription)")
            }
        }

        metrics.eventSaveTime = totalTime
        metrics.totalEventsStored += testEvents.count
        metrics.averageSaveTime = totalTime / Double(testEvents.count)

        log("Saved 100 events in \(String(format: "%.3f", totalTime * 1000))ms")
        log("Average save time: \(String(format: "%.3f", metrics.averageSaveTime * 1000))ms per event")

        isLoading = false
    }

    func testRetrievePerformance() async {
        guard let cache = cache else {
            log("ERROR: Cache not initialized")
            return
        }

        isLoading = true
        log("Testing retrieve performance...")

        // First save some events
        let testEvents = createTestEvents(count: 50)
        for event in testEvents {
            try? await cache.saveEvent(event)
        }

        var totalTime: TimeInterval = 0
        var retrievedCount = 0

        for event in testEvents {
            let startTime = CFAbsoluteTimeGetCurrent()
            let retrieved = await cache.getEvent(id: event.id)
            let retrieveTime = CFAbsoluteTimeGetCurrent() - startTime
            totalTime += retrieveTime
            retrieveTimes.append(retrieveTime)

            if retrieved != nil {
                retrievedCount += 1
            }
        }

        metrics.eventRetrieveTime = totalTime
        metrics.averageRetrieveTime = totalTime / Double(testEvents.count)

        log("Retrieved \(retrievedCount)/50 events in \(String(format: "%.3f", totalTime * 1000))ms")
        log("Average retrieve time: \(String(format: "%.3f", metrics.averageRetrieveTime * 1000))ms per event")

        isLoading = false
    }

    func testQueryPerformance() async {
        guard let cache = cache else {
            log("ERROR: Cache not initialized")
            return
        }

        isLoading = true
        log("Testing query performance...")

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let filter = NDKFilter(kinds: [1], limit: 100)
            let results = try await cache.queryEvents(filter)

            let queryTime = CFAbsoluteTimeGetCurrent() - startTime
            metrics.queryTime = queryTime
            metrics.totalQueries += 1

            log("Query returned \(results.count) events in \(String(format: "%.3f", queryTime * 1000))ms")
            events = results

        } catch {
            log("ERROR querying: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func testTextSearch() async {
        guard let nostrDBCache = nostrDBCache else {
            log("Text search requires NostrDB (not available with SQLite fallback)")
            return
        }

        isLoading = true
        log("Testing text search for 'bitcoin'...")

        let startTime = CFAbsoluteTimeGetCurrent()
        let results = await nostrDBCache.textSearch("bitcoin", limit: 20)
        let searchTime = CFAbsoluteTimeGetCurrent() - startTime

        metrics.textSearchTime = searchTime

        log("Text search found \(results.count) events in \(String(format: "%.3f", searchTime * 1000))ms")

        if !results.isEmpty {
            events = results
        }

        isLoading = false
    }

    func clearLogs() {
        logs.removeAll()
    }

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
        print("[\(timestamp)] \(message)")
    }

    private func createTestEvents(count: Int) -> [NDKEvent] {
        let testPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"

        return (0..<count).map { i in
            NDKEvent(
                id: String(format: "%064x", i),
                pubkey: testPubkey,
                createdAt: Timestamp(Date().timeIntervalSince1970 - Double(i)),
                kind: 1,
                tags: [],
                content: "Test event \(i) - Bitcoin Nostr Lightning \(UUID().uuidString)",
                sig: String(repeating: "0", count: 128)
            )
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var viewModel: NostrDBViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                StatusBar()

                // Main content
                TabView {
                    PerformanceView()
                        .tabItem {
                            Label("Performance", systemImage: "gauge.with.dots.needle.67percent")
                        }

                    EventsView()
                        .tabItem {
                            Label("Events", systemImage: "list.bullet")
                        }

                    LogsView()
                        .tabItem {
                            Label("Logs", systemImage: "terminal")
                        }
                }
            }
            .navigationTitle("NostrDB Demo")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if !viewModel.isInitialized {
                    await viewModel.initialize()
                }
            }
        }
    }
}

// MARK: - Status Bar

struct StatusBar: View {
    @EnvironmentObject var viewModel: NostrDBViewModel

    var body: some View {
        HStack {
            Circle()
                .fill(viewModel.isInitialized ? Color.green : Color.red)
                .frame(width: 10, height: 10)

            Text(viewModel.isInitialized ? "\(viewModel.cacheType) Ready" : "Initializing...")
                .font(.caption)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Text("\(viewModel.metrics.totalEventsStored) stored")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

// MARK: - Performance View

struct PerformanceView: View {
    @EnvironmentObject var viewModel: NostrDBViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Metrics cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCard(
                        title: "Init Time",
                        value: String(format: "%.1fms", viewModel.metrics.cacheInitTime * 1000),
                        icon: "bolt.fill",
                        color: .blue
                    )

                    MetricCard(
                        title: "Avg Save",
                        value: String(format: "%.2fms", viewModel.metrics.averageSaveTime * 1000),
                        icon: "square.and.arrow.down.fill",
                        color: .green
                    )

                    MetricCard(
                        title: "Avg Retrieve",
                        value: String(format: "%.2fms", viewModel.metrics.averageRetrieveTime * 1000),
                        icon: "square.and.arrow.up.fill",
                        color: .orange
                    )

                    MetricCard(
                        title: "Query Time",
                        value: String(format: "%.1fms", viewModel.metrics.queryTime * 1000),
                        icon: "magnifyingglass",
                        color: .purple
                    )

                    MetricCard(
                        title: "Text Search",
                        value: String(format: "%.1fms", viewModel.metrics.textSearchTime * 1000),
                        icon: "doc.text.magnifyingglass",
                        color: .pink
                    )

                    MetricCard(
                        title: "Events Stored",
                        value: "\(viewModel.metrics.totalEventsStored)",
                        icon: "tray.full.fill",
                        color: .indigo
                    )
                }
                .padding(.horizontal)

                Divider()
                    .padding(.vertical, 8)

                // Action buttons
                VStack(spacing: 12) {
                    Text("Performance Tests")
                        .font(.headline)
                        .accessibilityIdentifier("performance_tests_header")

                    HStack(spacing: 12) {
                        ActionButton(title: "Save 100", icon: "plus.circle.fill") {
                            await viewModel.testSavePerformance()
                        }
                        .accessibilityIdentifier("save_100_button")

                        ActionButton(title: "Retrieve", icon: "arrow.down.circle.fill") {
                            await viewModel.testRetrievePerformance()
                        }
                        .accessibilityIdentifier("retrieve_button")
                    }

                    HStack(spacing: 12) {
                        ActionButton(title: "Query", icon: "magnifyingglass.circle.fill") {
                            await viewModel.testQueryPerformance()
                        }
                        .accessibilityIdentifier("query_button")

                        ActionButton(title: "Search", icon: "doc.text.magnifyingglass") {
                            await viewModel.testTextSearch()
                        }
                        .accessibilityIdentifier("search_button")
                    }

                    ActionButton(title: "Fetch from Relays", icon: "antenna.radiowaves.left.and.right") {
                        await viewModel.fetchEvents()
                    }
                    .accessibilityIdentifier("fetch_relays_button")
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
        }
        .accessibilityIdentifier("performance_view")
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityIdentifier("\(title.lowercased().replacingOccurrences(of: " ", with: "_"))_value")

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () async -> Void

    @State private var isRunning = false

    var body: some View {
        Button {
            Task {
                isRunning = true
                await action()
                isRunning = false
            }
        } label: {
            HStack {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(isRunning)
    }
}

// MARK: - Events View

struct EventsView: View {
    @EnvironmentObject var viewModel: NostrDBViewModel

    var body: some View {
        List {
            if viewModel.events.isEmpty {
                Text("No events loaded")
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("no_events_text")
            } else {
                ForEach(viewModel.events, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.content.prefix(100) + (event.content.count > 100 ? "..." : ""))
                            .font(.body)
                            .lineLimit(3)

                        HStack {
                            Text("Kind: \(event.kind)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(formatDate(event.createdAt))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .accessibilityIdentifier("events_list")
    }

    private func formatDate(_ timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Logs View

struct LogsView: View {
    @EnvironmentObject var viewModel: NostrDBViewModel

    var body: some View {
        VStack {
            HStack {
                Text("Debug Logs")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    viewModel.clearLogs()
                }
                .accessibilityIdentifier("clear_logs_button")
            }
            .padding(.horizontal)
            .padding(.top)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(log.contains("ERROR") ? .red : .primary)
                                .id(index)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: viewModel.logs.count) { _, _ in
                    if let last = viewModel.logs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .accessibilityIdentifier("logs_view")
    }
}
