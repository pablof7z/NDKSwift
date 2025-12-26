import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct ProfileHeaderView: View {
    @Environment(ChirpState.self) private var state
    let ndk: NDK
    let pubkey: String

    @State private var isNip05Verified: Bool = false
    @State private var isVerifying: Bool = false
    @State private var isFollowLoading: Bool = false

    public init(ndk: NDK, pubkey: String) {
        self.ndk = ndk
        self.pubkey = pubkey
    }

    private var isOwnProfile: Bool {
        state.ndk.sessionData?.pubkey == pubkey
    }

    private var isFollowing: Bool {
        state.ndk.sessionData?.followList.contains(pubkey) ?? false
    }

    public var body: some View {
        let profile = ndk.profile(for: pubkey)

        VStack(spacing: 0) {
            // Banner
            bannerSection(profile: profile)

            // Profile Info
            profileInfoSection(profile: profile)
        }
    }

    // MARK: - Banner Section

    private func bannerSection(profile: NDKProfile) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Banner Image
            if let bannerURL = profile.bannerURL {
                AsyncImage(url: bannerURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 120)
                            .clipped()
                    case .failure, .empty:
                        defaultBanner
                    @unknown default:
                        defaultBanner
                    }
                }
            } else {
                defaultBanner
            }
        }
        .frame(height: 120)
    }

    private var defaultBanner: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .frame(height: 120)
    }

    // MARK: - Profile Info Section

    private func profileInfoSection(profile: NDKProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Avatar row with name and follow button
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 72)
                    .overlay {
                        Circle()
                            .stroke(Color(uiColor: .systemBackground), lineWidth: 3)
                    }
                    .offset(y: -36)

                // Name and handle
                VStack(alignment: .leading, spacing: 2) {
                    Text(ndk.profile(for: pubkey).displayName)
                        .font(.title3.weight(.bold))

                    HStack(spacing: 4) {
                        if let nip05 = profile.nip05, !nip05.isEmpty {
                            Text(nip05)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if isNip05Verified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        } else {
                            Text(formatNpub(pubkey))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .task {
                        if let nip05 = profile.nip05, !nip05.isEmpty {
                            await verifyNip05(nip05: nip05)
                        }
                    }
                }

                Spacer()

                // Follow button (only show if not own profile)
                if !isOwnProfile {
                    followButton
                        .padding(.top, 4)
                }
            }
            .padding(.top, 8)

            // Bio
            if !profile.about.isEmpty {
                Text(profile.about)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -24) // Adjust for avatar offset
            }

            // Lightning address
            if let lud16 = profile.lud16, !lud16.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                    Text(lud16)
                        .font(.subheadline)
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Follow Button

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            Group {
                if isFollowLoading {
                    ProgressView()
                        .tint(isFollowing ? Color.primary : Color.white)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(width: 100, height: 34)
            .foregroundStyle(isFollowing ? Color.primary : Color.white)
            .background(isFollowing ? Color(.secondarySystemBackground) : .blue)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isFollowing ? Color(.separator) : .clear, lineWidth: 1)
            }
        }
        .disabled(isFollowLoading)
    }

    private func toggleFollow() {
        guard !isFollowLoading else { return }
        isFollowLoading = true

        let ndk = state.ndk
        let shouldUnfollow = isFollowing
        let targetPubkey = pubkey

        Task {
            // TODO: Implement follow/unfollow - methods don't exist on NDK yet
            print("Follow/unfollow not implemented: shouldUnfollow=\(shouldUnfollow), pubkey=\(targetPubkey)")
            await MainActor.run { isFollowLoading = false }
        }
    }

    // MARK: - Helpers

    private func formatNpub(_ pubkey: String) -> String {
        if let npub = try? Bech32.npub(from: pubkey) {
            return String(npub.prefix(12)) + "..." + String(npub.suffix(4))
        }
        return String(pubkey.prefix(8)) + "..."
    }

    private func verifyNip05(nip05: String) async {
        guard !isVerifying else { return }

        isVerifying = true
        defer { isVerifying = false }

        do {
            let verified = try await ndk.nip05Manager.verify(
                identifier: nip05,
                expectedPubkey: pubkey
            )
            await MainActor.run {
                isNip05Verified = verified
            }
        } catch {
            await MainActor.run {
                isNip05Verified = false
            }
        }
    }
}
