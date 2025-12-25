import SwiftUI
import NDKSwiftCore

struct LogsView: View {
    @State private var selectedLogLevel: NDKLogLevel = NDKLogger.logLevel
    @State private var enabledCategories: Set<NDKLogCategory> = NDKLogger.enabledCategories
    @State private var logNetworkTraffic: Bool = NDKLogger.logNetworkTraffic
    @State private var logMessages: [String] = []
    @State private var isCapturingLogs: Bool = false

    let allCategories = NDKLogCategory.allCases
    let logLevels: [NDKLogLevel] = [.off, .error, .warning, .info, .debug, .trace]

    var body: some View {
        List {
            Section("Log Level") {
                Picker("Level", selection: $selectedLogLevel) {
                    ForEach(logLevels, id: \.self) { level in
                        Text(level.description)
                            .tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedLogLevel) { _, newValue in
                    NDKLogger.setLogLevel(newValue)
                }
            }

            Section {
                Toggle("Network Traffic", isOn: $logNetworkTraffic)
                    .onChange(of: logNetworkTraffic) { _, newValue in
                        NDKLogger.setLogNetworkTraffic(newValue)
                    }
            } header: {
                Text("Options")
            }

            Section {
                ForEach(allCategories, id: \.self) { category in
                    Toggle(category.rawValue, isOn: Binding(
                        get: { enabledCategories.contains(category) },
                        set: { enabled in
                            if enabled {
                                enabledCategories.insert(category)
                            } else {
                                enabledCategories.remove(category)
                            }
                            NDKLogger.setEnabledCategories(enabledCategories)
                        }
                    ))
                }
            } header: {
                Text("Categories")
            }

            Section {
                Toggle("Capture Logs", isOn: $isCapturingLogs)
                    .onChange(of: isCapturingLogs) { _, newValue in
                        if newValue {
                            startCapturingLogs()
                        } else {
                            stopCapturingLogs()
                        }
                    }

                if isCapturingLogs {
                    Button("Clear Logs") {
                        logMessages.removeAll()
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Text("Live Logs")
            } footer: {
                Text("Enable log capture to see live logs in this view. Note: This only captures logs while this view is visible.")
            }

            if !logMessages.isEmpty {
                Section("Captured Logs (\(logMessages.count))") {
                    ForEach(Array(logMessages.enumerated().reversed()), id: \.offset) { _, message in
                        Text(message)
                            .font(.caption)
                            .monospaced()
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .onDisappear {
            stopCapturingLogs()
        }
    }

    private func startCapturingLogs() {
        logMessages.removeAll()
        NDKLogger.setLogHandler { message in
            Task { @MainActor in
                logMessages.append(message)
                // Keep only last 100 messages to prevent memory issues
                if logMessages.count > 100 {
                    logMessages.removeFirst()
                }
            }
        }
    }

    private func stopCapturingLogs() {
        NDKLogger.setLogHandler(nil)
    }
}

#Preview {
    NavigationStack {
        LogsView()
    }
}
