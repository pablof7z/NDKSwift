import SwiftUI

struct PrivacySettingsView: View {
    @AppStorage("hideReactionCount") private var hideReactionCount = false
    @AppStorage("hideFollowerCount") private var hideFollowerCount = false

    var body: some View {
        List {
            Section("Display") {
                Toggle("Hide Reaction Counts", isOn: $hideReactionCount)
                Toggle("Hide Follower Counts", isOn: $hideFollowerCount)
            }

            Section {
                NavigationLink {
                    ComingSoonView(feature: "Blocked Users")
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.xmark")
                        Text("Blocked Users")
                    }
                }

                NavigationLink {
                    ComingSoonView(feature: "Muted Words")
                } label: {
                    HStack {
                        Image(systemName: "speaker.slash")
                        Text("Muted Words")
                    }
                }
            } header: {
                Text("Content Filtering")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ComingSoonView: View {
    let feature: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 60))
                .foregroundStyle(OlasTheme.Colors.deepTeal)

            Text("\(feature)")
                .font(.title2.bold())

            Text("This feature is coming soon.")
                .foregroundStyle(.secondary)
        }
        .navigationTitle(feature)
        .navigationBarTitleDisplayMode(.inline)
    }
}
