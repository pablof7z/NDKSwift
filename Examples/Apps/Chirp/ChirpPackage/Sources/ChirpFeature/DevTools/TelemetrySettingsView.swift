import SwiftUI
import NDKSwiftCore

/// Stores telemetry configuration in UserDefaults.
/// Changes require app restart to take effect since NDK's telemetry config is set at init.
public enum TelemetrySettings {
    private static let enabledKey = "telemetry.enabled"
    private static let endpointKey = "telemetry.endpoint"
    private static let sampleRateKey = "telemetry.sampleRate"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    public static var endpoint: String? {
        get { UserDefaults.standard.string(forKey: endpointKey) }
        set { UserDefaults.standard.set(newValue, forKey: endpointKey) }
    }

    public static var sampleRate: Double {
        get {
            let rate = UserDefaults.standard.double(forKey: sampleRateKey)
            return rate > 0 ? rate : 1.0
        }
        set { UserDefaults.standard.set(newValue, forKey: sampleRateKey) }
    }

    /// Creates an NDKTelemetryConfig from stored settings
    public static func makeConfig(serviceName: String = "chirp") -> NDKTelemetryConfig {
        guard isEnabled else { return .disabled }

        let endpointURL = endpoint.flatMap { URL(string: $0) }

        return NDKTelemetryConfig(
            enabled: true,
            endpoint: endpointURL,
            serviceName: serviceName,
            sampleRate: sampleRate,
            enabledCategories: Set(TelemetryCategory.allCases)
        )
    }
}

struct TelemetrySettingsView: View {
    @State private var isEnabled: Bool = TelemetrySettings.isEnabled
    @State private var endpoint: String = TelemetrySettings.endpoint ?? ""
    @State private var sampleRate: Double = TelemetrySettings.sampleRate

    @Environment(ChirpState.self) private var state

    private var currentlyActive: Bool {
        state.ndk.telemetryConfig.enabled
    }

    private var currentEndpoint: String? {
        state.ndk.telemetryConfig.endpoint?.absoluteString
    }

    var body: some View {
        List {
            Section {
                Toggle("Enable Telemetry", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        TelemetrySettings.isEnabled = newValue
                    }
            } header: {
                Text("Telemetry")
            } footer: {
                Text("Export OpenTelemetry traces to an OTLP endpoint (e.g., Jaeger, Grafana Tempo).")
            }

            if isEnabled {
                Section {
                    TextField("OTLP Endpoint", text: $endpoint, prompt: Text("http://localhost:4318/v1/traces"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: endpoint) { _, newValue in
                            TelemetrySettings.endpoint = newValue.isEmpty ? nil : newValue
                        }
                } header: {
                    Text("Endpoint")
                } footer: {
                    Text("Leave empty for console output (debug mode).")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sample Rate: \(Int(sampleRate * 100))%")
                        Slider(value: $sampleRate, in: 0.01...1.0, step: 0.01)
                            .onChange(of: sampleRate) { _, newValue in
                                TelemetrySettings.sampleRate = newValue
                            }
                    }
                } header: {
                    Text("Sampling")
                } footer: {
                    Text("100% captures all spans. Lower values reduce overhead.")
                }
            }

            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    if currentlyActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Inactive", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if currentlyActive, let endpoint = currentEndpoint {
                    LabeledContent("Current Endpoint") {
                        Text(endpoint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if currentlyActive && !isEnabled {
                    Text("Telemetry will be disabled on next app launch.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !currentlyActive && isEnabled {
                    Text("Telemetry will be enabled on next app launch.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Current Session")
            }
        }
        .navigationTitle("Telemetry")
    }
}

#Preview {
    NavigationStack {
        TelemetrySettingsView()
    }
}
