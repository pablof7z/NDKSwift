import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

struct FollowPackCardView: View {
    let ndk: NDK
    let pack: FollowPack
    let isFeatured: Bool

    init(ndk: NDK, pack: FollowPack, isFeatured: Bool = false) {
        self.ndk = ndk
        self.pack = pack
        self.isFeatured = isFeatured
    }

    var body: some View {
        if isFeatured {
            featuredCard
        } else {
            standardCard
        }
    }

    // MARK: - Standard Card

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pack image or gradient
            packImage
                .frame(height: 80)
                .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(pack.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("\(pack.memberCount) accounts")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Member avatars
                memberAvatars(limit: 3)
            }
            .padding(12)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Featured Card

    private var featuredCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                // Pack image
                packImage
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                        Text("FEATURED")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.blue)

                    Text(pack.name)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Text("\(pack.memberCount) accounts")
                        Text("·")
                        Text("by")
                        NDKUIDisplayName(ndk: ndk, pubkey: pack.creatorPubkey)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()
            }
            .padding(16)

            // Member avatars row
            memberAvatars(limit: 6)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var packImage: some View {
        if let imageURL = pack.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    gradientBackground
                @unknown default:
                    gradientBackground
                }
            }
        } else {
            gradientBackground
        }
    }

    private var gradientBackground: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var gradientColors: [Color] {
        // Generate consistent colors based on pack name
        let hash = pack.name.hashValue
        let hue1 = Double(abs(hash) % 360) / 360.0
        let hue2 = Double(abs(hash >> 8) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.7, brightness: 0.8),
            Color(hue: hue2, saturation: 0.8, brightness: 0.6)
        ]
    }

    private func memberAvatars(limit: Int) -> some View {
        HStack(spacing: -8) {
            ForEach(Array(pack.pubkeys.prefix(limit).enumerated()), id: \.element) { _, pubkey in
                NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: isFeatured ? 36 : 24)
                    .overlay {
                        Circle()
                            .stroke(Color(.secondarySystemBackground), lineWidth: isFeatured ? 3 : 2)
                    }
            }

            if pack.memberCount > limit {
                Text("+\(pack.memberCount - limit)")
                    .font(isFeatured ? .caption : .system(size: 9))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: isFeatured ? 36 : 24, height: isFeatured ? 36 : 24)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Color(.secondarySystemBackground), lineWidth: isFeatured ? 3 : 2)
                    }
            }
        }
    }
}
