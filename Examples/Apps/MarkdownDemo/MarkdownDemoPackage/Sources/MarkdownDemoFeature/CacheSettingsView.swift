import SwiftUI
import NDKSwiftCore

struct CacheSettingsView: View {
    @AppStorage("selectedCacheType") private var selectedCacheTypeRaw: String = CacheType.sqlite.rawValue
    @State private var showRestartAlert = false
    @State private var pendingCacheType: CacheType?

    let currentCache: NDKCache

    private var selectedCacheType: CacheType {
        CacheType(rawValue: selectedCacheTypeRaw) ?? .sqlite
    }

    var body: some View {
        List {
            Section {
                Picker("Cache Type", selection: $selectedCacheTypeRaw) {
                    ForEach(CacheType.availableCases) { cacheType in
                        VStack(alignment: .leading) {
                            Text(cacheType.displayName)
                            Text(cacheType.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(cacheType.rawValue)
                    }
                }
                .onChange(of: selectedCacheTypeRaw) { oldValue, newValue in
                    if oldValue != newValue {
                        pendingCacheType = CacheType(rawValue: newValue)
                        showRestartAlert = true
                    }
                }
            } header: {
                Text("Cache Backend")
            } footer: {
                Text("Changing the cache type requires restarting the app to take effect.")
            }

            Section("Statistics") {
                NavigationLink {
                    CacheStatisticsView(cache: currentCache, cacheType: selectedCacheType)
                        .navigationTitle("Cache Statistics")
                } label: {
                    Label("View Statistics", systemImage: "chart.bar")
                }
            }
        }
        .navigationTitle("Cache Settings")
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("OK") {
                showRestartAlert = false
            }
        } message: {
            Text("Please restart the app for the cache change to take effect. The new cache type will be: \(pendingCacheType?.displayName ?? "Unknown")")
        }
    }
}
