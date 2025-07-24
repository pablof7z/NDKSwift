import SwiftUI
import NDKSwift

struct FollowPackDetailView: View {
    let followPack: FollowPack
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var profiles: [String: NDKUserProfile] = [:]
    @State private var showSuccess = false
    @State private var creator: NDKUserProfile?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    creatorSection
                    importSection
                    profilesSection
                }
                .padding(.vertical)
            }
            .background(Color.highlighterBackground)
            .navigationTitle("Follow Pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.highlighterPurple)
                }
            }
        }
        .task {
            await loadProfiles()
        }
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.highlighterPurple)
                
                Spacer()
                
                // Stats
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(followPack.profiles.count)")
                        .font(.highlighterTitle)
                        .foregroundColor(.highlighterPurple)
                    Text("Profiles")
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(followPack.title)
                    .font(.highlighterHeadline)
                
                if let description = followPack.description {
                    Text(description)
                        .font(.highlighterBody)
                        .foregroundColor(.highlighterSecondaryText)
                }
            }
        }
    }
    
    @ViewBuilder
    private var creatorSection: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.highlighterPurple)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Created by")
                    .font(.highlighterCaption)
                    .foregroundColor(.highlighterSecondaryText)
                
                Text(creator?.name ?? creator?.displayName ?? String(followPack.author.prefix(8)))
                    .font(.highlighterCaption)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [
                    Color.highlighterPurple.opacity(0.1),
                    Color.highlighterOrange.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var importSection: some View {
        Button(action: importFollowPack) {
            HStack {
                Image(systemName: showSuccess ? "checkmark.circle.fill" : "plus.circle.fill")
                Text(showSuccess ? "Imported!" : "Import Follow Pack")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                Group {
                    if showSuccess {
                        Color.green
                    } else {
                        LinearGradient(
                            colors: [.highlighterPurple, .highlighterPurple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(showSuccess)
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profiles in this pack")
                .font(.highlighterHeadline)
                .padding(.horizontal)
            
            ForEach(followPack.profiles, id: \.self) { pubkey in
                ProfileRow(pubkey: pubkey, profile: profiles[pubkey])
                    .padding(.horizontal)
            }
        }
    }
    
    private func loadProfiles() async {
        guard let ndk = appState.ndk else { return }
        
        // Load creator profile
        for await profile in await ndk.profileManager.observe(for: followPack.author, maxAge: 3600) {
            await MainActor.run {
                self.creator = profile
            }
            break
        }
        
        // Load profiles in the pack
        for pubkey in followPack.profiles {
            Task {
                for await profile in await ndk.profileManager.observe(for: pubkey, maxAge: 3600) {
                    await MainActor.run {
                        self.profiles[pubkey] = profile
                    }
                    break
                }
            }
        }
    }
    
    private func importFollowPack() {
        HapticType.medium.trigger()
        
        Task {
            // TODO: Implement actual follow list update
            // This would create/update the user's contact list event (kind 3)
            // For now, just show success immediately
            
            await MainActor.run {
                showSuccess = true
                HapticType.success.trigger()
                
                // Reset after delay
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        showSuccess = false
                    }
                }
            }
        }
    }
}

struct ProfileRow: View {
    let pubkey: String
    let profile: NDKUserProfile?
    @State private var isFollowing = false
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.highlighterPurple)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.name ?? profile?.displayName ?? String(pubkey.prefix(16)))
                    .font(.highlighterBody)
                    .fontWeight(.medium)
                
                if let about = profile?.about {
                    Text(about)
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: { isFollowing.toggle() }) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.highlighterCaption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(isFollowing ? Color.gray : Color.highlighterPurple)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
        }
        .padding()
        .background(Color.highlighterCardBackground)
        .cornerRadius(12)
    }
}

#Preview {
    FollowPackDetailView(
        followPack: FollowPack(
            id: "1",
            event: NDKEvent(id: "", pubkey: "", createdAt: 0, kind: 39089, tags: [], content: "", sig: ""),
            name: "bitcoin-devs",
            title: "Bitcoin Developers",
            description: "Core Bitcoin developers and contributors",
            image: nil,
            author: "test",
            createdAt: Date(),
            profiles: ["pubkey1", "pubkey2", "pubkey3"]
        )
    )
    .environmentObject(AppState())
}
