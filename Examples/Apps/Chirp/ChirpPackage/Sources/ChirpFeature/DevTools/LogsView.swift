import SwiftUI
import NDKSwiftCore

struct LogsView: View {
    @State private var selectedLogLevel: NDKLogLevel = NDKLogger.logLevel
    @State private var enabledCategories: Set<NDKLogCategory> = NDKLogger.enabledCategories
    @State private var logNetworkTraffic: Bool = NDKLogger.logNetworkTraffic

    private var logService: LogCaptureService { LogCaptureService.shared }

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
                Toggle("Capture Logs", isOn: Binding(
                    get: { logService.isCapturing },
                    set: { enabled in
                        if enabled {
                            logService.startCapturing()
                        } else {
                            logService.stopCapturing()
                        }
                    }
                ))

                if logService.isCapturing {
                    Button("Clear Logs") {
                        logService.clearMessages()
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Text("Log Capture")
            } footer: {
                Text("Logs are captured globally even when you navigate away from this view.")
            }

            if !logService.messages.isEmpty {
                Section("Captured Logs (\(logService.messages.count))") {
                    ForEach(Array(logService.messages.enumerated().reversed()), id: \.offset) { _, message in
                        Text(message)
                            .font(.caption)
                            .monospaced()
                    }
                }
            }
        }
        .navigationTitle("Logs")
    }
}

#Preview {
    NavigationStack {
        LogsView()
    }
}
