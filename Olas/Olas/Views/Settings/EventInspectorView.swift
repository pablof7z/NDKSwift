import SwiftUI
import NDKSwift

struct EventInspectorView: View {
    let ndk: NDK

    @State private var searchText = ""
    @State private var searchType: SearchType = .content
    @State private var selectedKind: Kind?
    @State private var events: [NDKEvent] = []
    @State private var isLoading = false
    @State private var selectedEvent: NDKEvent?

    enum SearchType: String, CaseIterable {
        case content = "Content"
        case eventId = "Event ID"
        case pubkey = "Pubkey"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search controls
            VStack(spacing: 8) {
                // Search type picker
                Picker("Search Type", selection: $searchType) {
                    ForEach(SearchType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(placeholderText, text: $searchText)
                        .textFieldStyle(.plain)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            events = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .padding(.horizontal)

                // Kind filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        KindFilterChip(label: "All", isSelected: selectedKind == nil) {
                            selectedKind = nil
                        }

                        ForEach(commonKinds, id: \.self) { kind in
                            KindFilterChip(
                                label: kindName(kind),
                                isSelected: selectedKind == kind
                            ) {
                                selectedKind = kind
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 12)
            .background(Color(.systemGroupedBackground))

            Divider()

            // Results
            if isLoading {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if events.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "Enter a search term" : "No events found")
                        .foregroundStyle(.secondary)
                    if searchType == .content && searchText.isEmpty {
                        Text("Search by content, event ID, or pubkey")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredEvents, id: \.id) { event in
                        EventRow(event: event)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEvent = event
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Event Inspector")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: searchText) { _, newValue in
            guard !newValue.isEmpty else {
                events = []
                return
            }
            Task {
                await performSearch()
            }
        }
        .onChange(of: searchType) { _, _ in
            if !searchText.isEmpty {
                Task {
                    await performSearch()
                }
            }
        }
        .sheet(item: $selectedEvent) { event in
            NavigationStack {
                EventDetailView(event: event, ndk: ndk)
            }
        }
    }

    private var placeholderText: String {
        switch searchType {
        case .content:
            return "Search event content..."
        case .eventId:
            return "Enter event ID (hex or note1...)"
        case .pubkey:
            return "Enter pubkey (hex or npub1...)"
        }
    }

    private var commonKinds: [Kind] {
        [0, 1, 3, 4, 5, 6, 7, 9735, 10002, 30023]
    }

    private var filteredEvents: [NDKEvent] {
        guard let kind = selectedKind else { return events }
        return events.filter { $0.kind == kind }
    }

    private func performSearch() async {
        isLoading = true
        defer { isLoading = false }

        guard let cache = ndk.cache as? NDKNostrDBCache else { return }

        switch searchType {
        case .content:
            events = await cache.textSearch(searchText, limit: 100)

        case .eventId:
            let eventId = normalizeEventId(searchText)
            if let event = await cache.getEvent(id: eventId) {
                events = [event]
            } else {
                events = []
            }

        case .pubkey:
            let pubkey = normalizePubkey(searchText)
            let filter = NDKFilter(authors: [pubkey], limit: 100)
            events = (try? await cache.queryEvents(filter)) ?? []
        }
    }

    private func normalizeEventId(_ input: String) -> String {
        // Handle note1... bech32 format
        if input.lowercased().hasPrefix("note1") {
            // Decode bech32 to hex
            if let decoded = try? Bech32.decode(input) {
                return decoded.data.map { String(format: "%02x", $0) }.joined()
            }
        }
        return input
    }

    private func normalizePubkey(_ input: String) -> String {
        // Handle npub1... bech32 format
        if input.lowercased().hasPrefix("npub1") {
            if let decoded = try? Bech32.decode(input) {
                return decoded.data.map { String(format: "%02x", $0) }.joined()
            }
        }
        return input
    }

    private func kindName(_ kind: Kind) -> String {
        switch kind {
        case 0: return "Profile"
        case 1: return "Note"
        case 3: return "Contacts"
        case 4: return "DM"
        case 5: return "Delete"
        case 6: return "Repost"
        case 7: return "Reaction"
        case 9735: return "Zap"
        case 10002: return "Relay List"
        case 30023: return "Long-form"
        default: return "Kind \(kind)"
        }
    }
}

// MARK: - Supporting Views

private struct KindFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .blue : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

private struct EventRow: View {
    let event: NDKEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Kind badge
                Text("Kind \(event.kind)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(kindColor.opacity(0.2))
                    .foregroundStyle(kindColor)
                    .cornerRadius(4)

                Spacer()

                // Timestamp
                Text(formatDate(event.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Content preview
            Text(event.content.isEmpty ? "(empty content)" : event.content)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .foregroundStyle(event.content.isEmpty ? .tertiary : .primary)

            // Event ID
            Text(event.id.prefix(16) + "...")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var kindColor: Color {
        switch event.kind {
        case 0: return .purple
        case 1: return .blue
        case 3: return .green
        case 4: return .orange
        case 7: return .pink
        case 9735: return .yellow
        default: return .gray
        }
    }

    private func formatDate(_ timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct EventDetailView: View {
    let event: NDKEvent
    let ndk: NDK

    @Environment(\.dismiss) private var dismiss
    @State private var showingRawJSON = false

    var body: some View {
        List {
            Section("Event Info") {
                LabeledContent("ID") {
                    Text(event.id)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("Kind") {
                    Text("\(event.kind)")
                        .font(.system(.body, design: .monospaced))
                }

                LabeledContent("Created At") {
                    Text(formatFullDate(event.createdAt))
                        .font(.caption)
                }

                LabeledContent("Pubkey") {
                    Text(event.pubkey)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section("Content") {
                Text(event.content.isEmpty ? "(empty)" : event.content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            if !event.tags.isEmpty {
                Section("Tags (\(event.tags.count))") {
                    ForEach(Array(event.tags.enumerated()), id: \.offset) { _, tag in
                        HStack(alignment: .top) {
                            Text(tag.first ?? "?")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                                .frame(width: 24, alignment: .leading)

                            Text(tag.dropFirst().joined(separator: " "))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Section("Signature") {
                Text(event.sig.isEmpty ? "(no signature)" : event.sig)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section {
                Button {
                    showingRawJSON = true
                } label: {
                    Label("View Raw JSON", systemImage: "doc.text")
                }

                Button {
                    copyEventJSON()
                } label: {
                    Label("Copy JSON", systemImage: "doc.on.doc")
                }
            }
        }
        .navigationTitle("Event Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingRawJSON) {
            NavigationStack {
                RawJSONView(event: event)
            }
        }
    }

    private func formatFullDate(_ timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func copyEventJSON() {
        if let json = try? event.toJSON() {
            UIPasteboard.general.string = json
        }
    }
}

private struct RawJSONView: View {
    let event: NDKEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            Text(prettyJSON)
                .font(.system(.caption, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .navigationTitle("Raw JSON")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = prettyJSON
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }

    private var prettyJSON: String {
        guard let json = try? event.toJSON(),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            return (try? event.toJSON()) ?? "{}"
        }
        return pretty
    }
}
