import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct ProfileHeaderView: View {
    @Environment(ChirpState.self) private var state
    let ndk: NDK
    let pubkey: String

    @State private var isNip05Verified: Bool = false
    @State private var isVerifying: Bool = false
    // Store profile reference so SwiftUI holds it and observes changes
    @State private var profile: NDKProfile?

    public init(ndk: NDK, pubkey: String) {
        self.ndk = ndk
        self.pubkey = pubkey
    }

    private var isOwnProfile: Bool {
        state.ndk.sessionData?.pubkey == pubkey
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Banner
            bannerSection

            // Profile Info
            profileInfoSection
        }
        .task {
            // Load profile and hold reference so SwiftUI observes changes
            profile = ndk.profile(for: pubkey)
        }
    }

    // MARK: - Banner Section

    private var bannerSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Banner Image
            if let bannerURL = profile?.bannerURL {
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

    private var profileInfoSection: some View {
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
                    Text(profile?.displayName ?? "...")
                        .font(.title3.weight(.bold))

                    HStack(spacing: 4) {
                        if let nip05 = profile?.nip05, !nip05.isEmpty {
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
                        if let nip05 = profile?.nip05, !nip05.isEmpty {
                            await verifyNip05(nip05: nip05)
                        }
                    }
                }

                Spacer()

                // Follow button (only show if not own profile)
                if !isOwnProfile {
                    NDKUIFollowButton(ndk: state.ndk, pubkey: pubkey, style: .compact)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 8)

            // Bio
            if let about = profile?.about, !about.isEmpty {
                Text(about)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -24) // Adjust for avatar offset
            }

            // Lightning address
            if let lud16 = profile?.lud16, !lud16.isEmpty {
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
