import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

struct FollowPackRowView: View {
    let ndk: NDK
    let pack: FollowPack

    var body: some View {
        HStack(spacing: 12) {
            // Pack image or gradient
            packImage
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(pack.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("\(pack.memberCount) accounts")
                    Text("·")
                    Text("by")
                    NDKUIDisplayName(ndk: ndk, pubkey: pack.creatorPubkey)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                // Member avatars
                memberAvatars
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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
        let hash = pack.name.hashValue
        let hue1 = Double(abs(hash) % 360) / 360.0
        let hue2 = Double(abs(hash >> 8) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.7, brightness: 0.8),
            Color(hue: hue2, saturation: 0.8, brightness: 0.6)
        ]
    }

    private var memberAvatars: some View {
        HStack(spacing: -6) {
            ForEach(Array(pack.pubkeys.prefix(5).enumerated()), id: \.element) { _, pubkey in
                NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 20)
                    .overlay {
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 1.5)
                    }
            }

            if pack.memberCount > 5 {
                Text("+\(pack.memberCount - 5)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 1.5)
                    }
            }
        }
    }
}
