import SwiftUI
import NDKSwift

struct LogViewerView: View {
    @State private var entries: [NDKLogEntry] = []
    @State private var selectedLevel: NDKLogLevel?
    @State private var selectedCategory: NDKLogCategory?
    @State private var searchText = ""
    @State private var isLive = true
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Level filter
                    Menu {
                        Button("All Levels") { selectedLevel = nil }
                        Divider()
                        ForEach([NDKLogLevel.error, .warning, .info, .debug, .trace], id: \.self) { level in
                            Button {
                                selectedLevel = level
                            } label: {
                                Label(level.description, systemImage: iconForLevel(level))
                            }
                        }
                    } label: {
                        FilterChip(
                            label: selectedLevel?.description ?? "Level",
                            isActive: selectedLevel != nil,
                            color: selectedLevel.map { colorForLevel($0) } ?? .secondary
                        )
                    }

                    // Category filter
                    Menu {
                        Button("All Categories") { selectedCategory = nil }
                        Divider()
                        ForEach(NDKLogCategory.allCases, id: \.self) { category in
                            Button(category.rawValue) {
                                selectedCategory = category
                            }
                        }
                    } label: {
                        FilterChip(
                            label: selectedCategory?.rawValue ?? "Category",
                            isActive: selectedCategory != nil,
                            color: .blue
                        )
                    }

                    // Live toggle
                    Button {
                        isLive.toggle()
                    } label: {
                        FilterChip(
                            label: isLive ? "Live" : "Paused",
                            isActive: isLive,
                            color: isLive ? .green : .orange
                        )
                    }

                    Spacer()

                    // Clear button
                    Button {
                        Task {
                            await NDKLogBuffer.shared.clearLogs()
                            await loadEntries()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Log entries
            if isLoading {
                Spacer()
                ProgressView("Loading logs...")
                Spacer()
            } else if filteredEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No log entries")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(filteredEntries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: filteredEntries.count) { _, _ in
                        if isLive, let lastEntry = filteredEntries.last {
                            withAnimation {
                                proxy.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Log Viewer")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        toggleLogLevel()
                    } label: {
                        Label("Log Level: \(NDKLogger.logLevel.description)", systemImage: "slider.horizontal.3")
                    }

                    Divider()

                    Button {
                        copyLogs()
                    } label: {
                        Label("Copy Logs", systemImage: "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        Task {
                            await NDKLogBuffer.shared.clearLogs()
                            await loadEntries()
                        }
                    } label: {
                        Label("Clear Logs", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await loadEntries()
            isLoading = false
        }
        .task(id: isLive) {
            guard isLive else { return }
            // Poll for updates when live mode is enabled
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await loadEntries()
            }
        }
        .refreshable {
            await loadEntries()
        }
    }

    private var filteredEntries: [NDKLogEntry] {
        var result = entries

        if let level = selectedLevel {
            result = result.filter { $0.level == level }
        }

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            result = result.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    private func loadEntries() async {
        entries = await NDKLogBuffer.shared.getEntries()
    }

    private func toggleLogLevel() {
        switch NDKLogger.logLevel {
        case .info:
            NDKLogger.logLevel = .debug
        case .debug:
            NDKLogger.logLevel = .trace
        case .trace:
            NDKLogger.logLevel = .info
        default:
            NDKLogger.logLevel = .info
        }
    }

    private func copyLogs() {
        let logText = filteredEntries.map { entry in
            "[\(formatTimestamp(entry.timestamp))] [\(entry.level)] [\(entry.category.rawValue)] \(entry.message)"
        }.joined(separator: "\n")

        UIPasteboard.general.string = logText
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func colorForLevel(_ level: NDKLogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .gray
        case .trace: return .secondary
        case .off: return .secondary
        }
    }

    private func iconForLevel(_ level: NDKLogLevel) -> String {
        switch level {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .debug: return "ladybug.fill"
        case .trace: return "ant.fill"
        case .off: return "nosign"
        }
    }
}

// MARK: - Supporting Views

private struct FilterChip: View {
    let label: String
    let isActive: Bool
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(isActive ? .semibold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? color.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
            .foregroundStyle(isActive ? color : .primary)
            .cornerRadius(16)
    }
}

private struct LogEntryRow: View {
    let entry: NDKLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Level indicator
                Circle()
                    .fill(colorForLevel(entry.level))
                    .frame(width: 8, height: 8)

                // Timestamp
                Text(formatTimestamp(entry.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Category
                Text(entry.category.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(4)

                Spacer()
            }

            // Message
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(colorForLevel(entry.level))
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func colorForLevel(_ level: NDKLogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .primary
        case .debug: return .secondary
        case .trace: return .secondary
        case .off: return .secondary
        }
    }
}
