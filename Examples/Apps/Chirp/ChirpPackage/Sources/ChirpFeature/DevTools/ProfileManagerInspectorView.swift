import SwiftUI
@preconcurrency import NDKSwiftCore
import NDKSwiftUI

struct ProfileManagerInspectorView: View {
    @Environment(ChirpState.self) private var state

    @State private var cacheStats: (size: Int, hitRate: Double)?
    @State private var profileCacheCount: Int = 0
    @State private var searchPubkey: String = ""
    @State private var showSearchedProfile = false
    @State private var selectedProfilePubkey: String?
    @State private var showingDetail = false
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            // Cache Stats Section - show immediately, values update as loaded
            Section("Cache Statistics") {
                LabeledContent("Profile Manager Cache") {
                    Text("\(cacheStats?.size ?? 0)")
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Profile Cache Count") {
                    Text("\(profileCacheCount)")
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Max Cache Size") {
                    Text("500")
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Memory Usage") {
                    Text(String(format: "%.1f%%", Double(profileCacheCount) / 500.0 * 100))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(profileCacheCount > 400 ? .orange : .green)
                }
            }

            // Profile Lookup Section
            Section("Profile Lookup") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter a public key (hex) to look up a profile:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Public key (hex)", text: $searchPubkey)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        showSearchedProfile = true
                    } label: {
                        Label("Look Up Profile", systemImage: "magnifyingglass")
                    }
                    .disabled(searchPubkey.isEmpty)

                    // Use ndk.profile(for:) directly - no @State storage needed
                    if showSearchedProfile && !searchPubkey.isEmpty {
                        let profile = state.ndk.profile(for: searchPubkey)

                        Divider()
                            .padding(.vertical, 4)

                        ProfileCacheRow(ndk: state.ndk, pubkey: searchPubkey, profile: profile)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedProfilePubkey = searchPubkey
                                showingDetail = true
                            }
                    }
                }
                .padding(.vertical, 4)
            }

            // Info Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Profile Cache Info", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("The profile cache stores observable NDKProfile instances in an LRU cache. Individual profiles cannot be listed directly, but you can look up specific profiles by public key.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            // Actions Section
            Section("Actions") {
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear All Caches", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Profile Manager")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .sheet(isPresented: $showingDetail) {
            if let pubkey = selectedProfilePubkey {
                NavigationStack {
                    // Use ndk.profile(for:) directly in the detail view
                    ProfileDetailView(ndk: state.ndk, pubkey: pubkey)
                }
            }
        }
        .alert("Clear Profile Caches", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await clearCache()
                }
            }
        } message: {
            Text("This will remove all cached profiles from memory. Profiles will be re-fetched from the database or relays as needed.")
        }
    }

    private func loadData() async {
        let ndk = state.ndk
        cacheStats = await ndk.profileManager.getCacheStats()
        profileCacheCount = cacheStats?.size ?? 0
    }

    private func clearCache() async {
        let ndk = state.ndk
        await ndk.profileManager.clearCache()
        showSearchedProfile = false
        await loadData()
    }
}

// MARK: - Profile Cache Row

private struct ProfileCacheRow: View {
    let ndk: NDK
    let pubkey: String
    let profile: NDKProfile

    var body: some View {
        HStack(spacing: 12) {
            // Profile picture using NDKSwiftUI
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 50)

            VStack(alignment: .leading, spacing: 6) {
                // Display name using NDKSwiftUI
                HStack {
                    NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                        .font(.body)
                        .lineLimit(1)

                    Spacer()

                    // Has metadata indicator
                    if profile.metadata != nil {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                }

                // Pubkey
                Text(formatPubkey(pubkey))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Metadata preview
                if !profile.about.isEmpty {
                    Text(profile.about)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatPubkey(_ key: String) -> String {
        String(key.prefix(8)) + "..." + String(key.suffix(8))
    }
}

// MARK: - Profile Detail View

private struct ProfileDetailView: View {
    let ndk: NDK
    let pubkey: String

    @Environment(\.dismiss) private var dismiss

    // Use ndk.profile(for:) directly - auto-updates
    private var profile: NDKProfile {
        ndk.profile(for: pubkey)
    }

    var body: some View {
        List {
            // Profile Header with NDKSwiftUI components
            Section {
                HStack(spacing: 16) {
                    // Profile picture
                    NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 80)

                    VStack(alignment: .leading, spacing: 8) {
                        // Display name
                        NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                            .font(.title2)
                            .fontWeight(.semibold)

                        // NIP-05 badge if available
                        if let nip05 = profile.nip05 {
                            Text(nip05)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // Identity Section
            Section("Identity") {
                LabeledContent("Public Key") {
                    HStack {
                        Text(formatPubkey(pubkey))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = pubkey
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                    }
                }
            }

            // Profile Details Section
            if hasProfileDetails {
                Section("Profile") {
                    if !profile.about.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("About")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(profile.about)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }

                    if let nip05 = profile.nip05 {
                        LabeledContent("NIP-05") {
                            Text(nip05)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }

            // Media Section
            if hasMedia {
                Section("Media") {
                    if let pictureURL = profile.pictureURL {
                        LabeledContent("Picture URL") {
                            Link("View", destination: pictureURL)
                                .font(.caption)
                        }
                    }

                    if let bannerURL = profile.bannerURL {
                        LabeledContent("Banner URL") {
                            Link("View", destination: bannerURL)
                                .font(.caption)
                        }
                    }
                }
            }

            // Lightning Section
            if hasLightning {
                Section("Lightning") {
                    if let lud16 = profile.lud16 {
                        LabeledContent("LUD-16") {
                            Text(lud16)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }

            // Actions Section
            Section {
                Button {
                    UIPasteboard.general.string = pubkey
                } label: {
                    Label("Copy Public Key", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    Task {
                        await clearFromCache()
                    }
                } label: {
                    Label("Remove from Cache", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Profile Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var hasProfileDetails: Bool {
        !profile.about.isEmpty || profile.nip05 != nil
    }

    private var hasMedia: Bool {
        profile.pictureURL != nil || profile.bannerURL != nil
    }

    private var hasLightning: Bool {
        profile.lud16 != nil
    }

    private func formatPubkey(_ key: String) -> String {
        String(key.prefix(16)) + "..." + String(key.suffix(16))
    }

    private func clearFromCache() async {
        await ndk.profileManager.clearCache()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ProfileManagerInspectorView()
    }
}
