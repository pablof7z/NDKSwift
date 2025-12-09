import SwiftUI
import NDKSwift
import NDKSwiftUI

public struct ProfileView: View {
    let ndk: NDK
    let pubkey: String
    let currentUserPubkey: String?
    var sparkWalletManager: SparkWalletManager?

    @EnvironmentObject private var muteListManager: MuteListManager
    @State private var profile: NDKUserMetadata?
    @State private var posts: [NDKEvent] = []
    @State private var followingCount = 0
    @State private var showEditProfile = false
    @State private var selectedTab: ProfileTab = .posts
    @State private var selectedPost: NDKEvent?

    private var isOwnProfile: Bool {
        guard let currentUserPubkey else { return false }
        return pubkey == currentUserPubkey
    }

    private var isMuted: Bool {
        muteListManager.isMuted(pubkey)
    }

    public init(ndk: NDK, pubkey: String, currentUserPubkey: String? = nil, sparkWalletManager: SparkWalletManager? = nil) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.currentUserPubkey = currentUserPubkey
        self.sparkWalletManager = sparkWalletManager
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero section with banner and profile info
                ProfileHeroSection(profile: profile)

                // Stats bar
                ProfileStatsBar(
                    postsCount: posts.count,
                    followingCount: followingCount
                )

                // Bio and actions
                ProfileBioSection(
                    ndk: ndk,
                    pubkey: pubkey,
                    profile: profile,
                    isOwnProfile: isOwnProfile,
                    isMuted: isMuted,
                    onEditProfile: { showEditProfile = true },
                    onToggleMute: { Task { await toggleMute() } }
                )

                // Collections
                ProfileCollectionsSection(isOwnProfile: isOwnProfile)

                // Tabs
                ProfileTabsBar(selectedTab: $selectedTab)

                // Content grid - shows posts as they stream in
                PostsGridView(posts: posts, ndk: ndk) { post in
                    selectedPost = post
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await loadProfile()
            await loadPosts()
            await loadFollowing()
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView(ndk: ndk, currentProfile: profile) {
                Task { await loadProfile() }
            }
        }
        .fullScreenCover(item: $selectedPost) { post in
            FullscreenPostViewer(
                event: post,
                ndk: ndk,
                isPresented: Binding(
                    get: { selectedPost != nil },
                    set: { if !$0 { selectedPost = nil } }
                )
            )
        }
        .toolbar {
            if isOwnProfile, let sparkWalletManager = sparkWalletManager {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(ndk: ndk, sparkWalletManager: sparkWalletManager)) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                }
            }
        }
    }

    private func loadProfile() async {
        for await metadata in await ndk.profileManager.subscribe(for: pubkey, maxAge: 60) {
            if let metadata {
                self.profile = metadata
            }
            break
        }
    }

    private var feedKinds: [Kind] {
        var kinds: [Kind] = [OlasConstants.EventKinds.image]
        if SettingsManager.shared.showVideos {
            kinds.append(OlasConstants.EventKinds.shortVideo)
        }
        return kinds
    }

    private func loadPosts() async {
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: feedKinds,
            limit: 50
        )

        let subscription = ndk.subscribe(filter: filter)

        // Stream posts as they arrive - insert sorted to maintain order
        for await event in subscription.events {
            // Insert in sorted position (newest first)
            let insertIndex = posts.firstIndex { event.createdAt > $0.createdAt } ?? posts.endIndex
            posts.insert(event, at: insertIndex)
        }
    }

    private func loadFollowing() async {
        let user = NDKUser(pubkey: pubkey)
        user.ndk = ndk

        do {
            let follows = try await user.follows()
            followingCount = follows.count
        } catch {
            followingCount = 0
        }
    }

    private func toggleMute() async {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        do {
            if isMuted {
                try await muteListManager.unmute(pubkey)
            } else {
                try await muteListManager.mute(pubkey)
            }
        } catch {
            // Mute/unmute failed silently
        }
    }
}
