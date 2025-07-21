import SwiftUI

struct AdvancedSettingsView: View {
    @AppStorage("auto_translate") private var autoTranslate = false
    @AppStorage("show_dev_options") private var showDevOptions = false
    @AppStorage("cache_size_mb") private var cacheSizeMB = 100
    @AppStorage("connection_timeout") private var connectionTimeout = 30
    @AppStorage("max_events_per_sub") private var maxEventsPerSub = 500
    
    @State private var showingCacheClear = false
    @State private var showingExportKeys = false
    
    var body: some View {
        List {
            // Performance
            Section {
                HStack {
                    Text("Cache Size")
                    Spacer()
                    Text("\(cacheSizeMB) MB")
                        .foregroundColor(.secondary)
                }
                
                Slider(value: Binding(
                    get: { Double(cacheSizeMB) },
                    set: { cacheSizeMB = Int($0) }
                ), in: 50...500, step: 50)
                
                Button(action: { showingCacheClear = true }) {
                    HStack {
                        Text("Clear Cache")
                        Spacer()
                        Text("~45 MB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Performance")
            }
            
            // Network
            Section {
                HStack {
                    Text("Connection Timeout")
                    Spacer()
                    Text("\(connectionTimeout)s")
                        .foregroundColor(.secondary)
                }
                
                Slider(value: Binding(
                    get: { Double(connectionTimeout) },
                    set: { connectionTimeout = Int($0) }
                ), in: 10...60, step: 5)
                
                HStack {
                    Text("Max Events per Subscription")
                    Spacer()
                    Text("\(maxEventsPerSub)")
                        .foregroundColor(.secondary)
                }
                
                Slider(value: Binding(
                    get: { Double(maxEventsPerSub) },
                    set: { maxEventsPerSub = Int($0) }
                ), in: 100...1000, step: 100)
            } header: {
                Text("Network")
            }
            
            // Features
            Section {
                Toggle(isOn: $autoTranslate) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-Translate")
                        Text("Automatically translate posts in foreign languages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Features")
            }
            
            // Developer Options
            Section {
                Toggle(isOn: $showDevOptions) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Developer Mode")
                        Text("Show advanced debugging options")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if showDevOptions {
                    NavigationLink(destination: DeveloperOptionsView()) {
                        Label("Developer Options", systemImage: "hammer")
                    }
                }
            } header: {
                Text("Developer")
            }
            
            // Data Management
            Section {
                Button(action: { showingExportKeys = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Keys")
                    }
                }
                
                NavigationLink(destination: DataExportView()) {
                    HStack {
                        Image(systemName: "archivebox")
                        Text("Export All Data")
                    }
                }
            } header: {
                Text("Data Management")
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            "Clear Cache",
            isPresented: $showingCacheClear,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                clearCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all cached data. The app will need to re-download content.")
        }
        .alert("Export Keys", isPresented: $showingExportKeys) {
            Button("Copy to Clipboard") {
                exportKeys()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your private keys will be copied to the clipboard. Make sure to store them securely.")
        }
    }
    
    private func clearCache() {
        // Implementation for clearing cache
    }
    
    private func exportKeys() {
        // Implementation for exporting keys
    }
}

struct DeveloperOptionsView: View {
    @AppStorage("debug_logging") private var debugLogging = false
    @AppStorage("show_event_ids") private var showEventIds = false
    @AppStorage("show_raw_events") private var showRawEvents = false
    
    var body: some View {
        List {
            Section {
                Toggle("Debug Logging", isOn: $debugLogging)
                Toggle("Show Event IDs", isOn: $showEventIds)
                Toggle("Show Raw Events", isOn: $showRawEvents)
            }
            
            Section {
                NavigationLink(destination: EventLogView()) {
                    Label("Event Log", systemImage: "doc.text")
                }
                
                NavigationLink(destination: RelayLogView()) {
                    Label("Relay Log", systemImage: "network")
                }
            }
        }
        .navigationTitle("Developer Options")
    }
}

struct DataExportView: View {
    var body: some View {
        List {
            Text("Export functionality coming soon")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
        }
        .navigationTitle("Export Data")
    }
}

struct EventLogView: View {
    var body: some View {
        List {
            Text("Event log coming soon")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
        }
        .navigationTitle("Event Log")
    }
}

struct RelayLogView: View {
    var body: some View {
        List {
            Text("Relay log coming soon")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
        }
        .navigationTitle("Relay Log")
    }
}