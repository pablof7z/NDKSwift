import SwiftUI
import NDKSwiftCore

struct ProfileCacheView: View {
    @Environment(ChirpState.self) private var state
    @State private var cacheSize: Int = 0
    @State private var hitRate: Double = 0.0

    var body: some View {
        List {
            Section("Profile Manager Cache") {
                LabeledContent("Cached Profiles", value: "\(cacheSize)")
                LabeledContent("Hit Rate") {
                    Text(String(format: "%.1f%%", hitRate * 100))
                        .foregroundStyle(hitRateColor)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About Profile Cache")
                        .font(.headline)
                    Text("The profile manager caches user profiles (kind 0 events) in memory for fast access. A higher hit rate means fewer network requests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Profile Cache")
        .task {
            await loadStats()
        }
        .refreshable {
            await loadStats()
        }
    }

    private var hitRateColor: Color {
        if hitRate >= 0.8 {
            return .green
        } else if hitRate >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }

    private func loadStats() async {
        let stats = await state.ndk.profileManager.getCacheStats()
        cacheSize = stats.size
        hitRate = stats.hitRate
    }
}

#Preview {
    NavigationStack {
        ProfileCacheView()
    }
}
