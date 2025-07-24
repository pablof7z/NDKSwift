import SwiftUI
import NDKSwift
import NDKSwiftUI

struct UserProfileView: View {
    let pubkey: String
    @EnvironmentObject var nostrManager: NostrManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var profile: NDKUserProfile?
    @State private var isFollowing = false
    @State private var followersCount = 0
    @State private var followingCount = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with profile picture and stats
                VStack(spacing: 16) {
                    NDKProfilePicture(pubkey: pubkey, size: 120)
                    
                    VStack(spacing: 8) {
                        Text(profile?.displayName ?? profile?.name ?? String(pubkey.prefix(16)))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        if let nip05 = profile?.nip05 {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.purple)
                                Text(nip05)
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.white.opacity(0.7))
                            }
                        }
                    }
                    
                    // Stats
                    HStack(spacing: 40) {
                        VStack {
                            Text("\(followersCount)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Followers")
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.6))
                        }
                        
                        VStack {
                            Text("\(followingCount)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Following")
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.6))
                        }
                    }
                    .padding(.top, 8)
                    
                    // Follow button
                    if pubkey != appState.currentUser?.pubkey {
                        Button(action: toggleFollow) {
                            Text(isFollowing ? "Following" : "Follow")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isFollowing ? .white : .black)
                                .frame(maxWidth: 200)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(isFollowing ? Color.white.opacity(0.2) : Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white, lineWidth: isFollowing ? 1 : 0)
                                )
                        }
                    }
                }
                .padding(.top, 20)
                
                // About section
                if let about = profile?.about, !about.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(about)
                            .font(.system(size: 14))
                            .foregroundColor(Color.white.opacity(0.8))
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 40)
            }
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .onAppear {
            loadProfile()
            checkFollowStatus()
        }
    }
    
    private func loadProfile() {
        Task {
            guard let ndk = nostrManager.ndk else { return }
            
            for await profile in ndk.profileManager.observe(for: pubkey, maxAge: 300) {
                await MainActor.run {
                    self.profile = profile
                }
                break // Just get the first result for now
            }
        }
    }
    
    private func checkFollowStatus() {
        guard let currentUser = appState.currentUser,
              let followList = appState.followLists[currentUser.pubkey] else { return }
        
        isFollowing = followList.contains(pubkey)
    }
    
    private func toggleFollow() {
        // TODO: Implement follow/unfollow functionality
        isFollowing.toggle()
    }
}