import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct ProfileHeaderView: View {
    let ndk: NDK
    let pubkey: String

    @State private var isNip05Verified: Bool = false
    @State private var isVerifying: Bool = false

    public init(ndk: NDK, pubkey: String) {
        self.ndk = ndk
        self.pubkey = pubkey
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
                            .frame(height: 150)
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

            // Avatar positioned at bottom-left, overlapping
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 86)
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 4)
                }
                .offset(x: 16, y: 43)
        }
        .frame(height: 150)
    }

    private var defaultBanner: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .frame(height: 150)
    }

    // MARK: - Profile Info Section

    private func profileInfoSection(profile: NDKProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top row: spacer for avatar overlap
            Spacer()
                .frame(height: 50)

            // Name and handle
            VStack(alignment: .leading, spacing: 2) {
                NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
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

            // Bio
            if !profile.about.isEmpty {
                Text(profile.about)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
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
